# Copy website, design system ("Glass Workbench")

Built with the 2389-research landing-page-design methodology (vibe discovery first,
anti-AI-slop typography/color, hero-first). Fully self-contained: no CDNs, web fonts, or
analytics. Fonts are self-hosted woff2 under `assets/fonts/`.

## Vibe spec

- **Vibe name:** Glass Workbench
- **Reference:** a pro macOS utility running late at night, Liquid Glass panels floating
  on near-black, lit like tools on a machinist's bench.
- **Emotion:** confident, focused (a precise power tool you trust).
- **Collision:** macOS Liquid Glass translucency × workbench/engineering precision
  (monospace labels, measured grid, exact hairlines).
- **Anti-patterns (never resemble):** SaaS-slop (purple gradient + Inter), crypto/AI hype,
  a Paste (pasteapp.io) clone, anything cute.
- **Signature:** a translucent glass "shelf" of clipboard cards that slides up on load;
  the one saturated accent (electric blue) is reserved for the selected card + CTAs.
- **Wildcard:** physical ⇧⌘V keycaps + a faint blueprint measurement grid behind the hero.

## Color (no purple; one electric accent)

```
--bg #0B0C0F  --bg-2 #101217  --surface #15171D  --surface-2 #1C1F27
--line #262A33  --line-2 #333A46
--text #ECEDF1  --dim #A2A8B4  --mute #6B7280
--accent #4C9DFF  --accent-2 #6FB0FF  --accent-dim #2E6FD6  (CTAs + selected card only)
```

## Type (kills Inter/Roboto defaults)

- **Display:** Sora 700/800 (self-hosted), geometric, technical, confident headlines.
- **Body:** system sans (`-apple-system`), authentic to a macOS product, fast, private.
- **Mono / labels / keycaps:** JetBrains Mono 500/700 (self-hosted), the "workbench"
  technical voice for eyebrows, section numbers (01/02/03), kbd chips, and card bodies.
- Fluid scale via `clamp()`; tight tracking on display.

## Layout & motion

- Dark, glass-panel-forward, hairline dividers (no color banding). Asymmetric hero
  (headline left, glass shelf bleeding off the right). Sections tagged with a mono number.
- Motion budget = the hero shelf (slide-up + staggered card settle) + quiet hover-lift on
  cards and a soft accent glow. `prefers-reduced-motion` fully respected (content always
  visible; no transforms/animation).

## Copy strategy

- **Headline (value prop + hook):** "Everything you copy, one shortcut away."
- **Subhead:** what + how (clipboard manager for macOS; ⇧⌘V slides up the shelf).
- **CTA:** "Get Copy, free" (answers the price objection in the button) + brew command.
- **Objections addressed:** built-in clipboard is enough (→ the visual shelf + power
  features), privacy (→ local-first section), price/subscription (→ free + GPL-3.0 in
  hero and CTA), native quality (→ the design + macOS-14 note).

## Constraints

- Self-contained (CSP-safe): the only external URLs are GitHub links and the site's own
  Open Graph og:url/og:image. No remote asset loads.
- `docs/appcast.xml` (Sparkle feed) is never touched by the site.
- App mockups stay accurate to the real UI (the blue "selected card" is the app's own
  behavior); site chrome uses the same single accent so the two read as one language.
