---
name: Kinetic Logistics
colors:
  surface: '#f9f9f9'
  surface-dim: '#dadada'
  surface-bright: '#f9f9f9'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f3f3f4'
  surface-container: '#eeeeee'
  surface-container-high: '#e8e8e8'
  surface-container-highest: '#e2e2e2'
  on-surface: '#1a1c1c'
  on-surface-variant: '#45464c'
  inverse-surface: '#2f3131'
  inverse-on-surface: '#f0f1f1'
  outline: '#76777d'
  outline-variant: '#c6c6cc'
  surface-tint: '#585e6f'
  primary: '#000000'
  on-primary: '#ffffff'
  primary-container: '#151b2a'
  on-primary-container: '#7e8395'
  inverse-primary: '#c1c6da'
  secondary: '#785900'
  on-secondary: '#ffffff'
  secondary-container: '#fdc003'
  on-secondary-container: '#6c5000'
  tertiary: '#000000'
  on-tertiary: '#ffffff'
  tertiary-container: '#191c1f'
  on-tertiary-container: '#818488'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#dde2f6'
  primary-fixed-dim: '#c1c6da'
  on-primary-fixed: '#151b2a'
  on-primary-fixed-variant: '#414657'
  secondary-fixed: '#ffdf9e'
  secondary-fixed-dim: '#fabd00'
  on-secondary-fixed: '#261a00'
  on-secondary-fixed-variant: '#5b4300'
  tertiary-fixed: '#e0e2e6'
  tertiary-fixed-dim: '#c4c7ca'
  on-tertiary-fixed: '#191c1f'
  on-tertiary-fixed-variant: '#44474a'
  background: '#f9f9f9'
  on-background: '#1a1c1c'
  surface-variant: '#e2e2e2'
typography:
  display-lg:
    fontFamily: Poppins
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Poppins
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
  headline-lg-mobile:
    fontFamily: Poppins
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  title-md:
    fontFamily: Poppins
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-lg:
    fontFamily: Poppins
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Poppins
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-lg:
    fontFamily: Poppins
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
  label-md:
    fontFamily: Poppins
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  xs: 4px
  sm: 12px
  md: 16px
  lg: 24px
  xl: 32px
  gutter: 16px
  margin-mobile: 16px
  margin-desktop: 48px
---

## Brand & Style

The design system is engineered for a multi-tenant logistics marketplace where efficiency and trust are paramount. The visual language adopts a **Corporate Modern** style, heavily influenced by **Material 3** principles but refined for a high-stakes professional environment. 

The aesthetic is defined by high-contrast structural elements, utilizing a Deep Navy foundation to signify stability and an Amber Gold accent to represent speed and premium service. The interface prioritizes clarity and rapid information processing, reflecting the urgent nature of delivery and transport. Whitespace is used systematically to separate distinct marketplace entities while maintaining a unified, authoritative presence. The emotional response is one of reliability, precision, and institutional strength.

## Colors

The palette is anchored by **Deep Navy (#0D1321)**, used for primary actions, structural navigation, and high-level headings. **Amber Gold (#FFC107)** serves as the high-visibility accent, reserved for critical calls-to-action (CTAs), Floating Action Buttons (FABs), and status highlights related to active movement or priority.

The background uses **Light Gray (#E5E7EB)** to provide a subtle contrast against **White (#FFFFFF)** surface cards, creating a clear "layered" effect that distinguishes content blocks. Functional colors for success, danger, and warning follow high-saturation standards to ensure immediate recognition in data-heavy dashboards. Gradients are strictly prohibited to maintain a clean, flat, and professional appearance.

## Typography

This design system utilizes **Poppins** across all levels to maintain a modern, geometric, and highly legible appearance. 

Headlines use SemiBold and Bold weights to create a strong hierarchy against the Deep Navy background or surface cards. Body text is kept at a comfortable 14px or 16px to ensure readability during fast-paced logistics operations. Labels use uppercase styling and increased letter-spacing for metadata, such as tracking numbers or timestamps, to distinguish them from primary content. On mobile devices, headline scales are reduced to prevent excessive wrapping while maintaining visual impact.

## Layout & Spacing

The layout follows a **fluid grid** model based on an **8px rhythm**. For mobile interfaces, a 4-column grid is used with 16px margins; for desktop, a 12-column grid with 24px gutters and 48px margins is standard.

Components and sections should scale based on logical multipliers of the base 8px unit. Spacing density is moderate—tight enough to display significant data in logistics tables, but generous enough around primary CTAs to avoid user error during high-speed navigation. Padding within cards should remain consistent at 16px (md) to maintain internal alignment.

## Elevation & Depth

In alignment with Material 3, hierarchy is established through **Tonal Layers** and **Ambient Shadows**. 

The background (#E5E7EB) acts as Level 0. Surfaces and cards (#FFFFFF) sit at Level 1, utilizing a soft, diffused shadow (0px 2px 8px rgba(13, 19, 33, 0.08)). Active elements or modals sit at Level 2 with a more pronounced shadow (0px 4px 16px rgba(13, 19, 33, 0.12)). 

Navigation bars and footers use a flat Deep Navy fill rather than elevation shadows to provide a "heavy" anchor to the layout. Interaction states (hover/active) should be signaled by a subtle shift in surface color or a 2dp elevation increase rather than complex gradients.

## Shapes

The design system employs a **Rounded** shape language to balance professional rigidity with modern accessibility. 

Standard UI elements like buttons, input fields, and small cards utilize an **8px (0.5rem)** corner radius. Large containers and main dashboard cards may use **16px (1rem)** for a softer, more distinctive containment. Floating Action Buttons and status chips utilize a **Pill** shape (max radius) to differentiate them from structural data containers.

## Components

### Buttons
- **Primary:** Solid Deep Navy (#0D1321) with White (#FFFFFF) text. 8px rounded corners.
- **Secondary/FAB:** Solid Amber Gold (#FFC107) with Deep Navy text. Pill-shaped for FABs, 8px rounded for standard buttons.
- **Ghost:** Deep Navy outline (1px) with transparent background and Deep Navy text.

### Inputs & Selects
- Background: White (#FFFFFF).
- Border: 1px Solid Light Gray (#E5E7EB), turning Deep Navy on focus.
- Placeholder: Medium Gray text in Poppins 14px.

### Cards
- Background: White.
- Border-radius: 8px or 16px.
- Padding: 16px.
- Use: Grouping logistics details, order summaries, and marketplace listings.

### Status Chips
- Height: 24px or 32px.
- Shape: Pill-shaped.
- Styling: Light tinted background of the status color (e.g., 10% opacity Success Green) with high-contrast text.

### Lists & Tables
- Dividers: 1px Solid #E5E7EB.
- Row Height: 56px for standard lists, 72px for lists with avatars or secondary icons.
- Font: Poppins 14px for primary data, 12px for metadata labels.