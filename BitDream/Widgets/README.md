## BitDream Widgets – Architecture and Behavior

### Overview
- A single WidgetKit extension (iOS + macOS) renders SwiftUI views.
- Widgets are configuration-driven via App Intents, allowing the user to select a server per widget instance.
- Data is supplied from the host app through a lightweight snapshot written to a shared App Group container.

### Key Components
- App Group: `group.crapshack.BitDream`
  - Shared container for widget snapshots and a server index file.
  - No credentials are stored in the widget extension.
- App Intents
  - `ServerEntity` exposes servers to the widget’s configuration UI.
  - `SessionOverviewIntent` stores the per-widget server selection.
- Snapshot IO (App-side)
  - Writers live in `BitDream/Widgets/ServerSnapshotIO.swift`.
  - Files:
    - `servers.json`: list of available servers for the picker.
    - `session_<hash>.json`: per-server snapshot consumed by the widget.

### Data Flow
1) App (Store) refreshes Transmission state on a timer (macOS: always while app runs; iOS: when in foreground or BG task wakes).
2) After refresh, the app writes a JSON snapshot to the App Group.
3) The widget provider reads the snapshot at render time and constructs the view.
4) The app nudges WidgetKit via `WidgetCenter.reloadTimelines(ofKind:)` after writing.

### Update Strategy
- Timeline policy: `.after(now + X minutes)` to align with WidgetKit guidance on budgeting and predictable refreshes.
- Reload triggers:
  - Host app writes a new snapshot (foreground updates).
  - iOS Background Tasks periodically wake the app to refresh and write snapshots.
  - User edits the widget’s configuration (server selection) → WidgetKit requests a new timeline.

### iOS Background Refresh (by the book)
- Capability: Background Modes → Background fetch (enabled on iOS target).
- Scheduler: `BGTaskScheduler` with identifier `crapshack.BitDream.refresh`.
- Flow:
  - Register on app launch.
  - Schedule on launch and when entering background.
  - Handler fetches latest state per saved server, writes snapshots, then calls `WidgetCenter.reloadTimelines`.
- Budget: Respects system-controlled reload budgets; cadence targeted at ~15–30 minutes but ultimately governed by iOS.

### macOS Behavior
- Uses the app’s existing refresh loop to keep snapshots current while the app is running.
- No BGTaskScheduler on macOS; if true background/launch-at-login behavior is needed, integrate a login item helper separately.

### Security Model
- The widget extension never handles credentials.
- Only sanitized, minimal snapshot data is read by the extension from the App Group.
- All network I/O occurs in the host app process.

### Configuration
- App Group must be enabled for:
  - iOS app target
  - macOS app target
  - Widget extension target
- iOS only: Add `BGTaskSchedulerPermittedIdentifiers` to Info.plist with `crapshack.BitDream.refresh`.
 - macOS widget extension: Enable App Sandbox capability (required for the extension to load/show on macOS).

### Performance and Budgeting
- Keep snapshot files small and writes atomic.
- Avoid excessive `WidgetCenter.reload…` calls; coalesce reloads where possible.
- Timeline intervals should be ≥ 5 minutes; WidgetKit may adjust scheduling based on usage.

### Testing
- iOS: Xcode → Debug → Simulate Background Fetch to validate BG task execution and widget updates.
- Verify the App Group container path returns a valid URL in both app and extension.
- Use Widget Previews for layout across supported families (small/medium).
- Deep links: Tap the widget to open BitDream directly to the selected server.

### Error Tolerance
- If a snapshot is missing or unreadable, the widget presents a configuration prompt rather than failing.
- Network errors are contained to the host app; the widget never performs network requests.

### Extensibility
- Additional widget families/screens can reuse the same snapshot mechanism.
- To add more configuration parameters, extend the App Intent and persist those values as part of the widget’s configuration only (not in the snapshot).

### Deep Linking
- Scheme: `bitdream://`
- Builder: `DeepLinkBuilder.serverURL(serverId:)` in `BitDream/AppConfig.swift`.
- Widget: `.widgetURL(DeepLinkBuilder.serverURL(serverId: snap.serverId))` per entry.
- App handling: `BitDreamApp` uses `.onOpenURL` to parse `bitdream://server?id=<coredata-URI>`, resolves the `Host` by URI, and calls `store.setHost(host:)` to navigate.
- Benefit: Each widget instance opens directly to its configured server.

### Source of Truth
- The app (Store + BackgroundRefreshManager on iOS) is the sole producer of widget data.
- The widget is a pure consumer, with read-only access to the App Group files.

### Known gaps / next steps
- macOS background updates when the app isn’t running are not implemented.
  - Option A: add `NSBackgroundActivityScheduler` to coalesce refreshes while the app is open but idle.
  - Option B: add a Login Item helper (`SMAppService`) to refresh when the app is closed.
- No WidgetKit push notifications. Current strategy relies on timelines + app-triggered reloads.
- iOS BG hygiene: we don’t cancel existing BG requests before scheduling a new one; consider `BGTaskScheduler.shared.cancelAllTaskRequests()` (or per-identifier cancellation) before submit.
- Reload coalescing: `WidgetCenter.reloadTimelines` is called after each snapshot write; add throttling and `getCurrentConfigurations` checks to reload only when a matching configuration exists.
- Timeline relevance: `relevance()` not implemented; adding relevance improves Smart Stack surfacing.
- “Last updated” affordance: not shown; consider a compact timestamp label instead of any iconography.
- Provider networking: widget extension intentionally performs no network I/O; alternative is self-fetch with Keychain sharing and careful budgeting.


