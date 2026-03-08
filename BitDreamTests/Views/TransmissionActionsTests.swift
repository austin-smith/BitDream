import XCTest
@testable import BitDream

@MainActor
final class TransmissionActionsTests: XCTestCase {
    func testPerformStructuredTransmissionOperationReturnsValueWithoutCallingOnError() async {
        var errors: [String] = []

        let result = await performStructuredTransmissionOperation(
            operation: { 42 },
            onError: { errors.append($0) }
        )

        XCTAssertEqual(result, 42)
        XCTAssertTrue(errors.isEmpty)
    }

    func testPerformStructuredTransmissionOperationMapsErrorsAndReturnsNil() async {
        var errors: [String] = []
        let expectedMessage = TransmissionUserFacingError.message(for: TransmissionError.unauthorized)

        let result: Int? = await performStructuredTransmissionOperation(
            operation: { throw TransmissionError.unauthorized },
            onError: { errors.append($0) }
        )

        XCTAssertNil(result)
        XCTAssertEqual(errors, [expectedMessage].compactMap { $0 })
    }

    func testPerformStructuredTransmissionOperationSuppressesCancelledParentTask() async {
        let gate = TaskStartGate()
        var errors: [String] = []

        let task = Task { @MainActor in
            await performStructuredTransmissionOperation(
                operation: {
                    await gate.markStarted()
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    return 42
                },
                onError: { errors.append($0) }
            )
        }

        await gate.waitUntilStarted()
        task.cancel()
        let result = await task.value

        XCTAssertNil(result)
        XCTAssertTrue(errors.isEmpty)
    }
}

private actor TaskStartGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func markStarted() {
        hasStarted = true
        continuation?.resume()
        continuation = nil
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}
