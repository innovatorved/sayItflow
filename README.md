# SayItFlow

**100% on-device push-to-talk voice dictation for macOS & Android.**

Hold a key → speak → release.  
Clean text appears instantly in any app.

- **macOS**: Runs on-device with [Desert Ant Voz](https://desertant.com/models/voz/) on the Apple Neural Engine + S1-mini.
- **Android**: Runs on-device with a **Whisper-Tiny INT8/Q4 ONNX + Live Streaming Hybrid Engine** + S1-mini across all Android phones (no Pixel Tensor required).

**Zero cloud. Near-zero idle footprint. Your audio never leaves your device.**

| Platform | Download | Push-to-Talk Trigger |
|----------|----------|----------------------|
| **macOS** (Apple Silicon, macOS 14+) | [`brew install --cask innovatorved/tap/sayitflow`](#macos) or [Download `.dmg`](https://github.com/innovatorved/sayItflow/releases) | Hold **Spacebar** (or Fn / custom shortcut) |
| **Android** (Android 8.0+ / API 26+) | [**Download `SayItFlow-Android-v1.7.0.apk`**](https://github.com/innovatorved/sayItflow/releases/download/v1.7.0/SayItFlow-Android-v1.7.0.apk) ([All Releases](https://github.com/innovatorved/sayItflow/releases)) | Hold **Volume Down** (or Volume Up) anywhere |

---

### Why most “local” dictation apps still feel heavy

Other on-device tools keep large models permanently resident in RAM 24/7 (often 500 MB–2.5 GB).  
They drain battery and warm up your laptop or phone even when you’re not speaking.

**SayItFlow is designed to disappear when you’re not using it — on both macOS and Android:**

- **macOS**: After 2 minutes of silence it cleanly unloads the models and drops to **~15–30 MB** with **0% CPU/GPU**. When you press the hotkey again, the models stream back in while you speak.
- **Android**: Uses **On-Demand RAM Lifecycle (`0 MB` idle model footprint)**. Whisper-Tiny INT8/Q4 ONNX stays on disk at rest, loads into memory in ~180 ms while you hold the Volume key and speak, and automatically unloads from RAM after dictation completes.

| Platform & State                 | Model RAM Footprint | Idle CPU / GPU |
|----------------------------------|---------------------|----------------|
| **macOS** — Idle (> 2 min)       | **15–30 MB**        | **0.0%**       |
| **macOS** — Active dictation     | ~1.1–1.3 GB         | ANE + Metal    |
| **Android** — Idle               | **0 MB (Unloaded)** | **0.0%**       |
| **Android** — Active dictation   | ~45 MB (Whisper Q4) | CPU / XNNPACK  |

---

## What it does

- **On macOS**: Hold **Spacebar** (or Fn / custom shortcut) anywhere → speak naturally → release to inject polished text into the focused app (VS Code, Slack, Chrome, Terminal, Notes, etc.).
- **On Android**: Hold **Volume Down** in any app (WhatsApp, Telegram, Chrome, Gmail, Notes, Slack) → speak naturally → release to inject clean text directly into the focused input field with a minimal floating bottom waveform pill.

**Key strengths**
- **Private** — Audio is processed locally; nothing leaves your Mac or Android phone
- **Fast** — Sub-second release-to-text latency on both Apple Silicon and standard ARM64 Android CPUs
- **Light** — Intelligent on-demand model loading & automatic idle RAM unloading
- **Multilingual & Hinglish** — Supports English, Hindi, Hinglish (Romanized), and 25+ languages
- **Clean Text** — S1-mini removes conversational fillers (`um`, `uh`), fixes punctuation, capitalization & numbers

---

## Install

### macOS

**Requirements:** macOS 14.0+ (Sonoma or Sequoia) on Apple Silicon (M1 / M2 / M3 / M4 or newer).

#### Homebrew
```bash
brew tap innovatorved/tap
brew install --cask sayitflow
```

To update later:
```bash
brew update && brew upgrade --cask sayitflow
```

#### Manual Download
Grab the latest `SayItFlow.dmg` from the [Releases](https://github.com/innovatorved/sayItflow/releases) page, drag it to `/Applications`, and launch.

---

### Android

**Requirements:** Android 8.0+ (API 26+) on any ARM64 phone.

#### Direct APK Download
1. Download [**`SayItFlow-Android-v1.7.0.apk`**](https://github.com/innovatorved/sayItflow/releases/download/v1.7.0/SayItFlow-Android-v1.7.0.apk) from the [Releases](https://github.com/innovatorved/sayItflow/releases) page.
2. Open the APK on your Android phone to install.
3. Launch **SayItFlow** and complete the 3 one-tap setup steps in the dashboard:
   - Grant **Microphone** permission
   - Grant **Overlay** permission (for the compact bottom waveform pill while holding Volume Down)
   - Enable **SayItFlow Accessibility Service** (detects Volume key hold-to-talk and injects text into any focused text box)

---

### Build from source

#### macOS (`apps/macos`)
```bash
git clone https://github.com/innovatorved/sayItflow.git
cd sayItflow
make dmg
```

#### Android (`apps/android`)
```bash
git clone https://github.com/innovatorved/sayItflow.git
cd sayItflow/apps/android
./gradlew assembleRelease
```

---

## Usage

### macOS Shortcuts

| Action            | Shortcut                              |
|-------------------|---------------------------------------|
| Push-to-talk      | Hold **Spacebar** (>0.5s), speak, release |
| Cancel            | **Escape**                            |
| Normal space      | Quick tap on Spacebar                 |
| Open dashboard    | Menu bar icon → Open Studio Dashboard |

### Android Shortcuts

| Action            | Trigger                               |
|-------------------|---------------------------------------|
| Push-to-talk      | Hold **Volume Down** (>0.22s), speak, release |
| Normal volume     | Quick tap on Volume Down / Volume Up  |
| In-app dictation  | Hold the **Hold to Dictate** button inside SayItFlow Studio |

---

## Architecture

### macOS (`apps/macos`)
`Mic → Desert Ant Voz (Core ML / Apple Neural Engine) → S1-mini → Injected text`

1. **Speech recognition** — [Desert Ant Voz](https://desertant.com/models/voz/) (467 MB, 25 languages, runs fully on the Apple Neural Engine)
2. **Text cleanup** — [S1-mini by Superwhisper](https://huggingface.co/superwhisper/s1-mini) polishes English (fillers, punctuation, numbers)
3. **Hotkey engine** — Low-level `CGEventTap` (cleanly distinguishes taps vs long holds)
4. **Text insertion** — Accessibility API + keystroke fallback
5. **UI** — Minimal monochromatic menu-bar design

### Android (`apps/android`)
`Mic (16 kHz Pre-Roll + Adaptive Tail) → Whisper-Tiny INT8/Q4 ONNX + Live Streaming Hybrid → Hinglish & S1-mini Normalizer → AccessibilityNodeInfo Text Injection`

1. **Speech recognition** — Bundled **Whisper-Tiny INT8/Q4 ONNX** (`43 MB`, CPU + XNNPACK accelerated, works offline on all Android devices) paired with live streaming partial previews while holding the button
2. **On-Demand RAM Lifecycle** — `0 MB` idle model RAM; loads on `ACTION_DOWN` while you speak and unloads automatically after idle timeout
3. **Zero-clipping audio capture** — Continuous 400 ms pre-roll ring buffer + adaptive acoustic tail flush (`20 ms` exit on trailing silence)
4. **Text cleanup & Hinglish** — On-device S1-mini filler removal, smart punctuation, and Hinglish/Devanagari normalization
5. **UI** — Warm Paper & Ink Neo-Brutalist Studio Dashboard + zero-idle-clutter bottom floating waveform pill

---

## License & Attribution

- **SayItFlow** - MIT © [innovatorved](https://github.com/innovatorved)
- **Desert Ant Voz** - Desert Ant Labs Source-Available License 1.0 (free under 100k MAUs)
- **OpenAI Whisper (ONNX INT8/Q4)** - Apache 2.0 / MIT
- **S1-mini** - Apache 2.0 + naming clause © Superwhisper (must be credited as “S1-mini by Superwhisper”)

---

**Built for people who want local voice input that doesn’t punish the rest of their Mac or Android phone.**

