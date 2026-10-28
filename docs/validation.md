# Validation

## Current acceptance snapshot (2026-10-28)

This table is the current summary. The dated sections below retain earlier observations, including failures subsequently fixed.

| Requirement | Evidence | Remaining acceptance |
| --- | --- | --- |
| Romanized Hinglish realtime STT | Physical Android Hinglish/Kannada capture and three repeated synthetic timing runs; Mac synthetic Bengali/Kannada/Tamil/Telugu streaming in native and Latin modes | User-accent quality, additional languages and microphone-to-editor timing |
| Dictionary | Physical Android with Sarvam/Vaani hints returned exact brand spellings; both clients serialize JSON hints and use v4 | Broader proper nouns and language coverage; hints are not guaranteed replacements |
| Android keyboard | Earlier fixture, Chrome address-field and offline WebView contenteditable Dictate/Finish/Insert; cancellation, password refusal, Done, Unicode Backspace; 12 editor and 8 capture lifecycle scenarios | Remote webpages/framework editors and more apps, broader Unicode/devices, ergonomics and TalkBack |
| Mac daily dictation | User completed OS approvals and confirmed dictation/paste in T3 on the Air; local capture reaches Listening | Muse insertion remains unreliable in the prior build; new delivery path requires actual Muse acceptance |
| Microphone preferences | Policy/profile persistence and Mac recovery model tests, actual Android built-in route confirmation, Mac listeners registered | USB/Bluetooth, monitor/hub changes, returning setups; Bottom input human-speech acceptance |
| Configurable polishing | Mac Finish/cancel state and pending HTTP cancellation tests; protocol tests; Android real-capture/local HTTP success, raw recovery, mic release, cancellation/socket abort and concurrent restart | Real configured model quality/provider latency; Mac physical capture-to-polish/paste acceptance |
| Explicit paired Tailscale sync | Actual Mac/Android pair/review/apply/discard/conflict/revoke/re-pair passed using isolated Mac credentials | Normal Mac Keychain persistence, broader networks/devices |
| Settings files | Native Mac and Android export/import/cancel; Mac future-schema rejection; codec Unicode/size checks and failed-save rollback | Actual exported-file transfer between devices; other document providers |
| Minimal native UI | Mac native UI inspection and Realme keyboard/settings screenshots | Multiple font/display sizes, VoiceOver/TalkBack, daily-use polish |
| Open source readiness | MIT license, build scripts and local checks | Remote CI and personal daily-use acceptance; distribution signing remains separate |

The user confirmed the private-aggregate fix restored Mac dictation on their Air. Broader editor and physical hot-plug acceptance remains open.

Current local checks: 97 Swift tests and 45 Android JVM tests pass. Android lint has zero errors and three dependency-update notices. The release Mac bundle is ad-hoc signed; physical Mac capture/paste is not established by compilation or signature verification.

## Next acceptance priorities

- Establish the Mac physical capture/global-shortcut/paste loop after OS approval; verify denial and changed-target behavior in real editors.
- Physically exercise USB/Bluetooth microphones and monitor/hub transitions, including disconnecting the preferred input and returning to saved setups.
- Expand language/brand-name fixtures and measure connection, first partial and finalization latency. Test actual interrupted networking and quota/auth failures; extend polishing cancellation acceptance to Mac.
- Exercise custom Android editors and broader Unicode/device coverage; review keyboard ergonomics and both platforms with screen readers.
- Verify normal Mac Keychain persistence and cross-device exported-file transfer. Both native picker paths have passed independently; remote CI has not run.

## Historical build and device evidence

## Established in the first build

- Swift debug build and macOS release app bundle build.
- XCTest cases cover remembered/ambiguous/missing microphone selection, stable setup ordering, replacement/deduplication of transcript events, out-of-order finals, URL validation, settings version/size limits, secret-free exports, the shared example and the current Sarvam audio envelope.
- A local diagnostic enumerated Camo Microphone and MacBook Pro Microphone, one display and zero USB devices without recording audio or accessing credentials. Hardware inventory is a snapshot.

- Final macOS release bundle rebuilt after audio-finalization review; ad-hoc signature verification passes.
- 22 macOS unit tests pass with zero failures, including migration from first-build settings, independent Home/Office profiles with identical hardware, profile persistence and precedence, missing-profile/input refusal, return to Automatic and profile exclusion from shared export.
- Android debug APK builds; 23 JVM unit tests pass with zero failures/errors. Tests cover canonical shared settings, route selection and fingerprints, independent profiles, communication-route cleanup and transcript accumulation.
- Android lint passes with zero errors and three dependency-update notices (Gradle, OkHttp and the test-only JSON library). No lint baseline or issue suppression was introduced.
- Shared example keys match the versioned schema, Info.plist validates, and the whitespace check passes. CI is configured for both clients, but has not run remotely.
- The updated Mac diagnostic confirms registration of 2 CoreAudio system listeners, 6 input-property listeners, a display observer, and USB attach/detach notifications on the current two-input setup. This establishes registration, not physical event delivery.
- The macOS `--check-sarvam` command opened and finalized an authenticated live Sarvam realtime session using a privately supplied key stored in Keychain. No microphone audio was captured by that check.

Compilation alone does not establish successful recording, transcription or insertion.

## Physical Android setup check (2026-10-28)

- Installed the debug APK on the physical Realme 2 Pro running Android 13.
- Fixed the exported settings activity filter to accept launch intents containing DEFAULT as well as LAUNCHER. Before the fix Android rejected the automation launch; after reinstall, the settings activity launched.
- Granted microphone permission through Android UI and enabled/selected the Vaani keyboard.
- Opened the temporary practice field; the Vaani IME rendered alphabet keys, actions and inline microphone selection.
- Dictate on an unknown multi-input setup opened the picker. Selecting a built-in input showed “Microphone remembered for this setup” and the mic summary updated.
- Dictate without a configured Android key returned “Add a Sarvam key in Vaani settings.” Insert remained disabled. This is error-path evidence, not successful transcription.
- The device screenshot exposed white-on-light native key colors. Explicit dark enabled/disabled key colors replace those defaults.
- T3 device_screenshot failed; the returned agent-device launcher screenshot command worked. The helper misclassified keyboard controls as covered by the keyboard, so screenshot-based coordinate taps were used and results verified with fresh accessibility snapshots.
- Reinstalled the contrast fix and inspected a fresh Realme screenshot: key labels are readable on dark backgrounds, with a dimmed disabled Insert action. The remembered built-in input survived the app update and process restart.

## Live speech and paired sync (2026-10-28)

- Generated a 3.02925-second, mono 16 kHz PCM16 synthetic Hindi/Hinglish fixture using the installed Lekha voice. No private conversation was used.
- The Mac production `SpeechConnection` streamed that fixture to live Sarvam, received changing partials and finalized to: `Kal office mein sarvam aur vani ka demo karna hai.` This proves the connection/audio envelope/accumulator path, not physical Mac capture or paste.
- An opt-in Android instrumentation runner used the production `DictationSession`, the remembered built-in input and actual routed-device confirmation. It played the fixture through an AudioTrack and captured it with the phone microphone. Live Sarvam finalized to: `Kal office mein Sarvam aur Vani ka demo karna hai.` No processing API was involved. This proves physical built-in capture and realtime finalization, not user-accent quality, latency targets or Bluetooth behavior.
- The Sarvam key was provisioned into Android Keystore through a temporary app-private file delivered using run-as stdin. The test runner verified the encrypted credential round trip and deleted the plaintext fixture. Credentials were not placed in source, APKs, shell arguments or logs. The optional runner ships only in the separate test APK.
- Added authenticated encrypted paired Sync now with receiving-device review. A temporary Mac service used the production controller, assigned tailnet address and an isolated settings store. The physical Realme used the production client over Tailscale: fetch, offer, fixture-only auto-apply, stale-revision rejection and wrong-key rejection all passed. The test did not use ADB forwarding and did not replace personal shared settings.
- Swift crypto tests reject ciphertext tampering, wrong keys, request/response reflection, expired requests, replay, invalid destinations and oversized frames. Android tests cover corresponding encryption/destination/allowlist constraints. The live cross-platform test additionally established combined AES-GCM envelope interoperability.
- Android Sync now controls were inspected in a fresh physical-device screenshot. Progress/error placement was then changed to the sync section so it remains visible at the bottom of settings. Full pair/choose/apply/revoke UI acceptance remains open.
- A rebuilt ad-hoc Mac executable stalled inside `SecItemCopyMatching` reading the earlier credential. The stalled test process was terminated. Fixture transcription then passed using a private key file held only for that invocation. This does not resolve daily Mac Keychain access after rebuilds. The build script now accepts `VAANI_SIGN_IDENTITY` for stable development signing; default remains ad-hoc. No Keychain ACLs or security settings were weakened.

## Opt-in smoke tools

`Vaani --transcribe-pcm <file> [--fixture-settings-file <shared-json>] [--fixture-key-file <private-file>]` accepts at most 60 seconds of raw mono 16 kHz signed little-endian PCM16. It streams intentionally supplied fixture audio and prints partial/final text. The private key override is transient and is not stored. Without it, the command reads the saved Sarvam key.

`Vaani --sync-smoke <new-empty-directory>` starts the actual tailnet listener using isolated settings, writes a temporary pairing credential with mode 0600, auto-applies the test offer only to that fixture store, and exits after a `done` file or two minutes. Never use personal settings directories. The Android test runner's explicit `sync` mode consumes `.sync-pairing` from app-private files and deletes it. Its explicit `capture` mode requires microphone permission, a remembered mic and an intentional fixture. No network/audio test runs by default.
- After moving feedback, tapping Sync now without a pairing showed the error inside the visible sync section on the Realme. Final builds passed 22 Swift tests, 23 Android JVM tests, Android lint (zero errors, three dependency notices), release signing verification and whitespace checks. The temporary sync listener was closed after the integration test.

## Mac setup and paste safeguards (2026-10-28)

- Classic login-Keychain reads now fail promptly when approval is required instead of blocking the main thread. Explicit Unlock saved keys performs prompt-capable reads on a background queue. Empty Save key does not delete credentials. Development ad-hoc rebuilds can still require fresh OS approval; no ACL was weakened.
- Native UI inspection verified the inline Try dictation controls and responsiveness while Keychain approval was pending. Automation is denied access to Apple SecurityAgent, so saved-key authorization and daily Mac dictation remain unverified.
- Added separate Voice → Allow microphone setup so API-key access cannot prevent reaching microphone consent. The rebuilt GUI reached the permission request. Automation was denied access to com.apple.UserNotificationCenter; consent was not completed. The CLI acoustic fixture previously returned microphone permission denied. No physical Mac capture claim is made.
- Automatic paste now retains the original focused AX field and selected range, checks secure input/password fields, and refuses a changed field or selection. Unsupported custom editors use Copy. These guards compile; live cross-app insertion and password-field acceptance remain open.
- Native Devices controls started sharing on the current Tailscale IPv4 and stopped it. An independent listener inspection confirmed port 47831 closed afterward. This establishes the start/stop UI path, not the full pair/apply/revoke flow.
- Android Sync now now explains how to pair when no Mac is saved. Sending Android settings also refuses an edited draft after sync review. The rebuilt APK was installed on the physical Realme; tapping Sync now visibly showed the new pairing instructions in the sync section.
- Current verification: 22 Swift tests and 23 Android JVM tests pass; Android lint reports zero errors and three dependency notices. Mac release build and strict signature verification pass. The classic-Keychain compatibility code emits two deprecation warnings.

`Vaani --capture-fixture <audio-file> --fixture-key-file <private-file>` is an explicit acoustic loopback check using production AudioCapture and SpeechConnection. It accepts a synthetic fixture of at most ten seconds, requests microphone access, verifies the remembered route, and does not save recordings. A shell invocation may have different macOS permission attribution from a GUI launch; do not treat its denial as proof that the GUI app is denied.

## Processing protocol checks (2026-10-28)

- Extracted production completion code into independently testable modules on both platforms. Requests preserve the configurable system prompt, dictionary, raw transcript, selected model and optional Bearer header; disabled processing skips HTTP.
- Fixed Android accepting JSON null/non-string content as text. Null, blank, numeric and array responses now fail, leaving DictationSession's raw-text fallback available. Both clients reject oversized completion payloads before JSON interpretation. Android bounds response buffering; the current Mac size check occurs after URLSession receives data.
- Swift transport fixtures cover valid Hinglish, prompt/dictionary/auth payloads, invalid content/JSON, HTTP errors and disabled processing. Android real local HTTP tests additionally exercise redirect refusal and oversized responses. These are protocol checks, not live model-quality evaluations.
- A separate opt-in `processing` instrumentation mode ran the production Android completion client on the physical Realme against device-local HTTP fixtures. Valid output, null-content rejection, HTTP 429 and redirect rejection passed with exact failure checks. It uses only synthetic text and a dummy fixture key; personal settings and credentials remain unchanged.
- Current Swift tests: 25 passed. Current Android JVM tests: 28 passed. Mac release rebuild and signature verification passed. Android debug APK and separate test APK rebuilt and installed.
- The separate test APK now contains a disposable editor fixture with two ordinary fields, text/numeric password fields and an editor-action field. This screen is excluded from the application APK; it does not save entered text.

## Physical Android editor checks (2026-10-28)

- Opened the separate disposable editor fixture on the Realme through agent-device. In both text-password and numeric-password fields, the actual Vaani keyboard exposed Dictate and Insert as disabled. Switching to the ordinary Done-action field re-enabled Dictate.
- Tapped the actual keyboard Enter key; the fixture reported editor action 6 (IME_ACTION_DONE). Filled a synthetic `A😀` in the first ordinary field, then tapped the keyboard Backspace key; the field became `A`, confirming the surrogate pair was deleted intact.
- The helper incorrectly classified keyboard button refs as covered by the keyboard. Those keyboard-key taps used coordinates from a fresh screenshot and were verified from subsequent accessibility snapshots.
- These checks do not establish active-dictation cancellation on field changes, selected-text deletion, complex emoji graphemes, actual transcript insertion, or behavior across third-party editors. Those acceptance items remain open.

## Actual Android IME dictation and cancellation (2026-10-28)

- Added opt-in synthetic PCM playback to the separate editor fixture. It reads only `files/hinglish-fixture.pcm` from the test APK's private storage, accepts at most ten seconds of mono 16 kHz PCM16, and releases its AudioTrack after playback or Activity destruction. The standalone test Activity uses Java because instrumentation dependencies (including Kotlin runtime) are deduplicated into the target APK and are unavailable in its independent process.
- On the physical Realme, the actual production Vaani keyboard entered Listening with the remembered built-in microphone, captured the fixture played by the separate test Activity, streamed to live Sarvam, and finalized to `Kal office mein Sarvam aur Vani ka demo karna hai.` Tapping the actual Insert button placed exactly that sentence into the focused first editor. Polishing was disabled; personal provider settings and saved keys were unchanged.
- Started another recording and played the fixture, then focused the second field. Recording cancelled, preview cleared, Insert became disabled, and the second field stayed empty. The first field retained only the previously inserted sentence. Subsequent snapshots showed no stale callback result. Android app-ops reported a completed RECORD_AUDIO duration rather than a running operation.
- Started recording in the second field, then used Android Back to hide the keyboard. The keyboard disappeared and app-ops no longer reported running capture. Reopening the same field showed the idle title, initial preview and disabled Insert; the field remained empty.
- Fixed stale keyboard presentation exposed by these runs: cancelling or changing fields resets the Listening status and preview; starting another dictation clears the previous preview; successful insertion returns the status to the keyboard title.
- This establishes the built-in Android IME capture/finalize/insert path and cancellation in a controlled standard editor. It does not establish user-accent quality, exact Vaani brand spelling, latency targets, USB/Bluetooth routing, third-party custom editors, or screen-reader behavior.

## Paired sync UI acceptance over Tailscale (2026-10-28)

- Added an opt-in isolated Mac UI fixture using the actual SettingsView and SettingsSyncController with a temporary PreferenceStore and in-memory pairing secret. The window is labelled as a fixture, speech is disabled, and automatic provider-key reads are skipped. Its private pairing file is removed when sharing stops; the fixture has a fifteen-minute lifetime and never auto-applies offers. Normal app storage/Keychain behavior is unchanged.
- Through native Mac UI, started sharing on the assigned Tailscale IPv4. Supplied the pairing code to Android's secure field via agent-device `fill --text-stdin`, without credential contents in shell arguments or tool output, then tapped the production Pair with Mac control.
- Android Sync now reached the direction/provider/prompt review. Use Mac persisted the fixture dictionary on Android. Restored Android's original prompt and empty dictionary through its actual fields and verified the entire shared object matched the private pre-test backup.
- Send Android queued the Mac review. Discard removed the offer and left the Mac fixture dictionary unchanged. A second offer followed by a local Mac dictionary edit was rejected by Apply; the concurrent edit remained persisted. After discarding and fetching again, Apply persisted an exact copy of Android's reviewed shared settings into the isolated Mac store. The incoming prompt disclosure was inspected before applying.
- Revoke stopped sharing; starting again generated a different pairing code. Android's old code failed to sync. Re-pairing with the replacement code successfully reached the review dialog, demonstrating the service was available and the old credential had been invalidated.
- Cancelled the final dialog, removed Android's temporary pairing through Forget paired Mac, revoked the replacement Mac pairing, and quit the fixture. Independent checks confirmed Android shared settings still matched the backup, the peer credential was absent, the temporary pairing file was absent, and no listener remained on TCP 47831.
- These checks prove the app UI and cross-platform protocol with temporary credentials. They do not prove normal Mac Keychain approval/persistence after an ad-hoc rebuild, the manual cross-device clipboard transport, or wider device/network coverage. No personal Mac shared settings were replaced.

## Live dictionary correction (2026-10-28)

- An opt-in physical Android capture test exposed two live provider constraints: comma-separated `keyterms` was rejected because the value must be a JSON array; after correcting that, Sarvam rejected hints on `saaras:v3-realtime` because only `saaras:v4` supports them.
- Both production request builders now JSON-encode the dictionary and use v4 whenever entries are present. The saved speech model is unchanged, so clearing the dictionary restores that selection. Mac Voice/Dictionary, Android settings and README disclose this behavior.
- Swift and Android regression tests round-trip spaces, commas, quotes, native script and plus signs through the query value, verify the v4 choice, and verify empty dictionaries omit hints and preserve the selected model/sample rate.
- Reinstalled the corrected APK on the Realme. The opt-in `capture-dictionary` runner used the actual built-in microphone, a synthetic speaker fixture, production DictationSession and live Sarvam with `Sarvam` and `Vaani` hints. With polishing disabled it finalized exactly: `Kal office mein Sarvam aur Vaani ka demo karna hai.` The runner restores prior shared settings in its finally block. This is acoustic fixture evidence, not a user-accent or universal dictionary-quality guarantee.
- Current checks: 26 Swift tests and 30 Android JVM tests passed; debug application/test APKs built; Android lint passed with zero errors and three dependency notices. Mac unit coverage establishes its request encoding/model selection; this run does not add physical Mac capture evidence.

## Mac server-ended speech lifecycle (2026-10-28)

- The microphone/session audit found that Mac SpeechConnection previously recorded `session.end` without notifying AppModel. A server-ended session could therefore leave the UI and microphone in Listening until the user stopped or another failure occurred.
- SpeechConnection now marks the session ended before notifying its owner, closes its audio stream, cancels pending audio sends and avoids sending another end event. AppModel handles an end received during Listening by synchronously stopping capture and then finishing the transcript/polishing path. This path suppresses automatic paste and shows a review notice. An end received before connection setup completes refuses to start capture.
- Four deterministic tests exercise the production SpeechConnection receiver/sender with an injected socket: server end preserves the final transcript and notifies the owner; early end refuses setup; pending-send cancellation does not produce a spurious failure; explicit Finish drains two ordered audio chunks before end and retains the final transcript. No network, microphone or saved key is used by those tests.
- All 30 Swift tests passed. The AppModel capture-stop integration compiles, but physical Mac microphone release and cross-app insertion still require OS consent and device acceptance.
- Rebuilt the release Mac bundle and passed strict signature verification. The updated production socket path streamed the existing synthetic PCM fixture to live Sarvam and finalized to `Kal office mein sarvam aur vani ka demo karna hai.` This regression used a transient private key file and the saved empty dictionary; it neither records the Mac microphone nor establishes exact brand spelling without hints. The existing two classic-Keychain deprecation warnings remain.

## Floating microphone/profile UI acceptance (2026-10-28)

- Inspected the actual native floating panel. Found that model notices (including saved-choice/copy feedback and the server-end review notice) were absent from FloatingView, and the active manual profile was not identified. The panel now displays notices, prefixes its input with the active profile or Automatic, constrains long names, and gives the Settings/Close icons explicit accessibility labels.
- Initial custom checkmark labels disappeared inside the native menu. Replaced those actions with inline native Pickers. A fresh screenshot of the final build showed checkmarks beside both MacBook Pro Microphone and Home; AX text alone did not expose those native selection marks.
- Used separate opt-in fixture bundles with isolated settings and speech disabled. Through actual native controls, created Home with the built-in input and Office with Camo; selecting Home in the floating menu restored the built-in choice. Readback confirmed two distinct persisted profile UIDs and Home active. This proves preference selection, not Camo audio capture.
- In the final native-picker build, created Home, opened the floating panel, returned to Automatic (which correctly showed Choose microphone on the unknown multi-input setup), and selected Camo from the panel. The screenshot showed Automatic · Camo Microphone and Microphone preference saved. Selecting Home restored Home · MacBook Pro Microphone. Isolated settings readback confirmed the automatic setup and Home retained different input UIDs.
- Both fixture stores stayed separate from personal settings; no provider-key approval or microphone consent was requested, and no recording or sharing was started. Fixture done files requested clean exit. The fixture launch now wires the same panel-presenting closure as the normal app, while speech remains disabled.
- All 30 Swift tests passed; the Mac release bundle rebuilt and passed strict signature verification. These screenshots and AX checks cover this Mac display configuration, not physical hot-plug, screen-reader operation or multiple font/display sizes.

## Microphone recovery model checks (2026-10-28)

- Found stale Mac status: a missing/unavailable microphone message was stored with general notices, so reconnecting a valid input did not clear it. Microphone status now has a separate published value, takes priority while a choice is required, and clears when inventory recovers. Both settings and the floating panel consume the combined status.
- Remember for this setup and Save as separate profile now re-enumerate the current setup and input before writing. If hardware changes before its OS notification reaches the UI, the stale action refreshes inventory and refuses the write. A later valid choice clears that action's error. Input-loss verification now refreshes the idle picker in the same pass after stopping the session.
- Added an inventory injection boundary and an option to omit observers for deterministic AppModel tests. Normal app defaults still enumerate actual CoreAudio/display/USB hardware and register the same observers/timer. Tests use only isolated temporary preference files and do not request microphone access or read saved keys.
- Eight AppModel tests cover: preferred input disappearance without substitution and return with a changed numeric port ID; no-input recovery while retaining unrelated feedback; missing manual-profile input taking priority over profile-success feedback; stale setup-save refusal followed by a valid choice; unknown setup save and independent return preferences; input loss before either save action; deferred setup changes while connecting; and input-loss handling preserving partial text and immediately requiring a new choice.
- These are model/lifecycle tests with simulated inventories, not physical USB/Bluetooth/monitor/hub acceptance. A current real inventory diagnostic still reports Camo and MacBook Pro inputs, one display, no USB devices, and registered CoreAudio/display/USB observers.
- Final verification: all 38 Swift tests passed with zero failures; the release Mac app rebuilt and strict signature verification passed. Existing classic-Keychain deprecation warnings remain. No Android implementation changed in this recovery pass.

## Indian-language synthetic checks (2026-10-28)

- Live Sarvam finalized Bengali, Kannada, Tamil and Telugu clips in both native and Latin modes; native-script finals exactly matched all four synthetic source sentences. Additional v4 Latin runs covered those languages and Hinglish. Tamil exposed a v3 transliteration difference that v4 improved in this fixture. See [source sentences, actual outputs and limits](language-validation.md).
- The physical Realme's production capture path recognized the Kannada clip with automatic language detection and Romanized output. The temporary acoustic fixture was restored to the original Hinglish bytes and verified by SHA-256. Personal model settings were preserved during this capture check.
- Added per-invocation fixture settings and monotonic timing output to the Mac PCM smoke command, enabling language/model tests without changing personal settings. A future-schema fixture was rejected before key lookup/network. This does not change ordinary dictation configuration.
- Added Android's missing speech-model picker, using the same existing shared sarvamModel field. Its selected value loads/saves with settings and participates in sync/export; no schema migration is required.
- Installed the new APK on the Realme and selected Saaras v4 through the actual Speech model spinner. Save settings persisted v4 while every other shared field matched the private baseline. The picker then showed v4 checked. Restored v3 through the same controls and verified exact equality of the entire shared-settings object with the baseline.
- Final local checks: 38 Swift tests and 30 Android JVM tests passed; Mac release build/strict signature verification passed; Android application/test APK builds and lint passed (zero errors, three dependency notices). The original acoustic fixture remains restored.

## Android settings sections and drafts (2026-10-28)

- Replaced the long settings form with Voice, Microphones, Polish, Dictionary and Devices sections. The final two-row navigation keeps all five destinations visible on the Realme; the first horizontal-row version hid most of Devices and was replaced after screenshot review. Save settings & keys stays outside the scrolling section. Added a dedicated Remember selected microphone control.
- Section changes hide the keyboard, preserve the existing field widgets and restore each section's scroll offset. They do not save shared settings automatically. Selected section survives activity recreation; unsaved form fields are not promised to survive recreation/process death.
- Installed the final debug APK on the physical Realme. Entered a synthetic three-line dictionary and a synthetic polishing prompt, switched between Dictionary, Polish and Devices, and verified persisted settings still equalled the private baseline before Save. Saving from Devices then persisted both exact drafts while every other shared field stayed unchanged, including the speech model and processing toggle.
- Restored the original dictionary and prompt through their actual controls, switched to Microphones and saved from there. Independent readback confirmed the entire shared object exactly matched the original baseline. The Microphones section showed the existing built-in input and Automatic profile. No recording or sharing was started in this UI pass.
- A fresh full-device screenshot verified legible selected/unselected tabs, all five destinations, the microphone/profile controls, saved feedback and the fixed Save action. T3 device_screenshot failed; the returned agent-device screenshot launcher succeeded. This is one-device visual evidence, not TalkBack or font-scaling acceptance.
- Devices → Sync now without a saved peer displayed pairing instructions in the visible section and common status area. Shared settings remained equal to the baseline afterward. Existing encrypted sync/protocol behavior was not changed.
- Final checks: Android application/test APKs built, all 30 JVM tests passed and lint passed with zero errors and three dependency notices. Mac source was unchanged in this pass.

## Android character-cluster deletion (2026-10-28)

- Found that Backspace deleted one Unicode code point, which could split joined emoji, skin-tone modifiers and combining sequences. The production IME now calls EditorActions: selected text is removed in one batch, otherwise Android ICU character boundaries determine the UTF-16 deletion span. Surrounding text is bounded to 4096 UTF-16 units, used locally and never retained or sent to speech/polishing services. A cluster that fills the entire context is refused with visible feedback instead of split. Editors that do not expose preceding text receive conventional Delete key events; their Unicode behavior remains editor-dependent.
- Installed the application and test APKs on the physical Realme Android 13. Opt-in `editing` instrumentation passed 12 checks using real Android EditText/EditableInputConnection and ICU: ASCII, simple emoji, skin tone, family ZWJ emoji, India flag, keycap, Latin combining accent, Devanagari vowel sign, Tamil vowel sign, selected mixed text, field-start no-op and oversized-cluster refusal. The first nine tests delete in the middle of text and verify the suffix and cursor remain intact.
- Opened the standalone disposable editor fixture, filled `A👨‍👩‍👧‍👦`, then tapped the actual production keyboard Backspace. Fresh accessibility state showed exactly `A`. The helper incorrectly rejected the keyboard's own ref as occluded; a coordinate from a fresh device screenshot reached the key. T3 device_screenshot failed again; agent-device screenshot succeeded. The temporary editor was cleared afterward. No recording, provider calls, settings writes or credential operations were performed.
- Application/test builds and all 30 JVM tests passed. Moved failure feedback into a string resource after lint identified a new hard-coded UI string; final app build and lint pass with zero errors and only the three existing dependency-update notices. The final APK was installed on the phone. Mac source was unchanged.
- Scope: Android 13's ICU and standard text editors, plus one actual IME family-emoji deletion. This does not establish all Unicode sequences, older/newer Android ICU versions, third-party custom editors, TalkBack or keyboard ergonomics.
- Re-run the device-only editor checks after installing both debug APKs: `adb -s <device> shell am instrument -w -e mode editing dev.vaani.keyboard.test/dev.vaani.keyboard.DeviceSmokeRunner`. This mode does not use credentials or the network.

## Android premature speech end and recovery (2026-10-28)

- Found a silent-loss path: Android selected only finalized utterances after session.end, even if the last visible partial had never been finalized. It could therefore drop the final words and report success. It now preserves the assembled transcript, identifies pending nonblank partials and returns a review notice when the server ends unexpectedly or leaves unfinished words. These review paths skip polishing, keeping the available words intact. Ordinary explicit Finish with finalized text still follows the configured polishing path. Insert remains explicit.
- Added internal configuration/socket injection to DictationSession. Production defaults still load personal preferences/keys and create the existing OkHttp websocket. Device tests supply isolated defaults, dummy keys and a scripted WebSocket.Factory, so they exercise production capture/routing/lifecycle without contacting providers or reading saved keys.
- On the physical Realme built-in microphone, all eight opt-in lifecycle scenarios passed: end before capture (zero audio sends), spontaneous end preserving partial text and a review notice, connection failure preserving partial text, malformed event preserving partial text, explicit Finish with unfinished partial, normal finalized Finish, cancellation with late events suppressed, and immediate restart. Result callbacks and end-event counts were checked. Successful restart exercises release of the process-wide capture lock and previous recording route; app-ops after the runner showed no running RECORD_AUDIO operation.
- Live Sarvam regression through production DictationSession then passed: `Kal office mein Sarvam aur Vani ka demo karna hai.` This uses the existing empty dictionary and synthetic acoustic fixture, so exact Vaani spelling is not claimed. Independent private readback confirmed the entire shared-settings object still equals the earlier saved baseline. App-ops again showed capture had ended.
- Final checks: application/test APKs built and installed; all 30 JVM tests passed; lint has zero errors and three existing dependency-update notices; git diff whitespace check passed. No Mac source changed.
- Re-run after installing both debug APKs: `adb -s <device> shell am instrument -w -e mode lifecycle dev.vaani.keyboard.test/dev.vaani.keyboard.DeviceSmokeRunner`. This mode briefly records the selected built-in/USB microphone, discards audio in its scripted transport and performs no speech/polishing network calls. It does not prove real radio interruptions, Bluetooth behavior, provider quota responses or cancellation during a remote polishing request.

## Mac unfinished transcript recovery (2026-10-28)

- Found the same final-word loss as Android: after session.end, AppModel replaced its visible live transcript with finalized-only text. A final utterance that remained partial could disappear even though the existing server-end callback correctly stopped capture.
- AppModel now preserves the accumulator's live text at completion. TranscriptAccumulator identifies nonblank pending partials. Unexpected end while Listening requires review even when all words are final; explicit Finish also requires review if unfinished words remain. Both review paths skip polishing and automatic paste. Normal finalized Finish retains the existing configured polishing/paste behavior. Unfinished streaming words may retain native script rather than the selected final-output script.
- Factored production event/end handlers into internal AppModel methods used by the connection callbacks. Four tests drive those same handlers/completion path with an isolated settings file and no device observers, saved keys, network, recording or clipboard operations: final-plus-partial server end; explicit Finish with only a partial; server end with finalized text; and a normal final replacing its partial. Tests enable automatic paste in their isolated store and assert review paths leave no paste failure, preserve exact raw/output text and show the review notice. Normal finalized Finish has no review notice; a later end during Finishing does not begin a second stop.
- All 42 Swift tests passed. This is AppModel/accumulator evidence with no active SpeechConnection or microphone; the existing separate socket tests cover transport ordering/early end. Physical Mac microphone release, shortcut and cross-app paste remain unverified pending OS consent. No Android source or personal settings were changed in this pass.
- The release Mac bundle rebuilt successfully and passed `codesign --verify --deep --strict build/Vaani.app`. The two existing classic-Keychain deprecation warnings remain. No runtime permission prompt was opened.

## Readable speech choices (2026-10-28)

- Both clients now show readable names for all 24 existing language choices instead of locale codes. Auto-detect explicitly includes Hinglish. Android's output picker now uses the same five readable labels as Mac: Romanized / Latin script, Original script, Native + English, English translation and Verbatim. Both Voice pages explain the default Hinglish combination.
- Display names remain separate from protocol identifiers. Android now saves the language/output codes by selected index rather than serializing the visible label. Mac Picker tags remain the existing locale codes. No schema, supported-language list or speech API values changed. A source consistency check verified all 24 supported codes have matching names across clients.
- Installed the Android build on the Realme. Through actual spinners selected Kannada and Original script, then saved. Independent private readback showed exactly kn-IN/transcribe; every other shared field matched the saved baseline. Menu readback showed Kannada checked. Restored Auto-detect and Romanized / Latin script using the controls and saved; private readback confirmed the entire shared-settings object exactly equals the baseline.
- Screenshot review of the Realme Voice section confirmed readable labels, Hinglish guidance, model guidance and fixed Save action without clipping. No dictation, provider request or sync was started. Mac labels compiled in the release bundle; native Mac visual acceptance of this wording remains unverified.
- Android application build and lint passed (zero errors, three existing dependency-update notices). Mac release build and strict signature verification passed, with the two existing classic-Keychain deprecation warnings. Existing 42 Swift/30 JVM test results are from the prior behavior changes; this display-only pass used build, lint, consistency and physical UI checks.

## Chrome address-field keyboard acceptance (2026-10-28)

- Used the existing physical Realme Chrome installation, outside Vaani's editor fixture. The actual Vaani q key entered q in Chrome's native address field. Filled synthetic A👍🏽 and tapped the actual Backspace key; fresh accessibility state showed exactly A, preserving the skin-tone emoji as one deletion. Test text was cleared before dictation.
- Added a delayed-playback button only to the separate androidTest editor Activity. It plays the existing three-second synthetic clip after 20 seconds, allowing the tester to switch to another app and start the production keyboard before audio begins. Handler callbacks are removed on destruction; the existing playback release behavior remains. This fixture is excluded from the main APK and does not request recording access.
- Scheduled the fixture, returned to Chrome's empty address field and tapped the production keyboard Dictate. It entered Listening with the remembered built-in microphone, streamed the synthetic acoustic playback to Sarvam and showed live text. Finish returned Ready to insert with `Kal office mein sarvam aur vani ka demo karna hai.` Tapping the actual Insert button placed exactly that sentence into Chrome's address field, cleared the keyboard result and disabled Insert. Dictionary was empty and polishing disabled; exact Vaani spelling is not claimed.
- Did not submit the address/search text or navigate to a result. Chrome may request suggestions while its address field changes. Cleared the test text using Chrome's own Clear input button; accessibility showed the empty Search Google or type URL field. Back hid the keyboard, and another Back left address editing. No tab was created. App-ops showed RECORD_AUDIO ended after Finish. Private readback confirmed the full shared-settings object still equals the baseline.
- The helper continues to classify keyboard keys as occluded, so actual-key taps used locations verified by a fresh screenshot and subsequent accessibility state. App-field actions used observed refs/selectors. A Chrome customization tip was dismissed via No thanks.
- The separate test APK rebuilt and installed successfully. Production source was unchanged in this pass; the previous build/test results remain the applicable code checks. This establishes one native third-party app field, not Chrome webpage/contenteditable fields, all custom InputConnections, messaging apps, screen readers or human-accent quality.

## Android polishing lifecycle with real capture (2026-10-28)

- Added an opt-in `polishing-lifecycle` device runner using production DictationSession and PostProcessor, the selected real built-in microphone, scripted speech events and an HTTP server bound to device loopback. Configuration is supplied in memory with dummy speech/processing keys; personal keys/settings are not read for provider configuration or modified. Microphone selection still uses the existing remembered routing preference. No speech/polishing provider is contacted.
- On the physical Realme, completion success returned the fixture's polished sentence. An HTTP 429 returned the exact raw sentence with Polishing failed. Raw text preserved. The local server verified completion path, dummy Authorization and exact raw transcript payload.
- The server held each response until the test checked Android AudioManager's recording inventory. It was empty during polishing. With the first request still pending, another production DictationSession successfully started and finished capture, proving the prior capture lock was available. After Cancel, the stalled HTTP server observed socket EOF and no result callback arrived during the bounded late-result window. Success/error scenarios each delivered exactly one result.
- The runner passed all scenarios without requiring a production code change. Separate app-ops inspection showed RECORD_AUDIO had stopped afterward. Independent private readback confirmed every shared setting still equals the saved baseline.
- Test APK rebuilt and installed. This extends earlier direct PostProcessor tests to the production capture/completion/cancel path. It does not establish quality/latency with a real configured model, every cancellation race, Bluetooth behavior, IME UI behavior during remote polishing or the equivalent Mac lifecycle.
- Re-run after installing both debug APKs: `adb -s <device> shell am instrument -w -e mode polishing-lifecycle dev.vaani.keyboard.test/dev.vaani.keyboard.DeviceSmokeRunner`. It briefly records and discards microphone audio, runs only device-local HTTP with dummy keys and refuses a Bluetooth input or already-active recorder for this fixture.
- Final lint passed with zero errors and the three existing dependency-update notices; git diff whitespace check passed. Production application sources were unchanged in this pass.

## Shared settings file limits and import rollback (2026-10-28)

- Audit found Mac file import replaced the active model before checking save success. It now applies through a validated method that restores the old shared model when persistence fails. Tests force failure using a regular file where the settings parent directory should be; both active shared settings and local microphone choices remain intact. A success/reload test confirms shared changes persist while local microphone mappings and auto-paste are retained; invalid future-schema input leaves both active and on-disk settings untouched.
- String limits differed: Swift counted extended graphemes and Android UTF-16 units. Both validators now count Unicode code points (Swift Unicode scalars), matching the JSON schema. Boundary tests accept 120 emoji or 60 decomposed accented letters and reject 121 emoji or 61 decomposed letters in a dictionary entry. Previously these cases could disagree across platforms. Existing normal settings remain unchanged.
- Added production SharedSettingsFile codecs used by native import/export. Both bound input and output to 256,000 bytes. Mac reads through a bounded FileHandle rather than loading an arbitrary file before checking its size; Android keeps bounded streaming and now rejects malformed UTF-8. Oversized exports are rejected before the destination stream/write is opened, avoiding creation of a file that the importer would reject. Valid version-1 data canonicalizes without unknown/private fields.
- New tests on both platforms cover Unicode/escaped dictionary and prompt round trips, removal of unknown credential/setup fields, invalid encoding/JSON/schema and oversized reads/exports. The two Mac AppModel-layer store tests cover import persistence/rollback. These are codec/store checks, not native file-picker acceptance or an actual Mac-export-to-Android-picker transfer; that acceptance remains open.
- All 48 Swift and 34 Android JVM tests passed. Android app/test APKs rebuilt and installed on the Realme; lint passed with zero errors and three existing dependency-update notices. No personal settings or keys were changed by tests. Mac release build/signature verification is recorded below after completion.
- Mac release build and strict signature verification passed. The two existing classic-Keychain deprecation warnings remain; no OS consent or Keychain dialog was opened in this pass.

## Android native document-picker acceptance (2026-10-28)

- Used production Devices → export and Android ACTION_CREATE_DOCUMENT on the Realme to create Downloads/vaani-ui-acceptance.json. DocumentsUI showed a 618-byte JSON file and Vaani reported Exported without credentials. No provider or sync request was made.
- Through Import shared settings and ACTION_OPEN_DOCUMENT, selected that export. Ordinary taps on the enabled file did not advance this device's picker; long-press followed by Select returned the URI and opened Vaani's import review dialog. Cancel left the full shared object equal to the baseline, verified by private readback.
- Saved a synthetic FileImportFixture dictionary entry through the real UI. Private readback confirmed only dictionary changed. Reopened the picker, selected the exported baseline and accepted Import. Independent readback confirmed every shared field exactly matched the original baseline, proving import replaced the changed persisted value rather than merely reopening identical settings.
- Removed only the newly created acceptance JSON using DocumentsUI's selected-file Delete/OK controls. A fresh Downloads listing showed the three pre-existing APKs and no acceptance file or in-progress deletion. Returned the phone to Vaani Devices.
- The exercise also caught inaccurate documentation: Android's export action already saves the current form before launching the destination picker. Renamed it Save & export shared settings to make that existing behavior explicit and corrected README/architecture. The preceding manual run used the original export label; behavior is unchanged. Cancelling the file destination does not roll back the initial save.
- This establishes Android's own export/import/cancel path through the native picker. Mac file-picker acceptance and an actual cross-device exported-file transfer remain open. Invalid encoding/schema/size and Mac persistence rollback are covered by the preceding codec/store tests, not this picker run.
- Final application build and lint passed; updated APK installed. Lint retains zero errors and the three existing dependency-update notices. The 48 Swift/34 JVM test results from the preceding codec change were not rerun for this label-only edit.

## Mac native settings file acceptance (2026-10-28)

- Created a separately identified opt-in fixture bundle from the current release app, pointing the existing isolated UI fixture to a new empty build/file-ui-acceptance directory. Its store/secret remain isolated; no personal settings or Keychain keys are loaded, speech is disabled, and sharing was never started.
- Through the real Devices UI, opened NSSavePanel, set a unique synthetic filename and saved into Documents. Independent file readback confirmed exact equality with the fixture's shared settings and exactly the nine shared fields, excluding local preferences/credentials.
- Replaced only that newly created synthetic file's contents with valid incoming Kannada/dictionary/prompt fixtures. Through NSOpenPanel, selected it and observed the destination/processing review alert. Cancel preserved the original fixture settings. Repeated selection and accepted Import; independent readback confirmed the entire incoming shared object persisted exactly. Voice showed Language: Kannada in the actual native picker.
- Changed only the synthetic input's schemaVersion to 2 and selected it through NSOpenPanel again. Vaani returned to Devices with visible Unsupported settings version feedback and no review/apply dialog. Saved settings still contained the last valid version-1 imported object.
- Removed the newly created Documents file after verifying it still held the exact expected synthetic data, retained a rejected fixture under build, and wrote the fixture's done file. CUA's fresh app inventory no longer contained the fixture app. Later panel inspection showed that hidden fixtures can be omitted while still running, so this inventory observation alone did not prove exit; the current process check below closes that cleanup gap. No provider request, microphone permission, saved-key approval or sharing listener was started.
- No product source changed; this turn adds native acceptance evidence for the existing release. The previous 48 Swift/34 JVM checks remain applicable. This establishes Mac and Android picker paths independently; it does not prove one device's actual export transferred into the other's picker, alternate document providers or normal Mac Keychain persistence.

## Repeated Android capture timing (2026-10-28)

- Added the opt-in test-only `capture-timing` mode, using monotonic callbacks around the existing physical acoustic capture path. No production source changed.
- Installed the rebuilt test APK and ran three sequential live Sarvam captures on the Realme built-in microphone. All passed with the same Romanized Hinglish result. Start-to-Listening ranged 476–598 ms, playback-to-first-text 2,066–2,090 ms and Finish-to-result 95–108 ms. Exact results and measurement limits are in [language-validation.md](language-validation.md#repeated-physical-android-timing-2026-10-28).
- Polishing was disabled during each run; the whole saved shared-settings object matched the earlier baseline afterward. App-ops showed RECORD_AUDIO completed, with no running interval. These results do not establish Mac capture, provider polishing, editor insertion latency, human accents, noisy rooms or long dictation performance.
- Test APK compilation and Android lint passed after the instrumentation edit. Lint retains zero errors and the three existing dependency-update notices. Existing unit suites were not rerun because production behavior did not change.

## Mac polishing lifecycle checks (2026-10-28)

- Added an injectable processing operation to AppModel; the default still calls the production PostProcessor with the captured session settings/key. Tests use isolated temporary preferences and synthetic final speech events, without microphone, Keychain, network or paste permission.
- Four AppModel tests cover pending raw output followed by successful replacement, provider failure retaining raw output/error feedback, and late success/late failure after Cancel leaving the captured words and cancellation notice intact. Error/cancellation tests enable auto-paste: no paste attempt replaces the expected state. Success explicitly disables automatic paste.
- A separate production PostProcessor test starts a pending URLSession request through a custom URLProtocol, cancels the Swift task, observes stopLoading and verifies a cancellation error rather than output. Existing HTTP/content validation tests remain green. This establishes URLSession cancellation propagation in the fixture, not a remote provider's server-side cancellation or socket behavior.
- All 53 Swift tests passed. Physical Mac capture release during polishing, real configured model quality, actual global shortcut/paste and normal Keychain persistence remain unverified. No personal settings or credentials were accessed by these tests.
- Release Mac bundle rebuilt and strict deep signature verification passed. The two existing classic-Keychain deprecation warnings remain.

## Physical Android WebView and field-switch acceptance (2026-10-28)

- Added a separate test-APK-only offline WebEditorFixtureActivity, reachable from the disposable native editor. It contains a textarea, contenteditable rich-text field and password input. JavaScript is disabled by default, network/file/content access is blocked, no form is submitted, and only synthetic text is used. The main APK is unchanged.
- Rebuilt/installed the test APK and exercised the actual Vaani IME on the Realme. A real q key appeared in the textarea; a real Backspace removed it (later snapshots showed the textarea empty).
- Scheduled the existing synthetic Hinglish AudioTrack from the native fixture, opened the offline rich-text field and tapped Dictate. The actual built-in capture/live Sarvam session displayed Listening and the recognized sentence. Finish produced Ready to insert; Insert committed exactly `Kal office mein Sarvam aur Vani ka demo karna hai.` into the contenteditable field, cleared the keyboard result and disabled Insert. No dictionary or polishing was enabled.
- Moving to the WebView password input visibly displayed Voice is off in password fields with both Dictate and Insert disabled. No password text was entered.
- Returned to the textarea and started another actual session. After observing Listening, tapped the rich-text field: the keyboard returned to idle, Insert stayed disabled, the textarea remained empty, and the previously inserted rich-text sentence stayed unchanged. App-ops showed the recording interval completed rather than running. This establishes active-session field-change cancellation in this WebView; it does not establish every editor restart/app-switch race or preservation of a completed uninserted draft.
- Inspected the accepted screenshot at `build/android-web-editor-accepted.png`, exited both disposable activities, and independently confirmed whole shared settings still match the saved baseline. No user text or settings were changed. Test APK assembly/lint passed. Removed the deprecated setSaveFormData call, which is a no-op on the supported modern WebView versions; no form persistence is added. Lint retains zero errors and three existing dependency-update notices. Existing 53 Swift/34 JVM results were not rerun for this test-only fixture change.
- This extends native/Chrome address-field evidence to Android WebView contenteditable input. It does not prove remote websites, JavaScript framework editors, other browsers, all contenteditable formatting, accessibility or human-accent quality.

## Android microphone settings refresh fix (2026-10-28)

- Reproduced stale routing UI on the physical Realme: created a temporary manual microphone profile, selected it, used the Voice practice keyboard's inline picker to switch back to Automatic, then reopened Microphones without leaving the Activity. Independent preferences readback showed no active manual profile, but the Microphones spinner still displayed the temporary profile. No recording was needed.
- SettingsActivity now refreshes routing on entering Microphones, and its no-change check compares the complete MicrophoneSnapshot instead of only fingerprint/manual-profile ID. A changed saved microphone decision or changed input metadata can therefore update the UI even when hardware identity/profile stay the same. An unchanged snapshot leaves draft selections alone.
- Rebuilt and installed the app. Repeated the same temporary-profile → inline Automatic → Microphones sequence: the spinner now showed Automatic immediately. Selected/deleted only the temporary profile through UI, restoring Automatic. Readback confirmed original microphone preference entries and active-profile state (absent/empty profile maps treated equivalently), and exact whole shared-settings equality with the saved baseline. No API key, user text or automatic mic preference was changed.
- All 34 Android JVM tests passed, app assembly succeeded and lint retained zero errors/three existing dependency-update notices. No new mirror-of-implementation unit test was added for this small UI refresh; the physical before/after sequence is its regression evidence. The existing 53 Swift tests were unaffected. USB/Bluetooth, display/hub transitions and real Mac capture remain separate open acceptance items.

## Android distinguishable microphone labels (2026-10-28)

- The physical Realme exposes two built-in inputs with the same product/type label. The prior settings picker and inline keyboard displayed identical names. Android reports their locations as back and bottom; both now display readable Back/Bottom suffixes in settings, the inline picker, selected summary and Listening status.
- For remaining same-name inputs without distinct location labels, presentation adds a short SHA-256-derived tag from the stable microphone UID. Tags are deterministic across enumeration order and transient numeric device-ID changes. Prefixes extend if needed to distinguish the current group. Exact duplicate UIDs show Cannot distinguish, and the existing selection policy still refuses an ambiguous saved identity.
- Only display labels change: UID/address/type/device ID, setup fingerprints, persisted preferences and resolution remain unchanged. Location names are limited to recognized built-in addresses; unknown vendor strings are not guessed or shown as physical locations. Tags distinguish current same-name inputs; they are not a claim about physical ports or guaranteed hardware identity when Android exposes duplicates.
- Added three JVM cases for readable built-in locations with unchanged routing fields, stable distinct labels across enumeration/port-ID changes, and duplicate/mixed identity refusal. All 37 Android JVM tests passed; app assembly/lint passed with zero lint errors and three existing dependency-update notices.
- Installed the app and inspected actual settings and keyboard pickers: Back was checked and Bottom separately listed. The accepted screenshot is `build/android-distinct-microphones.png`. No microphone choice was changed and no recording started. Independent readback confirmed baseline microphone choices/profile state and exact shared settings remained unchanged. This does not establish physical USB/Bluetooth switching or microphone quality differences.

## Realme built-in input comparison and empty-result feedback (2026-10-28)

- Selected Bottom from the actual keyboard picker; its summary changed and independent preferences readback confirmed the saved bottom UID. Ran the same live opt-in capture-timing fixture twice. Both passed Listening readiness (which requires AudioRecord routed-device confirmation and nonzero frame counts) but returned no transcript, causing the smoke runner's nonblank-speech assertion to fail. The raw outcomes are `build/android-bottom-mic-capture.txt` and `build/android-bottom-mic-capture-2.txt`.
- Restored Back through the actual Settings microphone picker and Remember action. The same acoustic clip immediately passed, returning `Kal office mein Sarvam aur Vani ka demo karna hai.` Start-to-Listening was 468 ms, playback-to-first-text 2,149 ms and Finish-to-result 138 ms. Raw outcome: `build/android-back-mic-restored-capture.txt`.
- This establishes selectable/saved input switching and successful recovery to Back, not speech quality on both inputs. Android accepting a route is not evidence of an audible/usable signal. No PCM samples or energy diagnostic were saved; acoustic placement, OEM audio policy/processing, input sensitivity and actual human speech on Bottom remain unknown. Vaani does not silently replace the user's microphone to hide the empty result.
- The empty transcript exposed a real UI issue: completion without an error always showed Ready to insert, even when Insert was disabled. VaaniIME now shows No speech detected and a retry/choose-another-microphone hint for empty successful completion. Actual provider errors retain their original status. Nonempty completion behavior is unchanged.
- Rebuilt/installed the app and exercised actual Dictate/Listening/Finish without intentional playback in the native practice editor. A blank result showed the new no-speech status/hint with Insert disabled; screenshot `build/android-empty-result.png` was visually inspected. No text was inserted. App assembly/lint passed with zero errors and three existing dependency-update notices. The preceding 37 JVM/53 Swift test results remain applicable; no redundant suite rerun was needed for this UI-only feedback edit.
- Final readback confirmed the original microphone preference entries/active-profile state and exact entire shared-settings baseline. App-ops showed recording completed with no running interval. Back remains the remembered input.

## Android microphone input-level meter (2026-10-28)

- Added a four-dp determinate input-level bar below the keyboard status, visible only during Listening. It computes RMS from already route-confirmed PCM16 capture slices and maps -60 dBFS to full scale onto a 0–100 display. Updates are limited to ten per second. No additional recording, PCM storage or provider payload is introduced; the bar is an energy indicator, not a calibrated loudness/quality score or proof of intelligible speech.
- Finish, completion, errors, Cancel and input/window teardown reset/hide the meter. The callback uses the existing session-generation guard. The progressbar has a Microphone input level accessibility label and no live-region announcement; this is not a TalkBack acceptance claim.
- Three JVM tests cover signed little-endian symmetry/full-scale handling, silence/unused buffer bytes/incomplete samples/bounds, increasing level and RMS rather than peak behavior. All 40 JVM tests passed. Both app/test APKs assembled and were installed; lint retained zero errors/three existing dependency-update notices.
- Live physical Back capture returned `Kal office mein sarvam aur vani ka demo karna hai.` with 41 level callbacks and a maximum display value of 74. Timing: 571 ms Start-to-Listening, 2,111 ms playback-to-first-text, 113 ms Finish-to-result. Raw local outcome is `build/android-meter-capture.txt`; no microphone audio is retained by the meter.
- Exercised the actual keyboard with delayed synthetic playback in the disposable native editor. Fresh screenshot showed the orange meter while Listening and the recognized sentence. Finish produced Ready to insert with the meter absent from both the screenshot and accessibility tree. Screenshots `build/android-input-meter-live.png` and `build/android-input-meter-finished.png` were visually inspected. The fixture playback had completed by the live screenshot, so that frame alone is not evidence of meter synchronization with the utterance; production callback statistics establish nonzero input-level updates during capture.
- Cancelled the uninserted result and exited the disposable editor. Final readback confirmed original microphone/profile preferences and the entire shared-settings baseline. App-ops showed recording stopped. Back remains preferred. Bottom signal-level diagnosis, hardware hotplug and human/noisy dictation remain open.

## Mac floating-panel native layout inspection (2026-10-28)

- Created a separately identified/ad-hoc-signed copy of the release bundle, Vaani Panel Acceptance.app, using a new empty isolated fixture directory. The existing fixture path loads no personal settings/Keychain keys, disables speech and never starts sharing unless explicitly requested; sharing was not started.
- Through native GUI automation, opened Show dictation panel and closed only the fixture Settings window to inspect the remaining floating panel. The initial microphone-choice notice, Dictate action, shortcut label, Settings/Close controls and microphone menu were all visible. Tapping Dictate produced the expected fixture-only speech-disabled error; the same controls/notice remained visible. No clipping was observed in these two states. This does not establish every multiline notice, longer error, font size, display configuration or actual dictation/paste loop, so no speculative layout patch was made.
- CUA's app inventory omitted the fixture even while its bound UI remained responsive. Corrected the earlier file-picker cleanup statement: absence from this inventory is insufficient proof of process termination. Wrote the panel fixture's done file; the subsequent bound UI read timed out, also not sufficient alone. Independent exact-executable process inspection then found zero panel-fixture processes and zero earlier file-acceptance fixture processes. No new user approval, recording, provider request or sync listener was triggered.
- No production source changed and the current 53 Swift/40 Android JVM checks were not rerun. The Mac's real capture/global-shortcut/paste loop still needs OS approval and physical acceptance; isolated panel rendering does not establish those behaviors.

## Core requirement audit and Mac approval handoff (2026-10-28)

The original scope remains the native Mac dictation app and Android keyboard, Sarvam realtime Hinglish/Indian-language STT, editable OpenAI-compatible polishing/prompt/dictionary, per-setup and manual Home/Office microphone preferences, a minimal floating panel and explicit paired Tailscale settings sync. File transfer, remote CI, distribution/notarization and exhaustive editor/language/hardware coverage are follow-up checks; passing those would not replace the missing Mac daily-use proof.

- Implementation is present for every core feature. Authoritative current paths include AppModel/DeviceInventory/PreferenceStore/SettingsSyncController and native settings/panel on Mac; VaaniIME/DictationSession/MicrophoneRouter/SettingsSyncClient on Android; shared version-1 schema and MIT license. The evidence table at the top distinguishes implementation from actual acceptance.
- Current Mac artifact exists and passes strict deep signature verification. Android app artifact exists and the current 40 JVM test result files report zero failures; prior Mac 53-test evidence remains current because no Mac source changed since that run. No commit, push, PR or publication has been requested.
- Android actual capture/recognition/Insert, dictionary hints, persisted microphone choice and paired sync have physical-device evidence. The Mac network STT path and native UI have evidence, but physical microphone capture/global shortcut/cross-app insertion do not. Automated tests or synthetic direct PCM streaming cannot substitute for this requirement.
- Rebinding the ordinary Mac app through CUA timed out twice. Exact process inspection confirmed one running production app; a two-second process sample showed the main thread in its normal AppKit event loop, not blocked in a Keychain call. This rules out the suspected synchronous startup hang in that sample; it does not establish permission status, shortcut delivery or paste. The private local sample is build/mac-startup-sample.txt, mode 0600.
- A read-only query of Vaani's TCC records was unavailable (database could not be opened). No permission database, ACL, signing identity or security setting was changed. Earlier protected macOS permission-dialog tool refusals remain a human handoff; no bypass/retry of those dialogs was attempted.

Required human-only step, once at the Mac: open Vaani from its menu bar → Voice, approve Allow microphone; use Unlock saved keys if the saved credential requests approval; enable Vaani in System Settings → Privacy & Security → Accessibility for paste testing. These steps do not ask the user to supply another API key or perform the dictation test. After approval, the agent should run the actual recording/global-shortcut/paste loop itself, inspect failures, and verify no recording remains active afterward. A pending asynchronous question requests notification when approvals are complete; lack of a reply is not approval.

The goal is not complete. Hardware unplug/reconnect acceptance also requires the relevant USB/Bluetooth/hub/monitor setup, and polishing quality requires a chosen real provider/model. No additional small fixture test or cosmetic change closes the Mac daily-use gate.

## Mac approval readback and resumed acceptance attempt (2026-10-28)

- After the user reported approvals completed, native System Settings readback showed the Vaani Microphone switch on. The Device Control and Data Access page (the app-control permission category on this Mac) listed 29 applications, but no Vaani entry. No permission switch or approval dialog was changed by the agent.
- CUA binding to the production bundle and its correct bundle identifier timed out with no visible window; SystemUIServer binding also timed out. This is an automation/window-access limitation, not evidence that the production app hung. No rebuild was performed, preserving the approved artifact.
- Opened a blank disposable TextEdit document and sent Control–Option–Space through the app-bound automation interface. TextEdit remained empty and no Vaani window became bindable. Per-app synthetic key delivery does not establish delivery of a system-global Carbon hotkey; this attempt neither passes nor definitively fails the shortcut implementation.
- Invoked the existing explicit capture-fixture CLI mode on the unchanged production executable with the short synthetic Hinglish WAV and private key file. It exited 1 immediately after requesting access, reporting “Microphone permission was denied.” No capture route was started and no transcript was produced. This process launch may have different macOS responsible-process attribution from the normal LaunchServices app; the result must not be treated as proof that normal app recording is denied. No TCC database/ACL bypass or reset was attempted.
- Asked the user to add the exact build/Vaani.app to Device Control and Data Access, and leave Vaani Settings visible for the next native-app test. Actual Mac recording, shortcut, paste and saved-key acceptance remain unverified. Android remains connected and authorized through adb as Realme 2 Pro (Android device entry present); no new Android recording was started.

## Mac app-control approval and capture startup fix (2026-10-28)

- User authenticated the System Settings change. Fresh native readback confirmed Vaani's Device Control and Data Access switch on. The running app's Voice page also reported saved keys unlocked. These supersede the earlier missing/off permission observations for that build.
- Production Dictate actions from both Settings and the floating panel repeatedly returned immediately to Ready with “The audio input was reconfigured. Recording stopped; partial text is preserved.” Native navigation remained responsive. Unified Core Audio logs confirmed actual capture attempts: at 13:09:15 the built-in input started, an IO-unit configuration notification arrived about 40 ms later, and Vaani stopped an engine that was still running. These were real startup failures, not merely dropped automation clicks. No transcript was produced.
- AudioCapture now tolerates a configuration notification only when the engine is still running, AudioUnit still reports the exact selected device, and the input's complete AVAudioFormat still matches the capture format. A stopped engine, unreadable/different route or different format still closes the PCM gate and reports failure. Existing buffer-format checks and hardware-change handling remain in place. This change addresses harmless startup/output-aggregate notifications without a time-based grace period; physical regression acceptance is still pending.
- All 53 Swift tests passed after the edit. Release bundle rebuilt and strict deep codesign verification passed. Quit/relaunched the app through native computer control; the new build requires renewed classic-Keychain ACL approval. Invoked Unlock saved keys and asked the user to complete the OS prompt. No password, credential value, permission database or Keychain ACL was read or altered through a bypass. Actual post-fix capture, shortcut and insertion remain unverified until that prompt is completed.

- Follow-up after the user approved rebuilt-app Keychain access: Voice confirmed saved keys unlocked. Dictate remained Connecting, and a two-second exact-process sample showed an idle AppKit event loop with no blocked audio-engine stack. Cancel returned to Ready with nothing inserted. Refresh permission status still exposed Allow microphone (the notDetermined branch); selecting it showed Waiting for microphone permission. The rebuilt app therefore also needs renewed microphone authorization before physical regression can proceed. CUA refused binding com.apple.UserNotificationCenter with “Computer Use is not allowed to use the app 'com.apple.UserNotificationCenter' for safety reasons.” No alternative approval route was attempted. Asked the user to accept the OS microphone prompt. No synthetic audio played, transcript appeared or paste occurred in this attempt. Local process sample: build/mac-capture-startup-sample.txt, mode 0600.

## Post-fix Mac startup and second-Mac delivery (2026-10-28)

- After microphone approval, native Voice readback confirmed Microphone access is allowed. Actual Dictate reached Listening and stayed active across the synthetic WAV playback; Finish returned Ready with No speech detected. The previous immediate configuration-change failure did not recur in this session. No transcript or insertion is claimed.
- Read-only audio inventory showed built-in speakers as default output, and native Sound settings showed 62 percent output, unmuted. Hardware model MacBookPro18,3 reported AppleClamshellState=Yes. Its closed-lid hardware microphone disconnect explains the silent built-in input. Requested opening the lid; the user instead requested delivery to their other Mac.
- An app-bound Control–Option–Space event from the blank TextEdit fixture did not change Vaani state. Global hotkey delivery through this automation path remains unproven; this does not isolate a product shortcut failure. Recording was already stopped and TextEdit stayed empty.
- At the user's request, copied the current release to SSH host test-mac, an arm64 Mac. Created build/Vaani-macos-arm64.zip with ditto, transferred it to ~/Downloads/Vaani-macos-arm64.zip, and extracted ~/Downloads/Vaani.app after confirming neither destination existed. Remote strict deep codesign verification passed; remote executable SHA-256 exactly matched the local build. No saved keys, settings or transcripts were transferred, and the remote app was not launched.

## Focused-input detection recovery (2026-10-28)

- The user reported a completed dictation refusing paste in T3 on the MacBook Air. Its screenshot shows the nil-destination branch, not the later destination-changed or permission-missing branch. The prior message incorrectly suggested enabling Accessibility for every failed capture. The screenshot does not distinguish permission unavailable at recording start from an unavailable/unsupported AX focus node; no exact remote focus tree was obtained.
- PasteDestination now checks system-wide focus and app focus, verifies the focused node belongs to the captured PID, normalizes text descendants to their editable ancestor, and handles a web-area/group wrapper containing a uniquely focused editor. It never guesses an unfocused editable sibling; ambiguous or traversal-limited results remain unavailable. Secure event input and secure-field ancestry are rejected before audio starts and during paste validation. Existing same-element/selection validation remains.
- When initial focus cannot resolve, requests the target app's AXManualAccessibility support (unsupported apps reject it) and retries focus over six cancellable 50-ms delays, verifying the destination app remains foreground. This supports lazy Chromium accessibility trees without reading editor values. The capture result records distinct missing-permission versus missing-editor feedback, which is surfaced during dictation and reused if paste is requested. Capture runs before credential/network/microphone startup, with generation/cancellation checks preventing late destination assignment.
- Six new resolver tests cover native/contenteditable text-leaf focus, web wrappers, nested focused text, refusal to guess unfocused/ambiguous editors, password ancestry/descendants, cycles and bounded traversal. All 59 Swift tests passed. Release build and strict deep signature verification passed; package is build/Vaani-input-fix.zip. These are policy/regression checks, not physical T3 insertion proof.
- Delivery to test-mac was attempted after the patch. Its SSH endpoint timed out on two bounded connections; no new app was installed, no running remote app was restarted, and no remote security setting was changed. Exact T3 accessibility compatibility and cross-app paste remain open acceptance items.

- Delivery retry succeeded at the user's request: updated archive transferred and extracted to test-mac:~/Downloads/Vaani-input-fix/Vaani.app. Remote strict deep signature verification passed and executable SHA-256 matched the local release. Existing installed/running app was not replaced or launched.

## Explicit app paste for opaque editors (2026-10-28)

- User's second T3 screenshot confirms the updated field-detection build still cannot resolve an editable focus node while Accessibility is enabled. The prior detection-only patch did not fix this actual editor. Remote package inspection confirms T3 is Electron, but a follow-up bounded package-source query timed out; its exact renderer AX behavior remains unknown.
- Corrected the manual-Paste design: when no editable field resolves but the original app exposes its focused native window, capture that window without its text/title. The explicit button becomes Paste to app. Only a user's manual click can use this route; it activates the original app, rechecks its PID/frontmost status and exact original focused-window identity, checks secure input and any exposed password focus, then sends Cmd-V to that window's current input. This intentionally does not claim original-field/selection verification inside opaque editors. When the original field is known, manual and automatic paste retain the stricter existing same-field/selection checks. Changed/missing windows, missing app-control permission and exposed secure fields still block paste.
- Automatic paste never uses the window fallback. It leaves the recognized text available with the manual-action notice. No arbitrary app-only fallback is added when neither field nor native window is available. Known secure fields are rejected; an opaque renderer may also hide password metadata, so this manual fallback cannot establish exhaustive protected-field detection.
- Suppressed duplicate identical error/notice rendering. Added local unified-log metadata for unresolved focus (PID, role, window-available Boolean only); no field values, selected text, window titles, transcripts or audio are logged.
- Five guard/route tests establish automatic fallback refusal, explicit route priority, matching original window, changed/missing window rejection and protected-focus rejection. Final full run: 64 Swift tests passed. Release build and strict deep signature verification passed. Artifact: build/Vaani-paste-fix.zip. This is tested policy and successful compilation, not physical T3 insertion proof. No Android code or user settings changed.
- Remote delivery remains pending: bounded SSH connections to test-mac timed out. Asked the user to keep the Air awake and Tailscale connected. No new remote app or running process has been replaced in this pass.

- After the user confirmed the Air awake/connected, delivery succeeded: test-mac:~/Downloads/Vaani-paste-fix/Vaani.app. Remote strict deep signature verification passed and executable SHA-256 matched the local release. Existing remote app was not restarted or replaced; actual T3 Paste to app acceptance remains unverified.


## Kivi-style compact panel and paste delivery (2026-10-28)

- User confirmed the previous build works in T3 on the Air, but reported unreliable insertion in Muse. Remote metadata logs show Muse exposing AXButton rather than an editable node, with a native window available. The local Muse installation requires login; remote native GUI control is unavailable, so actual Muse insertion is still unverified.
- Inspected the installed Kivi app through native UI: its idle surface is a tiny dark capsule with two white marks. Expanded Kivi controls did not respond to the attempted interactions. Vaani adopts that observed compact visual pattern; full Kivi interaction parity is not established. No vendor assets/source or personal preferences were copied.
- Replaced the large persistent overlay with a draggable compact pill, hover/recording controls and an expandable recovery card. Copy or acknowledged paste dispatch collapses the card while retaining text. X dismisses; Escape handlers dismiss/cancel while visible. The nonactivating panel cannot become key/main, preserving the destination editor focus.
- Isolated native GUI fixtures use synthetic listening/result/error states without personal credentials, recording or network. Verified waveform/Finish/X, fully visible expanded result/error text, Copy collapse, and X dismissal (fixture readback visible=false). Native geometry readback confirmed both pill and expanded-header movement, with key=false/main=false. Testing caught an intrinsic-hosting resize pushing the card below screen; native frame sizing now preserves the bottom edge and clamps to the visible screen. Local Escape dismissal was verified with Settings focused and fixture visibility=false; global Escape delivery from another app remains unverified by app-bound automation. Final drag toward the screen boundary stayed at y=0, fully inside the visible frame.
- Paste now waits for foreground activation, released shortcut modifiers and two stable destination validations. It checks native Paste availability, prefers the native menu action and otherwise targets Cmd-V to the captured PID. An uncertain action acknowledgement is never blindly retried. Dispatch does not prove insertion; text remains on the clipboard and in the recovery card.
- 70 Swift tests pass, including cancellation/readiness and native frame/focus regressions. Release build and strict signature verification pass. Android code is unchanged; its earlier 40 JVM tests/lint evidence remains historical.

- Delivered final artifact to `test-mac:~/Downloads/Vaani-panel-ux/Vaani.app`. Remote strict deep signature verification passed; executable SHA-256 matches local (`257622472cd4876ce4b1de76e17124aab567ab30a9a5c6346df79767058c1749`). Existing installed/running app was not replaced or restarted.


## Pill-only flow and selectable Right Option shortcut (2026-10-28)

- Per user feedback, removed expanded panel, branding, transcript, mic/profile menus and recovery controls from the floating UI. Only draggable pill, waveform/spinner, dictate/finish and dismiss remain. Settings retains errors and the in-memory last result.
- Normal explicit Finish directly pastes, including opaque editors with a captured native window. The old autoPaste Boolean remains readable for settings-file compatibility but no longer gates normal Finish. Unexpected session endings and unfinalized partial recovery still do not insert automatically.
- Removed saved selected-range reads and original-field equality checks. Paste uses the captured app/window's current input, allows cursor/selection changes, and retains secure-input/password checks and changed-window refusal. Clipboard is written before permission/destination checks, so failed insertion still leaves recoverable text.
- Voice → Shortcut offers Control–Option–Space and Right Option. Changes unregister the old binding/monitors and take effect immediately; the choice is local, persists across restart and defaults to the existing chord when loading old files. A Right Option tap toggles on release; intervening typing/clicks or other modifiers cancel the tap. Right Option requires Accessibility. Physical global Right Option delivery remains unverified; state-machine and settings compatibility tests cover its intended behavior.

- Final 74 Swift tests pass; release build, strict signature verification and whitespace check pass. Isolated native UI verified Right Option selection updates labels and settings.json persists `rightOption`; result/error states and clicking the pill never expose a card/name/transcript. Drag still changes native geometry without key/main focus. Actual global Right Option input and Muse insertion remain acceptance limits.

- Artifact: build/Vaani-minimal-pill.zip, executable SHA-256 `4174da83c10767b9b828be4bebc95d866d81769d42a1f5a754dcc09b30d58693`. Air delivery attempted twice; both bounded SSH connections timed out. The prior panel-ux build on the Air is unchanged.


## Android compact direct-insertion flow (2026-10-28)

- Removed keyboard branding/live transcript preview and the normal extra Insert step. Finalized successful dictation commits into the active input immediately; no cursor/selection lock is added. Mic/profile choices stay behind a compact Mic action.
- Failed commits and incomplete/error results retain text and show an explicit Insert saved text recovery action. A successful commit clears pending text; blank/cancelled/protected-field results do not commit. Existing generation guards and input/window lifecycle cancellation remain.

- Android final build and 45 JVM tests pass; lint has zero errors and the same three dependency-update notices after removing obsolete strings. Reinstalled on Realme 2 Pro. Fresh native screenshot confirms no branding/live preview/normal Insert and a compact Dictate/Cancel/Mic/Next row. A real capture followed by Finish automatically committed into the disposable editor; screenshot and AX readback confirm inserted text with no manual Insert action. The acoustic run also captured extra words beyond the intended fixture, so this establishes delivery, not clean STT accuracy. OP15 is only a Taildrop destination, not the physically tested device.

- Final resource-only cleanup build was reinstalled. Password editor readback confirms Dictate disabled; test text was cleared from the disposable editor. Packaged `build/Vaani-keyboard.apk`, SHA-256 `9afd85c7841b23fd174b9c645d96db35e8a5a7a984a3d241ba95ba8b81b49769`. Taildrop target test-android is online and responds to Tailscale ping, but the file-transfer CLI reports its receiving service is not replying; delivery is not yet confirmed.

- Bounded Taildrop retry also timed out after 30 seconds. Stopped the stalled transfer processes; APK delivery to OP15 remains pending until its receiving service responds. No OP15 install or successful receipt is claimed.


## Custom shortcut recorder and modifier event handling (2026-10-28)

- User reports Right Option still fails after selecting it; do not treat the earlier saved Control–Option–Space readback as proof of user error. Air readback showed the current minimal-pill executable SHA at /Applications/Vaani.app and saved controlOptionSpace; the discrepancy between the user's selection and persisted file remains unexplained.
- Replaced the two-choice picker with a native local key recorder. Records a key/chord/function key or standalone left/right modifier. Recording suspends dictation triggers; Cancel/window resignation preserves the current binding. Binding persistence is explicit and transactional rather than depending on SwiftUI onChange; a failed save restores the prior binding.
- Runtime uses a session CGEvent tap and physical key codes. Standalone modifier detection handles missing device-side bits, cancels on typing/clicks/other modifiers, and fires on release. Chord/bare-key matches suppress their down/up events, ignore autorepeat and dispatch the action off the tap callback. No typed key stream is logged or stored. Secure input may prevent shortcut delivery as controlled by macOS.
- Registration failure is visible separately from dictation errors. Retry is available; inactive registration retries automatically, including after Accessibility consent. Event tap timeout recovery re-enables the tap. Settings exposes Ready/inactive/Detected so recognizing the key can be distinguished from microphone or credential failures.
- 77 Swift tests passed. Regressions include missing side flags, left/right distinction, Option typing/click cancellation, other modifiers, legacy shortcut migration and custom chord persistence. These unit tests do not establish physical global shortcut delivery on the Air.

- Native isolated recorder acceptance: Control–Shift–K recording updated UI labels and persisted a custom binding; Cancel retained it; a function key was recorded. Function/navigation key matching now normalizes macOS's automatically attached Fn flag. Modifier-only combinations accept either press/release order. Final 79 Swift tests pass. CUA explicitly rejected a standalone Right Option keypress (`keyPressIncludedNoNonModifierKeys`), so physical global Right Option detection is still unverified.

- Final release rebuilt, strict signature and whitespace checks passed. Artifact `build/Vaani-shortcut-recorder.zip`; executable SHA-256 `7d564d1a242dac0dbbc4ad570cd6e5dc0e0f647f1f8dd0bef9e665d408fa3197`. Air SSH transfer timed out, Tailscale ping had no reply, and bounded Taildrop fallback reported Air offline/timed out. No new remote build was installed or launched.


## Startup approval recovery and connected-device setup names (2026-10-28)

- User confirms Right Option triggers a loader but startup returns idle within about a second, with no visible error. Air saved binding is the custom Right Option object. Read-only logs for its running Vaani PID contain CSSMERR_CSP_OPERATION_AUTH_DENIED at 18:01:46 and repeated at 18:03:54–55. This is evidence of failed credential access, not proof that every reported reset has the same cause; old code did not log startup stages.
- Explicit Dictate now attempts noninteractive Keychain access first, then requests normal OS approval off the main thread only for an approval-required error. Unrelated errors do not prompt; cancellation is checked before/after approval so late completion cannot start recording. ACLs and TCC settings remain unchanged. Voice's Unlock saved keys no longer requests the unrelated settings-sync credential.
- Connecting-stage text distinguishes destination/settings/keys/microphone permission/Sarvam/microphone startup. Errors and connecting status are pinned outside the Settings scroll content so users at the bottom of Voice can see them. The floating pill stays compact. Stage identifiers and Keychain OSStatus are logged; no audio, transcript, credential value or provider body is logged by these diagnostics.
- Automatic setup labels concatenate actual NSScreen monitor names and USB product names, grouping duplicate labels. IDs/serials and fingerprint/routing logic remain unchanged. New setup names default to this readable label; generic My setup is displayed with the connected names, while custom/manual names remain. This change is scoped to Mac.
- 87 Swift tests pass: approval fallback, unrelated-error refusal, cancelled-approval refusal, stable/deduplicated setup labels and preserved custom microphone names/routing. Actual Air Keychain approval/capture acceptance remains pending.

- Isolated native GUI acceptance: injected approval error remained pinned above Voice while scrolled to the bottom. Microphones showed the actual local Built-in Retina Display label and prefilled setup name. No personal Keychain item or microphone was opened by this fixture. Strict release signature verification and whitespace checks pass.

- Delivered `test-mac:~/Downloads/Vaani-startup-fix/Vaani.app`. Remote strict signature verification passed and executable SHA-256 matches local `93f59df11be4f5825628aeb258921d6abf9dfcb291928450b04dd7f1dd4cef08`. Existing running app was not replaced/restarted; actual post-fix Air capture remains unverified.

### Durable lifecycle diagnostics

Production builds write metadata-only JSONL to
`~/Library/Application Support/Vaani/diagnostics/events.jsonl`, with one rotated
`events.previous.jsonl`. Each file is bounded to 256 KiB, directory permissions
0700 and file permissions 0600. Events include process/run/session identifiers,
shortcut activation, command source, phase/startup transitions, first audio
buffer/signal, speech events/session end, stop/cancel reasons and paste dispatch.
They never include audio, transcripts, clipboard content, device/window names,
key streams, credentials or raw provider/error bodies. Isolated fixtures and
command-line smoke tests do not write production diagnostics. IO failure is
best-effort and cannot interrupt dictation.

Diagnostic rotation/schema/permissions test passes. Air's previous unified logs
reached Listening in two attempts; those logs did not record subsequent
stop/cancel/session-end paths, so the reported reset cause remains unconfirmed.

Mac builds can be installed directly into the Air's Applications folder with
`scripts/deploy-macos.sh test-mac`. It verifies the signed app before
replacement, retains the previous app under Vaani's Application Support/backups,
and leaves the running process alone. Reopen Vaani to load the installed build;
macOS may request renewed permissions after an ad-hoc signed update. The Voice
page's Troubleshooting card explains logging and provides Show logs in Finder.

### Air orange pill and startup preflight (2026-10-28)

Air's durable log from PID 69243 showed an explicit shortcut start, first audio
buffer and nonzero signal, another shortcut Finish two seconds later, session
end, processing, idle and acknowledged paste dispatch. Three subsequent shortcut
commands had no startup-stage event. This narrows those attempts to the preflight
returns; the old logger did not distinguish device-settling from missing choice,
so the exact live branch is not yet proven. No successful target insertion is
inferred merely from dispatch.

Corrected two demonstrated model behaviors: a pending Core Audio notification
no longer blocks startup if a fresh input/setup inventory is unchanged; a real
input/setup change still waits for debounce. Recovering from a transient start
block clears only that block's error, preserving unrelated failures. Missing-input
feedback now uses the specific microphone notice. Added metadata-only rejected
command reasons and device change/settle events so the next live attempt can
identify its exact guard. Five regression tests cover unchanged-input startup,
real setup/input transitions, stale-error recovery and missing-input return.
Full Swift suite: 93 tests passed. Air live acceptance remains pending reopen.

Additional physical Android check: Finish auto-inserted recognized text and
returned to Dictate. Acoustic output included extra words, so this is insertion
proof rather than clean fixture accuracy proof. Starting in a second empty
editor and switching to the password fixture cancelled recording, left that
second editor empty and disabled Dictate in the password field. No Android code
or APK changed in this pass.

### First-session-only failure: private Core Audio aggregates (2026-10-28)

The next Air run (PID 69916) again completed capture, finalization and paste
dispatch, then logged two `microphoneChoice` rejections. The user's Settings
screenshot showed "Choose a microphone for this setup", which is the ambiguous
inventory branch, not an unavailable microphone. A separate process on the Air
reported just its built-in microphone; saved setups/manual profiles were empty.
This is consistent with process-private aggregate devices appearing only in the
engine-owning process after its first recording.

Reproduced the inventory flaw with real HAL devices, without starting IO or
capturing audio: a temporary private aggregate using the built-in input appeared
as a user microphone before the fix (regression test failed). Public aggregate
visibility passed before and after the fix. Inventory now reads aggregate
composition and excludes only aggregates whose `private` flag is true. It does
not hide public aggregate devices or normal virtual microphones. Created test
aggregates are destroyed using defer. Both real HAL tests ran (no skips) and the
full 97-test Swift suite passed. No claim of live Air acceptance yet.

Added metadata-only policy reasons/input counts, selection changes and private
aggregate filtered counts. Empty selection reapplies current policy even if
cached hardware is unchanged; a missing remembered mic still never substitutes
another input. The orange compact pill now has an alert icon; clicking its face
opens the pinned Settings error. Error text also replaces the face's generic
hover help. There is no expanded transcript UI.

Native isolated error-feedback acceptance passed: synthetic microphone error
renders as a compact orange alert (no expanded content); after closing Settings,
clicking the pill's accessible Show dictation error details button reopened the
Settings window with the exact pinned error text. Fixture was ended through its
done sentinel. Updated release installed directly at Air /Applications/Vaani.app;
strict deep codesign passed and executable SHA-256 matched local release:
399a3031f85570ffff84f268ba16ac1830c0c9e5c066750270e45962db6f5313.


### Voice-only Android surface (2026-10-28)

Removed traditional typing rows, shift/symbol actions and the inline microphone
picker from the IME. Existing speech, mic routing/preferences, polishing and
recovery paths are reused. No keyboard fork or new runtime dependency was added.
Settings opens Voice, or the Microphones section if selection is needed.

Build, 45 JVM tests and Android lint passed. Physical Android 13 checks showed:
blank left surface starts listening, blank right surface finishes and inserts
recognized text; Cancel returns to Ready with the empty editor unchanged; the
corner gear opens Voice settings; password fields disable dictation while the
keyboard-switch control still switches to the other installed keyboard. Restored
Vaani through the system input-method picker afterward. Acoustic recognition
included ambient words; this is insertion/lifecycle proof, not clean accuracy
proof. Portrait screenshots show controls clear of the system navigation region.
Landscape, gesture navigation, large fonts and manual TalkBack remain unverified.

The device screenshot connector failed; agent-device screenshots and snapshots
provided native UI verification. Screenshot artifacts are local build/test
artifacts and are not committed.

### Responses API, service tiers and caching (2026-10-28)

Mac and Android Polish settings now persist/share a service tier, defaulting to
omitting the parameter. Legacy settings without the field remain readable;
unsupported values and invalid types are rejected. Requests use only Responses,
including normalization of old full Chat Completions URLs. Stable developer
prompt/dictionary input precedes each independent transcript, with a stable
prefix-derived cache key (at most 64 characters) and `store: false`.

99 Swift tests and 48 Android JVM tests passed, including request payloads,
all service tiers, cache-key stability across transcripts and tier changes,
cache-key changes when the prompt changes, legacy imports, multi-block output,
incomplete/refused output rejection and existing failure/cancellation coverage.
Android app/test APK builds and lint passed. Physical Android 13 local HTTP
fixtures passed Responses success, null output, HTTP error, redirect rejection,
raw recovery, mic release before polishing, restart and cancellation/socket abort.
These fixtures use dummy keys. No live provider cache-hit, tier entitlement,
price or latency claim is made.

### Air capture crash investigation (2026-10-28)

The two latest Air crash reports faulted in an AVAudioIOUnit property-listener
callback. One report showed AVAudioEngine deallocation from AudioCapture.start
on the main thread at the same time. Capture now retains and reuses one engine
across starts, stops and startup failures, while removing its tap/observer and
closing the PCM gate on stop. Tap installation is tracked so failed startup
does not remove a nonexistent tap. This addresses the observed teardown path;
hardware acceptance remains required before claiming the crash is resolved.

101 Swift tests and the signed release build passed. Added the explicit
`--capture-lifecycle-smoke` headless check: ten short built-in microphone starts
and stops, checking routing and PCM delivery without saving/sending audio or
requesting OS permission. The installed Air build's first attempt stopped with
microphone permission unavailable, so no capture cycles ran. The user must
renew the OS approval before hardware verification can continue.

### Follow-up Air crash and hardware acceptance (2026-10-28)

The next user-supplied report faulted in the main-thread shortcut event-tap
callback's MainActor.assumeIsolated executor check. The adapter now confines its
synchronous state to the main run loop, checks Thread.isMainThread, and queues
actions onto DispatchQueue.main outside the C callback.

Running the previous engine-based hardware fixture in the logged-in launchd
session exposed additional failures: its AudioUnit route could not be confirmed,
and a subsequent process hit an uncaught tap-format-mismatch exception. Retaining
the engine alone was insufficient. Replaced AVAudioEngine capture with an
AudioQueue explicitly bound to the selected input UID, verified before/after
start and before PCM delivery. Serial conversion retains mono 16 kHz PCM16;
running/device-change errors close the delivery gate and synchronous disposal
finishes callbacks before releasing their context.

101 local Swift tests and the signed release build passed. Native Air tests
could not run because its Command Line Tools lack XCTest; its release build also
lacked the SwiftUI macro plugin. The installed build uses the local toolchain.
After renewed microphone approval, a one-shot launchd job ran all 10 real Air
built-in input cycles successfully, delivering 15,648–16,372 PCM bytes per cycle,
verifying the route, stopping each capture, and exiting with status 0. No audio
was saved or transmitted. No newer crash report appeared during that acceptance;
the normal app remained running. The test launchd job was removed afterward.
Direct SSH launch had different TCC attribution and was not treated as a valid
app microphone approval check. Shortcut-tap registration remains a separate
permission/acceptance item for this rebuilt app.
