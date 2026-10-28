# Synthetic language checks · 2026-10-28

The Mac production SpeechConnection streamed four synthetic clips to live Sarvam with explicit language codes, no dictionary and no polishing. All four native-script (`transcribe`) finals exactly matched the supplied source strings. Each model/mode was sampled once; this is neither a representative accuracy benchmark nor a native-speaker review.

| Language / local voice | Synthetic source and exact native-script final |
| --- | --- |
| Bengali / Piya | আগামীকাল অফিসে নতুন অ্যাপের ডেমো হবে। |
| Kannada / Soumya | ನಾಳೆ ಕಚೇರಿಯಲ್ಲಿ ಹೊಸ ಅಪ್ಲಿಕೇಶನ್ ಪ್ರದರ್ಶನ ಇದೆ. |
| Tamil / Vani | நாளை அலுவலகத்தில் புதிய செயலியின் அறிமுகம் நடைபெறும். |
| Telugu / Geeta | రేపు ఆఫీసులో కొత్త యాప్ డెమో ఉంటుంది. |

The Latin-script (`translit`) finals were:

| Language | Saaras v3 Realtime | Saaras v4 |
| --- | --- | --- |
| Bengali | Agamikal office-e notun app-er demo hobe. | Agamikal office-e notun app-er demo hobe. |
| Kannada | Naale kacheriyalli hosa application pradarshana ide. | Naale kacheriyalli hosa application pradarshana ide. |
| Tamil | Naala alavukkattil puthiya seyaliyin arimugam naidaipadum. | Naalai aluvalagathil pudhiya seyaliyin arimugam nadaiperum. |
| Telugu | Repu office-lo kotha app demo untundi. | Repu office-lo kotta app demo untundi. |

The Tamil sample exposed a visible transliteration issue in v3: the source words for office and taking place were rendered as `alavukkattil` and `naidaipadum`. V4 rendered them `aluvalagathil` and `nadaiperum`, closer to the source. This single clip does not establish general model superiority. V3 remains the default; both models are selectable on Mac and Android. A nonempty dictionary selects v4 for recognition hints.

V4 also finalized the existing Hinglish clip without hints as `Kal office mein Sarvam aur Vani ka demo karna hai.`. Exact Vaani spelling still requires recognition hints in this fixture; earlier physical Android testing with hints returned Vaani correctly.

The physical Realme captured the Kannada clip through its remembered built-in microphone using production DictationSession, automatic language detection and Latin output. It finalized to `Naale kacheriyalli hosa application pradarshana ide.` Polishing was disabled. The original synthetic Hinglish fixture was restored afterward and verified by SHA-256. This instrumentation check does not establish Kannada insertion through a third-party editor.

Clips are 2.96–3.70 seconds, generated with installed macOS `say` voices and converted by ffmpeg to mono 16 kHz PCM16. No microphone recordings or private conversations were used as source audio. Mac streaming bypasses physical capture; Android used acoustic speaker-to-microphone playback. User accents, noisy rooms, longer passages, other Indian languages and representative end-to-end latency measurements remain open.

The opt-in Mac command now accepts `--fixture-settings-file <version-1-shared-json>` alongside `--transcribe-pcm <file>` and optional `--fixture-key-file <private-file>`. The settings file is size-limited and validated, used only for that invocation, and never saved to personal preferences. Invalid future-schema settings were rejected before credential lookup/network. Timing output uses a monotonic clock and reports session connection, first nonempty partial after PCM streaming starts, and Finish-to-session-end; it is protocol timing, not microphone-to-editor latency.

Raw local synthetic artifacts and timings are in `build/language-fixtures/` (ignored by Git). No keys are included in those artifacts.

## Repeated physical Android timing (2026-10-28)

Three sequential opt-in `capture-timing` runs on the Realme 2 Pro used the production DictationSession, remembered built-in input and live Sarvam. The 3.029-second synthetic Hinglish fixture played acoustically through AudioTrack into the microphone. Settings were automatic language detection, Romanized (`translit`) output, `saaras:v3-realtime`, no dictionary and polishing disabled.

| Run | Start to Listening | Playback to first text | Finish to result | Start to result |
| --- | ---: | ---: | ---: | ---: |
| 1 | 598 ms | 2,085 ms | 104 ms | 5,256 ms |
| 2 | 476 ms | 2,066 ms | 95 ms | 5,129 ms |
| 3 | 480 ms | 2,090 ms | 108 ms | 5,142 ms |

All three returned `Kal office mein Sarvam aur Vani ka demo karna hai.` The fixture still needs a dictionary hint for the exact Vaani spelling. No polishing provider or editor insertion was involved.

Instrumentation uses monotonic timestamps immediately before session start, playback and Finish, and in Listening/first nonblank text/result callbacks. First text may be partial or final; it is not specifically a first-partial metric. Start to Listening includes saved-key access, connection and audio startup. Finish to result includes capture shutdown and speech finalization. The runner intentionally waits the clip duration plus 1.5 seconds before Finish, so the total is not a minimum possible utterance-to-result time. Playback timing is a software call timestamp, not a measured acoustic onset. These three same-device/same-network synthetic samples are a repeatability check, not a percentile benchmark or a target for human/noisy dictation.

All runs passed. Independent readback afterward matched the entire saved shared-settings baseline; Android app-ops showed a completed RECORD_AUDIO interval with no running recording. Raw non-secret outcomes are retained locally as `build/android-capture-timing-{1,2,3}.txt`. The test-only runner is excluded from the main APK.

The later built-in-input comparison selected the Realme Bottom input and repeated the same acoustic Hinglish fixture twice. Both reached confirmed Listening but returned no transcript. Restoring Back immediately returned the expected sentence. This does not establish a broken Bottom microphone: no signal-energy measurement or human-speech comparison was performed. The successful repeated timing samples above used the remembered Back input; they should not be generalized to all inputs. Full evidence and the resulting empty-result UI fix are recorded in validation.md.
