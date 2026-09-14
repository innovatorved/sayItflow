# SayItFlow

Push-to-talk voice dictation for macOS.

Runs entirely on-device using [Desert Ant Voz](https://desertant.com/models/voz/) on the Apple Neural Engine. Zero cloud, 0% CPU/GPU overhead.

---

## What it does

Hold **Spacebar** (or Fn / custom shortcut) anywhere on your Mac. Speak. Release.

Your speech is transcribed locally and typed directly into whichever app has focus — VS Code, Slack, Chrome, Terminal, Notes, or anything else.

- **Private**: Audio never leaves your Mac.
- **Fast**: Core ML running on the Apple Neural Engine (ANE).
- **Light**: Native Swift menu bar app with zero idle bloat.
- **Multilingual**: Supports 25 languages.

---

## Why SayItFlow? (Zero Idle Footprint)

Most on-device AI voice apps leave large language and speech models resident in your Mac's RAM 24/7 — consuming **1.2 GB to 2.5 GB of unified memory**, draining battery, and keeping GPU buffers warm even when you haven't spoken in hours.

**SayItFlow is engineered to be invisible when you're not speaking.**

### Intelligent Model Lifecycle Management

SayItFlow uses a **smart 120-second inactivity lifecycle**:
1. **While speaking & during active sessions**: Models remain hot and warm in memory for instantaneous, zero-latency dictations and rapid back-to-back phrases.
2. **After 120 seconds of silence**: SayItFlow cleanly unloads the Core ML Neural Engine weights from unified memory and shuts down the S1-mini normalizer process, dropping background footprint to just **~15–30 MB**.
3. **When you press the hotkey again**: Thanks to Apple Silicon's Unified Memory Architecture (UMA) and NVMe speeds (3,000–5,000 MB/s), the model streams into memory in sub-second time **while you are speaking**. By the time you finish your sentence and release the key, the entire pipeline is primed and ready.

### Memory & Performance Profile

| State | Model Residency | Total RAM Footprint | CPU / GPU Overhead |
| :--- | :--- | :--- | :--- |
| **Idle** (> 2 min of silence) | **Unloaded** (ANE weights released, server stopped) | **~15 – 30 MB** | **0.0%** (Zero background load) |
| **Active Dictation** | **Hot** (Voz Core ML + S1-mini warm in memory) | ~1.1 – 1.3 GB | High-efficiency ANE + Metal GPU |
| **Successive Phrases** (< 2 min apart) | **Hot** (0 ms load penalty) | ~1.1 – 1.3 GB | Instantaneous transcription & injection |

### Model Load & Response Speeds

| Component | Weight Size | Engine / Hardware | Cold Load from Idle | Runtime Speed |
| :--- | :--- | :--- | :--- | :--- |
| **Desert Ant Voz** | 467 MB | Apple Neural Engine (Core ML) | **~400 ms – 900 ms** (loads while speaking) | **290x real-time** (10m in ~2s) |
| **S1-mini Normalizer** | 462 MB (Q4_K_M) | Metal GPU | **~1.2 s – 1.8 s** | **50 ms – 150 ms** inference |

### Engineered for Real-Time Smoothness
- **Hardware SIMD Audio Math**: Peak volume meters use Apple's `Accelerate` framework (`vDSP_rmsqv`) for zero-overhead vector calculations.
- **Zero Allocator Pressure**: Pre-allocates a 120-second audio capture ring buffer to eliminate heap reallocations mid-speech.
- **Pre-compiled Regex & Formatter Caching**: Speech disfluency cleanup and logging use cached formatters and compiled regexes to eliminate syscall and allocation churn.

---

## Requirements

- macOS 14.0+ (Sonoma or Sequoia)
- Apple Silicon (M1, M2, M3, M4, or newer)

---

## Install

### Download DMG

Download `SayItFlow.dmg`, drag **SayItFlow.app** to `/Applications`, and launch it.

On first launch, follow the setup to grant:
1. **Microphone**: to capture audio while the hotkey is held.
2. **Accessibility**: to inject text at the active caret.
3. **Input Monitoring**: to detect the global push-to-talk key.

### Build from source

```bash
git clone git@github.com:innovatorved/sayitflow.git
cd sayitflow

# Build and package DMG
make dmg

# Or build and run tests
make test
```

---

## Usage

| Action | Shortcut |
| :--- | :--- |
| **Push to Talk** | Hold **Spacebar** (>0.5s), speak, release |
| **Cancel Dictation** | Press **Escape** |
| **Normal Space** | Tap **Spacebar** quickly |
| **Dashboard** | Click menu bar icon → **Open Studio Dashboard** |

---

## Architecture

SayItFlow uses a two-stage on-device pipeline:

```
Audio (Mic) ──▶ Desert Ant Voz (Apple Neural Engine Core ML) ──▶ S1-mini by Superwhisper (ANE / Mac Runtime) ──▶ Injected Text
```

1. **Speech Recognition**: [Desert Ant Voz](https://desertant.com/models/voz/) runs on the Apple Neural Engine via Core ML (467 MB weights, 290x real-time, 25 languages).
2. **Text Normalization**: ["S1-mini" by "Superwhisper"](https://huggingface.co/superwhisper/s1-mini) (596M parameter causal LM based on Qwen3) polishes English transcripts: removes filler words ("um", "uh", "like"), fixes punctuation/numbers, and structures output. Non-English dictations pass directly without alteration.
3. **Hotkey Engine**: Low-level `CGEventTap` accurately distinguishes instant tap vs. long hold (>0.5s).
4. **Text Insertion**: Accessibility API (`AXUIElement`) with keystroke fallback into active caret.
5. **UI**: Monochromatic precision design (dark `#000000` / light `#ffffff`).

---

## License & Attribution

- **SayItFlow App**: [MIT License](LICENSE) © [innovatorved](https://github.com/innovatorved)
- **Desert Ant Voz Model**: Licensed under the [Desert Ant Labs Source-Available License 1.0](https://license.desertant.com/1.0) (`LicenseRef-DAL-Source-Available-1.0`) © 2026 Desert Ant Labs B.V.
  - Free below 100,000 monthly active devices per platform.
  - Prohibits using model outputs to train competing on-device models.
  - See [Desert Ant Licensing](https://license.desertant.com/1.0) and [Attribution](https://license.desertant.com/attribution) for full terms.
- **S1-mini Model**: ["S1-mini" by "Superwhisper"](https://huggingface.co/superwhisper/s1-mini) is licensed under the Apache License 2.0 with the additional requirement to identify the model by its original name: **"S1-mini"** by **"Superwhisper"**. © 2026 Superwhisper (https://superwhisper.com).

