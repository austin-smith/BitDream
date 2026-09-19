import Foundation
import Network

// Invoked only by the local Go integration test. All credentials and nodes are
// temporary fixtures. Verifies Apple's actual SOCKS implementation with tsnet.
let arguments = CommandLine.arguments
let port = NWEndpoint.Port(rawValue: UInt16(arguments[1])!)!
var proxy = ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: port))
proxy.applyCredential(username: "bitdream", password: arguments[2])
proxy.allowFailover = false
let configuration = URLSessionConfiguration.ephemeral
configuration.proxyConfigurations = [proxy]
configuration.timeoutIntervalForRequest = 10
configuration.timeoutIntervalForResource = 15
let session = URLSession(configuration: configuration)
Task {
    do {
        var request = URLRequest(url: URL(string: arguments[3])!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"method":"session-get","arguments":{}}"#.utf8)
        let (_, challenge) = try await session.data(for: request)
        guard let challenge = challenge as? HTTPURLResponse, challenge.statusCode == 409,
              let token = challenge.value(forHTTPHeaderField: "X-Transmission-Session-Id") else { exit(2) }
        request.setValue(token, forHTTPHeaderField: "X-Transmission-Session-Id")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              String(data: data, encoding: .utf8)?.contains("4.0.6") == true else { exit(3) }
        print("URLSession: MagicDNS through SOCKS, 409 challenge and RPC response passed")
        session.invalidateAndCancel()
        exit(0)
    } catch {
        print("URLSession probe failed: \(error)")
        exit(1)
    }
}
dispatchMain()
