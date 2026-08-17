# QuickDelivery Brand Identity & Visual Language Guidelines

> [!NOTE]
> **Specification Context**: This document formalizes the brand identity, visual rationale, voice, and competitor benchmarks for QuickDelivery (QD). It reconciles the existing design system implementation in [`frontend/lib/core/theme.dart`](../../frontend/lib/core/theme.dart) with enterprise product design best practices.

---

## 1. Brand Rationale & Color Personality

> [!IMPORTANT]
> **Formal Rationale Note**: This brand rationale is reconstructed and formalized based on the app's primary domain (B2B/B2C logistics & delivery SaaS) and the existing token implementation in `theme.dart`.

### Color Palette Meaning
The QuickDelivery color palette balances enterprise-grade industrial reliability with high-urgency commercial vitality:

* **Primary — Deep Navy (`#0D1321` / `AppColors.primary`)**:
  * **Personality**: Enterprise trust, architectural stability, precision, and security.
  * **Role**: Structural and architectural brand color used for dominant headers, dark mode surfaces, primary typography, and dark container backgrounds. Communicates industrial logistics rigor.
* **Secondary — Amber Gold (`#FFC107` / `AppColors.secondary`)**:
  * **Personality**: High-visibility energy, nocturnal movement, speed, and premium execution.
  * **Role**: Confirmed primary CTA and conversion action color across all primary action buttons (`PrimaryButton`), high-visibility anchors, active state indicators, call-to-action highlights, interactive focus states, and badge highlights.
* **Surfaces & Backgrounds**:
  * **Scaffold Background (`#E5E7EB` / `AppColors.scaffoldBackground`)**: Neutral cool gray providing clean separation between elevated content cards.
  * **Surface Container (`#FFFFFF` / `AppColors.surface`)**: Pure white card container background maximizing readability and contrast.
* **Functional & Status Colors (WCAG AA Compliant)**:
  * **Success (`#15803D` / `AppColors.success`)**: Dark green providing $\ge 5.02:1$ contrast ratio on white for completed states and verified badges.
  * **Danger (`#BA1A1A` / `AppColors.danger`)**: High-visibility crimson red ($\ge 10.1:1$ contrast) for cancellation actions, critical errors, and rejected statuses.
  * **Warning (`#B45309` / `AppColors.warning`)**: Warm amber-700 ($\ge 5.02:1$ contrast) for pending approvals, active negotiations, and escrow review warnings.

---

## 2. Logo & Logotype Usage Rules

### Asset & Emblem Specs
* **Asset Location**: [`frontend/assets/branding/qd_logo.svg`](../../frontend/assets/branding/qd_logo.svg)
* **Logotype Variant**: "QD" stylized monogram badge rendered on authentication screens (`login_screen.dart`, `signup_screen.dart`).

### Clear-Space & Sizing Rules
1. **Minimum Dimensions**:
   * **Standalone Badge**: $32 \times 32\text{ dp}$ (mobile navigation / app bar branding).
   * **Primary Auth Header**: $80 \times 80\text{ dp}$ container width for header branding cards.
2. **Clear-Space Requirement**:
   * A minimum padding of $8\text{ dp}$ ($1\times \text{AppSpacing.base}$) must surround the emblem boundary on all sides to prevent visual noise.
3. **Approved Background Contexts**:
   * **Dark Mode / Deep Navy**: Emblem rendered with Amber Gold outline/fill over `#0D1321`.
   * **Light Mode / Card Surface**: Emblem rendered inside a `ThemedCard` container over pure white `#FFFFFF` with `#0D1321` border tint.
   * **Forbidden Usage**: Never place raw SVG vectors directly over un-tinted photo assets or low-contrast gradients without an intermediate elevated container card.

---

## 3. Voice & Tone Guidance (UI Copy & Egyptian Market Localization)

Our UI copy directly reflects the Egyptian Colloquial Arabic (عامية مصرية) localization established in [`app_ar.arb`](../../frontend/lib/l10n/app_ar.arb).

### Tone Principles
1. **Direct & Conversational**: Use natural, everyday Egyptian commercial terms (e.g. "طلب السحب", "تجهيز الشحنة", "الباقة الأساسية") rather than overly formal Classical Arabic (فصحى) or dry technical jargon.
2. **Action-Oriented Verbs**: Button copy must use clear imperative or action verbs ("إرسال طلب السحب", "تأكيد الطلب", "حفظ التغييرات").
3. **Empathetic & Solution-Focused Error Handling**: When operations fail (e.g. invalid withdrawal amount or network loss), state the exact issue and immediate fix path clearly:
   * *Correct*: "المبلغ المطلوب يتجاوز الرصيد المتاح للسحب (200.00 ج.م)"
   * *Incorrect*: "خطأ في النظام 500: فشل العملية"

---

## 4. Competitor Benchmarks (Uber & Talabat UI Patterns)

QuickDelivery targets the visual rigor and interaction speed of market leaders like Uber and Talabat:

1. **Bottom-Sheet-Driven Lightweight Workflows**:
   * *Benchmark Pattern*: Rather than launching disruptive full-screen modal flows for quick inputs, lightweight actions (negotiation proposals, payout method pickers, quick confirmation dialogs) use bottom sheets or elevated overlay cards anchored to the bottom.
2. **Persistent Live Status Tickers & Micro-Pills**:
   * *Benchmark Pattern*: Active jobs feature persistent, glanceable status pills (e.g., live GPS pulse, step-by-step order progress timeline) that remain pinned at the top of the viewport.
3. **Single Primary Action per Card Container**:
   * *Benchmark Pattern*: Content is grouped into elevated `ThemedCard` containers where each card presents a clear visual hierarchy ending in a single high-contrast primary button, eliminating decision friction for field workers and business owners.
