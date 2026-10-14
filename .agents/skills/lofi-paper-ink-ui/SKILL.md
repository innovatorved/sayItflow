---
name: lofi-paper-ink-ui
description: Monitor YT Lo-Fi Paper & Ink Neo-Brutalist UI Design System used across SayItFlow Android and macOS. Trigger whenever building, updating, or styling UI, icons, cards, pills, headers, or floating HUDs for SayItFlow or when the user requests the Monitor YT / SayItFlow Lo-Fi Paper & Ink aesthetic.
---

# Monitor YT Lo-Fi Paper & Ink Neo-Brutalist UI System

This skill enforces the signature **Monitor YT (`monitoryt.com`) Lo-Fi Paper & Ink Neo-Brutalist** visual language across Android (Jetpack Compose) and macOS (SwiftUI / AppKit), including app icons, headers, cards, pills, and floating overlays.

## 1. Exact Color Tokens

Never substitute flat generic grays or muted pastels. Always use these exact hex values:

| Token | Hex | Purpose |
|---|---|---|
| `PaperBg` | `#FBF3E4` | Primary warm paper background (paired with radial ink dot-grid) |
| `PaperDeep` | `#F3E4C6` | Secondary warm parchment surface (tab bar track, secondary badges, history container) |
| `CardWhite` | `#FFFFFF` | Primary studio card surface |
| `CardButter` | `#FFF7E0` | Sticky-note yellow card surface (setup checklist, editable scratchpad, active waveform box) |
| `CardMint` | `#E6FBF6` | Mint card surface (language selector card, success banners) |
| `CardPeach` | `#FFF0EC` | Peach card surface (REC timer badge, clear/delete pills, alert states) |
| `Ink` | `#1B1712` | Primary text, all `2px` borders, all hard offset shadows, ticker strip background |
| `InkSoft` | `#5A5044` | Secondary body/subtitle copy |
| `InkMuted` | `#8A7E6E` | Placeholder text and subtle labels |
| `AccentRed` | `#FF3B2F` | Primary CTA button fill (`Start Voice Dictation`), recording status dot, active waveform peaks |
| `AccentRedDeep` | `#D52817` | Recording timer text color |
| `AccentYellow` | `#FFCE4A` | Brand icon badge fill, active segmented tab fill, `STUDIO` tag pill, ticker right highlight |
| `AccentTeal` | `#36C2AD` | Ready status pill fill, `NOTE` tag fill, transcribing waveform bars, completed checkmarks |
| `AccentSky` | `#74A7FF` | Step badges and accent chips |
| `AccentCoral` | `#FF9E86` | Secondary warm badge accent |
| `AccentLilac` | `#C8A8FF` | Secondary creative/AI accent |

## 2. Signature Brand Icon (Yellow Neo-Brutalist 3-Bar Box)

The SayItFlow app icon (both inside the header bar and as the Android/macOS launcher icon) MUST always match the in-app `LofiHeaderBar` brand mark:
- **Outer Canvas / Adaptive Background**: Warm paper `#FBF3E4` (with subtle dot grid or clean `#FBF3E4` surface).
- **Boxed Badge**: Rounded square (`cornerRadius` ~28% of box size) filled with **`AccentYellow` (`#FFCE4A`)**, bordered by a crisp **`Ink` (`#1B1712`) stroke**, with a **hard bottom-right offset shadow in solid `Ink` (`#1B1712`)**.
- **3 Vertical Waveform Bars inside the Yellow Box**: Three rounded vertical capsules in solid **`Ink` (`#1B1712`)** arranged horizontally with equal spacing:
  - **Left bar**: Short height (~26% of box height)
  - **Center bar**: Tall height (~47% of box height)
  - **Right bar**: Medium height (~32% of box height)
