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

Launch `build/Vaani.app` from Finder. The app lives in the menu bar. On first launch:

1. Add your Sarvam API key in **Voice**; it is stored in macOS Keychain.
2. Open **Microphones**, select an input and remember it for the current setup. You can name it Home, Office, etc.
3. In another app, press **Control–Option–Space** to start and again to finish. Microphone permission is requested on the first recording.
4. Grant Vaani Accessibility permission for direct paste when dictation finishes. Text is also placed on the clipboard. Editors with opaque accessibility details use their captured native window's current input. Vaani waits for app activation and released shortcut keys, prefers the native Paste command, and never blindly retries a dispatched paste.

Default output is **Romanized Hinglish with English words preserved**. Sarvam streaming partials can use native script; the final output uses the selected mode. Original-script transcription and English translation are also available.

The floating panel is only a compact draggable pill: no expanded card, app name or live transcript. Tap to start/finish dictation; recording shows a waveform and processing shows a spinner. Finishing pastes directly into the captured app window's current input and keeps text on the clipboard. Cursor/selection changes do not block paste. Password/secure input protection remains; opaque editors may hide password metadata. Errors show an orange alert icon; click it to open error details in Settings. Hover still exposes Retry/Dictate and Dismiss controls. X or Escape dismisses/cancels. Click Voice → Shortcut to record your own key, combination, function key or standalone left/right modifier. A bare-key binding replaces that key's normal typing while Vaani is running. Modifier combinations used for typing do not toggle a standalone modifier binding. The shortcut is local to each Mac and is saved immediately across restarts. Settings shows Ready/inactive/detected state; inactive registration retries automatically after Accessibility is granted. Abnormally ended sessions and unfinished partials remain in Settings for recovery rather than being inserted automatically.

Choose and remember microphones/profiles in Settings → Microphones. Process-private audio-engine aggregates are excluded from microphone choices; public user-created aggregates and virtual microphones remain available. Automatic setup matching follows monitors and USB devices; OS device notifications coalesce brief hub/monitor changes before choosing a new setup. Input-route or audio-format changes during recording stop capture and preserve text.

For Home and Office setups with identical hardware, select a mic, enter a name, and choose **Save as separate profile**. Switch profiles from Settings → Microphones. A manual profile stays selected across restarts and hardware changes until you choose **Automatic**. A missing preferred mic always needs a new choice.

Automatic setup names join the connected monitor and USB product names (for example, `DELL + USB Hub`). Hardware IDs still determine matching; custom Home/Office names are preserved.

In **Voice**, use **Allow microphone** to complete microphone setup independently of your API key. If a development rebuild needs Keychain approval, Dictate requests the normal OS approval off the main thread; **Unlock saved keys** is also available in Voice. Startup steps and errors stay visible at the top of Settings even while scrolled down. Stable development signing can reduce repeated approval prompts; see `VAANI_SIGN_IDENTITY` in the build script.

**Polish** accepts an OpenAI-compatible `/v1` base URL or complete `/chat/completions` URL. Supply the provider's model name and key. Edit the prompt freely. Processing is off by default; raw transcription remains available on failure. HTTPS is required except for a server on localhost. Remote HTTP endpoints over Tailscale are not supported in this milestone.

**Dictionary** accepts one spelling per line and supplies it as recognition hints and processing context. A nonempty dictionary uses Saaras v4 because v3 Realtime does not support recognition hints; clearing it restores the selected speech model. Recognition hints improve probability; they are not guaranteed replacements.

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

The build is locally ad-hoc signed, not notarized. Permissions can need regranting after rebuilding. No login item is installed.

For development builds, `VAANI_SIGN_IDENTITY="<your existing code-signing identity>" ./scripts/build-macos.sh` uses a stable signing identity. The default is ad-hoc signing, which can trigger Keychain reauthorization after rebuilding. Signing/notarization and the daily Mac insertion loop still require validation.

## Android keyboard

The current APK uses the prototype keyboard. A HeliBoard-based replacement is planned; this repository does not yet contain that fork.

Requires Android 9+, JDK 17, Android SDK 36 and Gradle 8.13 (wrapper included).

```sh
cd android
./gradlew assembleDebug testDebugUnitTest lintDebug
```

Install `android/app/build/outputs/apk/debug/app-debug.apk`, open Vaani → **Voice**, save your Sarvam key, allow the microphone, enable the keyboard and select it. Settings are grouped into Voice, Microphones, Polish, Dictionary and Devices; Save settings & keys is always reachable. Switching sections preserves unsaved drafts until you save or the activity is recreated. **Dictate → Finish** inserts finalized text directly at the current cursor. The keyboard has no branding or live transcript preview; microphone choices stay behind **Mic**. Failed or incomplete results expose **Insert saved text** for explicit recovery; successful insertion clears pending text to avoid duplicate retries. A small input-level meter shows the selected microphone signal while listening; it uses only the current capture buffers and saves no samples. Voice is disabled in password fields; hiding the keyboard or changing fields cancels recording. Includes a basic alphabet/symbol keyboard, next-keyboard button and editor-action key. Backspace deletes a selection or the preceding character cluster using Android's Unicode rules, keeping supported joined emoji and combining marks together. Surrounding text is inspected locally and never sent to a provider.

The settings screen supports the same language, speech-model choice, prompt, provider and dictionary format as macOS. Credentials are encrypted with Android Keystore and excluded from backup. Input choices can be remembered per connected audio-device combination. Unknown setups with multiple inputs ask you to choose. Named Home/Office profiles override hardware matching until you return to Automatic. Preferred-device requests are verified against the actual recording route; Bluetooth input still needs physical-device validation.

## Sync now over Tailscale

1. Connect the Mac and Android to Tailscale.
2. On Mac, open **Devices → Start sharing**. Vaani detects the Mac's Tailscale IPv4 address and listens only there on TCP 47831.
3. Copy the pairing code privately to Android, open Vaani → **Devices**, paste it into **Pairing code from your Mac**, and tap **Pair with Mac**. Treat the code like a password.
4. Tap **Sync now** on Android. Review the Mac's provider destination, prompt and dictionary, then choose **Use Mac** or **Send Android**. Incoming Android settings wait for **Apply settings** in the Mac's Devices page. A concurrent edit requires another sync.

The Mac must be awake, running Vaani, and sharing. Sharing starts only when you click Start sharing and stops when Vaani quits. Stop sharing to close the listener; Revoke pairing invalidates the code. Tailnet ACLs must allow Android to reach this Mac on TCP 47831. The first version supports numeric Tailscale IPv4 addresses; no public listener, discovery or hosted account is used.

File export/import remains available for Taildrop, USB or another transfer. File import also shows the provider destination before applying changes. Files are limited to 256 KB; shorten the prompt or dictionary if export exceeds that limit. Android's Save & export action saves the current form before opening the destination picker.

Included: language, output mode, Sarvam model, prompt, dictionary, processing toggle, provider URL and model.

Excluded: API keys, audio, transcripts, microphone IDs and setup preferences.

Transfers use AES-256-GCM authentication and encryption in addition to Tailscale. A 256-bit pairing secret stays in Mac Keychain / Android Keystore storage. Sync is explicit; there is no automatic background merge. See [architecture](docs/architecture.md) for protocol and limits.

## Data boundaries

- Audio streams directly to Sarvam while recording. Optional polishing sends the transcript and dictionary to your configured provider.
- Vaani writes no audio or transcript history. Current text stays in memory until another recording or app exit. Pasted/copied text stays on the system clipboard.
- Microphone preferences and settings stay local, unless you explicitly sync or export the shared subset. Providers have their own data policies.
- No telemetry, analytics, account, background recording or secret sync.
- No existing Kivi/Wispr preferences or credentials are read or changed.

See [synthetic language results](docs/language-validation.md) and [validation and next steps](docs/validation.md) for the remaining acceptance work. MIT licensed.
