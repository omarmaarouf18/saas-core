# Waddify brand spec

Working reference for the rebrand decided in [ADR-0029](../adr/0029-rebrand-to-waddify.md). The ADR holds the
decision and its reasons; this file is what implementers copy from. Visual board (owner's private design
canvas): https://claude.ai/artifact/9TkAegce2oLaQWSnhJjSSC

## Assets

| File | Use |
| :--- | :--- |
| [waddify/mark.svg](waddify/mark.svg) | Full-colour mark, 48 px and up |
| [waddify/mark-mono.svg](waddify/mark-mono.svg) | One colour (`currentColor`), 24-47 px; under 24 px drop the tail |
| [waddify/app-icon.svg](waddify/app-icon.svg) | 1024 px app icon master (Ink tile, full bleed) |

These are concept-quality vectors drawn in code. Before release a designer redraws them as the final master
and exports the iOS and Android (adaptive: foreground + background layers) icon sets.

## Wordmark and lockups

- Latin wordmark: `waddify`, Readex Pro Bold, letter-spacing about -3 % of the size, `wadd` in Ink and `ify` in Nile.
  On dark: white + Nile Light.
- Arabic wordmark: `ودّيفاي`, Readex Pro Bold, Ink (white on dark).
- Horizontal lockup (LTR): mark, then `waddify`. Arabic lockup (RTL): mark on the reading start (right), then `ودّيفاي`.
- Primary lockup: mark above `waddify | ودّيفاي`, tagline `خليها تطير · Let it fly` below.
- Endorsement badge inside business-branded surfaces: pill, `Powered by [mark] waddify` (light) or
  `بتشغيل [mark] waddify` (dark). The business's brand leads; the badge is never larger than its body text.

## Tokens

```text
ink         #10233F   text, mark, dark surfaces
nile        #0E7C7B   primary action fill (on-nile: #FFFFFF)
nileLight   #2FB5B3   accent on dark only
sun         #F2A541   highlight / CTA on nile (on-sun: #10233F); not for text on light backgrounds
sand        #F7F6F2   app background
line        #D6D2C6   hairlines, dividers
muted       #5C6470   secondary text on sand/white (passes 4.5:1)
```

Font: Readex Pro 400 / 500 / 700 for Arabic and Latin.

## Copy

- Customers: خليها تطير. Market screen heading: مين يطيّرهالك؟ (ranked by rating).
- Businesses: شركتك في أمان، وأوردراتك بتطير. / أبلكيشن توصيل باسم شركتك، وأدوات إدارة ومتابعة كاملة.
- Store title: `Waddify: منصة نقل وتوصيل`.
- Never promise that Waddify itself delivers or guarantees a time; the chosen provider does.

## Don'ts

- Don't rotate, mirror or re-tilt the mark (55° is fixed), add outlines or shadows, or place it on busy photos.
- Don't write the name as two words or translate it.
- Don't use Sun for body text on light backgrounds or Nile Light on light backgrounds (contrast).
