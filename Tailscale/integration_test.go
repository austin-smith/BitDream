package main

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os/exec"
	goruntime "runtime"
	"testing"
	"time"

	"tailscale.com/net/netns"
	"tailscale.com/tailcfg"
	"tailscale.com/tsnet"
	"tailscale.com/tstest/integration"
	"tailscale.com/tstest/integration/testcontrol"
	"tailscale.com/types/logger"
)

// Exercises real encrypted userspace nodes with a local control server and DERP.
// This does not enroll any device in a real user's tailnet.
func TestEncryptedRPCThroughEmbeddedProxy(t *testing.T) {
	netns.SetEnabled(false)
	t.Cleanup(func() { netns.SetEnabled(true) })
	control := &testcontrol.Server{
		DERPMap:   integration.RunDERPAndSTUN(t, logger.Discard, "127.0.0.1"),
		DNSConfig: &tailcfg.DNSConfig{Proxied: true}, MagicDNSDomain: "test.ts.net", Logf: logger.Discard,
	}
	control.HTTPTestServer = httptest.NewServer(control)
	t.Cleanup(control.HTTPTestServer.Close)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	newNode := func(name string) *tsnet.Server {
		node := &tsnet.Server{Dir: t.TempDir(), Hostname: name, ControlURL: control.HTTPTestServer.URL,
			UserLogf: logger.Discard, Logf: logger.Discard}
		if _, err := node.Up(ctx); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { node.Close() })
		return node
	}
	remote := newNode("transmission")
	client := newNode("bitdream")
	listener, err := remote.Listen("tcp", ":9091")
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/transmission/rpc" {
			http.NotFound(w, r)
			return
		}
		if r.Header.Get("X-Transmission-Session-Id") != "test-token" {
			w.Header().Set("X-Transmission-Session-Id", "test-token")
			w.WriteHeader(409)
			return
		}
		io.WriteString(w, `{"result":"success","arguments":{"version":"4.0.6"}}`)
	})}
	go server.Serve(listener)
	t.Cleanup(func() { server.Close() })
	local, err := client.LocalClient()
	if err != nil {
		t.Fatal(err)
	}
	for {
		status, err := local.Status(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if len(status.Peer) > 0 {
			break
		}
		select {
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		case <-time.After(50 * time.Millisecond):
		}
	}
	proxy, err := newProxy(tailnetDialer(client))
	if err != nil {
		t.Fatal(err)
	}
	defer proxy.Close()
	proxyURL := &url.URL{Scheme: "socks5", Host: proxy.Addr().String(), User: url.UserPassword("bitdream", proxy.password)}
	transport := &http.Transport{Proxy: http.ProxyURL(proxyURL)}
	defer transport.CloseIdleConnections()
	httpClient := &http.Client{Transport: transport, Timeout: 15 * time.Second}
	remoteAPI, _ := remote.LocalClient()
	remoteStatus, err := remoteAPI.Status(ctx)
	if err != nil {
		t.Fatal(err)
	}
	endpoint := "http://" + remoteStatus.Self.DNSName + ":9091/transmission/rpc"
	first, err := httpClient.Get(endpoint)
	if err != nil {
		t.Fatal(err)
	}
	first.Body.Close()
	if first.StatusCode != 409 {
		t.Fatalf("expected session challenge, got %d", first.StatusCode)
	}
	request, _ := http.NewRequestWithContext(ctx, "POST", endpoint, nil)
	request.Header.Set("X-Transmission-Session-Id", first.Header.Get("X-Transmission-Session-Id"))
	response, err := httpClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		t.Fatalf("expected RPC success, got %d", response.StatusCode)
	}
	if goruntime.GOOS == "darwin" {
		probeContext, probeCancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer probeCancel()
		command := exec.CommandContext(probeContext, "xcrun", "swift", "testdata/URLSessionProbe.swift",
			fmt.Sprint(proxy.Addr().(*net.TCPAddr).Port), proxy.password, endpoint)
		if output, err := command.CombinedOutput(); err != nil {
			t.Fatalf("Apple URLSession: %v\n%s", err, output)
		} else {
			t.Log(string(output))
		}
	}
	// Private routing must reject even a reachable loopback HTTP server.
	if response, err := httpClient.Get(control.HTTPTestServer.URL); err == nil {
		response.Body.Close()
		t.Fatal("embedded proxy escaped to the system network")
	}
}
