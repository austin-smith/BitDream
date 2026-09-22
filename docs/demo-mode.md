# Demo mode

Select **BitDreamDemo** in Xcode and Run on macOS or an iOS simulator. The app
opens with seven sample torrents on **Demo Server**. No server or
internet connection is required.

The library defaults to Date Added, newest first, with Mozart at the top.

Demo data and preferences are separate from your real setup. Relaunching resets
servers and torrents but preserves demo preferences. Select **BitDream** to
return to real servers.

If macOS launches without a window, choose **Window → BitDream (Dev)**.

## Servers

Select a server from the normal server list:

| Server | Behavior |
| --- | --- |
| Demo Server (default) | Seven sample torrents, with matching files and peers |
| Remote Server | Connection fails with an authentication error |

To see an empty library, remove all torrents from Demo Server. Relaunch to reset.

## Interactions and limits

Pause/resume, remove, rename, move, labels, queue order, file selection, file
priorities, and session settings last until relaunch. File operations never touch
disk. Progress and rates do not advance; resumed transfers remain at zero speed.
Verify stays in the verifying state. Reannounce leaves torrent state unchanged.
Network diagnostics return fixed sample responses.

To exercise Add Torrent, paste this sample magnet:

```text
magnet:?xt=urn:btih:0000000000000000000000000000000000000008
```

This creates a dummy torrent named **Sintel**, an animated short film by the
Blender Foundation. No files are downloaded. Submit it again to test duplicate
torrent handling.

Arbitrary URLs and torrent files are rejected.

## Update sample data

Demo mode and previews share these sources:

- `BitDream/Widgets/SampleLibrary.swift`: torrent data, server identity, and
  widget snapshots.
- `BitDream/SampleSupport/SampleFixtures.swift`: torrent details, files, and peers.
- `BitDream/SampleSupport/SampleSessionSettings.swift`: server settings.
- `BitDream/SampleSupport/SampleTransmissionServer.swift`: simulated actions and
  responses. New RPC requests need sample behavior and regression tests;
  unsupported requests return errors.
