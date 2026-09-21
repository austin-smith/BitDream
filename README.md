<h1 align="center">
  <img src="BitDream/Assets.xcassets/AppIconPreview-Default.imageset/BitDreamAppIconDefault-iOS-Default-60x60@3x.png" width="128" height="128" alt="BitDream Icon">
  <br><span style="font-family: monospace;">BitDream</span>
</h1>

BitDream is a native and feature-rich remote control client for Transmission web server. It provides a modern, seamless interface to manage your Transmission server from anywhere.

<p align="center">
  <img src="./docs/screenshots/screen-grab-light.png" alt="Light mode" width="49%" />
  <img src="./docs/screenshots/screen-grab-dark.png" alt="Dark mode" width="49%" />
</p>

## Features

- Fully native apps for both macOS and iOS
- Remote management of Transmission server
- Real-time torrent status monitoring
- Add, remove, and manage torrents remotely
- View detailed torrent information and statistics
- Secure connection to Transmission's RPC interface
- Built-in Tailscale integration for private connections to your Transmission servers

## Tailscale

Sign in to Tailscale directly in BitDream on macOS and iOS. When adding or editing a server, choose **Tailscale** under **Connect using**, sign in, and select a machine.

Your Transmission server must already be accessible through Tailscale, with remote access (RPC) enabled.

## About Transmission

[Transmission](https://transmissionbt.com/) is a fast, easy, and free BitTorrent client for macOS, Windows, and Linux.

BitDream connects to Transmission's RPC (Remote Procedure Call) interface, allowing you to control your Transmission server from anywhere. For more information about Transmission's RPC specification, see the [official documentation](https://github.com/transmission/transmission/blob/main/docs/rpc-spec.md).
