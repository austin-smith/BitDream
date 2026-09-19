package main

import (
	"context"
	"io"
	"net"
	"net/netip"
	"testing"
	"time"

	"golang.org/x/net/proxy"
	"tailscale.com/ipn/ipnstate"
	"tailscale.com/types/key"
)

func TestPeerDestinationNeverUsesSystemDNSOrPublicRoutes(t *testing.T) {
	status := &ipnstate.Status{Peer: map[key.NodePublic]*ipnstate.PeerStatus{
		key.NewNode().Public(): {DNSName: "nas.tail123.ts.net.", TailscaleIPs: []netip.Addr{
			netip.MustParseAddr("100.64.1.2"), netip.MustParseAddr("fd7a:115c:a1e0::1234"),
		}},
	}}
	for _, address := range []string{"nas:9091", "NAS.tail123.ts.net.:9091", "100.64.1.2:65535", "[fd7a:115c:a1e0::1234]:9091"} {
		if _, err := peerDestination(status, address); err != nil {
			t.Errorf("%s: %v", address, err)
		}
	}
	for _, address := range []string{"example.com:9091", "localhost:9091", "127.0.0.1:9091", "192.168.1.2:9091", "100.64.9.9:9091", "nas:0", "nas:65536"} {
		if _, err := peerDestination(status, address); err == nil {
			t.Errorf("unexpected route: %s", address)
		}
	}
}

func TestProxyRequiresCredentialsForwardsHostnameAndClosesActiveConnections(t *testing.T) {
	echo, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer echo.Close()
	go func() {
		conn, err := echo.Accept()
		if err == nil {
			defer conn.Close()
			io.Copy(conn, conn)
		}
	}()
	destinations := make(chan string, 1)
	listener, err := newProxy(func(_ context.Context, network, address string) (net.Conn, error) {
		destinations <- address
		return net.Dial("tcp", echo.Addr().String())
	})
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	unauthorized, err := proxy.SOCKS5("tcp", listener.Addr().String(), &proxy.Auth{User: "bitdream", Password: "wrong"}, proxy.Direct)
	if err != nil {
		t.Fatal(err)
	}
	if conn, err := unauthorized.Dial("tcp", "nas.tail123.ts.net:9091"); err == nil {
		conn.Close()
		t.Fatal("accepted invalid credentials")
	}
	dialer, err := proxy.SOCKS5("tcp", listener.Addr().String(), &proxy.Auth{User: "bitdream", Password: listener.password}, proxy.Direct)
	if err != nil {
		t.Fatal(err)
	}
	conn, err := dialer.Dial("tcp", "nas.tail123.ts.net:9091")
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(3 * time.Second))
	if got := <-destinations; got != "nas.tail123.ts.net:9091" {
		t.Fatalf("hostname not preserved: %s", got)
	}
	if _, err := conn.Write([]byte("rpc")); err != nil {
		t.Fatal(err)
	}
	data := make([]byte, 3)
	if _, err := io.ReadFull(conn, data); err != nil {
		t.Fatal(err)
	}
	listener.Close()
	if _, err := conn.Read(data); err == nil {
		t.Fatal("active socket survived shutdown")
	}
	if listener.healthy() {
		t.Fatal("closed listener reported healthy")
	}
}
