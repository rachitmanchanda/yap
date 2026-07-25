# VoiceCards

VoiceCards is an iOS 17+ voice-first memory app: capture speech or shared content, keep it as a searchable card, then paste it from a custom keyboard. Because iOS custom keyboards cannot access the microphone, the keyboard’s Speak button runs a system-mediated App Intent that foregrounds VoiceCards already recording; the main app owns the audio session.

## Open and configure

1. Open `VoiceCards.xcodeproj` in Xcode 16 or newer (Swift 5.10+).
2. Select `VoiceCardsApp`, `VoiceCardsKeyboard`, `VoiceCardsShare`, and `VoiceCardsLiveActivity`, choose your development team, and replace the `com.APP` bundle-ID prefix with a prefix you own.
3. In Certificates, Identifiers & Profiles, create `group.com.APP.shared` (using the same replacement) and enable it for all three App IDs. Update `AppGroup.identifier`, the three entitlements files, and `APP_GROUP_IDENTIFIER` in `Configuration/Shared.xcconfig` to match.
4. Run the **VoiceCards** scheme on a physical iPhone. The extension schemes are shared for focused builds; Xcode hosts the keyboard or share extension in a compatible app.

SwiftData is attempted first and its SQLite/WAL store lives at a fixed URL inside the App Group. Every process creates its own `ModelContainer` against that URL. Persistence sits behind repositories, so a GRDB store can replace SwiftData if extension testing on supported devices reveals instability.

## Managed API and authentication

Users sign in through Supabase Auth and never manage provider credentials. The Supabase project URL and publishable key are safe client configuration; access and refresh tokens are stored in Keychain. The release UI offers only native Sign in with Apple and exchanges its ID token with Supabase. Add the final app bundle identifier to the Apple provider's authorized Client IDs.

Apple must be enabled in the configured Supabase project and its native Client ID must be authorized. Provider keys belong only in Supabase Edge Function secrets.

Debug builds retain the ten-tap local bypass so development and UI tests remain unblocked. The bypass code is excluded from Release and therefore cannot ship in TestFlight or the App Store.

Voice transcription starts a `transcribe-stream` WebSocket as capture begins. The app sends 16 kHz mono PCM through the relay to Sarvam Saaras v3 in transliteration mode, so Hindi-English speech stays in stable Roman-script Hinglish while recognition happens. The language and output style are fixed when recording starts and reused by every fallback. The same 16 kHz PCM is retained as a WAV until a card saves; this avoids route-dependent AAC encoder failures while remaining small enough for the three-minute cap. If the stream fails or returns no speech, `transcribe` retries the completed file and Apple Speech remains the offline fallback.

The deployed `rewrite` function owns Claude and DeepSeek routing. The app remembers an exponentially weighted latency per provider, prefers the fastest one, and the function fails over to the other provider. Provider keys stay in the `SARVAM`, `CLAUDE`, and `DEEPSEEK` Supabase secrets; users never enter or receive them.

## Vernacular intelligence and personal terms

VoiceCards preserves three layers: the verbatim STT result (`rawText`), conservative smart cleanup (`enhancedText`), and an optional mode rewrite (`processedText`). The detail screen always exposes the original. Cleanup may fix clear recognition, punctuation, casing, and agreement errors, but its prompt explicitly forbids translation, formalization, or flattening vernacular/code-switching.

After a card is accepted, the on-device personal lexicon learns recognized names immediately and recurring two-word sayings after repeated use. Up to 40 high-value terms are supplied to Whisper and the cleanup provider. Terms never leave the device except as vocabulary hints in a transcription/cleanup request.

## Enable the keyboard

On iPhone, open **Settings → General → Keyboard → Keyboards → Add New Keyboard → VoiceCards**, then enable **Allow Full Access**. Full Access is needed only to read the private App Group database. The keyboard does not access the microphone, monitor the clipboard, or transmit typed text.

The idle keyboard is split into **Clipboard Items** and **Tap to Speak**. Clipboard history is captured locally whenever the app or keyboard is active and may trigger Apple’s paste-permission prompt. iOS does not expose copies made before VoiceCards observed them and VoiceCards never attempts background monitoring. Text and links insert directly; tapping an image restores it to the system clipboard and explains how to use the host app’s Paste command. Images are stored in the private App Group and are never sent to an AI provider.

Speak uses `StartKeyboardDictationIntent` to foreground the main app because iOS extensions cannot own microphone capture. After the audio engine and ActivityKit respond, VoiceCards shows **Mic is on** with an animated bottom-edge swipe instruction; swipe right along the Home indicator to return to the previous app while capture and streaming continue. When recording stops, the Live Activity ends and the transcript is immediately published to the keyboard, which inserts it into the active text field without another tap. The same text is copied as a recovery path if iOS replaced the keyboard. Modes remain available when re-running the saved card.

## Architecture

The main app uses SwiftUI with `@Observable` MV models. Shared SwiftData models and repositories are compiled into the app and data extensions. `TranscriptionService` and `RewriteService` isolate providers; `RecordingSessionModel` owns the capture state machine and only deletes audio after a card saves. Failed audio stays in `PendingAudio`, is represented by `PendingOperation`, and retries at launch or when connectivity returns. Pinned cards are exempt from automatic retention. Settings shows the last measured recorder-ready, stop-to-transcript, rewrite, and stop-to-insert timings.

The share extension accepts text, Safari URLs, and images. Since OCR and image storage are v1 non-goals, an image creates a provenance card rather than inventing extracted text. The keyboard reads recent/pinned cards, searches locally, and inserts `processedText`, then `enhancedText`, then `rawText`. A small App Group session state machine coordinates keyboard dictation without giving the extension microphone access. The main app keeps its audio session alive after the handoff, publishes recording/transcribing state to the Live Activity, and the keyboard polls only that tiny state record so it can auto-insert completed text.

## Build verification

The following command is compile-only. Do not install its output in Simulator because disabling code signing also strips the simulated App Group entitlement:

```sh
xcodebuild -project VoiceCards.xcodeproj \
  -scheme VoiceCards \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/VoiceCardsDerived \
  CODE_SIGNING_ALLOWED=NO build
```

To run in Simulator, select the **VoiceCards** scheme in Xcode and press Run, or build without the `CODE_SIGNING_ALLOWED=NO` override. Xcode uses ad-hoc simulator signing and registers `group.com.APP.shared` for the app and both data extensions.

Unit tests use an in-memory SwiftData container and provider doubles. Run them on an installed iOS simulator or a signed device with the VoiceCards scheme.
