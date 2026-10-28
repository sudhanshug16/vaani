<img src="assets/icon.svg" width="64" height="64" alt="Vaani">

# Vaani

A small, native dictation app for the way you speak. Sarvam realtime speech recognition for Indian languages and Hinglish, optional polishing through your own OpenAI-compatible provider, and microphone choices that follow your desk setup.

**Early personal-use prototype.** Mac dictation/paste has passed personal-use checks; Android built-in dictation/insertion and paired Tailscale sync have passed physical-device checks. Broader editor compatibility, microphone hot-plug behavior and language quality still need acceptance testing.

## macOS

Requires macOS 14+, Xcode command-line tools and Swift 5.10+.

```sh
./scripts/build-macos.sh
swift test --package-path macos
```

Launch `build/Vaani.app` from Finder. Vaani appears in the Dock and menu bar, and opens Settings on launch. Click its Dock icon to restore Settings after closing or minimizing the window. Closing Settings leaves dictation running; use Quit Vaani to exit. On first launch:

1. Add your Sarvam API key in **Voice**; it is stored in macOS Keychain.
2. Open **Microphones**, select an input and remember it for the current setup. You can name it Home, Office, etc.
3. In another app, press **Control–Option–Space** to start and again to finish. Microphone permission is requested on the first recording.
4. Grant Vaani Accessibility permission for direct paste when dictation finishes. Text is also placed on the clipboard. Editors with opaque accessibility details use their captured native window's current input. Vaani waits for app activation and released shortcut keys, prefers the native Paste command, and never blindly retries a dispatched paste.

Default output is **Romanized Hinglish with English words preserved**. Sarvam streaming partials can use native script; the final output uses the selected mode. Original-script transcription and English translation are also available.

The floating panel is only a compact draggable pill: no expanded card, app name or live transcript. Tap to start/finish dictation; recording shows a waveform and processing shows a spinner. Finishing pastes directly into the captured app window's current input and keeps text on the clipboard. Cursor/selection changes do not block paste. Password/secure input protection remains; opaque editors may hide password metadata. Errors show an orange alert icon; click it to open error details in Settings. Hover still exposes Retry/Dictate and Dismiss controls. X or Escape dismisses/cancels. Click Voice → Shortcut to record your own key, combination, function key or standalone left/right modifier. A bare-key binding replaces that key's normal typing while Vaani is running. Modifier combinations used for typing do not toggle a standalone modifier binding. The shortcut is local to each Mac and is saved immediately across restarts. Settings shows Ready/inactive/detected state; inactive registration retries automatically after Accessibility is granted. Abnormally ended sessions and unfinished partials remain in Settings for recovery rather than being inserted automatically.

Choose and remember microphones/profiles in Settings → Microphones. Process-private audio-engine aggregates are excluded from microphone choices; public user-created aggregates and virtual microphones remain available. Automatic setup matching follows monitors and USB devices; OS device notifications coalesce brief hub/monitor changes before choosing a new setup. Input-route or audio-format changes during recording stop capture and preserve text.

Mac capture resamples the selected microphone to mono 16 kHz PCM16 without automatic gain or noise suppression. The waveform is smoothed for display only. The bundled RNNoise and gain pipeline remains experimental and disabled in normal capture after reported transcription regressions; synthetic noise reduction is not evidence of Hinglish recognition quality.

For Home and Office setups with identical hardware, select a mic, enter a name, and choose **Save as separate profile**. Switch profiles from Settings → Microphones. A manual profile stays selected across restarts and hardware changes until you choose **Automatic**. A missing preferred mic always needs a new choice.

Automatic setup names join the connected monitor and USB product names (for example, `DELL + USB Hub`). Hardware IDs still determine matching; custom Home/Office names are preserved.

In **Voice**, use **Allow microphone** to complete microphone setup independently of your API key. If a development rebuild needs Keychain approval, Dictate requests the normal OS approval off the main thread; **Unlock saved keys** is also available in Voice. Startup steps and errors stay visible at the top of Settings even while scrolled down. Stable development signing can reduce repeated approval prompts; see `VAANI_SIGN_IDENTITY` in the build script.

**Polish** uses only the Responses API: supply a `/v1` base URL or full `/responses` URL, model name and key. Old saved `/chat/completions` URLs resolve to `/responses`; there is no Chat Completions fallback. Edit the prompt freely. The default keeps every spoken sentence, including instructions spoken as dictation, and permits explicit self-corrections. The transcript and dictionary are sent as JSON data. Existing unmodified default prompts migrate to this version; custom prompts are preserved. Service tier offers Provider default (parameter omitted), Auto, Standard, Fast / Priority (`priority`) and Flex. Availability and pricing depend on the provider/model; Fast / Priority can cost more. Processing is off by default; raw transcription remains available on failure. HTTPS is required except for a server on localhost. Remote HTTP endpoints over Tailscale are not supported in this milestone.

Polishing keeps the developer prompt and dictionary before the changing transcript and supplies a stable SHA-256-based `prompt_cache_key` derived only from that prefix. Requests are independent and use `store: false`; dictations are not chained or cached locally. Provider-side prefix caching remains automatic and depends on model support, minimum prefix length and cache availability. The short default prompt may fall below the caching threshold; the app does not pad prompts or force model-specific cache retention/options.

Polish also offers **Reasoning effort**: Provider default (parameter omitted), None (off), Minimal, Low, Medium, High, Xhigh and Max. The selected value is saved and synced, and sent as `reasoning.effort`. Supported values depend on the model; `gpt-6-luna` supports None. Older saved Luna settings retain None until changed; explicit Provider default removes the override. Each dictation uses a single Responses request, independently of service tier and effort.

**Dictionary** has an Add/Edit/Remove form on Mac and Android. Enter a preferred spelling such as `Vaani`, `Sarvam` or `Sudhanshu`, then choose Add spelling. Each entry can be a name, word or short phrase (up to 120 characters); no comma-separated list, arrow or replacement syntax is required. Up to 500 entries are saved automatically. The list guides optional polishing. **Use dictionary as speech recognition hints** is off by default: hints can replace unrelated words in quiet or noisy speech. Enabling it with a nonempty dictionary uses Saaras v4; otherwise the selected speech model is used. Hints are not guaranteed replacements. Settings export/sync keeps the same array-of-strings format.

Version tags build draft pre-releases with Mac Apple-silicon/Intel ZIPs, a signed Android APK and checksums. See [releases](docs/releases.md) for tagging, signing and installation details.

A read-only hardware diagnostic is also available:

```sh
macos/.build/release/Vaani --diagnose
```

It prints microphone names and setup counts without reading credentials, capturing audio, or contacting providers.

After saving a Sarvam key, check authentication and session finalization without recording:

```sh
build/Vaani.app/Contents/MacOS/Vaani --check-sarvam
```

This contacts Sarvam with the saved key but does not start the microphone.

Mac releases use a permanent self-signed identity, not Apple notarization. Migrating from an old ad-hoc build may need one final permission approval. Subsequent updates retain the signing requirement; actual OS permission retention still needs verification. No login item is installed.

Local maintainer builds use the same permanent signing keychain when available. Other development builds default to ad-hoc signing unless `VAANI_SIGN_IDENTITY` (and optionally `VAANI_SIGN_KEYCHAIN`) is set. Ad-hoc updates can reset permissions. See [release signing](docs/releases.md#macos-signing).

## Android keyboard

The Android IME is a small voice-only surface. It uses native Android views and does not vendor a traditional keyboard engine.

Requires Android 9+, JDK 17, Android SDK 36 and Gradle 8.13 (wrapper included).

```sh
cd android
./gradlew assembleDebug testDebugUnitTest lintDebug
```

Install `android/app/build/outputs/apk/debug/app-debug.apk`, open Vaani → **Voice**, save your Sarvam key, allow the microphone, enable the keyboard and select it. Settings are grouped into Voice, Microphones, Polish, Dictionary and Devices; Save settings & keys is always reachable. Switching sections preserves unsaved drafts until you save or the activity is recreated. Tap anywhere on the voice surface to start dictation, and tap again to finish and insert finalized text at the current cursor. A corner Settings button opens Voice settings (or Microphones when a choice is needed). There are no letter/symbol rows, branding or live transcript preview. Failed or incomplete results expose **Insert saved text** for explicit recovery; successful insertion clears pending text to avoid duplicate retries. A small input-level meter shows the selected microphone signal while listening; it uses only the current capture buffers and saves no samples. Voice is disabled in password fields; hiding the keyboard or changing fields cancels recording. A bottom keyboard-switch control returns to another installed keyboard for ordinary typing. Cancel appears during dictation, and unfinished/failed insertion can expose an explicit recovery action. Touch targets are at least 48 dp; system navigation/cutout insets are respected without adding the keyboard's own IME inset. Landscape uses a shorter surface and never enters fullscreen editing.

The settings screen supports the same language, speech-model choice, prompt, provider and dictionary format as macOS. Credentials are encrypted with Android Keystore and excluded from backup. Input choices can be remembered per connected audio-device combination. Unknown setups with multiple inputs ask you to choose. Named Home/Office profiles override hardware matching until you return to Automatic. Preferred-device requests are verified against the actual recording route; Bluetooth input still needs physical-device validation.

## Sync now over Tailscale

1. Connect the Mac and Android to Tailscale.
2. On Mac, open **Devices → Start sharing**. Vaani detects the Mac's Tailscale IPv4 address and listens only there on TCP 47831.
3. Copy the pairing code privately to Android, open Vaani → **Devices**, paste it into **Pairing code from your Mac**, and tap **Pair with Mac**. Treat the code like a password.
4. Tap **Sync now** on Android. Review the Mac's provider destination, prompt and dictionary, then choose **Use Mac** or **Send Android**. Incoming Android settings wait for **Apply settings** in the Mac's Devices page. A concurrent edit requires another sync.

The Mac must be awake, running Vaani, and sharing. Sharing starts only when you click Start sharing and stops when Vaani quits. Stop sharing to close the listener; Revoke pairing invalidates the code. Tailnet ACLs must allow Android to reach this Mac on TCP 47831. The first version supports numeric Tailscale IPv4 addresses; no public listener, discovery or hosted account is used.

File export/import remains available for Taildrop, USB or another transfer. File import also shows the provider destination before applying changes. Files are limited to 256 KB; shorten the prompt or dictionary if export exceeds that limit. Android's Save & export action saves the current form before opening the destination picker.

Included: language, output mode, Sarvam model, recognition-hints toggle, prompt, dictionary, processing toggle, provider URL and model.

Excluded: API keys, audio, transcripts, microphone IDs and setup preferences.

Transfers use AES-256-GCM authentication and encryption in addition to Tailscale. A 256-bit pairing secret stays in Mac Keychain / Android Keystore storage. Sync is explicit; there is no automatic background merge. See [architecture](docs/architecture.md) for protocol and limits.

## Data boundaries

- Audio streams directly to Sarvam while recording. Optional polishing sends the transcript and dictionary to your configured provider.
- Vaani writes no audio or transcript history. Current text stays in memory until another recording or app exit. Pasted/copied text stays on the system clipboard.
- Microphone preferences and settings stay local, unless you explicitly sync or export the shared subset. Providers have their own data policies.
- No telemetry, analytics, account, background recording or secret sync.
- No existing Kivi/Wispr preferences or credentials are read or changed.

See [synthetic language results](docs/language-validation.md) and [validation and next steps](docs/validation.md) for the remaining acceptance work. MIT licensed.
