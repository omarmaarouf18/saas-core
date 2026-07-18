---
name: Nocturne Amber
colors:
  surface: '#121415'
  surface-dim: '#121415'
  surface-bright: '#37393b'
  surface-container-lowest: '#0c0e10'
  surface-container-low: '#1a1c1d'
  surface-container: '#1e2021'
  surface-container-high: '#282a2c'
  surface-container-highest: '#333537'
  on-surface: '#e2e2e4'
  on-surface-variant: '#c6c6cc'
  inverse-surface: '#e2e2e4'
  inverse-on-surface: '#2f3132'
  outline: '#909096'
  outline-variant: '#45464c'
  surface-tint: '#c1c6da'
  primary: '#c1c6da'
  on-primary: '#2a303f'
  primary-container: '#0d1321'
  on-primary-container: '#787e90'
  inverse-primary: '#585e6f'
  secondary: '#ffdf9e'
  on-secondary: '#3f2e00'
  secondary-container: '#fabd00'
  on-secondary-container: '#6a4e00'
  tertiary: '#abcae8'
  on-tertiary: '#12334b'
  tertiary-container: '#001525'
  on-tertiary-container: '#63819d'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#dde2f6'
  primary-fixed-dim: '#c1c6da'
  on-primary-fixed: '#151b2a'
  on-primary-fixed-variant: '#414657'
  secondary-fixed: '#ffdf9e'
  secondary-fixed-dim: '#fabd00'
  on-secondary-fixed: '#261a00'
  on-secondary-fixed-variant: '#5b4300'
  tertiary-fixed: '#cce5ff'
  tertiary-fixed-dim: '#abcae8'
  on-tertiary-fixed: '#001d31'
  on-tertiary-fixed-variant: '#2b4963'
  background: '#121415'
  on-background: '#e2e2e4'
  surface-variant: '#333537'
typography:
  headline-lg:
    fontFamily: Geist
    fontSize: 40px
    fontWeight: '700'
    lineHeight: 48px
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: Geist
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 38px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Geist
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-md:
    fontFamily: JetBrains Mono
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
    letterSpacing: 0.05em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  base: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 40px
  gutter: 24px
  margin-mobile: 16px
  margin-desktop: 64px
---

## Brand & Style

The design system is built upon a philosophy of "Technical Sophistication." It targets a professional, high-end demographic in fields like aerospace, deep-tech finance, or premium developer tools. The UI is designed to evoke a sense of precision, authority, and quiet confidence.

The design style is **Corporate Modern with a Minimalist edge**. It prioritizes extreme legibility and structural integrity. By utilizing a deep, monochromatic base punctuated by high-vibrancy accents, the system creates a focused "cockpit" environment where data and primary actions are unmistakably prioritized.

## Colors

This design system utilizes a high-contrast dark-mode palette. The foundation is **Deep Navy (#0D1321)**, serving as the core anchor for backgrounds and primary containers to reduce eye strain and establish a premium, technical atmosphere. 

**Amber Gold (#FFC107)** is the exclusive accent color. It is used sparingly for interactive highlights, call-to-actions, and critical state indicators. This color should always be paired with the primary navy for text to ensure AAA accessibility. Surface colors are slightly elevated versions of the primary navy to create subtle depth without breaking the dark aesthetic.

## Typography

The typography scale emphasizes technical clarity. We use a triple-font approach to categorize information types:
- **Headlines (Geist):** Used for structural headers. Its tight aperture and modern geometry reflect the "Technical Sophistication" brand pillar.
- **Body (Inter):** Used for all long-form reading and standard UI text. It provides maximum legibility across all display types.
- **Labels (JetBrains Mono):** Used for metadata, system status, and small utility text. The monospaced nature reinforces the developer-friendly and precise personality of the design system.

## Layout & Spacing

The design system employs a **Fixed Grid** philosophy for desktop layouts to maintain control over line lengths and information density. 

- **Grid:** 12-column system with a maximum content width of 1280px.
- **Rhythm:** An 8px linear scale (with a 4px "half-step" for tight components) governs all padding and margin decisions.
- **Adaptation:** On mobile devices, the 12-column grid collapses to 4 columns, and outer margins shrink from 64px to 16px. Gutters remain consistent at 24px to ensure breathing room between data points.

## Elevation & Depth

Depth is achieved through **Tonal Layers** rather than traditional drop shadows. In this dark environment, we use a "Source of Light" logic:
- **Level 0 (Background):** The Primary Deep Navy (#0D1321).
- **Level 1 (Cards/Panels):** A slightly lighter navy hex to indicate a raised surface.
- **Level 2 (Popovers/Modals):** These use a 1px low-contrast outline in a muted secondary tint to define boundaries against the dark background. 

Avoid heavy blurs or skeuomorphic shadows. The interface should feel like a flat, illuminated glass instrument.

## Shapes

The shape language is disciplined and "Soft-Square." By using a **0.25rem (4px)** base radius, we avoid the aggressive nature of sharp 90-degree corners while maintaining a professional, engineered look. 

- **Standard Elements:** 4px radius (Buttons, Inputs).
- **Containers:** 8px radius (Cards, Modals).
- **Interactive Icons:** 0px radius (Sharp) to maintain a technical, iconographic feel.

## Components

### Buttons
Primary buttons use the **Amber Gold (#FFC107)** background with **Deep Navy (#0D1321)** text. They are high-contrast and strictly rectangular with a 4px corner radius. Secondary buttons use a ghost style with an Amber Gold 1px border.

### Input Fields
Inputs are dark-filled (slightly lighter than the background) with a 1px subtle border. Upon focus, the border transitions to Amber Gold. All labels use the monospaced Label font for a "form-fill" aesthetic.

### Cards
Cards do not have shadows. They are defined by a background color that is one step lighter than the main canvas and a subtle 1px border to separate content blocks.

### Status Chips
Chips use a de-saturated version of the Amber Gold or Error Red. Text inside chips should always be uppercase and set in the monospaced font to differentiate them from standard body text.