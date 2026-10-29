# Vaani architecture

## Product direction

The first useful loop is: shortcut → correct microphone → streaming words → optional polish → insert. Microphone behavior matters as much as transcription quality. Keep the app small and predictable before adding accounts, teams, transcript archives, model downloads or a hosted backend.

macOS uses SwiftUI + AppKit, AVAudioEngine/AudioUnit, CoreAudio, IOKit and URLSession. Android uses InputMethodService, AudioRecord, Android Keystore and OkHttp. Native UI avoids an Electron runtime in a latency-sensitive background utility.

## Speech pipeline

Both clients use the current Sarvam realtime endpoint:

`wss://api.sarvam.ai/speech-to-text-realtime/ws`

Authenticate with `Api-Subscription-Key`. Default model is `saaras:v3-realtime`; `saaras:v4` can be selected on either client and transferred in shared settings. Stream 16 kHz mono signed 16-bit little-endian PCM in base64 `audio_input` events. Wait for `session.begin` before capturing. Receive `transcript.partial` / `transcript.final`, keyed by `utterance_idx`. Partials replace rather than append; finals override and deduplicate. Send `end` after the audio queue drains and wait for `session.end` before processing. A timeout keeps partial text visible instead of pretending it is final.

macOS resamples the selected input through AVAudioConverter and has a bounded send queue. Android reads PCM16 directly, caps the WebSocket queue and verifies an explicit preferred route before transmitting each chunk. Neither implementation reconnects an active recording automatically: losing or duplicating an unknown span of speech is worse than a clear retry.

Dictionary entries are sent as a JSON array in `keyterms` only when recognition hints are explicitly enabled. Sarvam accepts these hints only on `saaras:v4`; enabling hints with entries selects v4 for that session. With hints off or no entries, the stored model choice is used. Dictionary entries also accompany optional polishing; neither hinting nor polishing promises exact recognition.

Reference checked on 2026-10-28: [Sarvam realtime specification](https://docs.sarvam.ai/api-reference/speech-to-text/transcribe/realtime/ws.md). No legacy WebSocket wire format is assumed.

When Mac receives a server `session.end`, it closes the PCM queue and cancels pending sends before notifying AppModel. If capture is active, AppModel stops it immediately and finalizes the available text without automatic paste. Normal user-initiated Finish still drains queued PCM before sending end. A session that ends before readiness cannot start capture. Deterministic socket tests cover these protocol paths; physical Mac capture acceptance remains separate.

## Microphone policy

On Mac, enumerate actual CoreAudio input streams and persist the device UID, not its list index or display name. Set the current device on the app's AudioUnit only; do not change the system default input.

A setup signature contains sorted display vendor/model/serial identities and USB vendor/product/serial identities, encoded with length prefixes. Preferences map that signature to a friendly name and microphone UID.

- Known signature and present preferred UID: select it.
- Unknown signature, one input: select it for this session.
- Unknown signature, multiple inputs: ask which one to use.
- Known signature, preferred input absent: ask; never silently substitute.
- Active input disappears: stop and preserve text.
- Display or hub changes mid-recording: defer the setup transition until recording ends.

CoreAudio system/input-property listeners, IOKit USB attach/detach notifications and display-change notifications drive refreshes. A 700 ms debounce coalesces device bursts before replacing the idle setup; an eight-second inventory fallback covers missed notifications. Starting dictation during the settling interval asks for a retry. Capture uses a device-bound AudioQueue, with CurrentDevice set and checked against the selected microphone UID before/after starting and before delivering each buffer. This changes only the queue's device, never the system default. Input is converted to mono 16 kHz PCM16 on a serial capture queue. Device/running-state notifications and conversion failures synchronously close the PCM delivery gate; synchronous AudioQueue disposal guarantees callbacks have finished before their session context is released, keeping already-captured text visible. A fresh UID lookup after the network handshake handles a mic disappearing while connecting.

Mac device warnings are separate from transient action feedback. Missing/unavailable inputs take priority; a recovered valid input clears that warning without erasing unrelated feedback. Idle choice saves re-enumerate hardware before persisting, refusing an outdated setup/input. The model accepts an injected inventory and can disable observers for deterministic tests of reconnects and deferred transitions; normal builds use CoreAudio/display/USB inventory and observers.

Named manual profiles support two places with identical hardware. They take precedence over automatic hardware mapping, remain active across restarts/hardware changes, and are switched explicitly from Settings or the floating microphone menu. A missing profile or preferred input never falls through to another preference. Returning to Automatic restores hardware matching. The local settings decoder migrates the first build's saved mappings without requiring new fields. Manual profiles are excluded from shared exports.

Connecting/disconnecting devices can still create new signatures after the debounce interval. Identical displays without serial numbers are indistinguishable automatically. Wi-Fi/location permissions are not requested. Notification delivery and actual USB/Bluetooth hot-plug behavior still require physical acceptance evidence; successful listener registration alone does not prove them.

Android fingerprints connected input and output identities and stores device-local preferences and named manual profiles. Unknown multi-input combinations ask for a choice; missing preferred or ambiguous inputs do not silently fall back. IDs use device type, product name and address; some manufacturers provide insufficient identity. Android 31+ requests a communication device for Bluetooth; Android 28–30 negotiates legacy SCO. Owned routes are cleared before finalization/polishing, and the prior audio mode is restored. Frames are withheld until the actual recording route matches; later changes stop capture. A physical Realme built-in recording passed, but physical Bluetooth/USB switching remains unverified.

## Post-processing

The provider receives a stable developer prompt/dictionary prefix followed by a user transcript via non-streaming `POST /responses`. A SHA-256-derived prefix key supports prompt-cache routing without putting transcript text in the key. No dictation history, response IDs or local transcript cache is reused. Requests set `store: false`; cache hits remain provider/model dependent. Provider URL/model/prompt and service tier are editable and shared; the API key is local. Missing service tier in older settings defaults to omission. Old full Chat Completions URLs normalize to Responses. Only completed assistant `output_text` blocks are accepted; incomplete, refused or malformed responses preserve raw text. Redirects are refused. HTTPS is required except on localhost. No silent provider fallback. Failure leaves raw text available and does not auto-paste an unreviewed fallback.

Generation IDs and cancellation prevent a late response from overwriting a new dictation or inserting into a different Android field. The macOS destination app and native window are captured when dictation starts outside Vaani, without reading destination text. Paste uses the current input in that captured window; cursor and selection changes do not block it. Vaani waits for app activation and shortcut modifier release, prefers the native Paste command, and does not blindly retry a dispatched paste. Secure input and exposed password fields refuse dictation/paste. Opaque editors can hide password metadata. User-confirmed Mac dictation/paste works; broader editor compatibility remains an acceptance item.

## Storage and sync

Shared preferences use version 1 JSON, with identical field names on both platforms. The export omits credentials, recording data and device-specific setup maps. Imports validate version, allowed speech options, size and provider URL, and ask for confirmation with the destination displayed. Settings can be exchanged using explicit paired Sync now over Tailscale or file export/import. Plain JSON files are readable by anyone with file access, so prompts/dictionary should be treated as personal data.

Native file actions use SharedSettingsFile codecs with a 256,000-byte limit on both input and output. Reads are bounded before parsing; Android uses strict UTF-8 decoding. Unknown fields are dropped on canonical export. Both validators count Unicode code points (Swift Unicode scalars), matching the JSON schema's maxLength rather than platform-specific grapheme/UTF-16 counts. Mac import validates first and restores its prior active shared settings if persistence fails. Android commits the validated canonical object before reloading fields. Mac exports its active shared model. Android's Save & export saves the form first, then exports saved preferences; cancelling the destination picker does not undo that save.

Paired sync uses a Mac `NWListener` bound to an actually assigned numeric Tailscale IPv4 address (100.64.0.0/10), TCP 47831. It never binds 0.0.0.0, a LAN address or a public address. Sharing is manual per app run. Android stores the pairing code using the existing Keystore credential envelope; Mac stores the random 256-bit pairing key in Keychain. Revoke deletes the key and closes all active connections.

Each TCP connection carries one request and one response. A four-byte big-endian length precedes an AES-256-GCM combined envelope: 12-byte random nonce, ciphertext, 16-byte tag. Authenticated data is `dev.vaani.settings.v1.request` or `.response`, preventing reflection across directions. Frames are capped at 256,000 bytes, connections at eight, and the whole Mac exchange at 15 seconds. Android uses numeric-address sockets, an eight-second connect timeout and a 12-second read timeout. Authentication failures close the connection without plaintext details.

Requests contain protocol version, UUID, timestamp, operation and optional settings/revision. The Mac rejects duplicate UUIDs and clocks outside a two-minute window, with a bounded replay cache. Version 2 get returns validated shared settings and a separate allowlisted credentials object (sarvam/processing only), inside the encrypted envelope. Its SHA-256 revision covers settings and credentials, so key changes also invalidate stale offers. Version 1 remains settings-only for old Android clients; updated Android requires version 2 on Mac. Offer requires the exact current revision and queues one incoming settings snapshot. Apply on the Mac checks the revision again; local edits or active dictation prevent applying a stale offer. Android explicitly reviews a fetched snapshot before applying it, and detects changed local drafts. The response is bound to the request UUID. This is whole-document selection with conflict rejection, not an automatic merge.

Incoming provider destinations and prompts remain reviewable on the receiving device, because local API keys may later be used with them. Shared settings and file exports are an allowlist and exclude all credentials, microphone mappings and captured text/audio. Paired sync separately carries only saved Sarvam and polishing API keys; blank/missing source values preserve destination keys. Mac writes incoming keys to Keychain with rollback on settings/key write failure; Android encrypts keys and commits them with settings in one preferences transaction. Neither UI review nor diagnostic logs show key values. Pairing credentials never travel in the settings payload. Production offers always wait for local Mac review; only the `--sync-smoke` isolated test store auto-applies test offers. No tombstones are needed for the first whole-document replacement protocol.

## Boundaries for the next milestone

Physical microphone switching, finalization timing and insertion correctness need acceptance evidence. A Mac `--check-sarvam` command can validate a saved key and realtime session finalization without starting audio capture. Then prioritize configurable shortcuts and push-to-talk, physical Bluetooth/USB routing checks, keyboard ergonomics and normal Keychain-backed pairing persistence. Distribution signing/notarization and wider open-source release come after the personal daily loop works.


## Isolated sync UI acceptance

`--sync-ui-smoke <new-empty-directory>` runs the actual Mac settings UI and sync controller against an isolated PreferenceStore and a temporary in-memory pairing key. Speech is disabled and automatic provider-key loading is skipped. The same mode can be selected in a separate test bundle with the `VaaniSyncUIFixtureDirectory` Info.plist key; the production bundle does not contain it. The window identifies itself as an isolated fixture. Sharing still starts only from Devices. A private `pairing.json` (0600) supports secret stdin transfer into Android's password field; it is removed when sharing stops. Revoke rotates only the fixture credential, leaving personal Keychain items untouched. A done file or fifteen-minute deadline closes the fixture. It never auto-applies incoming settings.

The physical Realme and Mac UI completed Pair, Use Mac, Send Android, Discard, a concurrent local-edit conflict, Apply, Revoke, rejection of the old pairing code, and successful re-pairing with the replacement code over Tailscale. Android's shared settings were restored exactly and its temporary peer credential removed. This establishes the UI/protocol path with temporary credentials; normal Mac Keychain approval after ad-hoc rebuilds remains unresolved.

## Android settings navigation

The native Activity groups controls into five sections matching the Mac settings vocabulary. Section views remain instantiated while hidden, preserving unsaved field values across navigation. A fixed Save action commits the complete shared draft and keys from any section; selecting a tab never auto-saves. Microphone preference actions remain explicit. Per-section scroll offsets are in memory, and only the selected section is restored through Activity saved state; drafts/credentials are not manually serialized into that state. Physical Realme acceptance covered cross-section draft saving and exact settings restoration.


## Voice-only Android input surface

The IME renders a native tappable surface, with no alphabet/symbol keyboard or
upstream keyboard engine. Settings occupies a corner; keyboard switching remains
available even in protected fields. A surface tap starts in Ready and finishes
only once Listening; connecting/finalizing ignore additional surface taps while
Cancel remains usable. Finish still commits via DictationDelivery, retaining
explicit recovery for failed/unfinalized results. Settings navigation cancels
capture and uses an allowlisted section extra to open Microphones when needed.

The input view adds system-bar and display-cutout padding, excluding IME insets
(which describe the keyboard itself). Controls have minimum 48-dp targets, text
can grow the layout, landscape uses a shorter center, and fullscreen editing is
disabled. Password restrictions and input/window cancellation stay in place.

The synchronous shortcut event-tap adapter is main-run-loop confined and checks thread ownership directly. It does not call MainActor.assumeIsolated from its C callback. Dictation actions are queued onto the main queue outside the event tap.


## Dictionary bias controls

`recognitionHintsEnabled` is an optional shared boolean, default false for older
settings too. Dictionary entries always remain available to optional polishing.
Only explicitly enabled, nonempty recognition hints send Sarvam keyterms and
select v4; disabling hints retains the user's chosen model. Quiet real-audio
fixtures reproduced unrelated dictionary names in raw STT, so hints are no
longer implicit. User recordings and evaluation transcripts stay outside Git.

Polishing sends a JSON transcript object separately from the developer prefix
and JSON dictionary array. The new default prompt preserves spoken instructions
as text and only removes explicit disfluencies. Old default text, ignoring
whitespace differences, migrates during loading/canonicalization; custom prompt
text is unchanged. The prompt-cache hash includes the dictionary and prompt;
recordings and transcripts never enter the routing key.
