# Transmission Refactor Plan

## Current-State Findings

- **The RPC boundary is incorrect:** `TransmissionGenericResponse` ignores the required `result` field, status-only requests treat any HTTP 200 as success, and `torrent-add` duplicate responses are treated as failures even though the RPC spec defines them as successful outcomes.

- **The endpoint model is too weak:** `TransmissionConfig = URLComponents` is not a sufficient long-term representation of a Transmission RPC endpoint, and request code currently reconstructs `/transmission/rpc` for each call.

- **Configuration and credentials have duplicate sources of truth:** `AppStore.setHost` caches `Server(config, auth)`, while most request paths rebuild from `store.host` and Keychain. Settings flows use `currentServerInfo`, and updating an existing server does not refresh that cached server state. Subsequent settings requests can therefore use stale host or credential data until reconnect or reselection.

- **There is no owning Transmission client abstraction:** The repo currently has 49 `makeConfig(store:)` call sites. Views and helper types assemble transport and auth state directly instead of calling one dependency-owned client.

- **The client boundary is split across app, settings, and widgets:** The main app, settings flows, and widget/background refresh code all construct Transmission request state independently. The current design does not provide one shared client boundary that works across all three contexts.

- **Transmission-specific integration logic is stranded in `Utilities.swift`:** `Utilities.swift` currently owns `makeConfig(store:)`, refresh and poll orchestration, and the main app's read-side integration with Transmission. That preserves coupling between `AppStore` and the transport boundary under a generic filename.

- **The refresh lifecycle is implicit and unsafe:** Selecting a server, polling, reconnecting, settings refreshes, and widget refresh all manage request work independently. In-flight responses are not tied to one active connection identity, so late results from an old host can overwrite state after a host switch or reconnect.

- **The error surface is inconsistent and lossy:** Some APIs return `Result`, some return `(value?, String?)`, some use separate success and error closures, some return `TransmissionResponse`, and `addTorrent` returns an ad hoc tuple. Failures are often collapsed into `.configError` or `.failed`, and some query helpers convert failures into empty values instead of surfacing them.

- **`torrent-add` duplicate handling is incorrect:** The RPC spec defines both `torrent-added` and `torrent-duplicate` as valid successful outcomes with `result == "success"`. The current API only treats `torrent-added` as success.

- **The concurrency model is half-migrated:** Core transport is callback-based, wrapped with `Task` hops, duplicated into background-only variants, and then bridged back into `async` with continuations. Widget refresh still blocks on `DispatchGroup`.

- **Per-server mutable state has no explicit ownership model:** Session-token caching, retry behavior, and concurrent request coordination are currently spread across a global token store and callback transport. The code does not define one serialized ownership boundary for per-server mutable state.

- **Transport is tightly coupled and hard to test:** Request building, decoding, retry behavior, token handling, and `URLSession.shared` usage are all inline. No Transmission-focused tests are present in the repo.

- **The Transmission layer lacks focused automated tests:** The repo does not currently contain Transmission-focused tests for RPC `result` handling, HTTP 409 session-token retry behavior, HTTP 401 unauthorized handling, `torrent-add` duplicate success behavior, or failure propagation.

- **Settings autosave can lose newer edits:** `SessionSettingsEditModel` uses one shared dirty-state buffer for both pending edits and in-flight `session-set` payloads. A successful older save can therefore clear newer edits that were made while that request was still in flight.

- **User-facing error handling is coupled to `TransmissionResponse`:** Shared helpers and UI flows currently rely on `TransmissionResponse` and `handleTransmissionResponse` for user-facing error mapping. Removing `TransmissionResponse` without a replacement boundary would push transport and domain error interpretation into view code.

- **Shared request definitions are duplicated:** Repeated `torrent-get` field lists and related request-shape definitions are copied across list, widget, and detail flows, which creates drift risk when fields change.

- **`TorrentActionExecutor.swift` is a transitional wrapper, not a stable architectural center:** Some torrent mutation flows go through it, but many still bypass it directly.

- **`TransmissionFunctions.swift` is a god file with mixed responsibilities:** It is 1,076 lines long, exposes 30 public functions, and combines transport, authentication, token caching, decoding, torrent RPCs, session RPCs, queue and file operations, and utility behavior.

- **The Transmission layer has accumulated code-shape debt:** The current implementation repeats request field lists, duplicates near-identical wrappers, and still contains unused code such as `SessionInfo`.

## Target Architecture

- **Use a dedicated endpoint type:** Replace `TransmissionConfig = URLComponents` with a `TransmissionEndpoint` value type that represents one validated Transmission RPC destination and owns the canonical RPC URL or equivalent validated endpoint data. Credentials remain separate from the endpoint.

- **Keep custom RPC paths out of scope for this refactor:** `TransmissionEndpoint` standardizes the currently supported endpoint shape and continues to target the default `/transmission/rpc` path. Supporting custom RPC paths is a separate follow-up, not part of this migration.

- **Use one connection-construction path across contexts:** App, settings, and widget/background refresh build `TransmissionConnection` instances from one shared descriptor and factory path rather than each reconstructing config, auth, and credential-loading rules independently.

- **Use a transport-private RPC envelope:** Model the real Transmission response contract, including `result`, `arguments`, and optional `tag`. Transport interprets RPC success and failure and converts non-success results into typed errors before domain code sees them.

- **Define one typed error taxonomy for the Transmission layer:** The domain-facing client throws one shared `TransmissionError` taxonomy with explicit categories for invalid endpoint configuration, unauthorized/auth failures, transport failures, timeout, cancellation, non-retriable HTTP status failures, RPC-level failures, invalid response shape, and decoding failures. Multi-outcome domain operations such as `torrent-add` duplicate remain typed success outcomes, not errors.

- **Stage contract primitives before the full client migration:** Introduce the minimal `TransmissionRPCEnvelope` and `TransmissionError` types before broad client migration work so Phase 0 and Phase 1 tests can assert the intended contract directly instead of encoding temporary `NSError` or `TransmissionResponse` behavior.

- **Introduce one authenticated per-server connection:** `actor TransmissionConnection` becomes the single owner of endpoint, credentials, token state, and injected networking dependencies.

- **Make per-server mutable state ownership explicit:** `TransmissionConnection` is an actor and owns token state, retry behavior, and concurrent request coordination for one server.

- **Split the layer by responsibility:**
  - `TransmissionModels.swift`: shared Transmission types such as `TransmissionEndpoint`, credentials, typed errors, and shared domain-neutral models.
  - `TransmissionTransport.swift`: low-level transport only, including request construction, auth headers, session-token handling, retry behavior, raw `URLSession` calls, and JSON encode/decode.
  - `TransmissionConnection.swift`: the owning authenticated connection and entry point for domain operations.
  - `TransmissionTorrents.swift`: torrent-domain operations only, including queries, mutations, file operations, queue actions, peers, and pieces.
  - `TransmissionSession.swift`: session-domain operations only, including `session-get`, `session-stats`, `session-set`, `free-space`, `port-test`, and blocklist operations.

- **Expose domain methods on the owning connection:** Torrent and session APIs live as methods or extensions on `TransmissionConnection`, not as another layer of top-level helper functions.

- **Standardize on an `async throws` domain API:** Remove the current mix of callback APIs, `TransmissionResponse`, `(value?, String?)` patterns, widget-only request variants, and continuation adapters.

- **Model multi-outcome operations explicitly:** Operations such as `torrent-add` return domain results that distinguish outcomes like added vs. duplicate instead of collapsing them into generic success or failure buckets.

- **Use the same client semantics across all contexts:** Main app refresh, settings flows, and widget/background refresh all use the same connection and transport behavior rather than maintaining separate request paths.

- **Keep scheduler lifecycle separate from client semantics:** Foreground polling, iOS background refresh scheduling, and macOS background activity scheduling remain context-specific, but the work they trigger uses the same Transmission transport and domain client behavior rather than widget-only request helpers or alternate retry rules.

- **Keep the client usable from any isolation context:** `TransmissionConnection` is not `@MainActor`-bound; foreground app flows, settings flows, and widget/background refresh can all call it safely from their own isolation contexts.

- **Keep persistence models outside the Transmission boundary:** The Transmission layer accepts plain descriptor and credential inputs rather than depending directly on `Host`, SwiftData models, or widget snapshot persistence types.

- **Define one explicit connection lifecycle for the selected server:** The selected-server store, currently named `AppStore` and scheduled to be renamed to `TransmissionStore` in Phase 3, owns one active `TransmissionConnection` for the selected host plus the app-level lifecycle state associated with it. Host changes, reconnects, and credential changes replace that connection and cancel any polling or in-flight refresh work associated with the old one.

- **Make refresh ownership explicit:** The selected-server store owns the active connection identity or generation token plus the cancellable task or tasks that perform read-side refresh work for that connection. Refresh ownership does not live implicitly inside timers, callbacks, or view helpers.

- **Define one explicit refresh lifecycle:** Read-side refresh work runs through the active connection only, captures the active connection identity when it starts, and applies results only if that identity still matches the current active connection when results are ready. Use one cancellable async polling loop instead of timer-driven callback fan-out. High-frequency polling and session-configuration refresh are separate concerns unless a shared cycle is intentionally justified.

- **Apply read-side results as coherent snapshots:** Polling and refresh paths produce snapshot values for torrents, session stats, and other read-side state, and the selected-server store applies them through one controlled boundary rather than allowing loosely related callbacks to mutate store state independently.

- **Treat reconnect as a lifecycle event, not an incidental retry:** Manual reconnect, automatic retry, host reselection, and credential changes all flow through the same connection-replacement rules so older in-flight work is invalidated consistently even if the selected host record itself has not changed.

- **Preserve one shared app-level error translation boundary:** Typed transport and domain errors are converted into user-facing messages in one shared app-level mapping layer rather than duplicating alert and message logic across views.

- **Introduce the replacement error boundary before removing legacy wrappers:** A shared app-level typed-error translation and compatibility adapter exists before `TransmissionResponse` and other legacy callback result shapes are removed, so caller migration does not push raw transport or domain error handling into views.

- **Centralize shared request field and query definitions:** Shared `torrent-get` field sets and similar request-shape definitions live in one source of truth inside the new Transmission layer so app, widget, and detail flows do not maintain parallel copies.

- **Use named query specifications instead of ad hoc field arrays:** Reusable request-shape definitions are expressed as named Transmission-layer query specs or domain methods that match real use cases, rather than leaving raw string arrays scattered across callers or replacing them with one unstructured constants dump.

## Migration Phases

Each phase migrates a complete slice end-to-end and removes the replaced path in the same phase.

- **Phase 0 - Establish the executable RPC contract:** Add a Transmission-focused test target, introduce the smallest transport seams needed for deterministic tests, add the minimal production contract types needed for those tests, and lock in the correct RPC contract before changing live request semantics.

  **Status:** Complete

  The executable RPC contract, focused Transmission transport tests, and supporting CI coverage for this phase are now in place.

  - Test the correct Transmission contract, not the current buggy behavior.
  - Keep this phase limited to testability seams plus the minimal production contract primitives required for the tests; do not mix in broad production refactors.
  - Introduce a transport-private RPC response envelope that models `result`, `arguments`, and optional `tag`.
  - Introduce the initial shared `TransmissionError` taxonomy that covers the protocol and transport cases Phase 0 and Phase 1 must validate.
  - Cover RPC `result` success and failure handling.
  - Cover HTTP 409 session-token refresh and retry of the same request.
  - Cover HTTP 401 unauthorized handling and token-state clearing.
  - Cover `torrent-add` added vs. duplicate success outcomes.
  - Cover failure propagation so transport and domain errors are not silently converted into empty values or generic success buckets.
  - Cover overlapping requests on one connection so token refresh, cancellation, unauthorized handling, and other per-connection mutable state remain correct under concurrency, not just in single-request flows.
  - Establish the expected mapping from protocol and transport conditions into the typed `TransmissionError` categories, even if the surrounding caller APIs are still legacy-shaped.

- **Phase 1 - Correct the RPC boundary:** Rework the existing request path to use the Phase 0 RPC envelope and `TransmissionError` primitives. Fix RPC `result` handling, status-only success and failure semantics, `torrent-add` duplicate success behavior, and HTTP 409 / 401 handling in the existing boundary, using the Phase 0 contract tests as the acceptance gate for each change.

  **Status:** Complete

  The legacy request path now enforces the corrected RPC contract and passes the focused Transmission contract suite.

  - Keep legacy outward-facing wrappers only as temporary adapters over the corrected envelope and typed error behavior.

- **Phase 2a - Introduce the core client foundation:** Add `TransmissionEndpoint`, `actor TransmissionConnection`, and the transport layer. Move endpoint, auth, and token ownership into that boundary and establish the minimal internal `async throws` client surface needed for migration.

  **Status:** Complete

  The endpoint model, stateless transport, actor-owned connection boundary, and temporary legacy adapter migration path are now in place.

  - Reuse and extend the Phase 0 contract tests while moving behavior into the new client boundary.
  - Preserve deterministic transport injection and token-state testability in the new abstractions.
  - Keep this sub-phase focused on the core client foundation so it does not become a long-lived branch that mixes foundational transport work with broad caller-facing migration setup.

- **Phase 2b - Establish the caller migration surface:** Build the remaining shared client surface needed for caller migration, including query definitions, the shared app-level error translation boundary, compatibility adapters, and the shared connection-construction path used by app-selected hosts, settings flows, and widget/background host snapshots.

  **Status:** Complete

  The shared connection-construction path, named query surface, app-level error translation boundary, and temporary compatibility shims for caller migration are now in place.

  - Establish shared request field and query definitions in the new Transmission layer so subsequent caller migrations reuse one source of truth.
  - Define those shared request shapes as named query specifications or domain-owned methods for real use cases such as torrent summary, widget summary, files, peers, pieces, and session settings.
  - Add the shared app-level typed-error translation boundary and any temporary compatibility adapter needed so caller migrations can leave `TransmissionResponse` behind without duplicating message mapping across views.
  - Introduce the shared connection descriptor and factory path used by app-selected hosts, settings flows, and widget/background host snapshots.
  - Carry forward and refine the Phase 0 `TransmissionError` taxonomy in the new client boundary so callers do not throw ad hoc `NSError` values or unclassified transport errors.

- **Phase 3 - Migrate read-side app and widget flows:** Move polling, refresh, session stats, torrent list, and widget read paths onto the new client. Cover the selected-server store (`AppStore.swift`, renamed to `TransmissionStore.swift` as part of this phase), the Transmission-specific parts of `Utilities.swift`, and `WidgetRefreshOperation.swift`, and delete the read-side helpers those paths replace.
  - Rename `AppStore` to `TransmissionStore` as part of this phase so the selected-server state owner has a Transmission-specific name that matches its responsibility and does not read like StoreKit or App Store infrastructure.
  - Replace `Timer`-driven polling and callback fan-out with an async refresh coordinator owned by the selected-server store.
  - Introduce active-connection identity checks so stale results from superseded refresh work cannot overwrite current store state.
  - Return and apply coherent read snapshots rather than mutating the selected-server store piecemeal from multiple unrelated callbacks.
  - Replace widget/background `DispatchGroup` coordination and background-only request wrappers with shared async client calls using structured concurrency.
  - Keep iOS and macOS scheduling triggers separate, but make the triggered refresh body use the same transport, retry, auth, and decoding semantics as foreground refresh.
  - Propagate cancellation from background task expiration into the in-flight refresh work instead of relying only on outer cancellation flags.
  - Delete widget-only Transmission request entry points once the shared async path is in place.
  - Route user-facing read-path failures through the shared app-level typed-error mapper rather than relying on ad hoc `localizedDescription` handling.
  - Decompose `Utilities.swift` as these migrations land: remove Transmission-specific config, refresh, and legacy error-handling helpers from that file, move any remaining generic sorting or formatting helpers into focused non-Transmission files, and delete `Utilities.swift` once it no longer represents a coherent module boundary.

- **Phase 4 - Migrate settings and session flows:** Move `session-get`, `session-set`, `free-space`, `port-test`, and `blocklist-update` onto the new client. Remove `currentServerInfo` and delete the old settings and session request path in the same phase.
  - Define ordered `session-set` write behavior so overlapping settings saves cannot lose newer pending edits.
  - Wire the selected-server edit flow so saving changes to the currently selected host replaces the active connection immediately instead of leaving `AppStore` on stale cached endpoint or credential state.
  - Remove `AppStore.Server`, the published `server` cache, and `currentServerInfo` as part of this migration so settings flows stop depending on cached config or auth tuples and use the active connection boundary instead.
  - Route settings and session-operation failures through the shared app-level typed-error mapper instead of introducing per-view message mapping.
  - Remove duplicate config/auth caches and connection-construction helpers that are superseded by the shared descriptor/factory path.

- **Phase 5 - Migrate torrent actions and detail flows:** Move torrent mutations, add and remove, rename, set location, file operations, peers, and pieces onto the new client across shared, iOS, and macOS UI paths. Remove `TransmissionResponse`, callback wrappers, and continuation adapters from these flows. Keep `TorrentActionExecutor.swift` only if it still provides meaningful shared UI orchestration after the migration.
  - Remove `TorrentActionExecutor.swift` once the shared typed-error translation boundary is in place unless it still owns meaningful shared UI orchestration such as batching, optimistic updates, refresh triggering, or selection-driven flow coordination; it must not remain as a thin wrapper around `TransmissionConnection` calls or as the primary home of user-facing error mapping.
  - Finish removing `TransmissionResponse` and any temporary compatibility adapters only after caller migrations are using the shared typed-error translation boundary.

- **Phase 6 - Residual cleanup sweep (small and optional):** Remove any remaining dead helper types, leftover compatibility code, or minor call-site remnants that were not worth deleting earlier. This is an intentionally small, optional cleanup pass, not a place to defer major migration work or unresolved architectural decisions.

## Validation Criteria

- **RPC response handling:** Success requires `result == "success"`. HTTP 200 alone is not a successful RPC outcome.

- **Session-token and auth flow:** HTTP 409 updates the session token and retries the same request. HTTP 401 clears cached token or auth state and surfaces an unauthorized failure correctly.

- **`torrent-add` outcomes:** Both `torrent-added` and `torrent-duplicate` are treated as valid success outcomes and surfaced distinctly in the domain API.

- **Failure propagation:** Query and mutation failures surface as errors instead of being silently converted into empty arrays, zero values, or generic success and failure buckets.

- **Typed error classification is stable and consistent:** Equivalent failure conditions map to the same `TransmissionError` categories across app, settings, and widget/background contexts instead of surfacing as inconsistent `NSError` payloads or ad hoc strings.

- **Shared client behavior across contexts:** Main app refresh, settings flows, and widget/background refresh all use the same client and transport semantics.

- **Widget/background refresh uses structured concurrency:** Background refresh paths do not rely on widget-only callback wrappers or blocking `DispatchGroup` waits; they use the shared async client with real cancellation and timeout behavior.

- **Updated server configuration takes effect immediately:** Editing the currently selected server's host or credentials rebuilds the active connection immediately, and subsequent requests use the updated endpoint and credentials without requiring reconnect, reselection, or duplicated state synchronization.

- **Connection construction has one source of truth:** App, settings, and widget/background refresh all use the same descriptor validation, credential resolution, and connection-construction rules instead of maintaining parallel config or auth assembly paths.

- **Endpoint correctness:** Requests derive from one validated endpoint model rather than ad hoc `URLComponents` rebuilding, and the configured RPC path comes from that single source of truth.

- **Refresh correctness across lifecycle changes:** Host switches, reconnects, and credential changes cancel or invalidate older refresh work so stale responses cannot overwrite state owned by the current connection.

- **Refresh ownership is explicit and serialized:** App-level refresh tasks have one owning boundary, use active-connection identity validation, and do not rely on independent timers and callback chains to coordinate correctness.

- **Read snapshots remain coherent:** One refresh cycle cannot mix state from different servers or different connection generations, and read-side store updates are applied through one controlled snapshot boundary rather than piecemeal writes.

- **Per-server state correctness under concurrency:** Concurrent requests for one server share one serialized ownership boundary for token updates, retry behavior, and related mutable connection state.

- **Settings write ordering:** Rapid settings changes do not lose newer edits behind earlier successful `session-set` responses.

- **Automated coverage for the corrected RPC contract:** The transport and client layer includes automated tests for RPC `result` handling, HTTP 409 retry behavior, HTTP 401 unauthorized handling, `torrent-add` success variants, and failure propagation.

- **Tests guard the correct contract, not legacy bugs:** Test coverage serves as an executable specification for the intended Transmission RPC semantics and is established before the first behavior-changing refactor.

- **Typed contract primitives exist before caller migration:** `TransmissionRPCEnvelope` and the initial `TransmissionError` taxonomy are introduced before broad client migration so Phase 0 and Phase 1 can validate the real contract without asserting temporary legacy error shapes.

- **User-facing error handling remains centralized:** Removing `TransmissionResponse` does not scatter transport or domain error interpretation across views; user-facing message mapping remains in one shared app-level boundary.

- **Legacy error-shape removal is sequenced safely:** `TransmissionResponse` and other legacy callback result shapes are removed only after the shared typed-error translation boundary is in place and adopted by migrated callers.

- **Shared request definitions remain centralized:** App, widget, and detail flows reuse one source of truth for shared field sets and request-shape definitions instead of maintaining duplicated query lists.

- **Centralized request definitions remain intentional:** Shared request definitions are organized as named query specs or domain methods for distinct use cases, not as duplicated inline field arrays and not as one oversized catch-all field list.
