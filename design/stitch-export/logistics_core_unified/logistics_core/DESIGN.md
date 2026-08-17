---
name: Logistics Core
colors:
  surface: '#faf8ff'
  surface-dim: '#dad9e1'
  surface-bright: '#faf8ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f4f3fa'
  surface-container: '#eeedf4'
  surface-container-high: '#e8e7ef'
  surface-container-highest: '#e2e2e9'
  on-surface: '#1a1b21'
  on-surface-variant: '#45464c'
  inverse-surface: '#2f3036'
  inverse-on-surface: '#f1f0f7'
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
  tertiary-container: '#00210a'
  on-tertiary-container: '#339650'
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
  tertiary-fixed: '#95f8a7'
  tertiary-fixed-dim: '#79db8d'
  on-tertiary-fixed: '#00210a'
  on-tertiary-fixed-variant: '#005323'
  background: '#faf8ff'
  on-background: '#1a1b21'
  surface-variant: '#e2e2e9'
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
  label-md:
    fontFamily: Poppins
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
  caption:
    fontFamily: Poppins
    fontSize: 11px
    fontWeight: '400'
    lineHeight: 14px
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  base: 8px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  gutter: 16px
  margin-mobile: 16px
  margin-desktop: 32px
---

## Brand & Style
The design system is engineered for high-stakes logistics and transportation management. It prioritizes **Enterprise Trust** and **Operational Efficiency**. The visual language is a blend of **Corporate Modernism** and **Tactile Precision**, ensuring that data-heavy interfaces remain legible and actionable under pressure.

The aesthetic evokes stability through a Deep Navy foundation, while Amber Gold accents provide "high-visibility" cues reminiscent of industrial signage and logistics infrastructure. The interface avoids unnecessary decorative elements, focusing instead on structural clarity, high information density, and rapid cognitive processing.

## Colors
This design system utilizes a high-contrast palette to distinguish between organizational structure and operational action.

- **Primary (Deep Navy):** Used for global navigation, headers, and structural elements to convey authority.
- **Accent (Amber Gold):** Reserved exclusively for primary calls-to-action, active states, and critical highlights.
- **Semantic Colors:** Success (Green), Danger (Red), and Warning (Amber) follow industry standards for logistics safety and status reporting.
- **Surface Strategy:** The light gray background (#E5E7EB) provides a neutral canvas that allows white cards (#FFFFFF) to stand out, creating a clear physical separation between the workspace and the content.

## Typography
Poppins is used across all levels to maintain a clean, geometric, and modern feel. 

- **Hierarchy:** Display and Headline levels use tighter tracking and heavier weights for immediate impact. 
- **Body Text:** Standardized at 14px (md) for operational density, ensuring more information is visible on screen without sacrificing legibility.
- **Labels:** Uppercase application is recommended for `label-md` when used in table headers or small badges to improve scannability.
- **RTL Support:** The typeface selection ensures balanced x-heights for seamless transition between English and Arabic scripts.

## Layout & Spacing
The system follows a strict **8dp-based grid**. All dimensions, padding, and margins must be multiples of 8 (or 4 for micro-adjustments).

- **Fluid Infrastructure:** The layout uses a 12-column fluid grid for desktop and a 4-column grid for mobile.
- **Information Density:** For data-heavy tables and dashboards, the `sm` (8px) and `md` (16px) spacing tokens should be favored to keep related information grouped tightly.
- **Mobile-First:** On mobile, margins are fixed at 16px. Content should stack vertically, with operational cards taking full width.
- **RTL Logic:** Spacing and layout directions must mirror automatically; "padding-left" becomes "padding-inline-start".

## Elevation & Depth
This design system uses a **Tonal Layering** approach combined with subtle ambient shadows to define hierarchy.

- **Level 0 (Background):** #E5E7EB. The base canvas.
- **Level 1 (Surface):** #FFFFFF. Used for main content cards. Features a soft, low-opacity shadow (0px 2px 4px rgba(13, 19, 33, 0.08)).
- **Level 2 (Interactive):** Used for dropdowns and hovering states. Features a more pronounced shadow (0px 4px 12px rgba(13, 19, 33, 0.12)).
- **Level 3 (Modals/Sheets):** Used for bottom sheets and dialogs. High elevation shadow to isolate the component from the background process.

## Shapes
The shape language is restrained and professional, favoring functional geometry over decorative softness.

- **Micro (2px):** Used for state indicators and checkbox markers.
- **Small (4px):** Used for status badges and small tags.
- **Standard (8px):** The default for buttons, input fields, and standard controls.
- **Medium (12px):** Used for operational cards and content containers.
- **Large (24px):** Specifically for top corners of mobile bottom sheets and prominent dashboard widgets.
- **Pill Shapes:** Avoided except for purely cosmetic, non-functional icons or very specific high-contrast labels.

## Components

### Buttons
- **Primary:** Amber Gold (#FFC107) background with Navy (#0D1321) text. Bold, high-visibility for main actions like "Confirm Shipment."
- **Secondary:** Deep Navy (#0D1321) ghost buttons or solid Navy with White text for navigation/utility.
- **Destructive:** Solid Danger Red (#BA1A1A) with White text.

### Text Fields & Dropdowns
- **Input:** 8px radius, white surface, 1px border (#D1D5DB). On focus, border changes to Deep Navy with a 2px stroke.
- **Labels:** Always positioned above the field using `label-md`.

### Status Badges
- **Style:** Small radius (4px), light tinted background of the semantic color with a dark, high-contrast text label (e.g., Success Light background + Success Dark text).

### Operational Cards
- White surface, 12px radius. Should include a "header" area for IDs (e.g., Tracking #) and a "body" for logistics details. Use a vertical 8px padding rhythm between data rows.

### Bottom Sheets (Mobile)
- Used for quick status updates or filter selections. 24px top-left and top-right radius. Includes a "drag handle" at the top center.

### Progress Timelines
- Vertical for mobile, horizontal for desktop. Use Deep Navy for completed steps and Amber Gold for the current "In-Transit" active step.