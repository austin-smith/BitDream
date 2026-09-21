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
	"tailscale.com/tailcfg"
	"tailscale.com/types/key"
)

func TestSummaryUsesCurrentTailnetDisplayNameWithoutChangingIdentity(t *testing.T) {
	status := &ipnstate.Status{
		CurrentTailnet: &ipnstate.TailnetStatus{Name: "user.github", MagicDNSSuffix: "tail123.ts.net"},
		Self:           &ipnstate.PeerStatus{ID: "node-a", UserID: 123},
	}
	for _, tt := range []struct {
		name   string
		values []tailcfg.RawMessage
		want   string
	}{
		{name: "default", want: "user.github"},
		{name: "custom", values: []tailcfg.RawMessage{`"Home Network"`}, want: "Home Network"},
		{name: "renamed", values: []tailcfg.RawMessage{`"New Name"`}, want: "New Name"},
		{name: "empty", values: []tailcfg.RawMessage{`""`}, want: "user.github"},
		{name: "malformed", values: []tailcfg.RawMessage{`42`}, want: "user.github"},
		{name: "removed", want: "user.github"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			status.Self.CapMap = nil
			if tt.values != nil {
				status.Self.CapMap = tailcfg.NodeCapMap{tailcfg.NodeAttrTailnetDisplayName: tt.values}
			}
			got := summarize(status)
			if got.AccountName != tt.want {
				t.Errorf("account name = %q, want %q", got.AccountName, tt.want)
			}
			if got.AccountID != "tailscale-user/123" {
				t.Errorf("display name affected account identity: %q", got.AccountID)
			}
		})
	}
}

func TestAccountIdentitySurvivesRegistrationAndDNSChanges(t *testing.T) {
	status := &ipnstate.Status{
		CurrentTailnet: &ipnstate.TailnetStatus{Name: "user.github", MagicDNSSuffix: "tail123.ts.net"},
		Self:           &ipnstate.PeerStatus{ID: "node-a", UserID: 123},
	}
	original := summarize(status).AccountID
	status.Self.ID = "node-b"
	status.CurrentTailnet.MagicDNSSuffix = "renamed-tailnet.ts.net"
	if got := summarize(status).AccountID; got != original || got == "" {
		t.Fatalf("same account changed identity after registration: %q -> %q", original, got)
	}
	status.Self.UserID = 456
	if got := summarize(status).AccountID; got == original || got == "" {
		t.Fatalf("different account was not distinguished: %q", got)
	}
	for _, userID := range []tailcfg.UserID{0, -1} {
		status.Self.UserID = userID
		if got := summarize(status).AccountID; got != "" {
			t.Errorf("incomplete identity produced an account: %q", got)
		}
	}
}

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

// This is the same scope used by Swift's connection attempt. Expiry/revocation
// must cancel a native dial, even if SOCKS has not returned a connection yet.
func TestConnectionOperationCancellationStopsDialAndListener(t *testing.T) {
	id := beginOperation(time.Minute, true, 0)
	defer endOperation(id)
	op := operationForID(id)
	entered, cancelled := make(chan struct{}), make(chan struct{})
	listener, err := op.connectionProxy(1, func(ctx context.Context) (*proxyListener, error) {
		return newProxyWithContext(ctx, func(ctx context.Context, _, _ string) (net.Conn, error) {
			close(entered)
			<-ctx.Done()
			close(cancelled)
			return nil, ctx.Err()
		})
	})
	if err != nil {
		t.Fatal(err)
	}
	dialer, err := proxy.SOCKS5("tcp", listener.Addr().String(), &proxy.Auth{User: "bitdream", Password: listener.password}, proxy.Direct)
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		conn, err := dialer.Dial("tcp", "nas.test.ts.net:9091")
		if conn != nil {
			conn.Close()
		}
		done <- err
	}()
	select {
	case <-entered:
	case <-time.After(time.Second):
		t.Fatal("dial did not start")
	}
	cancelOperation(id)
	select {
	case <-cancelled:
	case <-time.After(time.Second):
		t.Fatal("native dial survived cancellation")
	}
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("cancelled proxy request succeeded")
		}
	case <-time.After(time.Second):
		t.Fatal("SOCKS client remained blocked")
	}
}

func TestNativeCommandCancellationDoesNotCancelSiblingOrOutliveParent(t *testing.T) {
	parent := beginOperation(time.Minute, true, 0)
	defer endOperation(parent)
	first := beginOperation(time.Minute, false, parent)
	defer endOperation(first)
	second := beginOperation(time.Minute, false, parent)
	defer endOperation(second)
	cancelOperation(first)
	if operationForID(second).ctx.Err() != nil {
		t.Fatal("cancelled a sibling request")
	}
	cancelOperation(parent)
	if operationForID(second).ctx.Err() == nil {
		t.Fatal("request survived its attempt")
	}
	runtimeGate <- struct{}{}
	defer unlockRuntime()
	if err := lockRuntime(operationForID(second).ctx); err == nil {
		t.Fatal("cancelled command acquired busy gate")
	}
}

func TestSignOutRevokesStartupCommandsAndProxyScope(t *testing.T) {
	parent := beginOperation(time.Minute, true, 0)
	defer endOperation(parent)
	command := beginOperation(time.Minute, false, parent)
	defer endOperation(command)
	cancelConnectionOperations(errSignedOut)
	if got := nativeFailure(operationForID(command)).ErrorCode; got != "signed_out" {
		t.Fatalf("revoked command reported %q instead of sign-in required", got)
	}
	if _, err := operationForID(parent).connectionProxy(1, func(ctx context.Context) (*proxyListener, error) {
		t.Fatal("created proxy after sign-out")
		return nil, nil
	}); err == nil {
		t.Fatal("revoked attempt created a proxy")
	}
}
