import XCTest
@testable import BitDream

func makeLegacyAdapter(steps: [QueueSender.Step]) -> TransmissionLegacyAdapter {
    TransmissionLegacyAdapter(
        transport: TransmissionTransport(sender: QueueSender(steps: steps))
    )
}

let successEmptyBody = #"{"result":"success","arguments":{}}"#
