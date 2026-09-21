import Foundation

/// An attempt owns readiness and one end-to-end deadline. Failures propagate
/// immediately; the store owns retry scheduling and presentation.
/// Task-local scope follows the factory and concurrent RPC reads without being
/// retained by cached connections or affecting later torrent-changing requests.
enum TransmissionConnectionAttempt {
    @TaskLocal static var deadline: ContinuousClock.Instant?
    @TaskLocal static var tailscaleOperation: TailscaleNativeOperation?

    static func run<Value: Sendable>(
        timeout: Duration = .seconds(10),
        usesTailscale: Bool,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        let native = usesTailscale ? TailscaleNativeOperation(timeout: timeout, ownsProxy: true) : nil
        defer { native?.close() }
        return try await withTaskCancellationHandler {
            try await $deadline.withValue(deadline) {
                try await $tailscaleOperation.withValue(native) {
                    try await withThrowingTaskGroup(of: Value.self) { group in
                        group.addTask { try await operation() }
                        group.addTask {
                            try await Task.sleep(until: deadline, clock: .continuous)
                            native?.cancel()
                            throw TransmissionError.timeout
                        }
                        defer { group.cancelAll() }
                        return try await group.next()!
                    }
                }
            }
        } onCancel: {
            native?.cancel()
        }
    }

    static func checkDeadline() throws {
        try Task.checkCancellation()
        if let deadline, ContinuousClock.now >= deadline { throw TransmissionError.timeout }
    }
}
