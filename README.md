# SayItFlow

**100% on-device push-to-talk voice dictation for macOS.**

Hold a key → speak → release.  
Clean text appears instantly in any app.

Runs entirely on-device with [Desert Ant Voz](https://desertant.com/models/voz/) on the Apple Neural Engine + S1-mini.  
**Zero cloud. Near-zero idle footprint. Your audio never leaves your Mac.**

---

### Why most “local” dictation apps still feel heavy

Other on-device tools keep large models loaded 24/7 (often 1.2–2.5 GB of RAM).  
They drain battery and keep your Mac warm even when you’re not speaking.

**SayItFlow is designed to disappear when you’re not using it.**

After 2 minutes of silence it cleanly unloads the models and drops to **~15–30 MB** with **0% CPU/GPU**.  
When you press the hotkey again, the models stream back in while you speak — so by the time you release the key, everything is already ready.

| State                    | RAM Footprint   | Overhead     |
|--------------------------|-----------------|--------------|
| Idle (> 2 min silence)   | **15–30 MB**    | **0.0%**     |
| Active dictation         | ~1.1–1.3 GB     | ANE + Metal  |
| Rapid successive use     | ~1.1–1.3 GB     | Instant      |

---

## What it does

- Hold **Spacebar** (or Fn / custom shortcut) anywhere
- Speak naturally
- Release → polished text is typed into the focused app (VS Code, Slack, Chrome, Terminal, Notes, etc.)

**Key strengths**
- **Private** — Audio never leaves your machine
- **Fast** — Voz on the Apple Neural Engine (up to 290× real-time)
- **Light** — Native Swift menu-bar app with intelligent model unloading
- **Multilingual** — 25 languages
- **Clean English** — S1-mini removes fillers, fixes punctuation & numbers

---

## Requirements

- macOS 14.0+ (Sonoma or Sequoia)
- Apple Silicon (M1 / M2 / M3 / M4 or newer)

---

## Install

### Download
Grab the latest `SayItFlow.dmg` from the [Releases](https://github.com/innovatorved/sayItflow/releases) page, drag it to `/Applications`, and launch.

On first run grant:
1. Microphone
2. Accessibility
3. Input Monitoring

### Build from source

```bash
git clone git@github.com:innovatorved/sayitflow.git
cd sayitflow
make dmg
```

---

## Usage

| Action            | Shortcut                              |
|-------------------|---------------------------------------|
| Push-to-talk      | Hold **Spacebar** (>0.5s), speak, release |
| Cancel            | **Escape**                            |
| Normal space      | Quick tap on Spacebar                 |
| Open dashboard    | Menu bar icon → Open Studio Dashboard |

---

## Architecture

`Mic → Desert Ant Voz (Core ML / Apple Neural Engine) → S1-mini → Injected text`

1. **Speech recognition** — [Desert Ant Voz](https://desertant.com/models/voz/) (467 MB, 25 languages, runs fully on the Neural Engine)
2. **Text cleanup** — [S1-mini by Superwhisper](https://huggingface.co/superwhisper/s1-mini) polishes English (fillers, punctuation, numbers). Non-English is left untouched.
3. **Hotkey engine** — Low-level `CGEventTap` (cleanly distinguishes taps vs long holds)
4. **Text insertion** — Accessibility API + keystroke fallback
5. **UI** — Minimal monochromatic menu-bar design

Extra engineering for smoothness:
- Hardware-accelerated audio metering (Accelerate / vDSP)
- Pre-allocated 120-second ring buffer (zero mid-speech allocations)
- Cached regexes & formatters

---

## License & Attribution

- **SayItFlow** - MIT © [innovatorved](https://github.com/innovatorved)
- **Desert Ant Voz** - Desert Ant Labs Source-Available License 1.0 (free under 100k MAUs)
- **S1-mini** - Apache 2.0 + naming clause © Superwhisper (must be credited as “S1-mini by Superwhisper”)

---

**Built for people who want local voice input that doesn’t punish the rest of the machine.**
