import Foundation
import Synchronization
import TailscaleCore

/// A native context can be cancelled from any thread, including while a C call
/// is waiting. Its private proxy and URLSession live only for this attempt.
final class TailscaleNativeOperation: Sendable {
    let id: UInt64
    private let session = Mutex<(port: UInt16?, value: URLSession)?>(nil)

    init(timeout: Duration, ownsProxy: Bool = false, parent: UInt64 = 0) {
        let parts = timeout.components
        let milliseconds = max(1, parts.seconds * 1_000 + parts.attoseconds / 1_000_000_000_000_000)
        id = BDTailscaleBeginOperation(milliseconds, ownsProxy ? 1 : 0, parent)
    }

    func urlSession(port: UInt16?, make: () throws -> URLSession) rethrows -> URLSession {
        try session.withLock {
            if let session = $0, session.port == port { return session.value }
            $0?.value.invalidateAndCancel()
            let created = try make()
            $0 = (port, created)
            return created
        }
    }

    func cancel() {
        BDTailscaleCancelOperation(id)
        session.withLock { $0?.value.invalidateAndCancel() }
    }

    func close() {
        cancel()
        BDTailscaleEndOperation(id)
    }
}
