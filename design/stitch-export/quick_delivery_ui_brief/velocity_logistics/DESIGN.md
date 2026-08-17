---
name: Velocity Logistics
colors:
  surface: '#fcf8fa'
  surface-dim: '#dcd9da'
  surface-bright: '#fcf8fa'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f6f3f4'
  surface-container: '#f0edee'
  surface-container-high: '#eae7e9'
  surface-container-highest: '#e5e2e3'
  on-surface: '#1b1b1d'
  on-surface-variant: '#45464c'
  inverse-surface: '#313031'
  inverse-on-surface: '#f3f0f1'
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
  tertiary-container: '#281808'
  on-tertiary-container: '#987f69'
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
  tertiary-fixed: '#fbddc3'
  tertiary-fixed-dim: '#dec1a8'
  on-tertiary-fixed: '#281808'
  on-tertiary-fixed-variant: '#574330'
  background: '#fcf8fa'
  on-background: '#1b1b1d'
  surface-variant: '#e5e2e3'
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
  headline-md:
    fontFamily: Poppins
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  headline-sm:
    fontFamily: Poppins
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  title-lg:
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
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
    letterSpacing: 0.1px
  label-sm:
    fontFamily: Poppins
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.5px
  headline-lg-mobile:
    fontFamily: Poppins
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 36px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 8px
  margin-mobile: 16px
  gutter: 16px
  stack-sm: 8px
  stack-md: 16px
  stack-lg: 24px
---

## Brand & Style

The design system is engineered for **Quick Delivery (QD)**, focusing on the intersection of logistics efficiency and marketplace accessibility. The brand personality is **modern, trustworthy, and fast**, emphasizing a "mobile-native" DNA that feels responsive to real-time updates.

The visual style follows a **Corporate Modern** approach with high-performance utility. It utilizes a structured grid and clear hierarchy to ensure users can navigate complex delivery data and product listings with zero friction. The aesthetic combines the stability of deep navy with the kinetic energy of amber gold, creating an interface that feels both authoritative and urgent. 

Key design principles:
- **Kinetic Utility:** Every interaction should feel snappy.
- **Trusted Clarity:** Information density is balanced by generous whitespace to prevent cognitive overload.
- **Mobile-First Ergonomics:** Touch targets and bottom-oriented navigation are prioritized for one-handed operation.

## Colors

The palette is anchored by **Deep Navy (#0D1321)**, providing a premium and reliable foundation. **Amber Gold (#FFC107)** serves as the high-visibility accent, used exclusively for primary actions, status indicators related to "speed," and brand-critical touchpoints.

### Dark Mode Adaptation
In Dark Mode, the primary surface transitions to a deep variation of the navy family. 
- **Surface:** #161C2A
- **Background/Scaffold:** #0D1321
- **Secondary (Amber):** Remains consistent at #FFC107 to maintain high contrast and brand recognition.

### Status Colors
- **Success:** Use for "Delivered" or "Payment Confirmed."
- **Danger:** Use for "Cancelled" or "Critical Delay."
- **Warning:** Use for "Action Required" or "Awaiting Pickup."

## Typography

This design system uses **Poppins** across all levels to maintain a clean, geometric, and modern look. 

- **Headings:** Utilize **Bold (700)** or **SemiBold (600)** for clear hierarchy and a "strong" brand voice.
- **Body:** Use **Regular (400)** for long-form content and **Medium (500)** for emphasis within text blocks or buttons.
- **RTL Support:** The system is optimized for Arabic. Ensure line-heights are slightly increased (1.2x) when rendering Arabic script to prevent clipping of diacritics.

## Layout & Spacing

The system is built on a strict **8dp grid** to ensure mathematical harmony across all screen sizes.

- **Margins:** Standard mobile margins are fixed at **16dp**. 
- **Columns:** Use a 4-column grid for mobile and a 12-column fluid grid for desktop/tablet web views.
- **RTL Behavior:** All horizontal layouts must flip. Leading icons move to the right, and the navigation drawer slides from the right.
- **Vertical Spacing:** Use 8px increments (8, 16, 24, 32, 48) to separate logical sections.

## Elevation & Depth

Visual hierarchy is managed through **Tonal Layers** and subtle shadows.

- **Level 0 (Scaffold):** The #E5E7EB base layer.
- **Level 1 (Cards/Surface):** White surfaces with a very soft, diffused shadow (Blur: 8px, Y: 2px, Opacity: 4% Navy tint).
- **Level 2 (Active/Floating):** Used for FABs or active cards during drag-and-drop. Increased shadow (Blur: 16px, Y: 4px, Opacity: 8% Navy tint).
- **Glassmorphism:** Reserved for the Header/Top Bar. A 70% opacity surface with a 12px backdrop blur ensures content remains readable as it scrolls beneath the header.

## Shapes

The shape language reflects the "Rounded Square" badge of the logo.

- **Buttons & Inputs:** 8dp radius for a precise, technical feel.
- **Standard Cards:** 12dp radius to soften the layout.
- **Hero/Featured Elements:** 16dp radius to draw visual attention.
- **Bottom Sheets:** 24dp top-only radius to emphasize the "drawer" metaphor and mobile-native feel.

## Components

### Buttons
- **Primary:** Amber Gold (#FFC107) fill with Deep Navy (#0D1321) text. 8dp radius. Use for "Order Now," "Confirm," or "Pay."
- **Secondary:** Transparent fill with Deep Navy (#0D1321) 1.5px outline. 8dp radius. Use for "Cancel," "Back," or "Details."

### Input Fields
- 8dp corner radius. 1.5px outline using the **Outline Variant (#8E8F95)**.
- On focus: Outline changes to **Primary (#0D1321)** with a 2px width.

### Header (Top Bar)
- **Leading:** Logo badge (Deep Navy rounded square with 'QD' wordmark).
- **Trailing:** Notification bell icon with an Amber Gold dot for active alerts.
- **Background:** Tinted transparent with backdrop-blur.

### Navigation
- **Bottom Navigation:** A 4-tab shell (Home, Orders, Wallet, Profile). Active state uses a Primary Navy icon with an Amber underline or tint.

### Lists & Chips
- **Chips:** 40dp height, 20dp radius (pill), using a light tint of the primary color for unselected and Amber for selected states.
- **Lists:** Clean dividers using the **Scaffold (#E5E7EB)** color, 1px height.