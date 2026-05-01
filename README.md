# Note365 — Mobile (Flutter)

Cross-platform iOS / Android client for the Note365 real-time clinical
voice-transcription pipeline. Pairs with the .NET API in `Backend5/` (Google
STT v2 streaming + Gemini clinical-note generation) over a single
`/ws/transcribe` WebSocket.

## What it does

1. Captures microphone audio at 16 kHz / 16-bit / mono LPCM.
2. Streams it in 100 ms frames over WebSockets to the .NET backend.
3. Renders interim and final transcripts as the user speaks.
4. On stop, displays the Gemini-generated SOAP-style clinical note in a
   rich bottom sheet with copy / share / new-session actions.

## Architecture

Feature-based clean architecture with [Riverpod](https://riverpod.dev) for
state and DI, [`go_router`](https://pub.dev/packages/go_router) for routing,
and a small core layer for cross-cutting concerns. New features (auth,
patient history, settings…) drop into `lib/features/<name>/` without
touching transcription.

```
lib/
├─ main.dart                                  # ProviderScope bootstrap
├─ app/                                       # MaterialApp, router, theme
│  ├─ app.dart
│  ├─ router.dart
│  └─ theme/
│     ├─ app_colors.dart
│     └─ app_theme.dart
├─ core/                                      # Cross-cutting infrastructure
│  ├─ config/app_config.dart                  # --dart-define driven config
│  ├─ constants/audio_constants.dart          # 16 kHz, 16-bit, 100 ms frames
│  ├─ errors/failures.dart                    # Typed failures
│  ├─ logging/app_logger.dart                 # `logger` facade
│  └─ permissions/permission_service.dart     # Mic permission helper
└─ features/
   └─ transcription/
      ├─ data/
      │  ├─ models/                           # SessionConfig, TranscriptionEvent
      │  ├─ services/
      │  │  ├─ audio_capture_service.dart     # PCM-16 streaming + RMS
      │  │  └─ transcription_socket_service.dart  # WS protocol client
      │  └─ repositories/
      │     └─ transcription_repository.dart  # Audio + WS orchestration
      └─ presentation/
         ├─ controllers/
         │  ├─ transcription_state.dart
         │  └─ transcription_controller.dart  # StateNotifier + providers
         ├─ widgets/
         │  ├─ mic_hub.dart                   # Big animated record button
         │  ├─ waveform_visualizer.dart       # Live audio bars
         │  ├─ session_status_chip.dart       # STANDBY / LIVE / GENERATING
         │  ├─ ai_processing_indicator.dart   # Shimmer panel
         │  ├─ live_transcript_view.dart
         │  ├─ clinical_note_panel.dart       # Bottom-sheet final note
         │  └─ config_sheet.dart              # Custom prompt / model
         └─ screens/
            └─ transcription_screen.dart
```

### Why these choices

- **Riverpod** is the de-facto state management & DI standard for scalable
  Flutter apps: compile-time safe, asynchronous-first, testable, and
  decouples features without `InheritedWidget` ceremony.
- **`record` package** exposes a `Stream<Uint8List>` of raw PCM bytes so we
  match the React frontend's exact wire shape (16 kHz mono Linear16) without
  resampling on the server.
- **`web_socket_channel`** keeps the transport layer trivially testable —
  same package the rest of the Dart ecosystem standardizes on.
- **`go_router`** gives us a declarative route table that scales to deeper
  flows without a rewrite.

### WebSocket protocol (matches React frontend exactly)

1. Client opens `wss://…/ws/transcribe`.
2. **First text frame**: JSON `{ "prompt"?: string, "model"?: string }`.
3. **Audio**: binary frames of 16-bit LE PCM, ≤100 ms each.
4. **Stop**: text frame `"STOP"`.
5. Server streams JSON frames `{ transcript, isFinal, confidence, speakerLabel }`
   live, and finally one frame with `processedNote` + `fullTranscript`.

See `lib/features/transcription/data/services/transcription_socket_service.dart`.

## Running

### Prerequisites

- Flutter 3.41.x stable (Dart 3.11.x)
- Android: Android Studio + an emulator or USB-debug device
- iOS: Xcode + a simulator or signed provisioning profile

### Install dependencies

```bash
flutter pub get
```

### Run

The default backend URL points to the production Cloud Run instance the
React app uses (no extra setup required):

```bash
flutter run
```

To point at a local backend instead, override the URL at launch:

```bash
flutter run --dart-define=TRANSCRIPTION_WS_URL=ws://10.0.2.2:5000/ws/transcribe
```

> **Android emulator note:** `localhost` from the host maps to `10.0.2.2`
> inside the emulator.

### Build release artifacts

```bash
# Android (release APK)
flutter build apk --release \
  --dart-define=TRANSCRIPTION_WS_URL=wss://your-prod-url/ws/transcribe

# iOS (release IPA — requires Xcode signing)
flutter build ipa --release \
  --dart-define=TRANSCRIPTION_WS_URL=wss://your-prod-url/ws/transcribe
```

### Tests & analysis

```bash
flutter analyze
flutter test
```

## Permissions

| Platform | Permission                | Where                                                       |
| -------- | ------------------------- | ----------------------------------------------------------- |
| Android  | `RECORD_AUDIO`, `INTERNET`, `MODIFY_AUDIO_SETTINGS` | `android/app/src/main/AndroidManifest.xml` |
| iOS      | `NSMicrophoneUsageDescription` | `ios/Runner/Info.plist`                                |

Runtime mic permission is requested through `PermissionService` the first
time the user taps the mic button.

## Adding new features

1. Create `lib/features/<feature>/` with the same `data/` + `presentation/`
   split.
2. Register Riverpod providers under that feature.
3. Add a route in `lib/app/router.dart`.

The transcription feature is fully self-contained and is a good template
for the next ones.
