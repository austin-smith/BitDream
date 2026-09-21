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
	"tailscale.com/ipn"
	"tailscale.com/ipn/ipnstate"
	"tailscale.com/net/socks5"
	"tailscale.com/tailcfg"
	"tailscale.com/tsnet"
	"tailscale.com/types/logger"
)

type request struct {
	Action       string `json:"action"`
	Directory    string `json:"directory"`
	Hostname     string `json:"hostname"`
	WaitingState string `json:"waitingState"`
	PeerAddress  string `json:"peerAddress"`
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
	ErrorCode     string `json:"errorCode,omitempty"`
}

// Commands are serialized across the ABI, including startup and shutdown. No Go
// pointer crosses into Swift, and there is only one node per host-app process.
var runtime struct {
	server     *tsnet.Server
	proxy      *proxyListener
	generation uint64
}

// A cancellable gate serializes mutations without stranding expired commands
// behind another native request. Readiness subscriptions wait outside this gate.
var runtimeGate = make(chan struct{}, 1)

func lockRuntime(ctx context.Context) error {
	select {
	case runtimeGate <- struct{}{}:
		if err := ctx.Err(); err != nil {
			<-runtimeGate
			return err
		}
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func unlockRuntime() { <-runtimeGate }

func init() {
	// This application does not upload Tailscale diagnostic logs. This is the
	// supported process-wide tsnet opt-out; control-plane metadata still exists.
	envknob.SetNoLogsNoSupport()
}

//export BDTailscaleBeginOperation
func BDTailscaleBeginOperation(milliseconds C.longlong, ownsProxy C.int, parent C.ulonglong) C.ulonglong {
	return C.ulonglong(beginOperation(time.Duration(milliseconds)*time.Millisecond, ownsProxy != 0, uint64(parent)))
}

//export BDTailscaleCancelOperation
func BDTailscaleCancelOperation(id C.ulonglong) { cancelOperation(uint64(id)) }

//export BDTailscaleEndOperation
func BDTailscaleEndOperation(id C.ulonglong) { endOperation(uint64(id)) }

//export BDTailscaleCommand
func BDTailscaleCommand(input *C.char, id C.ulonglong) *C.char {
	var req request
	if err := json.Unmarshal([]byte(C.GoString(input)), &req); err != nil {
		return response(snapshot{Error: "Invalid native request"})
	}
	op := operationForID(uint64(id))
	if op == nil {
		return response(snapshot{Error: "Tailscale operation ended"})
	}
	if req.Action == "wait" {
		// Subscribe and wait without the runtime gate: status, logout, and
		// cancellation must remain available while the control plane starts.
		if err := waitForChange(op.ctx, req); err != nil {
			return response(nativeFailure(op))
		}
		req.Action = "status"
	}
	if err := lockRuntime(op.ctx); err != nil {
		return response(nativeFailure(op))
	}
	defer unlockRuntime()
	value, err := execute(op, req)
	if err != nil {
		// Never return engine error strings: they can contain an authorization URL.
		value = nativeFailure(op)
	}
	value.Generation = runtime.generation
	return response(value)
}

func waitForChange(ctx context.Context, req request) error {
	if err := lockRuntime(ctx); err != nil {
		return err
	}
	server := runtime.server
	unlockRuntime()
	if server == nil {
		return nil
	}
	return waitForServerChange(ctx, server, req)
}

func waitForServerChange(ctx context.Context, server *tsnet.Server, req request) error {
	client, err := server.LocalClient()
	if err != nil {
		return err
	}
	watcher, err := client.WatchIPNBus(ctx, ipn.NotifyInitialState|ipn.NotifyInitialStatus|ipn.NotifyPeerChanges)
	if err != nil {
		return err
	}
	defer watcher.Close()
	for {
		if _, err := watcher.Next(); err != nil {
			return err
		}
		// Fetch after subscribing, including on the initial notification, so a
		// change between Swift's previous snapshot and this wait cannot be lost.
		status, err := client.Status(ctx)
		if err != nil {
			return err
		}
		if status.BackendState != req.WaitingState || (status.BackendState == "NeedsLogin" && status.AuthURL != "") {
			return nil
		}
		if req.PeerAddress != "" {
			_, err := peerDestination(status, req.PeerAddress)
			if err == nil || errors.Is(err, errAmbiguousPeer) {
				return nil
			}
		}
	}
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

func execute(op *nativeOperation, req request) (snapshot, error) {
	if err := op.ctx.Err(); err != nil {
		return snapshot{}, err
	}
	if req.Action == "stop" {
		return snapshot{State: "Stopped"}, stop(errConnectionChanged)
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
	ctx, cancel := context.WithTimeout(op.ctx, 5*time.Second)
	defer cancel()
	switch req.Action {
	case "login":
		if err := client.StartLoginInteractive(ctx); err != nil {
			return snapshot{}, err
		}
	case "logout":
		cancelConnectionOperations(errSignedOut)
		closeProxy()
		if err := client.Logout(ctx); err != nil {
			return snapshot{}, err
		}
		return snapshot{State: "Stopped"}, stop(errSignedOut)
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
		proxy := runtime.proxy
		if op.owner != nil {
			proxy, err = op.connectionProxy(runtime.generation, func(ctx context.Context) (*proxyListener, error) {
				return newProxyWithContext(ctx, tailnetDialer(runtime.server))
			})
			if err != nil {
				return snapshot{}, err
			}
		}
		result.ProxyPort = uint16(proxy.Addr().(*net.TCPAddr).Port)
		result.ProxyPassword = proxy.password
	} else {
		closeProxy()
	}
	return result, nil
}

func summarize(status *ipnstate.Status) snapshot {
	result := snapshot{State: status.BackendState, AuthURL: status.AuthURL}
	if status.Self != nil && status.CurrentTailnet != nil {
		// UserID identifies the account within Tailscale's hosted control plane.
		// Node registration and editable DNS names must not change this binding.
		if status.Self.UserID > 0 {
			result.AccountID = fmt.Sprintf("tailscale-user/%d", status.Self.UserID)
		}
		result.AccountName = status.CurrentTailnet.Name
		// CurrentTailnet.Name is the legacy domain, not the editable display name.
		if names, err := tailcfg.UnmarshalNodeCapJSON[string](status.Self.CapMap, tailcfg.NodeAttrTailnetDisplayName); err == nil && len(names) > 0 && names[0] != "" {
			result.AccountName = names[0]
		}
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

func stop(reason error) error {
	cancelConnectionOperations(reason)
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
	cancel      context.CancelFunc
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
	if listener.cancel != nil {
		listener.cancel()
	}
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
	return newProxyWithContext(context.Background(), dial)
}

func newProxyWithContext(parent context.Context, dial func(context.Context, string, string) (net.Conn, error)) (*proxyListener, error) {
	var secret [32]byte
	if _, err := rand.Read(secret[:]); err != nil {
		return nil, err
	}
	listener, err := net.Listen("tcp4", net.JoinHostPort("127.0.0.1", strconv.Itoa(0)))
	if err != nil {
		return nil, err
	}
	lifetime, cancel := context.WithCancel(parent)
	proxy := &proxyListener{Listener: listener, password: hex.EncodeToString(secret[:]), connections: make(map[*proxyConn]struct{}), cancel: cancel}
	context.AfterFunc(lifetime, func() { proxy.Close() })
	server := &socks5.Server{Username: "bitdream", Password: proxy.password, Logf: logger.Discard,
		Dialer: func(ctx context.Context, network, address string) (net.Conn, error) {
			if network != "tcp" {
				return nil, errors.New("only TCP RPC is supported")
			}
			requestContext, cancel := context.WithCancel(ctx)
			stop := context.AfterFunc(lifetime, cancel)
			defer stop()
			defer cancel()
			return dial(requestContext, network, address)
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

var errAmbiguousPeer = errors.New("ambiguous peer")

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
			return netip.AddrPort{}, errAmbiguousPeer
		}
		for _, ip := range candidate.TailscaleIPs {
			if (parsed.IsValid() && parsed.Unmap() == ip.Unmap()) || (nameMatches && !destination.IsValid()) {
				if destination.IsValid() && destination != ip {
					return netip.AddrPort{}, errAmbiguousPeer
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
