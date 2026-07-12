enum RefreshOutcome: Equatable, Sendable {
    case succeeded
    case unavailable
    case failed
    case cancelled
}
