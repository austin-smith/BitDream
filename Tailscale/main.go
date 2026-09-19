// BitDream's narrow Apple ABI around the supported tsnet API.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"strconv"
	"strings"
	"sync"
	"time"
	"unsafe"

	"tailscale.com/envknob"
	"tailscale.com/ipn/ipnstate"
	"tailscale.com/net/socks5"
	"tailscale.com/tsnet"
	"tailscale.com/types/logger"
)

type request struct {
	Action    string `json:"action"`
	Directory string `json:"directory"`
	Hostname  string `json:"hostname"`
}

type peer struct {
	ID      string   `json:"id"`
	Name    string   `json:"name"`
	Address string   `json:"address"`
	Online  bool     `json:"online"`
	IPs     []string `json:"ips"`
}

type snapshot struct {
	Generation    uint64 `json:"generation"`
	State         string `json:"state"`
	AuthURL       string `json:"authURL,omitempty"`
	AccountID     string `json:"accountID,omitempty"`
	AccountName   string `json:"accountName,omitempty"`
	Peers         []peer `json:"peers"`
	ProxyPort     uint16 `json:"proxyPort,omitempty"`
	ProxyPassword string `json:"proxyPassword,omitempty"`
	Error         string `json:"error,omitempty"`
}

// Commands are serialized across the ABI, including startup and shutdown. No Go
// pointer crosses into Swift, and there is only one node per host-app process.
var runtime struct {
	sync.Mutex
	server     *tsnet.Server
	proxy      *proxyListener
	generation uint64
}

func init() {
	// This application does not upload Tailscale diagnostic logs. This is the
	// supported process-wide tsnet opt-out; control-plane metadata still exists.
	envknob.SetNoLogsNoSupport()
}

//export BDTailscaleCommand
func BDTailscaleCommand(input *C.char) *C.char {
	runtime.Lock()
	defer runtime.Unlock()
	var req request
	if err := json.Unmarshal([]byte(C.GoString(input)), &req); err != nil {
		return response(snapshot{Error: "Invalid native request"})
	}
	value, err := execute(req)
	if err != nil {
		// Never return engine error strings: they can contain an authorization URL.
		value = snapshot{State: "Error", Error: "Tailscale could not complete " + req.Action}
	}
	value.Generation = runtime.generation
	return response(value)
}

//export BDTailscaleFree
func BDTailscaleFree(value *C.char) { C.free(unsafe.Pointer(value)) }

func response(value snapshot) *C.char {
	if value.Peers == nil {
		value.Peers = []peer{}
	}
	data, _ := json.Marshal(value)
	return C.CString(string(data))
}

func execute(req request) (snapshot, error) {
	if req.Action == "stop" {
		return snapshot{State: "Stopped"}, stop()
	}
	if req.Action == "start" && runtime.server == nil {
		if req.Directory == "" || req.Hostname == "" {
			return snapshot{}, errors.New("missing configuration")
		}
		server := &tsnet.Server{Dir: req.Directory, Hostname: req.Hostname,
			UserLogf: logger.Discard, Logf: logger.Discard}
		// Start is non-blocking with respect to authorization. Never call Up with
		// an unbounded context while waiting for a browser interaction.
		if err := server.Start(); err != nil {
			return snapshot{}, err
		}
		runtime.server = server
		runtime.generation++
	}
	if runtime.server == nil {
		return snapshot{State: "Stopped"}, nil
	}
	client, err := runtime.server.LocalClient()
	if err != nil {
		return snapshot{}, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	switch req.Action {
	case "login":
		if err := client.StartLoginInteractive(ctx); err != nil {
			return snapshot{}, err
		}
	case "logout":
		closeProxy()
		if err := client.Logout(ctx); err != nil {
			return snapshot{}, err
		}
		return snapshot{State: "Stopped"}, stop()
	case "start", "status":
	default:
		return snapshot{}, errors.New("unknown operation")
	}
	status, err := client.Status(ctx)
	if err != nil {
		return snapshot{}, err
	}
	result := summarize(status)
	if status.BackendState == "Running" {
		if runtime.proxy == nil || !runtime.proxy.healthy() {
			closeProxy()
			runtime.proxy, err = newProxy(tailnetDialer(runtime.server))
			if err != nil {
				return snapshot{}, err
			}
			runtime.generation++
		}
		result.ProxyPort = uint16(runtime.proxy.Addr().(*net.TCPAddr).Port)
		result.ProxyPassword = runtime.proxy.password
	} else {
		closeProxy()
	}
	return result, nil
}

func summarize(status *ipnstate.Status) snapshot {
	result := snapshot{State: status.BackendState, AuthURL: status.AuthURL}
	if status.Self != nil && status.CurrentTailnet != nil {
		result.AccountID = fmt.Sprintf("%s/%d/%s", status.CurrentTailnet.MagicDNSSuffix, status.Self.UserID, status.Self.ID)
		result.AccountName = status.CurrentTailnet.Name
	}
	for _, value := range status.Peer {
		address := strings.TrimSuffix(value.DNSName, ".")
		if address == "" && len(value.TailscaleIPs) > 0 {
			address = value.TailscaleIPs[0].String()
		}
		ips := make([]string, 0, len(value.TailscaleIPs))
		for _, ip := range value.TailscaleIPs {
			ips = append(ips, ip.String())
		}
		if address != "" {
			result.Peers = append(result.Peers, peer{string(value.ID), value.HostName, address, value.Online, ips})
		}
	}
	return result
}

func closeProxy() {
	if runtime.proxy != nil {
		runtime.proxy.Close()
		runtime.proxy = nil
		runtime.generation++
	}
}

func stop() error {
	closeProxy()
	server := runtime.server
	runtime.server = nil
	runtime.generation++
	if server != nil {
		return server.Close()
	}
	return nil
}

// proxyListener tracks accepted sockets so revocation closes existing HTTP/TLS
// connections as well as the listening socket. Restarting only the listener would
// leave old authenticated sessions alive.
type proxyListener struct {
	net.Listener
	password    string
	mu          sync.Mutex
	closed      bool
	connections map[*proxyConn]struct{}
}

type proxyConn struct {
	net.Conn
	owner *proxyListener
}

func (conn *proxyConn) Close() error {
	conn.owner.mu.Lock()
	delete(conn.owner.connections, conn)
	conn.owner.mu.Unlock()
	return conn.Conn.Close()
}

func (listener *proxyListener) Accept() (net.Conn, error) {
	conn, err := listener.Listener.Accept()
	if err != nil {
		return nil, err
	}
	listener.mu.Lock()
	defer listener.mu.Unlock()
	if listener.closed {
		conn.Close()
		return nil, net.ErrClosed
	}
	tracked := &proxyConn{Conn: conn, owner: listener}
	listener.connections[tracked] = struct{}{}
	return tracked, nil
}

func (listener *proxyListener) Close() error {
	listener.mu.Lock()
	defer listener.mu.Unlock()
	if listener.closed {
		return nil
	}
	listener.closed = true
	err := listener.Listener.Close()
	for conn := range listener.connections {
		conn.Conn.Close()
	}
	clear(listener.connections)
	return err
}

func (listener *proxyListener) healthy() bool {
	listener.mu.Lock()
	closed := listener.closed
	listener.mu.Unlock()
	if closed {
		return false
	}
	conn, err := net.DialTimeout("tcp", listener.Addr().String(), 250*time.Millisecond)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func newProxy(dial func(context.Context, string, string) (net.Conn, error)) (*proxyListener, error) {
	var secret [32]byte
	if _, err := rand.Read(secret[:]); err != nil {
		return nil, err
	}
	listener, err := net.Listen("tcp4", net.JoinHostPort("127.0.0.1", strconv.Itoa(0)))
	if err != nil {
		return nil, err
	}
	proxy := &proxyListener{Listener: listener, password: hex.EncodeToString(secret[:]), connections: make(map[*proxyConn]struct{})}
	server := &socks5.Server{Username: "bitdream", Password: proxy.password, Logf: logger.Discard,
		Dialer: func(ctx context.Context, network, address string) (net.Conn, error) {
			if network != "tcp" {
				return nil, errors.New("only TCP RPC is supported")
			}
			ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
			defer cancel()
			return dial(ctx, network, address)
		}}
	go func() { _ = server.Serve(proxy); _ = proxy.Close() }()
	return proxy, nil
}

// Dial explicitly through netstack. tsnet.Server.Dial intentionally permits a
// system-network fallback for non-tailnet destinations, which is inappropriate
// for a saved private RPC route. Resolve only peers from this node's map; no
// system DNS, subnet routes, exit nodes, or public destinations are consulted.
func tailnetDialer(server *tsnet.Server) func(context.Context, string, string) (net.Conn, error) {
	return func(ctx context.Context, network, address string) (net.Conn, error) {
		client, err := server.LocalClient()
		if err != nil {
			return nil, err
		}
		status, err := client.Status(ctx)
		if err != nil {
			return nil, err
		}
		if status.BackendState != "Running" {
			return nil, errors.New("node is not ready")
		}
		destination, err := peerDestination(status, address)
		if err != nil {
			return nil, err
		}
		dial := server.Sys().Dialer.Get().NetstackDialTCP
		if dial == nil {
			return nil, errors.New("tailnet transport unavailable")
		}
		return dial(ctx, destination)
	}
}

func peerDestination(status *ipnstate.Status, address string) (netip.AddrPort, error) {
	host, rawPort, err := net.SplitHostPort(address)
	if err != nil {
		return netip.AddrPort{}, err
	}
	port, err := strconv.ParseUint(rawPort, 10, 16)
	if err != nil || port == 0 {
		return netip.AddrPort{}, errors.New("invalid port")
	}
	host = strings.ToLower(strings.TrimSuffix(host, "."))
	parsed, _ := netip.ParseAddr(host)
	var destination netip.Addr
	for _, candidate := range status.Peer {
		dnsName := strings.ToLower(strings.TrimSuffix(candidate.DNSName, "."))
		nameMatches := dnsName != "" && (host == dnsName || host == strings.Split(dnsName, ".")[0])
		if nameMatches && destination.IsValid() {
			return netip.AddrPort{}, errors.New("ambiguous peer")
		}
		for _, ip := range candidate.TailscaleIPs {
			if (parsed.IsValid() && parsed.Unmap() == ip.Unmap()) || (nameMatches && !destination.IsValid()) {
				if destination.IsValid() && destination != ip {
					return netip.AddrPort{}, errors.New("ambiguous peer")
				}
				destination = ip
				break
			}
		}
	}
	if !destination.IsValid() {
		return netip.AddrPort{}, errors.New("destination is not a visible tailnet peer")
	}
	return netip.AddrPortFrom(destination, uint16(port)), nil
}

func main() {}
