## BitDream Widgets – Architecture and Behavior

### Overview
- A single WidgetKit extension (iOS + macOS) renders SwiftUI views.
- Widgets are configuration-driven via App Intents, allowing the user to select a server per widget instance.
- Data is supplied from the host app through a lightweight snapshot written to a shared App Group container.

### Key Components
- App Group: `group.com.crapshack.BitDream`
  - Shared container for widget snapshots and a server index file.
  - No credentials are stored in the widget extension.
- App Intents
  - `ServerEntity` exposes servers to the widget’s configuration UI.
  - `SessionOverviewIntent` stores the per-widget server selection.
- Snapshot IO (App-side)
  - Writers live in `BitDream/Widgets/DataWriter.swift` and `AppGroup.swift`.
  - Files:
    - `servers.json`: list of available servers for the picker.
    - `session_<hash>.json`: per-server snapshot consumed by the widget.

### Data Flow
1) `TransmissionStore` supplies snapshots from normal app polling. Background schedulers independently use `WidgetRefreshRunner` to fetch saved servers through the host-only refresh catalog.
2) After refresh, the app writes a JSON snapshot to the App Group.
3) The widget provider reads the snapshot at render time and constructs the view.
4) The app nudges WidgetKit via `WidgetCenter.reloadTimelines(ofKind:)` after writing.

### Update Strategy
- Timeline policy: `.after(now + X minutes)` to align with WidgetKit guidance on budgeting and predictable refreshes.
- Reload triggers:
  - Host app writes a new snapshot (foreground updates).
  - iOS may launch or resume the app for a scheduled background refresh, which fetches fresh data and writes snapshots.
  - User edits the widget’s configuration (server selection) → WidgetKit requests a new timeline.

### iOS Background Refresh

- The host app declares `UIBackgroundModes = [fetch]` and `BGTaskSchedulerPermittedIdentifiers = [$(PRODUCT_BUNDLE_IDENTIFIER).refresh]` in `BitDream/Info.plist`. These iOS settings share the direct app's plist with macOS; the macOS App Store target uses its separate plist. The widget extension does not register or execute background tasks.
- `BitDreamApp.init` registers the launch handler synchronously, before app launch completes. Registration failures are logged.
- The app submits a request after startup bootstrap and when its scene enters the background. The launch handler submits the next request before fetching data.
- Submission uses the completion-handler API on iOS 27 and the synchronous API on iOS 26. Submitting the same identifier replaces the pending request; no separate cancellation is needed. Submission results are logged under the `backgroundRefresh` category.
- The requested earliest start is 15 minutes later. This is a lower bound, **not a refresh interval or deadline**. iOS can defer execution for hours or decline it entirely based on settings, usage, and system conditions. WidgetKit separately controls when a requested timeline reload appears.
- A refresh loads saved host descriptors, obtains credentials in the host app, and fetches each server with a 15-second timeout. Network failures preserve that server's previous snapshot; other servers are still attempted. Successful session stats can be saved even if the torrent summary request fails.
- Snapshots replace their previous files atomically. A completed batch requests one timeline reload. Expiration cancels queued or active refresh work and reports failure; the task completion guard prevents duplicate completion. Cancelled work skips subsequent snapshot writes and the batch reload.
- Credentials use Keychain accessibility after first unlock. Test locked-device operation after unlocking once following a reboot. Background App Refresh must be enabled, and the app must have been opened to save its server configuration. Force-quitting the app prevents normal background launches until the user opens it again.

Apple references: [background task setup](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app), [BGAppRefreshTask requirements](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask), [iOS 27 submission API](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/submittaskrequest(_:completionhandler:)), and [Apple's clarification that submission supports any thread](https://developer.apple.com/forums/thread/840876).

### macOS Behavior
- Uses the app's existing refresh loop to keep snapshots current while the app is running.
- NSBackgroundActivityScheduler continues updates when app is minimized/hidden (15 minute intervals).
- Background scheduler respects system power management and coordinates with user poll interval settings.
- No updates when app is completely quit; requires Login Item helper for that functionality.

### Security Model
- The widget extension never handles credentials.
- Only sanitized, minimal snapshot data is read by the extension from the App Group.
- All network I/O occurs in the host app process.

### Configuration
- App Group must be enabled for:
  - iOS app target
  - macOS app target
  - Widget extension target
- iOS only: Add `BGTaskSchedulerPermittedIdentifiers` to Info.plist with `com.crapshack.BitDream.refresh`.
 - macOS widget extension: Enable App Sandbox capability (required for the extension to load/show on macOS).

### Performance and Budgeting
- Keep snapshot files small and writes atomic.
- Avoid excessive `WidgetCenter.reload…` calls; coalesce reloads where possible.
- Timeline intervals should be ≥ 5 minutes; WidgetKit may adjust scheduling based on usage.

### Testing

- The iOS CI job uses GitHub's `xcode-27` runner because the new submission API requires the iOS 27 SDK. macOS jobs keep their existing runner.
- `WidgetRefreshOperationTests` covers snapshot production, timeout behavior, partial network failure, one reload per batch, serialized refreshes, and cancellation of active and queued work.
- Verify App Group access from both the host app and widget extension. Use Widget Previews for supported layouts.

#### Physical-device background task checks

Apple's [development task simulation](https://developer.apple.com/documentation/backgroundtasks/starting-and-terminating-tasks-during-development) works on physical devices. Xcode's legacy **Simulate Background Fetch** command does not exercise this `BGTaskScheduler` handler.

1. Build with Xcode 27 or later and run on an iPhone. Add a reachable server, open the app once, and configure a widget for it. Check `backgroundRefresh` logs for successful submission and verify the pending request identifier is `com.crapshack.BitDream.refresh`.
2. Set a breakpoint after successful submission in `logSubmission(error:)`. Use Apple's debugger-only command, then resume:

   ```text
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.crapshack.BitDream.refresh"]
   ```

3. Verify that the launch handler runs, requests its successor, writes fresh session JSON in the shared App Group, requests a timeline reload, and completes once. The JSON timestamp is the direct freshness check; WidgetKit may defer the visible reload.
4. With a slow or unreachable server, break after `expirationHandler` is installed and simulate expiration, then resume:

   ```text
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"com.crapshack.BitDream.refresh"]
   ```

   Confirm cancellation, one unsuccessful completion, and no subsequent snapshot write or batch reload from that cancelled refresh.
5. Test an offline server alongside a reachable one, no saved servers, and Background App Refresh disabled. Verify existing snapshots survive failures and submission errors are logged without crashing.
6. Finally, run without the debugger, background the app normally, and verify a later refresh on a locked device after first unlock. Repeat on iOS 26 and 27 to cover both submission APIs. Natural execution is system-controlled; debugger simulation proves the handler, not an execution cadence.

The private simulation selectors above belong only in the debugger. Never add them to app code.

### Error Tolerance
- If a snapshot is missing or unreadable, the widget presents a configuration prompt rather than failing.
- Network errors are contained to the host app; the widget never performs network requests.

### Extensibility
- Additional widget families/screens can reuse the same snapshot mechanism.
- To add more configuration parameters, extend the App Intent and persist those values as part of the widget’s configuration only (not in the snapshot).

### Deep Linking
- Scheme: `bitdream://`
- Builder: `DeepLinkBuilder.serverURL(serverId:)` in `BitDream/Widgets/WidgetKitBridge.swift`.
- Widget: `.widgetURL(DeepLinkBuilder.serverURL(serverId: snap.serverId))` per entry.
- App handling: `BitDreamApp` uses `.onOpenURL` to parse `bitdream://server?id=<coredata-URI>`, resolves the `Host` by URI, and calls `store.setHost(host:)` to navigate.
- Benefit: Each widget instance opens directly to its configured server.

### Source of Truth
- The app (TransmissionStore + BackgroundRefreshManager on iOS) is the sole producer of widget data.
- The widget is a pure consumer, with read-only access to the App Group files.
- Provider networking: widget extension intentionally performs no network I/O (by design).

### Background Refresh Roadmap (Hybrid Approach)

**Phase 1 (DONE)**: NSBackgroundActivityScheduler
- macOS widgets update when app is minimized/hidden
- Shared refresh logic between iOS and macOS

**Phase 2**: Login Item Helper
- macOS widgets update even when app is quit
- Uses SMAppService, reuses existing refresh logic
- User-controlled via settings

**Phase 3**: Background Refresh Optimization
- Reload coalescing: Check `getCurrentConfigurations` before reloading
- Network reachability checks before attempting refresh

### Known gaps / next steps
- macOS background updates when the app isn't running (Phase 2 of roadmap addresses this)
- Reload coalescing: `WidgetCenter.reloadTimelines` called after each snapshot write
- Timeline relevance: `relevance()` not implemented; affects Smart Stack surfacing
- "Last updated" affordance: not shown; consider compact timestamp label
- Provider networking: widget extension intentionally performs no network I/O

