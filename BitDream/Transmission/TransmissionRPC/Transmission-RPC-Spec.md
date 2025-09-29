# Transmission's RPC specification

> Source: [Transmission RPC spec](https://github.com/transmission/transmission/blob/main/docs/rpc-spec.md)
>
> Last synced: 2025-09-28

This document describes a protocol for interacting with Transmission sessions remotely.

See example responses in `BitDream/Transmission/TransmissionRPC/Examples/`.

### 1.1 Terminology
The [JSON](https://www.json.org/) terminology in [RFC 4627](https://datatracker.ietf.org/doc/html/rfc4627) is used.
RPC requests and responses are formatted in JSON.

### 1.2 Tools
If `transmission-remote` is called with a `--debug` argument, its RPC traffic to the Transmission server will be dumped to the terminal. This can be useful when you want to compare requests in your application to another for reference.

If `transmission-qt` is run with an environment variable `TR_RPC_VERBOSE` set, it too will dump the RPC requests and responses to the terminal for inspection.

Lastly, using the browser's developer tools in the Transmission web client is always an option.

### 1.3 Libraries of ready-made wrappers
Some people outside of the Transmission project have written libraries that wrap this RPC API. These aren't supported by the Transmission project, but are listed here in the hope that they may be useful:

| Language | Link
|:---|:---
| C# | https://www.nuget.org/packages/Transmission.API.RPC
| Go | https://github.com/hekmon/transmissionrpc
| Python | https://github.com/Trim21/transmission-rpc
| Rust | https://crates.io/crates/transmission-rpc


## 2 Message format
Messages are formatted as objects. There are two types: requests (described in [section 2.1](#21-requests)) and responses (described in [section 2.2](#22-responses)).

All text **must** be UTF-8 encoded.

### 2.1 Requests
Requests support three keys:

1. A required `method` string telling the name of the method to invoke
2. An optional `arguments` object of key/value pairs. The keys allowed are defined by the `method`.
3. An optional `tag` number used by clients to track responses. If provided by a request, the response MUST include the same tag.

```json
{
   "arguments": {
     "fields": [
       "version"
     ]
   },
   "method": "session-get",
   "tag": 912313
}
```


### 2.2 Responses
Responses to a request will include:

1. A required `result` string whose value MUST be `success` on success, or an error string on failure.
2. An optional `arguments` object of key/value pairs. Its keys contents are defined by the `method` and `arguments` of the original request.
3. An optional `tag` number as described in 2.1.

```json
{
   "arguments": {
      "version": "2.93 (3c5870d4f5)"
   },
   "result": "success",
   "tag": 912313
}
```

### 2.3 Transport mechanism
HTTP POSTing a JSON-encoded request is the preferred way of communicating
with a Transmission RPC server. The current Transmission implementation
has the default URL as `http://host:9091/transmission/rpc`. Clients
may use this as a default, but should allow the URL to be reconfigured,
since the port and path may be changed to allow mapping and/or multiple
daemons to run on a single server.

#### 2.3.1 CSRF protection
Most Transmission RPC servers require a `X-Transmission-Session-Id`
header to be sent with requests, to prevent CSRF attacks.

When your request has the wrong id -- such as when you send your first
request, or when the server expires the CSRF token -- the
Transmission RPC server will return an HTTP 409 error with the
right `X-Transmission-Session-Id` in its own headers.

So, the correct way to handle a 409 response is to update your
`X-Transmission-Session-Id` and to resend the previous request.

#### 2.3.2 DNS rebinding protection
Additional check is being made on each RPC request to make sure that the
client sending the request does so using one of the allowed hostnames by
which RPC server is meant to be available.

If host whitelisting is enabled (which is true by default), Transmission
inspects the `Host:` HTTP header value (with port stripped, if any) and
matches it to one of the whitelisted names. Regardless of host whitelist
content, `localhost` and `localhost.` domain names as well as all the IP
addresses are always implicitly allowed.

For more information on configuration, see settings.json documentation for
`rpc-host-whitelist-enabled` and `rpc-host-whitelist` keys.

#### 2.3.3 Authentication
Enabling authentication is an optional security feature that can be enabled
on Transmission RPC servers. Authentication occurs by method of HTTP Basic
Access Authentication.

If authentication is enabled, Transmission inspects the `Authorization:`
HTTP header value to validate the credentials of the request. The value
of this HTTP header is expected to be [`Basic <b64 credentials>`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Authorization#basic),
where <b64 credentials> is equal to a base64 encoded string of the
username and password (respectively), separated by a colon.

## 3 Torrent requests
### 3.1 Torrent action requests
| Method name          | libtransmission function | Description
|:--|:--|:--
| `torrent-start`      | tr_torrentStart          | start torrent
| `torrent-start-now`  | tr_torrentStartNow       | start torrent disregarding queue position
| `torrent-stop`       | tr_torrentStop           | stop torrent
| `torrent-verify`     | tr_torrentVerify         | verify torrent
| `torrent-reannounce` | tr_torrentManualUpdate   | re-announce to trackers now

Request arguments: `ids`, which specifies which torrents to use.
All torrents are used if the `ids` argument is omitted.

`ids` should be one of the following:

1. an integer referring to a torrent id
2. a list of torrent id numbers, SHA1 hash strings, or both
3. a string, `recently-active`, for recently-active torrents

Note that integer torrent ids are not stable across Transmission daemon
restarts. Use torrent hashes if you need stable ids.

Response arguments: none

### 3.2 Torrent mutator: `torrent-set`
Method name: `torrent-set`

Request arguments:

| Key | Value Type | Value Description
|:--|:--|:--
| `bandwidthPriority`   | number   | this torrent's bandwidth tr_priority_t
| `downloadLimit`       | number   | maximum download speed (KBps)
| `downloadLimited`     | boolean  | true if `downloadLimit` is honored
| `files-unwanted`      | array    | indices of file(s) to not download
| `files-wanted`        | array    | indices of file(s) to download
| `group`               | string   | The name of this torrent's bandwidth group
| `honorsSessionLimits` | boolean  | true if session upload limits are honored
| `ids`                 | array    | torrent list, as described in 3.1
| `labels`              | array    | array of string labels
| `location`            | string   | new location of the torrent's content
| `peer-limit`          | number   | maximum number of peers
| `priority-high`       | array    | indices of high-priority file(s)
| `priority-low`        | array    | indices of low-priority file(s)
| `priority-normal`     | array    | indices of normal-priority file(s)
| `queuePosition`       | number   | position of this torrent in its queue [0...n)
| `seedIdleLimit`       | number   | torrent-level number of minutes of seeding inactivity
| `seedIdleMode`        | number   | which seeding inactivity to use. See tr_idlelimit
| `seedRatioLimit`      | double   | torrent-level seeding ratio
| `seedRatioMode`       | number   | which ratio to use. See tr_ratiolimit
| `sequential_download` | boolean  | download torrent pieces sequentially
| `trackerAdd`          | array    | **DEPRECATED** use trackerList instead
| `trackerList`         | string   | string of announce URLs, one per line, and a blank line between [tiers](https://www.bittorrent.org/beps/bep_0012.html).
| `trackerRemove`       | array    | **DEPRECATED** use trackerList instead
| `trackerReplace`      | array    | **DEPRECATED** use trackerList instead
| `uploadLimit`         | number   | maximum upload speed (KBps)
| `uploadLimited`       | boolean  | true if `uploadLimit` is honored

Just as an empty `ids` value is shorthand for "all ids", using an empty array
for `files-wanted`, `files-unwanted`, `priority-high`, `priority-low`, or
`priority-normal` is shorthand for saying "all files".

   Response arguments: none

### 3.3 Torrent accessor: `torrent-get`
Method name: `torrent-get`.

Request arguments:

1. An optional `ids` array as described in 3.1.
2. A required `fields` array of keys. (see list below)
3. An optional `format` string specifying how to format the
   `torrents` response field. Allowed values are `objects`
   (default) and `table`. (see "Response arguments" below)

Response arguments:

1. A `torrents` array.

   If the `format` request was `objects` (default), `torrents` will
   be an array of objects, each of which contains the key/value
   pairs matching the request's `fields` arg. This was the only
   format before Transmission 3 and has some obvious programmer
   conveniences, such as parsing directly into Javascript objects.

   If the format was `table`, then `torrents` will be an array of
   arrays. The first row holds the keys and each remaining row holds
   a torrent's values for those keys. This format is more efficient
   in terms of JSON generation and JSON parsing.

2. If the request's `ids` field was `recently-active`,
   a `removed` array of torrent-id numbers of recently-removed
   torrents.

Note: For more information on what these fields mean, see the comments
in [libtransmission/transmission.h](../libtransmission/transmission.h).
The 'source' column here corresponds to the data structure there.

| Key | Value Type | transmission.h source
|:--|:--|:--
| `activityDate` | number | tr_stat
| `addedDate` | number | tr_stat
| `availability` | array (see below)| tr_torrentAvailability()
| `bandwidthPriority` | number | tr_priority_t
| `comment` | string | tr_torrent_view
| `corruptEver`| number | tr_stat
| `creator`| string | tr_torrent_view
| `dateCreated`| number| tr_torrent_view
| `desiredAvailable`| number| tr_stat
| `doneDate`| number | tr_stat
| `downloadDir` | string  | tr_torrent
| `downloadedEver` | number  | tr_stat
| `downloadLimit` | number  | tr_torrent
| `downloadLimited` | boolean | tr_torrent
| `editDate` | number | tr_stat
| `error` | number | tr_stat
| `errorString` | string | tr_stat
| `eta` | number | tr_stat
| `etaIdle` | number | tr_stat
| `file-count` | number | tr_info
| `files`| array (see below)| n/a
| `fileStats`| array (see below)| n/a
| `group`| string| n/a
| `hashString`| string| tr_torrent_view
| `haveUnchecked`| number| tr_stat
| `haveValid`| number| tr_stat
| `honorsSessionLimits`| boolean| tr_torrent
| `id` | number | tr_torrent
| `isFinished` | boolean| tr_stat
| `isPrivate` | boolean| tr_torrent
| `isStalled` | boolean| tr_stat
| `labels` | array of strings | tr_torrent
| `leftUntilDone` | number| tr_stat
| `magnetLink` | string| n/a
| `manualAnnounceTime` | number| tr_stat
| `maxConnectedPeers` | number| tr_torrent
| `metadataPercentComplete` | double| tr_stat
| `name` | string| tr_torrent_view
| `peer-limit` | number| tr_torrent
| `peers` | array (see below)| n/a
| `peersConnected` | number| tr_stat
| `peersFrom` | object (see below)| n/a
| `peersGettingFromUs` | number| tr_stat
| `peersSendingToUs` | number| tr_stat
| `percentComplete` | double | tr_stat
| `percentDone` | double | tr_stat
| `pieces` | string (see below)| tr_torrent
| `pieceCount`| number| tr_torrent_view
| `pieceSize`| number| tr_torrent_view
| `priorities`| array (see below)| n/a
| `primary-mime-type`| string| tr_torrent
| `queuePosition`| number| tr_stat
| `rateDownload` (B/s)| number| tr_stat
| `rateUpload` (B/s)| number| tr_stat
| `recheckProgress`| double| tr_stat
| `secondsDownloading`| number| tr_stat
| `secondsSeeding`| number| tr_stat
| `seedIdleLimit`| number| tr_torrent
| `seedIdleMode`| number| tr_inactivelimit
| `seedRatioLimit`| double| tr_torrent
| `seedRatioMode`| number| tr_ratiolimit
| `sequential_download`| boolean| tr_torrent
| `sizeWhenDone`| number| tr_stat
| `startDate`| number| tr_stat
| `status`| number (see below)| tr_stat
| `trackers`| array (see below)| n/a
| `trackerList` | string | string of announce URLs, one per line, with a blank line between tiers
| `trackerStats`| array (see below)| n/a
| `totalSize`| number| tr_torrent_view
| `torrentFile`| string| tr_info
| `uploadedEver`| number| tr_stat
| `uploadLimit`| number| tr_torrent
| `uploadLimited`| boolean| tr_torrent
| `uploadRatio`| double| tr_stat
| `wanted`| array (see below)| n/a
| `webseeds`| array of strings | tr_tracker_view
| `webseedsSendingToUs`| number| tr_stat

`availability`: An array of `pieceCount` numbers representing the number of connected peers that have each piece, or -1 if we already have the piece ourselves.

`files`: array of objects, each containing:

| Key | Value Type | transmission.h source
|:--|:--|:--
| `bytesCompleted` | number | tr_file_view
| `length` | number | tr_file_view
| `name` | string | tr_file_view
| `begin_piece` | number | tr_file_view
| `end_piece` | number | tr_file_view

Files are returned in the order they are laid out in the torrent. References to "file indices" throughout this specification should be interpreted as the position of the file within this ordering, with the first file bearing index 0.

`fileStats`: a file's non-constant properties. An array of `tr_info.filecount` objects, in the same order as `files`, each containing:

| Key | Value Type | transmission.h source
|:--|:--|:--
| `bytesCompleted` | number | tr_file_view
| `wanted` | boolean | tr_file_view (**Note:** Not to be confused with `torrent-get.wanted`, which is an array of 0/1 instead of boolean)
| `priority` | number | tr_file_view

`peers`: an array of objects, each containing:

| Key | Value Type | transmission.h source
|:--|:--|:--
| `address`            | string     | tr_peer_stat
| `clientName`         | string     | tr_peer_stat
| `clientIsChoked`     | boolean    | tr_peer_stat
| `clientIsInterested` | boolean    | tr_peer_stat
| `flagStr`            | string     | tr_peer_stat
| `isDownloadingFrom`  | boolean    | tr_peer_stat
| `isEncrypted`        | boolean    | tr_peer_stat
| `isIncoming`         | boolean    | tr_peer_stat
| `isUploadingTo`      | boolean    | tr_peer_stat
| `isUTP`              | boolean    | tr_peer_stat
| `peerIsChoked`       | boolean    | tr_peer_stat
| `peerIsInterested`   | boolean    | tr_peer_stat
| `port`               | number     | tr_peer_stat
| `progress`           | double     | tr_peer_stat
| `rateToClient` (B/s) | number     | tr_peer_stat
| `rateToPeer` (B/s)   | number     | tr_peer_stat

`peersFrom`: an object containing:

| Key | Value Type | transmission.h source
|:--|:--|:--
| `fromCache`    | number     | tr_stat
| `fromDht`      | number     | tr_stat
| `fromIncoming` | number     | tr_stat
| `fromLpd`      | number     | tr_stat
| `fromLtep`     | number     | tr_stat
| `fromPex`      | number     | tr_stat
| `fromTracker`  | number     | tr_stat


`pieces`: A bitfield holding pieceCount flags which are set to 'true' if we have the piece matching that position. JSON doesn't allow raw binary data, so this is a base64-encoded string. (Source: tr_torrent)

`priorities`: An array of `tr_torrentFileCount()` numbers. Each is the `tr_priority_t` mode for the corresponding file.

`status`: A number between 0 and 6, where:

| Value | Meaning
|:--|:--
| 0 | Torrent is stopped
| 1 | Torrent is queued to verify local data
| 2 | Torrent is verifying local data
| 3 | Torrent is queued to download
| 4 | Torrent is downloading
| 5 | Torrent is queued to seed
| 6 | Torrent is seeding


`trackers`: array of objects, each containing:

| Key | Value Type | transmission.h source
|:--|:--|:--
| `announce` | string | tr_tracker_view
| `id` | number | tr_tracker_view
| `scrape` | string | tr_tracker_view
| `sitename` | string | tr_tracker_view
| `tier` | number | tr_tracker_view

`trackerStats`: array of objects, each containing:

| Key | Value Type | transmission.h source
|:--|:--|:--
| `announce`                | string     | tr_tracker_view
| `announceState`           | number     | tr_tracker_view
| `downloadCount`           | number     | tr_tracker_view
| `hasAnnounced`            | boolean    | tr_tracker_view
| `hasScraped`              | boolean    | tr_tracker_view
| `host`                    | string     | tr_tracker_view
| `id`                      | number     | tr_tracker_view
| `isBackup`                | boolean    | tr_tracker_view
| `lastAnnouncePeerCount`   | number     | tr_tracker_view
| `lastAnnounceResult`      | string     | tr_tracker_view
| `lastAnnounceStartTime`   | number     | tr_tracker_view
| `lastAnnounceSucceeded`   | boolean    | tr_tracker_view
| `lastAnnounceTime`        | number     | tr_tracker_view
| `lastAnnounceTimedOut`    | boolean    | tr_tracker_view
| `lastScrapeResult`        | string     | tr_tracker_view
| `lastScrapeStartTime`     | number     | tr_tracker_view
| `lastScrapeSucceeded`     | boolean    | tr_tracker_view
| `lastScrapeTime`          | number     | tr_tracker_view
| `lastScrapeTimedOut`      | boolean    | tr_tracker_view
| `leecherCount`            | number     | tr_tracker_view
| `nextAnnounceTime`        | number     | tr_tracker_view
| `nextScrapeTime`          | number     | tr_tracker_view
| `scrape`                  | string     | tr_tracker_view
| `scrapeState`             | number     | tr_tracker_view
| `seederCount`             | number     | tr_tracker_view
| `sitename`                | string     | tr_tracker_view
| `tier`                    | number     | tr_tracker_view


`wanted`: An array of `tr_torrentFileCount()` 0/1, 1 (true) if the corresponding file is to be downloaded. (Source: `tr_file_view`)

**Note:** For backwards compatibility, in `4.x.x`, `wanted` is serialized as an array of `0` or `1` that should be treated as booleans.
This will be fixed in `5.0.0` to return an array of booleans.

Example:

Say we want to get the name and total size of torrents #7 and #10.

Request:

```json
{
   "arguments": {
       "fields": [ "id", "name", "totalSize" ],
       "ids": [ 7, 10 ]
   },
   "method": "torrent-get",
   "tag": 39693
}
```

Response:

```json
{
   "arguments": {
      "torrents": [
         {
             "id": 10,
             "name": "Fedora x86_64 DVD",
             "totalSize": 34983493932
         },
         {
             "id": 7,
             "name": "Ubuntu x86_64 DVD",
             "totalSize": 9923890123
         }
      ]
   },
   "result": "success",
   "tag": 39693
}
```

### 3.4 Adding a torrent
Method name: `torrent-add`

Request arguments:

| Key | Value Type | Description
|:--|:--|:--
| `cookies`             | string    | pointer to a string of one or more cookies.
| `download-dir`        | string    | path to download the torrent to
| `filename`            | string    | filename or URL of the .torrent file
| `labels`              | array     | array of string labels
| `metainfo`            | string    | base64-encoded .torrent content
| `paused`              | boolean   | if true, don't start the torrent
| `peer-limit`          | number    | maximum number of peers
| `bandwidthPriority`   | number    | torrent's bandwidth tr_priority_t
| `files-wanted`        | array     | indices of file(s) to download
| `files-unwanted`      | array     | indices of file(s) to not download
| `priority-high`       | array     | indices of high-priority file(s)
| `priority-low`        | array     | indices of low-priority file(s)
| `priority-normal`     | array     | indices of normal-priority file(s)
| `sequential_download` | boolean   | download torrent pieces sequentially

Either `filename` **or** `metainfo` **must** be included. All other arguments are optional.

The format of the `cookies` should be `NAME=CONTENTS`, where `NAME` is the cookie name and `CONTENTS` is what the cookie should contain. Set multiple cookies like this: `name1=content1; name2=content2;` etc. See [libcurl documentation](http://curl.haxx.se/libcurl/c/curl_easy_setopt.html#CURLOPTCOOKIE) for more information.

Response arguments:

* On success, a `torrent-added` object in the form of one of 3.3's torrent objects with the fields for `id`, `name`, and `hashString`.

* When attempting to add a duplicate torrent, a `torrent-duplicate` object in the same form is returned, but the response's `result` value is still `success`.

### 3.5 Removing a torrent
Method name: `torrent-remove`

| Key | Value Type | Description
|:--|:--|:--
| `ids`               | array   | torrent list, as described in 3.1
| `delete-local-data` | boolean | delete local data. (default: false)

Response arguments: none

### 3.6 Moving a torrent
Method name: `torrent-set-location`

Request arguments:

| Key | Value Type | Description
|:--|:--|:--
| `ids`      | array   | torrent list, as described in 3.1
| `location` | string  | the new torrent location
| `move`     | boolean | if true, move from previous location. otherwise, search "location" for files (default: false)

Response arguments: none

### 3.7 Renaming a torrent's path
Method name: `torrent-rename-path`

For more information on the use of this function, see the transmission.h
documentation of `tr_torrentRenamePath()`. In particular, note that if this
call succeeds you'll want to update the torrent's `files` and `name` field
with `torrent-get`.

Request arguments:

| Key | Value Type | Description
|:--|:--|:--
| `ids` | array | the torrent list, as described in 3.1 (must only be 1 torrent)
| `path` | string | the path to the file or folder that will be renamed
| `name` | string | the file or folder's new name

Response arguments: `path`, `name`, and `id`, holding the torrent ID integer

## 4  Session requests
### 4.1 Session arguments
| Key | Value Type | Description
|:--|:--|:--
| `alt-speed-down` | number | max global download speed (KBps)
| `alt-speed-enabled` | boolean | true means use the alt speeds
| `alt-speed-time-begin` | number | when to turn on alt speeds (units: minutes after midnight)
| `alt-speed-time-day` | number | what day(s) to turn on alt speeds (look at tr_sched_day)
| `alt-speed-time-enabled` | boolean | true means the scheduled on/off times are used
| `alt-speed-time-end` | number | when to turn off alt speeds (units: same)
| `alt-speed-up` | number | max global upload speed (KBps)
| `blocklist-enabled` | boolean | true means enabled
| `blocklist-size` | number | number of rules in the blocklist
| `blocklist-url` | string | location of the blocklist to use for `blocklist-update`
| `cache-size-mb` | number | maximum size of the disk cache (MB)
| `config-dir` | string | location of transmission's configuration directory
| `default-trackers` | string | announce URLs, one per line, and a blank line between [tiers](https://www.bittorrent.org/beps/bep_0012.html).
| `dht-enabled` | boolean | true means allow DHT in public torrents
| `download-dir` | string | default path to download torrents
| `download-dir-free-space` | number |  **DEPRECATED** Use the `free-space` method instead.
| `download-queue-enabled` | boolean | if true, limit how many torrents can be downloaded at once
| `download-queue-size` | number | max number of torrents to download at once (see download-queue-enabled)
| `encryption` | string | `required`, `preferred`, `tolerated`
| `idle-seeding-limit-enabled` | boolean | true if the seeding inactivity limit is honored by default
| `idle-seeding-limit` | number | torrents we're seeding will be stopped if they're idle for this long
| `incomplete-dir-enabled` | boolean | true means keep torrents in incomplete-dir until done
| `incomplete-dir` | string | path for incomplete torrents, when enabled
| `lpd-enabled` | boolean | true means allow Local Peer Discovery in public torrents
| `peer-limit-global` | number | maximum global number of peers
| `peer-limit-per-torrent` | number | maximum global number of peers
| `peer-port-random-on-start` | boolean | true means pick a random peer port on launch
| `peer-port` | number | port number
| `pex-enabled` | boolean | true means allow PEX in public torrents
| `port-forwarding-enabled` | boolean | true means ask upstream router to forward the configured peer port to transmission using UPnP or NAT-PMP
| `queue-stalled-enabled` | boolean | whether or not to consider idle torrents as stalled
| `queue-stalled-minutes` | number | torrents that are idle for N minuets aren't counted toward seed-queue-size or download-queue-size
| `rename-partial-files` | boolean | true means append `.part` to incomplete files
| `reqq` | number | the number of outstanding block requests a peer is allowed to queue in the client
| `rpc-version-minimum` | number | the minimum RPC API version supported
| `rpc-version-semver` | string | the current RPC API version in a [semver](https://semver.org)-compatible string
| `rpc-version` | number | the current RPC API version
| `script-torrent-added-enabled` | boolean | whether or not to call the `added` script
| `script-torrent-added-filename` | string | filename of the script to run
| `script-torrent-done-enabled` | boolean | whether or not to call the `done` script
| `script-torrent-done-filename` | string | filename of the script to run
| `script-torrent-done-seeding-enabled` | boolean | whether or not to call the `seeding-done` script
| `script-torrent-done-seeding-filename` | string | filename of the script to run
| `seed-queue-enabled` | boolean | if true, limit how many torrents can be uploaded at once
| `seed-queue-size` | number | max number of torrents to uploaded at once (see seed-queue-enabled)
| `seedRatioLimit` | double | the default seed ratio for torrents to use
| `seedRatioLimited` | boolean | true if seedRatioLimit is honored by default
| `sequential_download` | boolean | true means sequential download is enabled by default for added torrents
| `session-id` | string | the current `X-Transmission-Session-Id` value
| `speed-limit-down-enabled` | boolean | true means enabled
| `speed-limit-down` | number | max global download speed (KBps)
| `speed-limit-up-enabled` | boolean | true means enabled
| `speed-limit-up` | number | max global upload speed (KBps)
| `start-added-torrents` | boolean | true means added torrents will be started right away
| `trash-original-torrent-files` | boolean | true means the .torrent file of added torrents will be deleted
| `units` | object | see below
| `utp-enabled` | boolean | true means allow UTP
| `version` | string | long version string `$version ($revision)`


`units`: an object containing:

| Key | Value Type | transmission.h source
|:--|:--|:--
| `speed-units`  | array  | 4 strings: KB/s, MB/s, GB/s, TB/s
| `speed-bytes`  | number | number of bytes in a KB (1000 for kB; 1024 for KiB)
| `size-units`   | array  | 4 strings: KB/s, MB/s, GB/s, TB/s
| `size-bytes`   | number | number of bytes in a KB (1000 for kB; 1024 for KiB)
| `memory-units` | array  | 4 strings: KB/s, MB/s, GB/s, TB/s
| `memory-bytes` | number | number of bytes in a KB (1000 for kB; 1024 for KiB)

`rpc-version` indicates the RPC interface version supported by the RPC server.
It is incremented when a new version of Transmission changes the RPC interface.

`rpc-version-minimum` indicates the oldest API supported by the RPC server.
It is changes when a new version of Transmission changes the RPC interface
in a way that is not backwards compatible. There are no plans for this
to be common behavior.

#### 4.1.1 Mutators
Method name: `session-set`

Request arguments: the mutable properties from 4.1's arguments, i.e. all of them
except:

* `blocklist-size`
* `config-dir`
* `rpc-version-minimum`,
* `rpc-version-semver`
* `rpc-version`
* `session-id`
* `units`
* `version`

Response arguments: none

#### 4.1.2 Accessors
Method name: `session-get`

Request arguments: an optional `fields` array of keys (see 4.1)

Response arguments: key/value pairs matching the request's `fields`
argument if present, or all supported fields (see 4.1) otherwise.

### 4.2 Session statistics
Method name: `session-stats`

Request arguments: none

Response arguments:

| Key | Value Type | Description
|:--|:--|:--
| `activeTorrentCount`       | number
| `downloadSpeed`            | number
| `pausedTorrentCount`       | number
| `torrentCount`             | number
| `uploadSpeed`              | number
| `cumulative-stats`         | stats object (see below)
| `current-stats`            | stats object (see below)

A stats object contains:

| Key | Value Type | transmission.h source
|:--|:--|:--
| `uploadedBytes`    | number     | tr_session_stats
| `downloadedBytes`  | number     | tr_session_stats
| `filesAdded`       | number     | tr_session_stats
| `sessionCount`     | number     | tr_session_stats
| `secondsActive`    | number     | tr_session_stats

### 4.3 Blocklist
Method name: `blocklist-update`

Request arguments: none

Response arguments: a number `blocklist-size`

### 4.4 Port checking
This method tests to see if your incoming peer port is accessible
from the outside world.

Method name: `port-test`

Request arguments: an optional argument `ip_protocol`.
`ip_protocol` is a string specifying the IP protocol version to be used for the port test.
Set to `ipv4` to check IPv4, or set to `ipv6` to check IPv6.
For backwards compatibility, it is allowed to omit this argument to get the behaviour before Transmission `4.1.0`,
which is to check whichever IP protocol the OS happened to use to connect to our port test service,
frankly not very useful.

Response arguments:

| Key | Value Type | Description
| :-- | :-- | :--
| `port-is-open` | boolean | true if port is open, false if port is closed
| `ip_protocol` | string | `ipv4` if the test was carried out on IPv4, `ipv6` if the test was carried out on IPv6, unset if it cannot be determined

### 4.5 Session shutdown
This method tells the transmission session to shut down.

Method name: `session-close`

Request arguments: none

Response arguments: none

### 4.6 Queue movement requests
| Method name | transmission.h source
|:--|:--
| `queue-move-top` | tr_torrentQueueMoveTop()
| `queue-move-up` | tr_torrentQueueMoveUp()
| `queue-move-down` | tr_torrentQueueMoveDown()
| `queue-move-bottom` | tr_torrentQueueMoveBottom()

Request arguments:

| Key | Value Type | Description
|:--|:--|:--
| `ids` | array | torrent list, as described in 3.1.

Response arguments: none

### 4.7 Free space
This method tests how much free space is available in a
client-specified folder.

Method name: `free-space`

Request arguments:

| Key | Value type | Description
|:--|:--|:--
| `path` | string | the directory to query

Response arguments:

| Key | Value type | Description
|:--|:--|:--
| `path` | string | same as the Request argument
| `size-bytes` | number | the size, in bytes, of the free space in that directory
| `total_size` | number | the total capacity, in bytes, of that directory

### 4.8 Bandwidth groups
#### 4.8.1 Bandwidth group mutator: `group-set`
Method name: `group-set`

Request parameters:

| Key | Value type | Description
|:--|:--|:--
| `honorsSessionLimits` | boolean  | true if session upload limits are honored
| `name` | string | Bandwidth group name
| `speed-limit-down-enabled` | boolean | true means enabled
| `speed-limit-down` | number | max global download speed (KBps)
| `speed-limit-up-enabled` | boolean | true means enabled
| `speed-limit-up` | number | max global upload speed (KBps)

Response arguments: none

#### 4.8.2 Bandwidth group accessor: `group-get`
Method name: `group-get`

Request arguments: An optional argument `group`.
`group` is either a string naming the bandwidth group,
or a list of such strings.
If `group` is omitted, all bandwidth groups are used.

Response arguments:

| Key | Value type | Description
|:--|:--|:--
|`group`| array | A list of bandwidth group description objects

A bandwidth group description object has:

| Key | Value type | Description
|:--|:--|:--
| `honorsSessionLimits` | boolean  | true if session upload limits are honored
| `name` | string | Bandwidth group name
| `speed-limit-down-enabled` | boolean | true means enabled
| `speed-limit-down` | number | max global download speed (KBps)
| `speed-limit-up-enabled` | boolean | true means enabled
| `speed-limit-up` | number | max global upload speed (KBps)