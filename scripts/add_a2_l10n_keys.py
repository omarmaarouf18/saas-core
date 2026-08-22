#!/usr/bin/env python3
"""A2 remediation helper: append missing l10n keys (en + ar_EG) to both ARB files.
Idempotent: keys already present are skipped. Placeholders get @key metadata."""
import json
import sys
from collections import OrderedDict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
EN = REPO / "frontend/lib/l10n/app_en.arb"
AR = REPO / "frontend/lib/l10n/app_ar.arb"

P = lambda **kw: {"placeholders": {k: {"type": "String"} for k in kw}}

KEYS = [
    # --- chat_screen ---
    ("chatStatusLive", "Live", "مباشر"),
    ("chatStatusDisconnected", "Disconnected", "مقطوع"),
    ("chatJobTag", "Job #{shortId}", "شحنة #{shortId}", P(shortId="")),
    ("chatDirectChannel", "Direct Real-time Channel", "قناة مباشرة لحظية"),
    ("chatAccessDeniedJob",
     "Access Denied: You are not authorized to view or join the chat for Job #{jobId}.",
     "ممنوع الدخول: مش مسموحلك تشوف أو تنضم لشات الشحنة #{jobId}.", P(jobId="")),
    # --- customer_home_screen ---
    ("customerHomeWhereDeliver", "Where to deliver?", "هتوصّل فين؟"),
    ("customerHomeSearchHint", "Enter destination or pickup area...",
     "اكتب مكان التسليم أو الاستلام..."),
    ("commonOrigin", "Origin", "الاستلام"),
    ("commonDestination", "Destination", "التسليم"),
    ("courierAssignedLabel", "Courier: Assigned", "الكورير: اتحدد"),
    ("findingCourierLabel", "Finding Courier...", "بنجيب كورير..."),
    ("paymentMethodLine", "Payment: {method}", "الدفع: {method}", P(method="")),
    # --- customer_job_map_screen (+ shared) ---
    ("mapPickupBadge", "Pickup", "استلام"),
    ("waitingCourierUpdates", "Waiting for courier location updates...",
     "مستنيين تحديثات موقع الكورير..."),
    ("reconnectingTrackingStream", "Reconnecting live tracking stream...",
     "بنعيد الاتصال ببث التتبع المباشر..."),
    # --- shared filters ---
    ("filterAll", "All", "الكل"),
    # --- customer_marketplace_screen ---
    ("distanceAwayLine", "{distance} km away", "{distance} كم بعيد", P(distance="")),
    ("pricingBreakdownLine", "Base: {base} + {perKm}/km", "الأساس: {base} + {perKm}/كم",
     P(base="", perKm="")),
    ("estPriceLine", "Est. Price: {price}", "التقديري: {price}", P(price="")),
    ("chooseSearchLocation", "Choose Search Location", "اختار مكان البحث"),
    ("confirmBookingTitle", "Confirm Booking", "تأكيد الحجز"),
    ("categoryLine", "Category: {category}", "الفئة: {category}", P(category="")),
    ("pickupDistanceLabel", "Pickup Distance:", "مسافة الاستلام:"),
    ("kmUnitLine", "{distance} km", "{distance} كم", P(distance="")),
    ("estimatedTotalLabel", "Estimated Total:", "الإجمالي التقديري:"),
    ("codOptionTitle", "Cash on Delivery (COD)", "الدفع عند الاستلام (كاش)"),
    ("codOptionSubtitle", "Pay in cash directly to the driver upon arrival",
     "ادفع كاش للسايق مباشرة لما يوصلك"),
    ("betaEscrowNote",
     "Note: Escrow payments and wallet deductions are currently deferred for this beta launch.",
     "ملحوظة: الدفع بالضمان والخصم من المحفظة متأجلين حاليًا في الإطلاق التجريبي ده."),
    ("noRatingsLabel", "No ratings", "مفيش تقييمات"),
    # --- customer_jobs_screen ---
    ("reasonLine", "Reason: {reason}", "السبب: {reason}", P(reason="")),
    # --- employee_history_screen ---
    ("recentActivityHeader", "Recent Activity", "آخر النشاطات"),
    ("employeeHistorySubtitle", "Completed and cancelled jobs.", "الشحنات المكتملة والملغاة."),
    # --- employee_screen ---
    ("employeeManageSubtitle", "Manage delivery personnel and status.", "أدر العاملين وحالاتهم."),
    ("employeeSearchHint", "Search workers by name or email...",
     "دوّر على عامل بالاسم أو الإيميل..."),
    ("employeeFrozenStatus", "Frozen", "مجمّد"),
    ("noWorkersMatchFilter", "No workers found matching your filter.",
     "مفيش عاملين مطابقين للفلتر."),
    ("workerIdBadge", "ID: #QD-{id}", "الرقم: #QD-{id}", P(id="")),
    ("targetStatusLabel", "Target Status", "الحالة المطلوبة"),
    ("secureVerificationNote", "Required for secure out-of-band operations verification.",
     "مطلوب لتأكيد العمليات الحساسة بشكل آمن."),
    ("clientIpLine", "IP: {ip}", "الـ IP: {ip}", P(ip="")),
    # --- shared validators (employee_screen / signup / forgot / otp / dialogs) ---
    ("usernameRequired", "Username is required", "اسم المستخدم مطلوب"),
    ("usernameTooShort", "Username must be at least 3 characters",
     "اسم المستخدم لازم يكون 3 حروف على الأقل"),
    ("usernameTooLong", "Username must be at most 30 characters",
     "اسم المستخدم أقصاه 30 حرف"),
    ("usernameInvalidChars", "Username contains invalid characters",
     "اسم المستخدم فيه حروف غير مسموحة"),
    ("emailRequired", "Email is required", "الإيميل مطلوب"),
    ("invalidEmailFormat", "Please enter a valid email", "اكتب إيميل صحيح"),
    ("passwordRequired", "Password is required", "الباسورد مطلوب"),
    ("passwordTooShort", "Password must be at least 6 characters",
     "الباسورد لازم يكون 6 حروف على الأقل"),
    ("employeeEmailRequired", "Employee email is required", "إيميل الموظف مطلوب"),
    ("ownerPasswordRequired", "Owner password is required to re-authenticate",
     "لازم باسورد المالك لإعادة التأكيد"),
    ("enterOtp6Digits", "Enter 6-digit OTP code", "اكتب كود التحقق المكوّن من 6 أرقام"),
    ("otpExactly6Digits", "OTP must be exactly 6 digits", "كود التحقق لازم يكون 6 أرقام بالظبط"),
    # --- forgot_password_screen ---
    ("devOtpBanner", "Dev OTP Code: {otp}", "كود التجربة: {otp}", P(otp="")),
    # --- otp_screen ---
    ("devOtpAutoFilled", "Dev Mode: Auto-populated OTP '{otp}' from response.",
     "وضع التجربة: كود التحقق '{otp}' اتضاف تلقائيًا.", P(otp="")),
    ("enterpriseTrustNote", "Secured by Enterprise Trust Protocol",
     "محمي ببروتوكول الحماية المؤسسي"),
    # --- home_screen (owner) ---
    ("jobsTrendChipMock", "+12% vs last week", "+12% عن الأسبوع اللي فات"),
    ("activeFleetMetricLabel", "ACTIVE FLEET", "الأسطول النشط"),
    ("quickConfigSubtitle", "Configure business profile, rates & coverage",
     "ظبّط بيانات نشاطك وأسعارك وتغطيتك"),
    ("urgentActionsHeader", "Urgent Actions", "إجراءات عاجلة"),
    ("vehicleMaintenanceTitle", "Vehicle Maintenance Required", "محتاج صيانة للمركبة"),
    ("vehicleMaintenanceDesc",
     "Van #402 reported engine warning. Schedule service immediately.",
     "الميكروبص رقم 402 بلّغ عن تحذير في المحرك. احجز صيانة فورًا."),
    ("scheduleAction", "Schedule", "حدّد موعد"),
    ("pendingReconciliationsHeader", "Pending Reconciliations", "تسويات معلّقة"),
    ("reconciliationPendingDesc", "Driver shifts from yesterday awaiting escrow settlement.",
     "ورديات الأمس لسه مستنية تسوية الضمان."),
    ("reviewAction", "Review", "راجع"),
    ("fleetOverviewHeader", "Fleet Overview", "نظرة على الأسطول"),
    ("activeZoneLabel", "Active Zone", "المنطقة النشطة"),
    ("downtownCoverageLabel", "Downtown Metro Coverage", "تغطية وسط المدينة"),
    # --- job_status_screen ---
    ("trackJobHeroTitle", "Track Job", "تابع الشحنة"),
    ("trackJobHeroSubtitle", "View real-time location on map",
     "شوف الموقع اللحظي على الخريطة"),
    ("fulfillmentProgressHeader", "Fulfillment Progress", "تقدم التنفيذ"),
    ("stepRequestQueuedSub", "Request placed & queued", "الطلب اتسجل وفي الطابور"),
    ("stepAssignedTitle", "Assigned", "اتحدد"),
    ("matchingCourierLabel", "Matching courier...", "بنختار كورير..."),
    ("assignedToLine", "Assigned to {name}", "اتحدد لـ{name}", P(name="")),
    ("courierAssignedShort", "Courier assigned", "الكورير اتحدد"),
    ("stepInTransitSub", "Package on route to destination", "الشحنة في الطريق للمكان"),
    ("stepDeliveredOkSub", "Delivered successfully", "اتسلّمت بنجاح"),
    ("stepPendingDeliverySub", "Pending delivery", "مستنية التسليم"),
    ("itineraryHeader", "Itinerary", "المسار"),
    ("pickupStageBadge", "PICKUP", "استلام"),
    ("originCustomerLocation", "Origin / Customer Location", "البداية / موقع العميل"),
    ("dropoffStageBadge", "DROPOFF", "تسليم"),
    ("deliveryDestinationLabel", "Delivery Destination", "مكان التسليم"),
    ("paymentSectionHeader", "Payment", "الدفع"),
    ("totalFareLabel", "Total Fare", "إجمالي الأجرة"),
    ("verifiedCourierDriver", "Verified Courier Driver", "كورير موثّق"),
    ("cancellationReasonLine", "Cancellation Reason: {reason}", "سبب الإلغاء: {reason}",
     P(reason="")),
    ("negotiationExpiredBanner", "Negotiation Window Expired (5-min limit lapsed)",
     "مهلة التفاوض خلصت (عدّت 5 دقايق)"),
    ("incomingProposalCard", "Incoming Proposal", "عرض واصل من الطرف التاني"),
    ("proposalByLine", "by {role}", "بواسطة {role}", P(role="")),
    ("proposalRoleCustomer", "Customer", "العميل"),
    ("proposalRoleDriverEmployee", "Driver / Employee", "السائق / الموظف"),
    ("proposedFareLabel", "Proposed Fare:", "الأجرة المعروضة:"),
    ("comparisonPrefix", "Comparison:", "المقارنة:"),
    ("vsSystemPrice", "vs System Price", "مقابل سعر النظام"),
    ("waitingProposalResponse", "Waiting for response to your proposal...",
     "مستنيين الرد على عرضك..."),
    ("submitCounterOfferBtn", "Submit Counter-Offer", "ابعت عرض مضاد"),
    ("allowedBoundLine", "Allowed bound: {min} – {max} (±50%)",
     "الحدود المسموحة: {min} – {max} (±50%)", P(min="", max="")),
    # --- kyc_document_upload_screen ---
    ("verificationStatusCardTitle", "Verification Status", "حالة التوثيق"),
    ("documentsLockedMessage", "Documents are locked because your account is approved.",
     "المستندات مقفولة لأن حسابك معتمد."),
    ("removeSelectionAction", "Remove selection", "شيل الاختيار"),
    ("requiredDocsHeader", "Required Verification Documents", "مستندات التوثيق المطلوبة"),
    ("kycOwnerDocsSub",
     "Owners must upload all 4 documents (ID Front, ID Back, Selfie, Business Proof).",
     "الملاك لازم يرفعوا الـ4 مستندات (هوية وش، هية ضهر، سيلفي، سجل تجاري)."),
    ("kycEmployeeDocsSub",
     "Employees must upload all 3 documents (ID Front, ID Back, Selfie).",
     "الموظفين لازم يرفعوا الـ3 مستندات (هوية وش، هية ضهر، سيلفي)."),
    # --- my_account_screen ---
    ("profileInfoCardTitle", "Profile Information", "بيانات الحساب"),
    # --- owner_configuration_screen ---
    ("sectionBusinessIdentity", "Business Identity", "هوية النشاط"),
    ("sectionBusinessIdentitySub", "Company details and classification",
     "تفاصيل الشركة وتصنيفها"),
    ("sectionLocationOperations", "Location & Operations", "الموقع والتشغيل"),
    ("sectionLocationOperationsSub", "Headquarters and coverage boundary",
     "المقر الرئيسي وحدود التغطية"),
    ("sectionPricingStructure", "Pricing Structure", "هيكل الأسعار"),
    ("sectionPricingStructureSub", "Base fare and distance-based fees",
     "الأجرة الأساسية ورسوم المسافة"),
    ("estDelivery10kmLabel", "Est. 10KM Delivery:", "تقدير توصيل 10 كم:"),
    # --- owner_fleet_map_screen ---
    ("fleetFilterAllFleet", "All Fleet", "كل الأسطول"),
    ("fleetFilterOnRoute", "On Route", "في الطريق"),
    ("fleetFilterIdle", "Idle", "واقف"),
    ("noEmployeesTransmitting", "No active employees transmitting location.",
     "مفيش موظفين نشطين بينضبط موقعهم."),
    ("assignedJobLine", "Assigned Job: #{jobId}", "الشحنة المسندة: #{jobId}", P(jobId="")),
    # --- owner_history_screen ---
    ("ownerJobsSearchHint", "Search by Job ID, customer, or reason...",
     "دوّر برقم الشحنة أو العميل أو السبب..."),
    ("noJobsMatchFilter", "No jobs found matching your filter.",
     "مفيش شحنات مطابقة للفلتر."),
    # --- owner_reconciliation_queue_screen ---
    ("reconQueueSearchHint", "Search queue by Job ID, customer, driver...",
     "دوّر في القائمة برقم الشحنة أو العميل أو السائق..."),
    ("reconFilterDistance", "Distance", "مسافة"),
    ("reconFilterTimeSpeed", "Time / Speed", "وقت / سرعة"),
    ("reconFilterOther", "Other", "تاني"),
    ("noReconMatchFilter", "No reconciliation jobs match your filter.",
     "مفيش تسويات مطابقة للفلتر."),
    # --- rating_screen ---
    ("deliveryIdTag", "Delivery ID: #QD-{id}", "رقم التوصيل: #QD-{id}", P(id="")),
    ("howWasDeliveryQuestion", "How was your delivery?", "كانت تجربة التوصيل إزاي؟"),
    ("ratingsBlindExplanation",
     "Ratings are blind. Neither party will see the other's feedback until both have submitted.",
     "التقييم مخبي. محدش هيشوف تقييم التاني غير لما الاتنين يقيّموا."),
    ("feedbackExperienceHint", "Tell us more about your experience...",
     "احكيلنا أكتر عن تجربتك..."),
    ("feedbackLockedInTitle", "Feedback Locked In!", "تقييمك اتقفل!"),
    ("bothRatingsVisibleDesc",
     "The other party has submitted their rating. Both feedbacks are now visible under profile summary.",
     "الطرف التاني قيّم. التقييمين بقوا ظاهرين في ملخص البروفايل."),
    ("waitingOtherPartyTitle", "Waiting for other party...", "مستنيين الطرف التاني..."),
    ("otherPartyNotRatedDesc",
     "The other party has not yet rated this transaction. Your ratings will remain hidden until they submit.",
     "الطرف التاني لسه ما قيمش. تقييمك هيفضل مخبي لحد ما يقيم."),
    ("unbiasedRatingDesc", "Preventing retaliatory or social-pressure ratings.",
     "منع تقييمات الانتقام أو ضغط الأصحاب."),
    ("reliabilityRanksDesc", "Ratings directly impact platform reliability ranks.",
     "التقييمات بتأثر على ترتيب الموثوقية."),
    ("windowDeadlineDesc", "Submit within 24 hours to ensure your score counts.",
     "قيّم خلال 24 ساعة عشان صوتك يتحسب."),
    # --- service_screen ---
    ("serviceMgmtHeader", "Service Management", "إدارة الخدمات"),
    ("serviceMgmtSubtitle", "Configure and monitor active logistics services.",
     "ظبّط وتابع خدمات الشحن النشطة."),
    ("verificationRequiredHeader", "Verification Required", "لازم توثيق"),
    ("kycRequiredDesc",
     "Please complete KYC verification to create new services or modify existing ones.",
     "كمّل توثيق KYC عشان تقدر تضيف أو تعدل خدمات."),
    ("baseRateBadge", "BASE RATE", "الأجرة الأساسية"),
    ("perKmBadge", "PER KM", "لكل كم"),
    ("serviceLocationLine", "Location: ({lat}, {lon})", "الموقع: ({lat}, {lon})",
     P(lat="", lon="")),
    # --- subscription_screen ---
    ("subscriptionManageDesc",
     "Manage your operational tier. Upgrade to unlock live driver tracking, advanced pricing metrics, and priority enterprise support.",
     "أدر باقتك. الترقية بتفتح تتبع السايقين المباشر ومؤشرات أسعار متقدمة ودعم أولوية."),
    ("yourCurrentPlanBadge", "YOUR CURRENT PLAN", "خطتك الحالية"),
    ("pendingActivationNote",
     "Pending activation. Please contact support to complete payment.",
     "مستنية التفعيل. كلّم الدعم لإتمام الدفع."),
    ("availablePlansHeader", "Available Plans", "الباقات المتاحة"),
    ("freeTierDesc", "Essential tools for independent operators.",
     "أدوات أساسية للأعمال الفردية."),
    ("proTierDesc", "Complete suite for fleet managers and growing businesses.",
     "حل متكامل لمديري الأسطول والأعمال اللي بتكبر."),
    ("billedMonthlyNote", "Billed monthly. Cancel anytime.",
     "الفاتورة شهرية. تقدر تلغي وقت ما تحب."),
    ("recommendedBadge", "RECOMMENDED", "موصى بيها"),
    # --- wallet_screen ---
    ("platformFeeLine", "Platform fee: {fee}%", "نسبة المنصة: {fee}%", P(fee="")),
    ("walletMyWalletTitle", "My Wallet", "محفظتي"),
    ("walletCorporateSubtitle", "Manage corporate finances and payouts.",
     "أدر فلوس الشركة والمصروفات."),
    ("availableBalanceBadge", "AVAILABLE BALANCE", "الرصيد المتاح"),
    ("balanceTrendChipMock", "+8.4% vs last mo", "+8.4% عن الشهر اللي فات"),
    ("totalPortfolioLine", "Total Portfolio: {amount} Credits", "إجمالي المحفظة: {amount} كريدت",
     P(amount="")),
    ("creditsAmountLine", "{amount} Credits", "{amount} كريدت", P(amount="")),
    ("ledgerJobLine", "Job: {jobId}", "شحنة: {jobId}", P(jobId="")),
    ("ledgerBalanceLine", "Bal: {balance}", "الرصيد: {balance}", P(balance="")),
    # --- widgets/dialogs ---
    ("cancelReasonRequiredLong",
     "Please provide a reason for cancelling this job. A valid cancellation reason is required.",
     "اكتب سبب إلغاء الشحنة. لازم سبب إلغاء صحيح."),
    ("createNewServiceTitle", "Create New Service", "إنشاء خدمة جديدة"),
    ("referenceIdLine", "Reference ID: #{ref}", "رقم المرجع: #{ref}", P(ref="")),
    ("depositFundsTitle", "Deposit Funds", "إيداع رصيد"),
    ("depositDialogDesc", "Enter the amount in credits to deposit to your wallet.",
     "اكتب المبلغ بالكريدت لإيداعه في محفظتك."),
    ("amountRequired", "Amount is required", "المبلغ مطلوب"),
    ("positiveNumberRequired", "Please enter a valid positive number", "اكتب رقم موجب صحيح"),
    ("basePriceRequired", "Base price is required", "السعر الأساسي مطلوب"),
    ("invalidPriceValue", "Invalid price", "سعر غير صحيح"),
    ("rateRequired", "Rate is required", "السعر لكل كم مطلوب"),
    ("invalidRateValue", "Invalid rate", "قيمة غير صحيحة"),
    ("fieldRequiredGeneric", "Required", "مطلوب"),
    ("latRangeMessage", "Must be between -90 and 90", "لازم تكون بين -90 و 90"),
    ("lonRangeMessage", "Must be between -180 and 180", "لازم تكون بين -180 و 180"),
    ("otpSentToEmail", "Enter the 6-digit verification code sent to {email}.",
     "اكتب كود التحقق (6 أرقام) اللي اتبعت على {email}.", P(email="")),
    ("devModeOtpLabel", "Dev Mode OTP", "كود وضع التجربة"),
    ("verificationCodeLine", "Verification code: {code}", "كود التحقق: {code}", P(code="")),
    ("verificationCodeLabel", "Verification Code", "كود التحقق"),
    ("verificationCodeRequired", "Verification code is required", "كود التحقق مطلوب"),
    ("accountDetailsLine", "Account: {account}", "الحساب: {account}", P(account="")),
    ("verifiedServiceScoreLabel", "Verified Service Score", "درجة الخدمة الموثقة"),
    ("basedOnRatingsLine", "Based on {count} ratings", "بناءً على {count} تقييم", P(count="")),
]


def load_ordered(path: Path) -> OrderedDict:
    return json.load(open(path, encoding="utf-8"), object_pairs_hook=OrderedDict)


def main() -> int:
    en = load_ordered(EN)
    ar = load_ordered(AR)
    added = []
    skipped = []
    for entry in KEYS:
        if len(entry) == 3:
            key, en_val, ar_val = entry
            meta = None
        else:
            key, en_val, ar_val, meta = entry
        if key in en or key in ar:
            skipped.append(key)
            continue
        en[key] = en_val
        ar[key] = ar_val
        if meta is not None:
            meta_entry = OrderedDict([("placeholders", meta["placeholders"])])
            en[f"@{key}"] = meta_entry
            ar[f"@{key}"] = json.loads(json.dumps(meta_entry))
        added.append(key)

    def dump(path: Path, data: OrderedDict) -> None:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")

    dump(EN, en)
    dump(AR, ar)
    print(f"Added {len(added)} keys to app_en.arb/app_ar.arb; skipped {len(skipped)} (already present)")
    for k in added:
        print(f"  +{k}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
