// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get cancel => 'إلغاء';

  @override
  String get close => 'إغلاق';

  @override
  String get retry => 'حاول تاني';

  @override
  String get search => 'بحث...';

  @override
  String get loading => 'جاري التحميل...';

  @override
  String get scheduleDayMon => 'الاتنين';

  @override
  String get scheduleDayTue => 'التلات';

  @override
  String get scheduleDayWed => 'الأربع';

  @override
  String get scheduleDayThu => 'الخميس';

  @override
  String get scheduleDayFri => 'الجمعة';

  @override
  String get scheduleDaySat => 'السبت';

  @override
  String get scheduleDaySun => 'الحد';

  @override
  String get otpFooterBrand => 'Quick Delivery';

  @override
  String get reconciliationNote => 'ملاحظات';

  @override
  String get employeeProposalRacedError =>
      'العميل بعت سعر خلاص — رد عليه بدل ما تبعت عرض.';

  @override
  String get enumPaymentWallet => 'المحفظة';

  @override
  String get enumRoleUser => 'مستخدم';

  @override
  String get enumTierFree => 'مجاني';

  @override
  String get enumTierPaid => 'مدفوع';

  @override
  String get enumTierPendingPayment => 'دفع معلق';

  @override
  String get enumPayoutVodafoneCash => 'فودافون كاش';

  @override
  String get enumTxnDeposit => 'إيداع';

  @override
  String get enumTxnEscrowLock => 'حجز ضمان';

  @override
  String get enumTxnEscrowRelease => 'صرف ضمان';

  @override
  String get enumTxnPlatformFee => 'رسوم المنصة';

  @override
  String get enumTxnPayout => 'سحب أرباح';

  @override
  String get enumTxnPayoutRefund => 'استرداد سحب';

  @override
  String get enumTxnRefund => 'استرداد';

  @override
  String get enumTxnFeeDeduction => 'خصم رسوم';

  @override
  String get statusCompleted => 'مكتمل';

  @override
  String get statusActive => 'نشط';

  @override
  String get statusAwaitingPrice => 'في انتظار السعر';

  @override
  String get statusPending => 'قيد الانتظار';

  @override
  String get statusPendingDispatch => 'جاري البحث عن كابتن';

  @override
  String get statusUnavailable => 'غير متاح';

  @override
  String get serviceTemporarilyUnavailable =>
      'الخدمة مش متاحة دلوقتي مؤقتًا — مفيش حاجة اتحولت. حاول تاني بعد شوية.';

  @override
  String get statusCancelled => 'ملغى';

  @override
  String get statusReconciliationRequired => 'يتطلب التسوية';

  @override
  String get statusUnknown => 'غير معروف';

  @override
  String get showPassword => 'إظهار كلمة السر';

  @override
  String get hidePassword => 'إخفاء كلمة السر';

  @override
  String get tooltipNotifications => 'الإشعارات';

  @override
  String get payoutMethodBankTransfer => 'تحويل بنكي';

  @override
  String get payoutMethodInstapay => 'إنستا باي';

  @override
  String get codOptionTitle => 'الدفع عند الاستلام كاش';

  @override
  String get auditActionAccountSuspended => 'تم تجميد الحساب';

  @override
  String get auditActionAccountReactivated => 'تم إعادة تنشيط الحساب';

  @override
  String get auditActionKycReviewed => 'مراجعة الهوية اكتملت';

  @override
  String get auditActionDocumentViewed => 'تم عرض المستند';

  @override
  String get usernameRequired => 'اسم المستخدم مطلوب';

  @override
  String get usernameTooShort => 'اسم المستخدم لازم يكون 3 حروف على الأقل';

  @override
  String get usernameTooLong => 'اسم المستخدم أقصاه 30 حرف';

  @override
  String get usernameInvalidChars => 'اسم المستخدم فيه حروف غير مسموحة';

  @override
  String get emailRequired => 'الإيميل مطلوب';

  @override
  String get invalidEmailFormat => 'اكتب إيميل صحيح';

  @override
  String get passwordRequired => 'الباسورد مطلوب';

  @override
  String get passwordTooShort => 'الباسورد لازم يكون 8 حروف على الأقل';

  @override
  String get passwordTooLong => 'الباسورد لازم يكون 72 بايت كحد أقصى';

  @override
  String get passwordTooCommon =>
      'الباسورد ده شائع أوي — اختار واحد صعب التخمين.';

  @override
  String get passwordTooWeak => 'الباسورد مبيحققش متطلبات الأمان.';

  @override
  String get userNotAuthenticatedError => 'المستخدم غير مسجّل الدخول.';

  @override
  String get unknownActionLabel => 'إجراء غير معروف';

  @override
  String get roleOwnerLabel => 'صاحب الحساب';

  @override
  String get roleEmployeeLabel => 'موظف';

  @override
  String get reconciliationUnderDistance =>
      'فرق في المسافة — أقل من 70% من المسافة المحددة';

  @override
  String get reconciliationUnrecordedEscrow => 'فشل تسجيل رصيد الضمان';

  @override
  String get reconciliationImplausibleSpeed => 'تم رصد سرعة انتقال غير منطقية';

  @override
  String get reconciliationRequiredDefault =>
      'مطلوب مراجعة تسوية الضمان يدويًا';

  @override
  String get newDispatchAlertMessage =>
      'تم استلام طلب توصيل جديد. جاري تحديث الطلبات المتاحة...';

  @override
  String get digitalPaymentsComingSoon =>
      'قريب: شحن المحفظة وسحب الأرباح مش متاحين لسه. الحجوزات بتتدفع كاش عند الاستلام.';

  @override
  String get qdStatusPending => 'مستني مندوب';

  @override
  String get qdStatusPendingDispatch => 'بندور على مندوب';

  @override
  String get qdStatusUnavailable => 'مفيش مندوب متاح';

  @override
  String get qdStatusAwaitingPrice => 'فيه عرض سعر';

  @override
  String get qdStatusAssigned => 'المندوب قبل';

  @override
  String get qdStatusActive => 'في الطريق';

  @override
  String get qdStatusCompleted => 'اتسلم';

  @override
  String get qdStatusCancelled => 'اتلغى';

  @override
  String get qdStatusUnderReview => 'بيتراجع';

  @override
  String get qdStatusCancellationRequested => 'طلب إلغاء';

  @override
  String get qdStatusUnknown => 'حالة مش معروفة';

  @override
  String get qdComingSoon => 'قريب';

  @override
  String get qdLoading => 'بيحمّل';

  @override
  String get qdErrorTitle => 'حصلت مشكلة';

  @override
  String get qdErrorBody => 'اتأكد من النت وجرّب تاني.';

  @override
  String qdTimeLeft(String time) {
    return 'فاضل $time';
  }

  @override
  String get qdPickup => 'الاستلام';

  @override
  String get qdDropoff => 'التسليم';

  @override
  String qdStepProgress(int current, int total) {
    return 'خطوة $current من $total';
  }

  @override
  String get qdTimelineDone => 'خلصت';

  @override
  String get qdTimelineCurrent => 'الخطوة الحالية';

  @override
  String get qdTimelineUpcoming => 'لسه';

  @override
  String qdMoneyAmount(String amount) {
    return '$amount ج.م';
  }

  @override
  String get qdMainNavigation => 'التنقل الرئيسي';

  @override
  String get custNavHome => 'الرئيسية';

  @override
  String get custNavOrders => 'طلباتي';

  @override
  String get custNavAccount => 'حسابي';

  @override
  String get custPickupFrom => 'الاستلام من';

  @override
  String get custCurrentLocation => 'مكانك الحالي';

  @override
  String get custPinnedLocation => 'مكان على الخريطة';

  @override
  String get custChooseLocation => 'اختار المكان';

  @override
  String get custHomeTitle => 'عايز تبعت إيه النهارده؟';

  @override
  String get custCatDelivery => 'توصيل طلب';

  @override
  String get custCatDeliverySub => 'من مكان لمكان جوه المدينة';

  @override
  String get custCatShipping => 'شحن طرد';

  @override
  String get custCatShippingSub => 'بين المحافظات';

  @override
  String get custCatRide => 'مشوار';

  @override
  String get custCatRideSub => 'عربية توصلك لحد ما تروح';

  @override
  String get custAllServices => 'كل الخدمات';

  @override
  String get custServicesSection => 'الخدمات';

  @override
  String get custOngoingOrder => 'طلب جاري';

  @override
  String get custNoOngoing => 'مفيش طلبات جارية دلوقتي.';

  @override
  String get custOrderFallback => 'طلب';

  @override
  String custOrderTitleRef(String title, String ref) {
    return '$title · $ref';
  }

  @override
  String get custTrack => 'التفاصيل';

  @override
  String custToPlace(String place) {
    return 'إلى $place';
  }

  @override
  String get custJobsLoadError => 'معرفناش نجيب طلباتك.';

  @override
  String custCompaniesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count شركة متاحة',
      two: 'شركتين متاحين',
      one: 'شركة واحدة متاحة',
      zero: 'مفيش شركات متاحة',
    );
    return '$_temp0';
  }

  @override
  String custNearPlace(String place, String km) {
    return 'قريب من $place · لحد $km كم';
  }

  @override
  String get custSortLabel => 'الترتيب';

  @override
  String get custSortNearest => 'الأقرب';

  @override
  String get custSortCheapest => 'الأرخص';

  @override
  String get custFilters => 'الفلاتر';

  @override
  String get custOpen => 'مفتوح';

  @override
  String get custClosed => 'مقفول';

  @override
  String custOpensAt(String when) {
    return 'بيفتح $when';
  }

  @override
  String custKmAway(String km) {
    return '$km كم منك';
  }

  @override
  String custAboutAmount(String amount) {
    return 'حوالي $amount';
  }

  @override
  String get custLocating => 'بنحدد مكانك…';

  @override
  String get custLocationOffBanner =>
      'مقدرناش نعرف مكانك، فالشركات دي حوالين المكان الافتراضي. اختار منطقتك عشان تشوف اللي قريب منك.';

  @override
  String get custPickArea => 'اختار المنطقة على الخريطة';

  @override
  String get custNoCompaniesTitle => 'مفيش شركات قريبة';

  @override
  String get custNoCompaniesBody => 'جرّب مسافة أكبر أو منطقة تانية.';

  @override
  String get custChangeFilters => 'غيّر الفلاتر';

  @override
  String get custFilterDistance => 'المسافة';

  @override
  String custRadiusKm(String km) {
    return '$km كم';
  }

  @override
  String get custSearchArea => 'منطقة البحث';

  @override
  String get custShowResults => 'اعرض النتايج';

  @override
  String get custPickupPlace => 'مكان الاستلام';

  @override
  String get custDropoffPlace => 'مكان التسليم';

  @override
  String get custPickerHint =>
      'حرّك الخريطة لحد ما العلامة تبقى على المكان بالظبط';

  @override
  String get custNoteLabel => 'علامة تساعد المندوب · اختياري';

  @override
  String get custNoteHint => 'مثلاً: العمارة اللي جنب الصيدلية، الدور التالت';

  @override
  String get custConfirmPlace => 'أكّد المكان';

  @override
  String get custMyLocation => 'مكاني الحالي';

  @override
  String get custLocationDenied =>
      'الموقع مقفول فمش هنقدر نحدد مكانك. حرّك الخريطة واختار المكان بنفسك.';

  @override
  String get custConfirmOrder => 'تأكيد الطلب';

  @override
  String get custChange => 'غيّر';

  @override
  String get custRouteTitle => 'من فين لفين؟';

  @override
  String get custChooseDropoff => 'اختار مكان التسليم';

  @override
  String get custPriceTitle => 'السعر';

  @override
  String get custBaseFare => 'فتح الطلب';

  @override
  String get custPerKm => 'سعر الكيلو';

  @override
  String custDistanceLine(String km, String rate) {
    return '$km كم × $rate';
  }

  @override
  String get custEstimate => 'المتوقع';

  @override
  String get custPriceNeedsDropoff => 'اختار مكان التسليم عشان نحسب السعر.';

  @override
  String get custPriceDisclaimer =>
      'ده تقدير بالمسافة المباشرة. السعر ممكن يتغير لو المندوب عرض سعر تاني ووافقت عليه.';

  @override
  String get custPayCash => 'كاش للمندوب';

  @override
  String get custPayOnlineSoon => 'الدفع الإلكتروني قريب';

  @override
  String get custChooseDropoffFirst => 'اختار مكان التسليم الأول';

  @override
  String get custOrderNow => 'اطلب دلوقتي';

  @override
  String custBookingFailed(String reason) {
    return 'مقدرناش نبعت طلبك. $reason';
  }

  @override
  String get custServiceClosed => 'الشركة دي مقفولة دلوقتي ومش بتاخد طلبات.';

  @override
  String get custOrdersTitle => 'طلباتي';

  @override
  String get custOrdersKind => 'نوع الطلبات';

  @override
  String custTabOngoing(int count) {
    return 'الجارية · $count';
  }

  @override
  String get custTabPast => 'السابقة';

  @override
  String get custCashOnDelivery => 'كاش عند الاستلام';

  @override
  String get custNoOngoingTitle => 'مفيش طلبات جارية';

  @override
  String get custNoPastTitle => 'لسه مفيش طلبات سابقة';

  @override
  String get custOrdersEmptyBody => 'اطلب توصيل أو شحن أو مشوار وهيظهر هنا.';

  @override
  String get custBrowseServices => 'شوف الخدمات';

  @override
  String custTodayAt(String time) {
    return 'النهارده · $time';
  }

  @override
  String custDateAt(String date, String time) {
    return '$date · $time';
  }

  @override
  String custNearYou(String km) {
    return 'قريب منك · لحد $km كم';
  }

  @override
  String custFromPrice(String base, String rate) {
    return 'من $base + $rate للكيلو';
  }

  @override
  String get ordTitle => 'طلبك';

  @override
  String get ordLoadError => 'مقدرناش نحمّل طلبك';

  @override
  String get ordRefreshError => 'مقدرناش نحدّث طلبك. ده آخر تحديث عندنا.';

  @override
  String get ordUnknownTitle => 'مش قادرين نعرض حالة الطلب ده';

  @override
  String get ordUnknownBody => 'اسحب لتحت عشان تحدّث. لو فضل كده كلّم الدعم.';

  @override
  String get ordPickupFrom => 'الاستلام من';

  @override
  String get ordDeliverTo => 'التسليم في';

  @override
  String get ordCashEstimate => 'كاش · متوقع';

  @override
  String get ordPayCash => 'هتدفع كاش';

  @override
  String get ordPaidCash => 'دفعت كاش';

  @override
  String get ordPriceNotSet => 'لسه متحددش';

  @override
  String get ordCourierFallback => 'المندوب بتاعك';

  @override
  String get ordChatCourier => 'محادثة المندوب';

  @override
  String get ordCancelledTitle => 'الطلب اتلغى';

  @override
  String get ordCancelledBody =>
      'الطلب ده مش هيكمّل. تقدر تطلب تاني في أي وقت.';

  @override
  String ordCancelReason(String reason) {
    return 'السبب: $reason';
  }

  @override
  String get ordProposalExpiredTitle => 'عرض السعر وقته خلص';

  @override
  String get ordProposalExpiredBody =>
      'محدش رد على عرض السعر في الوقت، فالطلب اتلغى. تقدر تطلب تاني.';

  @override
  String get ordReviewTitle => 'طلبك بيتراجع';

  @override
  String get ordReviewBody =>
      'الشركة بتراجع المشوار قبل ما تقفل الطلب. مش مطلوب منك حاجة.';

  @override
  String get ordOnHold => 'المبلغ المحجوز';

  @override
  String get chatYou => 'إنت';

  @override
  String chatUserFallback(String id) {
    return 'مستخدم $id';
  }

  @override
  String get chatLive => 'متصل';

  @override
  String get chatConnecting => 'بيتوصل…';

  @override
  String get chatOffline => 'مش متصل، بنحاول تاني';

  @override
  String get chatDenied => 'مش مسموحلك تفتح المحادثة دي.';

  @override
  String get chatEmptyTitle => 'مفيش رسايل لسه';

  @override
  String get chatEmptyBody => 'ابعت للمندوب أي تفاصيل زيادة عن طلبك.';

  @override
  String get chatHint => 'اكتب رسالة';

  @override
  String get chatSend => 'ابعت';

  @override
  String chatSendFailed(String error) {
    return 'مقدرناش نبعت الرسالة. $error';
  }

  @override
  String get ordSearchingTitle => 'بندور على مندوب';

  @override
  String get ordSearchingBody =>
      'بنعرض طلبك على المندوبين واحد ورا التاني لحد ما حد يقبل.';

  @override
  String ordSearchingBodyCompany(String company) {
    return 'بنعرض طلبك على مندوبين $company واحد ورا التاني لحد ما حد يقبل.';
  }

  @override
  String ordOfferedTitle(String name) {
    return '$name بيبص على طلبك';
  }

  @override
  String get ordOfferedTitleNoName => 'فيه مندوب بيبص على طلبك';

  @override
  String get ordOfferedSub => 'لو عندك تفاصيل زيادة ابعتهاله';

  @override
  String get ordCancelOrder => 'إلغاء الطلب';

  @override
  String get ordCancelSheetTitle => 'تلغي الطلب ده؟';

  @override
  String get ordCancelSheetBody => 'قول للشركة السبب. لازم تكتب سبب.';

  @override
  String get ordCancelReasonLabel => 'السبب';

  @override
  String get ordCancelKeep => 'خلّي الطلب';

  @override
  String get ordCancelDone => 'طلبك اتلغى.';

  @override
  String get ordCancelDoneRefunded => 'طلبك اتلغى والمبلغ رجعلك.';

  @override
  String get ordUnavailableTitle => 'مفيش مندوب متاح دلوقتي';

  @override
  String get ordUnavailableBody =>
      'كل المندوبين مشغولين. تقدر تبعت نفس الطلب تاني.';

  @override
  String get ordRetryBooking => 'اطلب تاني';

  @override
  String get ordRetryBooked => 'بعتنا طلبك تاني.';

  @override
  String ordProposalCourierTitle(String name) {
    return '$name عرض سعر تاني';
  }

  @override
  String get ordProposalCourierTitleNoName => 'المندوب عرض سعر تاني';

  @override
  String get ordProposalCourierSub => 'لازم توافق عشان يبدأ';

  @override
  String ordProposalMineTitle(String price) {
    return 'إنت عرضت $price';
  }

  @override
  String get ordProposalMineSub => 'مستنيين رد المندوب.';

  @override
  String get ordProposalOpenTitle => 'اتفق على السعر';

  @override
  String get ordProposalOpenSub => 'ابعت سعر في الحدود المسموحة.';

  @override
  String get ordOriginalPrice => 'السعر الأصلي';

  @override
  String get ordOfferedPrice => 'السعر المعروض';

  @override
  String ordPriceMore(String amount) {
    return 'أكتر بـ $amount';
  }

  @override
  String ordPriceLess(String amount) {
    return 'أقل بـ $amount';
  }

  @override
  String get ordPriceSame => 'نفس السعر';

  @override
  String get ordOfferExpiresIn => 'العرض بيخلص بعد';

  @override
  String get ordOfferExpiryNote =>
      'لو الوقت خلص من غير رد، الطلب بيتلغي وتقدر تطلب تاني.';

  @override
  String get ordDecline => 'مش موافق';

  @override
  String ordAcceptPrice(String price) {
    return 'موافق على $price';
  }

  @override
  String get ordYourPrice => 'السعر اللي تقترحه';

  @override
  String ordPriceRange(String min, String max) {
    return 'من $min لـ $max';
  }

  @override
  String get ordPriceInvalid => 'اكتب رقم، زي 42.';

  @override
  String ordPriceOutOfRange(String min, String max) {
    return 'اكتب سعر من $min لـ $max.';
  }

  @override
  String get ordSendOffer => 'ابعت العرض';

  @override
  String get ordOfferSent => 'عرضك اتبعت.';

  @override
  String get ordAccepted => 'وافقت على السعر.';

  @override
  String get ordDeclined => 'رفضت السعر.';

  @override
  String get ordStateChanged => 'الطلب اتغير: الطرف التاني رد أو حالته اتغيرت.';

  @override
  String get ordActiveTitle => 'المندوب شغال على طلبك';

  @override
  String get ordActiveSub => 'مكانه بيتحدث على الخريطة أول بأول';

  @override
  String get ordStepOrdered => 'طلبت';

  @override
  String ordStepAccepted(String name) {
    return '$name قبل الطلب';
  }

  @override
  String get ordStepAcceptedNoName => 'المندوب قبل الطلب';

  @override
  String get ordStepOnTheWay => 'شغال عليه';

  @override
  String get ordStepNow => 'دلوقتي';

  @override
  String get ordStepDelivered => 'اتسلم';

  @override
  String get ordSteps => 'مراحل الطلب';

  @override
  String get ordComplaint => 'فيه مشكلة؟ قدّم شكوى';

  @override
  String get ordMapWaiting => 'مستنيين مكان المندوب';

  @override
  String get ordMapReconnecting => 'بنرجّع التتبع المباشر…';

  @override
  String get ordMapDenied => 'مش مسموحلك تتابع الطلب ده على الخريطة.';

  @override
  String get ordMapLabel => 'خريطة بمكان المندوب';

  @override
  String get ordZoomIn => 'تكبير';

  @override
  String get ordZoomOut => 'تصغير';

  @override
  String get ordRecenter => 'رجّع الخريطة للنص';

  @override
  String get ordDeliveredTitle => 'طلبك اتسلم';

  @override
  String ordDeliveredPaidCash(String price) {
    return 'دفعت $price كاش';
  }

  @override
  String ordDeliveredPaid(String price) {
    return 'دفعت $price';
  }

  @override
  String ordRateCourier(String name) {
    return 'قيّم $name';
  }

  @override
  String get ordRateCourierNoName => 'قيّم المندوب';

  @override
  String get ordRateCompany => 'قيّم الشركة';

  @override
  String get ordRatedThanks => 'شكرًا، تقييمك اتبعت.';

  @override
  String rateQuestion(String name) {
    return 'إيه رأيك في $name؟';
  }

  @override
  String get rateQuestionCourier => 'إيه رأيك في المندوب؟';

  @override
  String get rateQuestionCompany => 'إيه رأيك في الشركة؟';

  @override
  String get rateStars => 'التقييم';

  @override
  String get rateBlindNote =>
      'تقييمك مش هيظهر للطرف التاني غير لما هو كمان يقيّمك، والتعليق بيروح للشركة بس.';

  @override
  String get rateComment => 'تعليق · اختياري';

  @override
  String get rateSend => 'ابعت التقييم';

  @override
  String get rateNotNow => 'مش دلوقتي';

  @override
  String rateFailed(String error) {
    return 'مقدرناش نبعت تقييمك. $error';
  }

  @override
  String get rateIdentityError => 'مش عارفين نقيّم مين في الطلب ده.';

  @override
  String get rateOtherRated => 'الطرف التاني قيّمك. التقييمين ظاهرين دلوقتي.';

  @override
  String get rateOtherCheckFailed => 'مقدرناش نعرف إذا كان الطرف التاني قيّمك.';

  @override
  String get rateClose => 'إغلاق';

  @override
  String rateStar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نجوم',
      two: 'نجمتين',
      one: 'نجمة',
    );
    return '$_temp0';
  }

  @override
  String get authSwitchLanguage => 'English';

  @override
  String get authSwitchLanguageLabel => 'غيّر اللغة للإنجليزي';

  @override
  String get authThemeLabel => 'غيّر المظهر';

  @override
  String get authBack => 'رجوع';

  @override
  String get authLoginTitle => 'أهلاً بيك';

  @override
  String get authLoginSubtitle => 'ادخل على حسابك عشان تطلب وتتابع طلباتك';

  @override
  String get authEmailLabel => 'الإيميل';

  @override
  String get authEmailHint => 'name@example.com';

  @override
  String get authEmailRequired => 'اكتب الإيميل';

  @override
  String get authEmailInvalid => 'اكتب إيميل صحيح زي name@example.com';

  @override
  String get authPasswordLabel => 'كلمة السر';

  @override
  String get authPasswordRequired => 'اكتب كلمة السر';

  @override
  String get authForgotPassword => 'نسيت كلمة السر؟';

  @override
  String get authSignIn => 'دخول';

  @override
  String get authNoAccount => 'معندكش حساب؟';

  @override
  String get authCreateAccountLink => 'اعمل حساب جديد';

  @override
  String get authSignupTitle => 'حساب جديد';

  @override
  String get authRoleQuestion => 'أنت مين؟';

  @override
  String get authRoleCustomer => 'عميل';

  @override
  String get authRoleCustomerHint => 'عايز أبعت طلبات';

  @override
  String get authRoleOwner => 'صاحب شغل';

  @override
  String get authRoleOwnerHint => 'عندي شركة ومندوبين';

  @override
  String get authCourierNote => 'المندوبين بياخدوا حساباتهم من صاحب الشغل.';

  @override
  String get authNameLabel => 'الاسم';

  @override
  String get authNameRequired => 'اكتب اسمك';

  @override
  String get authNameTooShort => 'الاسم لازم يكون 3 حروف على الأقل';

  @override
  String get authNameTooLong => 'الاسم ميزيدش عن 30 حرف';

  @override
  String get authNameInvalid => 'استخدم حروف وأرقام ومسافات أو _ بس';

  @override
  String get authPasswordHelp => '8 حروف على الأقل، ومتكونش سهلة زي 12345678';

  @override
  String get authCreateAccount => 'اعمل الحساب';

  @override
  String get authHaveAccount => 'عندك حساب؟';

  @override
  String get authSignInLink => 'ادخل';

  @override
  String get authOtpTitle => 'اكتب الكود';

  @override
  String get authOtpSentTo => 'بعتنا كود من 6 أرقام على';

  @override
  String get authOtpLabel => 'كود التأكيد';

  @override
  String get authOtpIncomplete => 'اكتب الـ 6 أرقام كلهم';

  @override
  String get authOtpConfirm => 'تأكيد';

  @override
  String get authResendWait => 'موصلكش؟ تقدر تبعته تاني بعد';

  @override
  String get authResendPrompt => 'موصلكش؟';

  @override
  String get authResendNow => 'ابعت الكود تاني';

  @override
  String get authCodeResent => 'بعتنالك كود جديد.';

  @override
  String authDevOtp(String otp) {
    return 'وضع التجربة: كتبنالك الكود $otp.';
  }

  @override
  String get resetTitle => 'نسيت كلمة السر؟';

  @override
  String get resetEmailBody => 'اكتب إيميل حسابك وهنبعتلك كود.';

  @override
  String get resetSendCode => 'ابعت الكود';

  @override
  String get resetCodeSent => 'بعتنا كود على إيميلك.';

  @override
  String get resetNewTitle => 'كلمة سر جديدة';

  @override
  String get resetNewBody => 'اختار كلمة سر مش مستخدمها في أي حتة تانية.';

  @override
  String get resetNewLabel => 'كلمة السر الجديدة';

  @override
  String get resetConfirmLabel => 'اكتبها تاني';

  @override
  String get resetMismatch => 'كلمتين السر مش زي بعض';

  @override
  String get resetSave => 'احفظ كلمة السر';

  @override
  String get resetDone => 'كلمة السر اتغيرت. ادخل بالجديدة.';

  @override
  String get resetExpired =>
      'وقت تغيير كلمة السر خلص. ابدأ من الأول عشان ياخد كود جديد.';

  @override
  String get resetStartAgain => 'ابدأ من الأول';

  @override
  String resetStep(int current, int total) {
    return 'خطوة $current من $total';
  }

  @override
  String get acctEdit => 'تعديل';

  @override
  String get acctSectionAccount => 'الحساب';

  @override
  String get acctSectionApp => 'التطبيق';

  @override
  String get acctSectionSupport => 'الدعم';

  @override
  String get acctMyDetails => 'بياناتي';

  @override
  String get acctSavedAddresses => 'العناوين المحفوظة';

  @override
  String get acctSecurity => 'الأمان';

  @override
  String get acctTwoFactorOn => 'التحقق بخطوتين شغال';

  @override
  String get acctTwoFactorOff => 'التحقق بخطوتين مقفول';

  @override
  String get acctWallet => 'المحفظة';

  @override
  String get acctLanguage => 'اللغة';

  @override
  String get acctLangArabic => 'العربية';

  @override
  String get acctLangEnglish => 'English';

  @override
  String get acctPhoneSetting => 'زي الموبايل';

  @override
  String get acctTheme => 'المظهر';

  @override
  String get acctThemeLight => 'فاتح';

  @override
  String get acctThemeDark => 'غامق';

  @override
  String get acctNotifications => 'الإشعارات';

  @override
  String get acctSupport => 'الدعم والشكاوى';

  @override
  String get acctLogout => 'تسجيل خروج';

  @override
  String get acctSuspendedTitle => 'حسابك متوقف';

  @override
  String get acctSuspendedDefault =>
      'مش هتقدر تغيّر بياناتك دلوقتي. كلم الدعم عشان تعرف أكتر.';

  @override
  String get acctLoadError => 'معرفناش نحدّث بيانات حسابك.';

  @override
  String get acctPhoneLabel => 'الموبايل';

  @override
  String get acctPhoneHint => '01xxxxxxxxx';

  @override
  String get acctChangeEmail => 'غيّر';

  @override
  String get acctChangeEmailLabel => 'غيّر الإيميل';

  @override
  String get acctEmailNote => 'عشان تغيّره هنبعت كود على الإيميل الجديد.';

  @override
  String get acctSave => 'احفظ';

  @override
  String get acctSaved => 'بياناتك اتحفظت.';

  @override
  String get acctAddAddress => 'ضيف عنوان';

  @override
  String get acctEditAddress => 'عدّل العنوان';

  @override
  String get acctAddressLabel => 'العنوان';

  @override
  String get acctAddressHint => 'العمارة، الشارع، المنطقة';

  @override
  String get acctAddressRequired => 'اكتب العنوان';

  @override
  String get acctAddressMax => 'تقدر تحفظ لحد 10 عناوين';

  @override
  String acctAddressCount(int count) {
    return '$count من 10';
  }

  @override
  String get acctAddressesNote =>
      'العناوين بتتحفظ كنص، من غير مكان على الخريطة.';

  @override
  String get acctAddressesEmpty => 'مفيش عناوين محفوظة لسه';

  @override
  String get acctAddressesEmptyBody => 'احفظ الأماكن اللي بتطلب منها كتير.';

  @override
  String get acctSaveAddress => 'احفظ العنوان';

  @override
  String acctDeleteAddress(String address) {
    return 'امسح $address';
  }

  @override
  String get acctAddressDeleted => 'العنوان اتمسح.';

  @override
  String get acctUndo => 'رجّعه';

  @override
  String get acctTwoFactor => 'التحقق بخطوتين';

  @override
  String get acctTwoFactorBody => 'هنبعتلك كود على الإيميل كل مرة تدخل.';

  @override
  String get acctTwoFactorOffTitle => 'تقفل التحقق بخطوتين؟';

  @override
  String get acctTwoFactorOffBody =>
      'ساعتها أي حد معاه كلمة السر هيقدر يدخل من غير كود.';

  @override
  String get acctTwoFactorTurnOff => 'اقفله';

  @override
  String get acctCancel => 'إلغاء';

  @override
  String get acctPasswordTitle => 'أكد إنه أنت';

  @override
  String get acctPasswordBody => 'اكتب كلمة السر عشان تقفل التحقق بخطوتين.';

  @override
  String get acctWrongPassword => 'كلمة السر دي مش صح.';

  @override
  String get acctTwoFactorOnDone => 'التحقق بخطوتين اشتغل.';

  @override
  String get acctTwoFactorOffDone => 'التحقق بخطوتين اتقفل.';

  @override
  String get acctNewEmailLabel => 'الإيميل الجديد';

  @override
  String get acctEmailChanged => 'الإيميل اتغير.';

  @override
  String get acctSameEmail => 'ده الإيميل بتاعك أصلاً';

  @override
  String get acctClose => 'اقفل';

  @override
  String get ntfTitle => 'الإشعارات';

  @override
  String get ntfMarkAllRead => 'قريت الكل';

  @override
  String get ntfClearAll => 'امسح الكل';

  @override
  String get ntfClearTitle => 'تمسح كل الإشعارات؟';

  @override
  String get ntfClearBody => 'مش هتقدر ترجّعهم تاني.';

  @override
  String get ntfClear => 'امسح';

  @override
  String get ntfToday => 'النهارده';

  @override
  String get ntfYesterday => 'امبارح';

  @override
  String get ntfJustNow => 'دلوقتي';

  @override
  String ntfMinutesAgo(int count) {
    return 'من $count دقيقة';
  }

  @override
  String ntfHoursAgo(int count) {
    return 'من $count ساعة';
  }

  @override
  String get ntfUnread => 'مش مقروء';

  @override
  String get ntfDismiss => 'امسح الإشعار';

  @override
  String get ntfLive => 'متصل: الإشعارات الجديدة بتظهر هنا';

  @override
  String get ntfOffline => 'مش متصل: الإشعارات الجديدة ممكن تتأخر';

  @override
  String get ntfConnectError => 'الاتصال المباشر وقع.';

  @override
  String get ntfReconnect => 'اتصل تاني';

  @override
  String get ntfEmptyTitle => 'مفيش إشعارات لسه';

  @override
  String get ntfEmptyBody => 'هنقولك هنا لما يحصل حاجة في طلباتك.';

  @override
  String get ntfLoadError => 'معرفناش نجيب الإشعارات.';

  @override
  String get ntfShowOlder => 'اعرض الأقدم';

  @override
  String get ntfAcceptedTitle => 'مندوب قبل طلبك';

  @override
  String get ntfAcceptedBody => 'تابعه من صفحة الطلب.';

  @override
  String get ntfUnavailableTitle => 'مفيش مندوب فاضي دلوقتي';

  @override
  String get ntfUnavailableBody => 'تقدر تطلب تاني من طلباتي.';

  @override
  String get ntfCancelledTitle => 'طلبك اتلغى';

  @override
  String get ntfOrdersBody => 'افتح طلباتي عشان تشوف التفاصيل.';

  @override
  String get ntfCompletedTitle => 'طلبك اتسلم';

  @override
  String get ntfTicketResolvedTitle => 'شكوتك اتحلت';

  @override
  String get ntfTicketAssignedTitle => 'الدعم دخل على شكوتك';

  @override
  String get ntfTicketAssignedBody => 'رد عليهم في محادثة الشكوى.';

  @override
  String get ntfDisputeTitle => 'مراجعة طلبك خلصت';

  @override
  String get supTitle => 'الدعم';

  @override
  String supOpenTab(int count) {
    return 'مفتوحة · $count';
  }

  @override
  String get supResolvedTab => 'اتحلت';

  @override
  String get supStatusPending => 'مستنية رد';

  @override
  String get supStatusAssigned => 'مع الدعم';

  @override
  String get supStatusResolved => 'اتحلت';

  @override
  String get supStatusOpen => 'مفتوحة';

  @override
  String supAboutOrder(String ref, String when) {
    return 'عن طلب $ref · $when';
  }

  @override
  String supGeneral(String when) {
    return 'عامة · $when';
  }

  @override
  String supResolution(String note) {
    return 'الحل: $note';
  }

  @override
  String get supHintTitle => 'عندك مشكلة في طلب؟';

  @override
  String get supHintBody =>
      'اختار الطلب واكتب اللي حصل، وفريق الدعم هيرد عليك هنا.';

  @override
  String get supNewComplaint => 'شكوى جديدة';

  @override
  String get supResolvedEmpty => 'مفيش شكاوى اتحلت لسه';

  @override
  String get supLoadError => 'معرفناش نجيب شكاويك.';

  @override
  String get supOrderLabel => 'أنهي طلب؟';

  @override
  String get supNoOrderOption => 'مش عن طلب';

  @override
  String get supOrdersLoading => 'بنجيب طلباتك…';

  @override
  String get supOrdersError => 'معرفناش نجيب طلباتك. تقدر تبعتها من غير طلب.';

  @override
  String get supSubjectLabel => 'الموضوع';

  @override
  String get supSubjectHint => 'باختصار';

  @override
  String get supSubjectRequired => 'اكتب الموضوع';

  @override
  String get supDescriptionLabel => 'إيه اللي حصل؟';

  @override
  String get supDescriptionHint => 'احكيلنا التفاصيل';

  @override
  String get supDescriptionRequired => 'اكتب اللي حصل';

  @override
  String get supSend => 'ابعت الشكوى';

  @override
  String get supSent => 'شكوتك وصلت. الدعم هيرد عليك في المحادثة بتاعتها.';

  @override
  String supComplaintRef(String ref) {
    return 'شكوى $ref';
  }

  @override
  String get supChatEmpty => 'اكتب للدعم هنا. تقدر ترفق صورة أو PDF.';

  @override
  String get supResolvedBanner => 'الشكوى دي اتحلت.';

  @override
  String get supReadOnly =>
      'الشكوى اللي اتحلت مينفعش يتبعت فيها رسايل. افتح شكوى جديدة لو محتاج.';

  @override
  String get supAttach => 'ارفق صورة أو PDF';

  @override
  String get supFileEmpty => 'الملف فاضي.';

  @override
  String get supFileTooBig => 'الملف ميزيدش عن 10 ميجا.';

  @override
  String get supAttachFailed => 'معرفناش نبعت الملف.';

  @override
  String get updTitle => 'لازم تحدّث التطبيق';

  @override
  String get updBody =>
      'النسخة دي مبقتش شغالة. نزّل النسخة الجديدة عشان تكمل على كويك ديليفري.';

  @override
  String get updInstalled => 'النسخة اللي عندك';

  @override
  String get updMinimum => 'أقدم نسخة شغالة';

  @override
  String get updLatest => 'أحدث نسخة';

  @override
  String get updLinkLabel => 'لينك التحميل';

  @override
  String get updCopy => 'انسخ لينك التحميل';

  @override
  String get updCopied =>
      'اللينك اتنسخ. افتحه في المتصفح ونزّل النسخة الجديدة.';

  @override
  String ownCourierUnknown(String id) {
    return 'مندوب $id';
  }

  @override
  String get ownAgoNow => 'دلوقتي';

  @override
  String ownAgoMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'من $count دقيقة',
      few: 'من $count دقايق',
      two: 'من دقيقتين',
      one: 'من دقيقة',
    );
    return '$_temp0';
  }

  @override
  String ownAgoHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'من $count ساعة',
      few: 'من $count ساعات',
      two: 'من ساعتين',
      one: 'من ساعة',
    );
    return '$_temp0';
  }

  @override
  String get ownNotNow => 'مش دلوقتي';

  @override
  String get ownRefresh => 'حدّث';

  @override
  String ownOrderTitle(String ref) {
    return 'طلب $ref';
  }

  @override
  String get ownOrderFallbackTitle => 'طلب';

  @override
  String get ownOrderMissing => 'الطلب ده مش في قايمتك دلوقتي.';

  @override
  String ownCancelReqTitle(String name) {
    return '$name طالب يلغي المهمة';
  }

  @override
  String ownCancelReqQuote(String reason) {
    return '«$reason»';
  }

  @override
  String get ownCancelReqNoReason => 'مكتبش سبب';

  @override
  String ownCancelReqSince(String ago) {
    return 'اتطلب $ago';
  }

  @override
  String get ownCancelReqKeep => 'يكمّل المهمة';

  @override
  String get ownCancelReqApprove => 'وافق على الإلغاء';

  @override
  String get ownCancelReqApproveTitle => 'توافق على الإلغاء؟';

  @override
  String get ownCancelReqApproveBody => 'الطلب هيتلغي والعميل هيعرف.';

  @override
  String get ownCancelReqKeepTitle => 'المهمة تكمّل؟';

  @override
  String ownCancelReqKeepBody(String name) {
    return '$name هيفضل على الطلب ولازم يخلّصه.';
  }

  @override
  String get ownCancelReqApproved => 'وافقت على الإلغاء والطلب اتلغى.';

  @override
  String get ownCancelReqDeclined => 'رفضت الطلب والمندوب مكمّل.';

  @override
  String get ownCancelReqConflict =>
      'الطلب ده اتغيّر خلاص، ممكن وقته يكون خلص. حدّثنا الطلب.';

  @override
  String get ownDistanceReviewTitle => 'المسافة باينة قصيرة، راجعها';

  @override
  String ownDistanceReviewBody(String actual, String booked) {
    return 'الرحلة اتسجّل فيها $actual كم من $booked كم في الحجز. الكاش اتسجّل عادي.';
  }

  @override
  String get ownSeeOnMap => 'شوف على الخريطة';

  @override
  String get ownRowCustomer => 'العميل';

  @override
  String ownCustomerRef(String id) {
    return 'عميل $id';
  }

  @override
  String get ownRowCourier => 'المندوب';

  @override
  String get ownCourierNone => 'لسه محدش استلمه';

  @override
  String get ownRowPayment => 'الدفع';

  @override
  String ownPayCash(String amount) {
    return 'كاش · $amount';
  }

  @override
  String get ownPayCashNoPrice => 'كاش · السعر لسه متحددش';

  @override
  String ownPayOther(String method, String amount) {
    return '$method · $amount';
  }

  @override
  String get ownRowCashRecorded => 'الكاش المتسجّل';

  @override
  String get ownRowOrdered => 'اتطلب';

  @override
  String get ownRowCancelReason => 'سبب الإلغاء';

  @override
  String get ownCancelOrder => 'إلغاء الطلب';

  @override
  String get ownCancelKeep => 'خلّي الطلب';

  @override
  String get ownCancelSheetTitle => 'تلغي الطلب ده؟';

  @override
  String get ownCancelSheetCod => 'العميل والمندوب هيعرفوا. اكتب سبب الإلغاء.';

  @override
  String ownCancelSheetHeld(String amount) {
    return 'الـ $amount المحجوزين للطلب هيرجعوا للعميل. اكتب سبب الإلغاء.';
  }

  @override
  String get ownCancelReasonLabel => 'السبب';

  @override
  String get ownCancelled => 'الطلب اتلغى.';

  @override
  String get ownCancelledRefunded => 'الطلب اتلغى والمبلغ المحجوز رجع للعميل.';

  @override
  String get ownOrdersTitle => 'الطلبات';

  @override
  String get ownOrdersSearchHint => 'رقم الطلب أو اسم المندوب';

  @override
  String get ownClearSearch => 'امسح البحث';

  @override
  String get ownOrdersKind => 'حالة الطلبات';

  @override
  String ownTabOngoing(int count) {
    return 'جارية · $count';
  }

  @override
  String get ownTabDone => 'خلصت';

  @override
  String get ownTabCancelled => 'اتلغت';

  @override
  String get ownOrdersLoadError => 'مقدرناش نحمّل الطلبات.';

  @override
  String get ownRefreshFailed => 'مقدرناش نحدّث. ده آخر اللي اتحمّل.';

  @override
  String get ownOrdersNoMatch => 'مفيش طلب زي اللي بتدوّر عليه';

  @override
  String get ownNoOngoing => 'مفيش طلبات جارية';

  @override
  String get ownNoDone => 'لسه مفيش طلبات خلصت';

  @override
  String get ownNoCancelled => 'مفيش طلبات اتلغت';

  @override
  String get ownOrdersEmptyBody =>
      'الطلبات اللي العملاء بيطلبوها منك هتظهر هنا.';

  @override
  String ownProposalLine(String proposed, String price) {
    return 'عرض سعر: $proposed بدل $price';
  }

  @override
  String ownProposalOnly(String proposed) {
    return 'عرض سعر: $proposed';
  }

  @override
  String ownOfferedTo(String name) {
    return 'معروض على $name';
  }

  @override
  String get ownReconTitle => 'مراجعة الحسابات';

  @override
  String get ownReconIntro =>
      'طلبات المبلغ فيها متحجوز لأن السيستم لقى حاجة مش منطقية. قرر الفلوس تروح لمين.';

  @override
  String get ownReconLoadError => 'مقدرناش نحمّل الطلبات اللي محتاجة مراجعة.';

  @override
  String get ownReconEmpty => 'مفيش حاجة محتاجة مراجعة';

  @override
  String get ownReconCodTitle => 'مع الدفع كاش بس';

  @override
  String get ownReconCodBody =>
      'الشاشة دي هتفضل فاضية غالباً لحد ما الدفع الإلكتروني يشتغل.';

  @override
  String get ownReconHeld => 'المبلغ المحجوز';

  @override
  String get ownReconPay => 'ادفعها للمندوب';

  @override
  String get ownReconRefund => 'رجّعها للعميل';

  @override
  String get ownReconPayTitle => 'تدفعها للمندوب؟';

  @override
  String get ownReconRefundTitle => 'ترجّعها للعميل؟';

  @override
  String ownReconPayBody(String amount, String ref, String name) {
    return '$amount بتوع طلب $ref هيروحوا لـ$name. مش هينفع ترجع فيها.';
  }

  @override
  String ownReconRefundBody(String amount, String ref) {
    return '$amount بتوع طلب $ref هيرجعوا للعميل. مش هينفع ترجع فيها.';
  }

  @override
  String get ownReconTheCourier => 'المندوب';

  @override
  String get ownReconPaid => 'الفلوس اتدفعت للمندوب.';

  @override
  String get ownReconRefunded => 'الفلوس رجعت للعميل.';

  @override
  String get ownReconFailed => 'مقدرناش نخلّص الطلب ده. جرّب تاني.';

  @override
  String get ownReasonShortDistance => 'المسافة أقل من المتوقع';

  @override
  String get ownReasonSpeed => 'السرعة مش منطقية';

  @override
  String get ownReasonUnrecorded => 'المبلغ المحجوز مش متسجّل';

  @override
  String get ownReasonOther => 'محتاج مراجعة';

  @override
  String get ownTeamTitle => 'الفريق';

  @override
  String get ownOnTheMap => 'على الخريطة';

  @override
  String get ownTeamKind => 'حالة المندوبين';

  @override
  String ownTeamAll(int count) {
    return 'الكل · $count';
  }

  @override
  String get ownTeamActive => 'شغالين';

  @override
  String get ownTeamFrozen => 'متجمدين';

  @override
  String get ownTeamLoadError => 'مقدرناش نحمّل الفريق.';

  @override
  String get ownTeamEmpty => 'لسه مفيش مندوبين';

  @override
  String get ownTeamEmptyBody =>
      'ضيف المندوبين بتوعك عشان يدخلوا ويستلموا طلبات.';

  @override
  String get ownTeamNoneHere => 'مفيش مندوبين هنا';

  @override
  String get ownAddCourier => 'إضافة مندوب';

  @override
  String get ownStateOnJob => 'في مهمة';

  @override
  String get ownStateFree => 'فاضي';

  @override
  String get ownStateFrozen => 'متجمد';

  @override
  String ownOnJobWith(String ref) {
    return 'في مهمة · $ref';
  }

  @override
  String get ownNoOrderNow => 'مفيش طلب دلوقتي';

  @override
  String get ownFrozenSubtitle => 'مش بيقدر يدخل ولا يستلم طلبات';

  @override
  String get ownEmployeeMissing => 'المندوب ده مش في فريقك دلوقتي.';

  @override
  String get ownEmpOrders => 'طلبات';

  @override
  String get ownEmpDelivered => 'اتسلمت';

  @override
  String get ownEmpCountsNote => 'محسوبة من آخر طلباتك اللي في التطبيق.';

  @override
  String get ownEmpIdCheck => 'التحقق من الهوية';

  @override
  String get ownKyeApproved => 'متراجع ومقبول';

  @override
  String get ownKyePending => 'بيتراجع';

  @override
  String get ownKyeRejected => 'مرفوض';

  @override
  String get ownKyeMissing => 'المستندات ناقصة';

  @override
  String get ownEmpCurrentOrder => 'المهمة الحالية';

  @override
  String get ownEmpNone => 'مفيش';

  @override
  String get ownEmpAllOrders => 'كل مهامه';

  @override
  String get ownEmpOnMap => 'مكانه على الخريطة';

  @override
  String get ownFreeze => 'تجميد الحساب';

  @override
  String get ownUnfreeze => 'فك تجميد الحساب';

  @override
  String get ownFreezeHint =>
      'هيخرج من التطبيق فوراً ومش هيستقبل مهام. هنطلب كلمة السر بتاعتك للتأكيد.';

  @override
  String get ownUnfreezeHint =>
      'هيقدر يدخل ويستلم مهام تاني. هنطلب كلمة السر بتاعتك للتأكيد.';

  @override
  String ownFreezeTitle(String name) {
    return 'تجمّد حساب $name؟';
  }

  @override
  String ownUnfreezeTitle(String name) {
    return 'تفك تجميد حساب $name؟';
  }

  @override
  String get ownFreezeBody =>
      'هيخرج من التطبيق فوراً ومش هيستقبل مهام. اكتب كلمة السر بتاعتك للتأكيد.';

  @override
  String get ownUnfreezeBody =>
      'هيقدر يدخل ويستلم مهام تاني. اكتب كلمة السر بتاعتك للتأكيد.';

  @override
  String get ownYourPassword => 'كلمة السر بتاعتك';

  @override
  String get ownPasswordRequired => 'اكتب كلمة السر.';

  @override
  String get ownPasswordWrong => 'كلمة السر دي مش صح.';

  @override
  String get ownToggleKybNeeded => 'لازم مستندات شغلك تتقبل الأول.';

  @override
  String get ownTogglePaidPlan => 'إدارة المندوبين محتاجة باقة مدفوعة.';

  @override
  String ownFrozenDone(String name) {
    return 'حساب $name اتجمد.';
  }

  @override
  String ownUnfrozenDone(String name) {
    return 'حساب $name رجع يشتغل.';
  }

  @override
  String get ownAddTitle => 'إضافة مندوب';

  @override
  String get ownAddBody => 'هيدخل بالإيميل وكلمة السر دول.';

  @override
  String get ownAddUsername => 'الاسم';

  @override
  String get ownAddEmail => 'الإيميل';

  @override
  String get ownAddPassword => 'كلمة السر';

  @override
  String get ownAddPasswordHelp => '8 حروف على الأقل.';

  @override
  String get ownAddSubmit => 'ضيف المندوب';

  @override
  String ownAdded(String name) {
    return '$name اتضاف ويقدر يدخل دلوقتي.';
  }

  @override
  String get ownTodayTitle => 'النهارده';

  @override
  String get ownNotifications => 'الإشعارات';

  @override
  String get ownTodayLoadError => 'مقدرناش نحمّل طلبات النهارده.';

  @override
  String get ownTileOngoing => 'جارية دلوقتي';

  @override
  String get ownTileDelivered => 'اتسلمت النهارده';

  @override
  String get ownTileCash => 'كاش متسجّل النهارده';

  @override
  String get ownTodayNote =>
      'اللي اتسلم والكاش محسوبين من الطلبات اللي اتطلبت النهارده.';

  @override
  String ownTodayNoteTruncated(int limit) {
    return 'محسوبة من آخر $limit طلب، وكلهم من النهارده. ممكن يكون فيه أكتر.';
  }

  @override
  String get ownNeedsYou => 'محتاج منك';

  @override
  String get ownNeedsNothing => 'مفيش حاجة محتاجاك دلوقتي.';

  @override
  String ownNeedsRequestTitle(String name) {
    return '$name طالب يلغي مهمة';
  }

  @override
  String ownNeedsReason(String reason) {
    return 'السبب: $reason';
  }

  @override
  String get ownNeedsRespond => 'رد عليه';

  @override
  String ownNeedsReviewsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count طلب محتاج مراجعة حسابات',
      few: '$count طلبات محتاجة مراجعة حسابات',
      two: 'طلبين محتاجين مراجعة حسابات',
      one: 'طلب محتاج مراجعة حسابات',
    );
    return '$_temp0';
  }

  @override
  String get ownNeedsReviewsBody => 'المسافة أو الوقت مش منطقيين';

  @override
  String get ownNeedsReview => 'راجع';

  @override
  String get ownTeamNow => 'الفريق دلوقتي';

  @override
  String get ownSeeAll => 'الكل';

  @override
  String get ownTeamNowEmpty => 'لسه مفيش مندوبين. ضيفهم من تاب الفريق.';

  @override
  String get ownRatingTitle => 'تقييمك';

  @override
  String get ownRatingNone => 'لسه مفيش تقييمات';

  @override
  String ownRatingValue(String average, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تقييم',
      few: '$count تقييمات',
      two: 'تقييمين',
      one: 'تقييم واحد',
    );
    return '$average · $_temp0';
  }

  @override
  String get ownYourBusiness => 'شغلك';

  @override
  String get ownLinkAllOrders => 'كل الطلبات';

  @override
  String get ownLinkServiceSetup => 'إعداد الخدمة';

  @override
  String get ownLinkWallet => 'المحفظة';

  @override
  String get ownLinkSubscription => 'الاشتراك';

  @override
  String get ownLinkHistory => 'النشاط والسجل';

  @override
  String get ownKybMissingTitle => 'وثّق شغلك';

  @override
  String get ownKybMissingBody => 'ارفع مستندات شغلك عشان تبدأ تستقبل طلبات.';

  @override
  String get ownKybUpload => 'ارفع المستندات';

  @override
  String get ownKybPendingTitle => 'مستنداتك بتتراجع';

  @override
  String get ownKybPendingBody => 'هنبلغك أول ما تتقبل.';

  @override
  String get ownKybView => 'شوف المستندات';

  @override
  String get ownKybRejectedTitle => 'مستنداتك اترفضت';

  @override
  String get ownKybRejectedBody => 'ارفعها تاني عشان تبدأ تستقبل طلبات.';

  @override
  String get ownKybUploadAgain => 'ارفعها تاني';

  @override
  String get ownNavToday => 'النهارده';

  @override
  String get ownNavOrders => 'الطلبات';

  @override
  String get ownNavTeam => 'الفريق';

  @override
  String get ownNavAccount => 'حسابي';

  @override
  String get ownSvcTitle => 'إعداد الخدمة';

  @override
  String get ownSvcSectionBusiness => 'الخدمة';

  @override
  String get ownSvcPhotoNote =>
      'العملا هيشوفوا الصورة دي على كارت خدمتك. JPEG أو PNG، لحد 5 ميجا.';

  @override
  String get ownSvcName => 'اسم الخدمة زي ما العميل هيشوفه';

  @override
  String get ownSvcNameRequired => 'اكتب اسم الخدمة';

  @override
  String get ownSvcKind => 'النوع';

  @override
  String get ownSvcKindDelivery => 'توصيل';

  @override
  String get ownSvcKindTransport => 'مشاوير';

  @override
  String get ownSvcKindShipping => 'شحن';

  @override
  String get ownSvcSectionPlace => 'المكان والتغطية';

  @override
  String get ownSvcPlace => 'مكان الشركة على الخريطة';

  @override
  String get ownSvcPlaceMissing => 'لازم تحدده';

  @override
  String get ownSvcPlaceSet => 'متحدد على الخريطة';

  @override
  String get ownSvcPickerTitle => 'مكان الشركة';

  @override
  String get ownSvcAddress => 'العنوان مكتوب';

  @override
  String get ownSvcAddressShort => 'اكتب 3 حروف على الأقل أو سيبه فاضي';

  @override
  String get ownSvcRadius => 'بتخدم لحد كام كيلو؟';

  @override
  String get ownSvcKm => 'كم';

  @override
  String get ownSvcRadiusInvalid => 'اكتب مسافة أكبر من صفر';

  @override
  String get ownSvcSectionHours => 'المواعيد';

  @override
  String get ownSvcHoursNone => 'مفيش مواعيد: العملا هيشوفوك فاتح على طول.';

  @override
  String get ownSvcHoursSet => 'حدد المواعيد';

  @override
  String get ownSvcHoursSame => 'نفس الميعاد كل يوم';

  @override
  String get ownSvcHoursPerDay => 'كل يوم لوحده';

  @override
  String get ownSvcOpens => 'بيفتح';

  @override
  String get ownSvcCloses => 'بيقفل';

  @override
  String get ownSvcDayOff => 'إجازة';

  @override
  String get ownSvcHoursRemove => 'شيل المواعيد';

  @override
  String get ownSvcHoursSameTime => 'ميعاد الفتح والقفل مينفعش يبقوا واحد';

  @override
  String get ownSvcHoursMissing => 'اختار الميعادين';

  @override
  String get ownSvcSectionPricing => 'التسعير';

  @override
  String get ownSvcBaseFee => 'فتح الطلب';

  @override
  String get ownSvcPerKm => 'لكل كيلو';

  @override
  String get ownSvcPriceInvalid => 'اكتب صفر أو أكتر';

  @override
  String ownSvcExample(int km, String price) {
    return 'مثال: مشوار $km كم هيتعرض للعميل بـ $price.';
  }

  @override
  String get ownSvcExampleEmpty => 'اكتب السعرين عشان تشوف العميل هيدفع كام.';

  @override
  String get ownSvcSave => 'احفظ';

  @override
  String get ownSvcSaved => 'الخدمة اتحفظت';

  @override
  String get ownSvcFixErrors => 'راجع الخانات اللي باللون الأحمر';

  @override
  String get ownSvcLoadError => 'معرفناش نحمّل خدمتك';

  @override
  String get ownSvcErrKyb =>
      'لازم أوراق الشغل يتوافق عليها الأول قبل ما تحفظ الخدمة.';

  @override
  String get ownSvcErrPlan => 'حفظ الخدمة محتاج باقة شغالة.';

  @override
  String get ownSvcErrUnavailable => 'ده مش متاح دلوقتي. جرّب كمان شوية.';

  @override
  String get ownSvcCurrency => 'ج.م';

  @override
  String get ownFleetMapLabel => 'خريطة أماكن المندوبين';

  @override
  String get ownFleetFilterLabel => 'فلتر';

  @override
  String get ownFleetAll => 'الكل';

  @override
  String get ownFleetFree => 'فاضيين';

  @override
  String get ownFleetDenied => 'مش مسموحلك تشوف خريطة الفريق ده.';

  @override
  String get ownFleetLoadError => 'أماكن المندوبين ماتحمّلتش.';

  @override
  String get ownFleetReconnecting => 'بنرجّع الاتصال بالأماكن المباشرة…';

  @override
  String get ownFleetNobody => 'مفيش مندوب بيشارك مكانه دلوقتي.';

  @override
  String get ownFleetRefresh => 'حدّث';

  @override
  String ownFleetSummary(int total, int onJob) {
    return 'على الخريطة: $total · في مهمة: $onJob';
  }

  @override
  String get ownFleetSummaryNone =>
      'المندوبين بيظهروا هنا وهم بيشاركوا مكانهم.';

  @override
  String get ownFleetTapHint => 'دوس على مندوب عشان تشوف طلبه.';

  @override
  String ownFleetLastUpdate(String ago) {
    return 'آخر تحديث $ago';
  }

  @override
  String get ownFleetClose => 'اقفل';

  @override
  String ownFleetOrderRef(String ref) {
    return 'طلب $ref';
  }

  @override
  String ownFleetOrderTo(String ref, String place) {
    return 'طلب $ref · إلى $place';
  }

  @override
  String get ownFleetCourierPage => 'صفحة المندوب';

  @override
  String get ownLogTitle => 'سجل النشاط';

  @override
  String get ownLogTabActivity => 'النشاط';

  @override
  String get ownLogTabMoney => 'الفلوس';

  @override
  String get ownLogPeriodLabel => 'الفترة';

  @override
  String get ownLogPeriodAll => 'الكل';

  @override
  String get ownLogPeriodToday => 'النهارده';

  @override
  String get ownLogPeriodWeek => 'آخر 7 أيام';

  @override
  String get ownLogActivityEmpty => 'مفيش نشاط لسه';

  @override
  String get ownLogActivityEmptyBody =>
      'حركات المندوبين وتغييرات الحساب بتظهر هنا.';

  @override
  String get ownLogMoneyEmpty => 'مفيش حركات فلوس لسه';

  @override
  String get ownLogMoneyEmptyBody =>
      'الطلبات بتتدفع كاش دلوقتي، فهنا هيفضل فاضي لحد ما الدفع الإلكتروني يبدأ.';

  @override
  String get ownLogNoneInPeriod => 'مفيش حاجة في الفترة دي';

  @override
  String get ownLogShowAll => 'اعرض الكل';

  @override
  String get ownLogActivityError => 'معرفناش نحمّل النشاط';

  @override
  String get ownLogMoneyError => 'معرفناش نحمّل حركات الفلوس';

  @override
  String get ownLogStale => 'معرفناش نحدّث. دي آخر قايمة اتحمّلت.';

  @override
  String get ownLogYou => 'إنت';

  @override
  String ownLogBalanceAfter(String amount) {
    return 'الرصيد بعدها $amount';
  }

  @override
  String ownLogMoneyIn(String amount) {
    return 'دخل $amount';
  }

  @override
  String ownLogMoneyOut(String amount) {
    return 'خرج $amount';
  }

  @override
  String get courNavTask => 'المهمة';

  @override
  String get courNavJobs => 'مهامي';

  @override
  String get courNavAccount => 'حسابي';

  @override
  String get courKyeMissing => 'ارفع مستنداتك علشان حسابك يتراجع.';

  @override
  String get courKyePending => 'حسابك مستني مراجعة المستندات.';

  @override
  String courKyeRejected(String reason) {
    return 'المستندات ما اتقبلتش: $reason';
  }

  @override
  String get courKyeRejectedNoReason => 'المستندات ما اتقبلتش. ارفعها تاني.';

  @override
  String get courKyeUpload => 'كمّل الرفع';

  @override
  String get courKyeView => 'شوف المستندات';

  @override
  String get courKyeReupload => 'ارفع تاني';

  @override
  String get courBlockedTitle => 'مش هتقدر تاخد مهام دلوقتي';

  @override
  String get courBlockedSuspended => 'حسابك اتوقف، فمش هتوصلك مهام.';

  @override
  String get courBlockedPaused =>
      'حسابك متوقف مؤقتاً، فمش هتوصلك مهام. الشركة أو Quick Delivery يقدروا يرجّعوه.';

  @override
  String get courBlockedReason => 'السبب';

  @override
  String get courBlockedWhat =>
      'كلّم صاحب الشغل، أو كلّم الدعم لو شايف إن ده غلط.';

  @override
  String get courBlockedCheck => 'اتأكد تاني';

  @override
  String get courLoadError => 'ما قدرناش نحمّل مهامك.';

  @override
  String get courRefresh => 'حدّث';

  @override
  String get courIdleOnlineTitle => 'مفيش مهمة دلوقتي';

  @override
  String get courIdleOnlineBody => 'إنت متاح. المهام الجديدة هتظهر هنا.';

  @override
  String get courIdleOfflineTitle => 'إنت مش متاح';

  @override
  String get courIdleOfflineBody => 'خلّي نفسك متاح علشان توصلك مهام.';

  @override
  String get courGoOnline => 'خلّيني متاح';

  @override
  String courKm(String km) {
    return '$km كم';
  }

  @override
  String get courPriceNotSet => 'لسه ما اتحددش';

  @override
  String get courPackageSmall => 'صغير';

  @override
  String get courPackageMedium => 'متوسط';

  @override
  String get courPackageLarge => 'كبير';

  @override
  String courPackage(String details) {
    return 'الطلب: $details';
  }

  @override
  String get courMapLabel => 'خريطة المسار ومكانك';

  @override
  String get courNoDestination => 'مكان التسليم لسه ما اتحددش';

  @override
  String get courChatTitle => 'العميل';

  @override
  String get courChatEmpty => 'رسايلك مع العميل عن الطلب ده هتظهر هنا.';

  @override
  String get courOfferSubtitle => 'مهمة جديدة ليك';

  @override
  String get courOfferTitle => 'طلب جديد';

  @override
  String get courOfferExpired => 'العرض ده خلص.';

  @override
  String courPickupFromYou(String distance) {
    return 'استلام · $distance منك';
  }

  @override
  String courDropoffTrip(String distance) {
    return 'تسليم · المشوار $distance';
  }

  @override
  String get courCashToCollect => 'هتحصّل كاش';

  @override
  String get courOrderPrice => 'سعر الطلب';

  @override
  String get courAskCustomer => 'اسأل العميل';

  @override
  String get courDecline => 'رفض';

  @override
  String get courAccept => 'قبول المهمة';

  @override
  String get courOfferAccepted => 'قبلت المهمة';

  @override
  String get courOfferDeclined => 'رفضت العرض';

  @override
  String get courOfferGone => 'العرض ده مبقاش متاح.';

  @override
  String get courPickedUpDone => 'اتسجل الاستلام. اتحرك على مكان التسليم.';

  @override
  String get courPickupAlready => 'الطلب ده متسجل إنه اتستلم خلاص.';

  @override
  String get courNotYours => 'الطلب ده مبقاش معاك.';

  @override
  String get courDelivered => 'الطلب اتسلّم. تسلم إيدك!';

  @override
  String get courCancelSent => 'اتبعت الطلب لصاحب الشغل.';

  @override
  String get courOtherJobsTitle => 'مهامك الشغالة';

  @override
  String courOtherJobs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'عندك $count مهام تانية شغالة.',
      one: 'عندك مهمة تانية شغالة.',
    );
    return '$_temp0';
  }

  @override
  String get courOtherJobsShow => 'اعرض';

  @override
  String get courPickedUp => 'استلمت الطلب';

  @override
  String courDeliveredCollected(String amount) {
    return 'سلّمت واستلمت $amount';
  }

  @override
  String get courDeliveredCash => 'سلّمت واستلمت الكاش';

  @override
  String get courDeliveredPlain => 'سلّمت الطلب';

  @override
  String get courOpenInMaps => 'افتح في الخرائط';

  @override
  String get courCurrentTitle => 'المهمة الحالية';

  @override
  String get courCancelPending => 'طلبت الإلغاء. مستني رد صاحب الشغل.';

  @override
  String get courCancelRejected => 'صاحب الشغل رفض الإلغاء. المهمة لسه معاك.';

  @override
  String get courRequestCancel => 'مش هقدر أكمل؟ اطلب إلغاء';

  @override
  String courEtaPickup(int minutes) {
    return 'تقدير: حوالي $minutes دقيقة لمكان الاستلام';
  }

  @override
  String courEtaDropoff(int minutes) {
    return 'تقدير: حوالي $minutes دقيقة لمكان التسليم';
  }

  @override
  String get courPhasePrice => 'بنتفق على السعر';

  @override
  String get courPhaseToPickup => 'رايح للاستلام';

  @override
  String get courPhasePickedUp => 'استلمت';

  @override
  String get courPhaseActive => 'شغال';

  @override
  String get courSharingLive => 'العميل شايف مكانك';

  @override
  String get courSharingOff => 'اللوكيشن مقفول';

  @override
  String get courSharingFailing => 'اللوكيشن مش بيتحدّث';

  @override
  String get courSharingStarting => 'بنشغّل اللوكيشن…';

  @override
  String get courPermissionTitle => 'شغّل اللوكيشن';

  @override
  String get courPermissionBody =>
      'العميل والشركة مش هيشوفوا مكانك لحد ما تسمح باللوكيشن.';

  @override
  String get courOpenSettings => 'افتح الإعدادات';

  @override
  String courWillPayCash(String amount) {
    return 'هيدفع $amount كاش';
  }

  @override
  String courOrderPriceValue(String amount) {
    return 'سعر الطلب $amount';
  }

  @override
  String get courChatWithCustomer => 'محادثة العميل';

  @override
  String courRecipientNotes(String notes) {
    return 'ملاحظات: $notes';
  }

  @override
  String get courAmountInvalid => 'اكتب المبلغ اللي استلمته، زي 42.';

  @override
  String get courCompleteTitle => 'سلّمت الطلب؟';

  @override
  String courCompleteCod(String amount) {
    return 'أكّد إنك سلّمته واستلمت $amount كاش.';
  }

  @override
  String get courCompleteCodNoPrice => 'أكّد إنك سلّمته واستلمت الكاش.';

  @override
  String get courCompleteNonCod => 'أكّد إنك سلّمت الطلب.';

  @override
  String get courCompleteDifferent => 'استلمت مبلغ مختلف';

  @override
  String get courCompleteAmountLabel => 'المبلغ اللي استلمته';

  @override
  String get courCompleteAmountHelp => 'بالجنيه المصري';

  @override
  String courCompleteConfirmAmount(String amount) {
    return 'أيوه، استلمت $amount';
  }

  @override
  String get courCompleteConfirmCash => 'أيوه، استلمت الكاش';

  @override
  String get courCompleteConfirm => 'أيوه، سلّمته';

  @override
  String get courNotYet => 'لسه';

  @override
  String get courCompleteNote => 'الشركة بتشوف المبلغ اللي بتأكده.';

  @override
  String get courCancelTitle => 'اطلب إلغاء';

  @override
  String get courCancelBody =>
      'صاحب الشغل هو اللي هيقرر. لحد ما يرد، المهمة معاك.';

  @override
  String get courCancelSend => 'ابعت الطلب';

  @override
  String get courCancelKeep => 'كمّل المهمة';

  @override
  String courPriceAcceptTitle(String price) {
    return 'توافق على $price؟';
  }

  @override
  String get courPriceAcceptBody => 'المشوار هيبدأ على طول بالسعر ده.';

  @override
  String get courProposalSent => 'السعر اتبعت. مستني رد العميل.';

  @override
  String get courPriceAccepted => 'السعر اتقبل. المشوار بدأ.';

  @override
  String get courPriceDeclined => 'رفضت السعر.';

  @override
  String courPriceCustomerTitle(String price) {
    return 'العميل عارض $price';
  }

  @override
  String courPriceWas(String price) {
    return 'السعر المقترح كان $price.';
  }

  @override
  String courPriceMineTitle(String price) {
    return 'إنت عرضت $price';
  }

  @override
  String get courPriceMineBody => 'مستني رد العميل.';

  @override
  String get courPriceProposeTitle => 'اقترح سعرك';

  @override
  String courPriceProposeBody(String price) {
    return 'السعر المقترح $price. تقدر تبعت عرض واحد، والعميل يقبله أو يرفضه.';
  }

  @override
  String get courPriceWaitingTitle => 'مستني الاتفاق على السعر';

  @override
  String get courPriceProposeLabel => 'سعرك';

  @override
  String courPriceBounds(String min, String max) {
    return 'من $min لـ $max';
  }

  @override
  String get courPriceExpired => 'وقت عرض السعر خلص.';

  @override
  String get courAvailableOn => 'متاح لاستقبال مهام';

  @override
  String get courAvailableOff => 'مش متاح';

  @override
  String get courAvailableOnBody => 'بنبعت مكانك لصاحب الشغل كل دقيقة.';

  @override
  String get courAvailableOffBody => 'مش هتوصلك مهام جديدة.';

  @override
  String get courAvailableLocked => 'مقفول طول ما عندك مهمة شغالة.';

  @override
  String get courTodayDone => 'مهام خلصت النهارده';

  @override
  String get courTodayCash => 'كاش النهارده بسعر الطلب';

  @override
  String get courTodayCashNote =>
      'الكاش محسوب بسعر طلبات الكاش اللي اتسلّمت النهارده، والشركة بتشوف المبلغ اللي أكدته.';

  @override
  String get courTodayByCreation =>
      'الطلبات القديمة مالهاش وقت خلصان، فبتتحسب بيوم إنشائها.';

  @override
  String get courFinishedHeader => 'اللي خلص';

  @override
  String courToPlace(String place) {
    return 'إلى $place';
  }

  @override
  String get courPayCash => 'كاش';

  @override
  String get courNoFinishedTitle => 'لسه مفيش مهام خلصت';

  @override
  String get courNoFinishedBody =>
      'المهام اللي بتسلّمها، واللي بتتلغي، هتظهر هنا.';

  @override
  String get courReasonPriceDisagreement => 'ما اتفقناش على السعر';

  @override
  String get acctVerification => 'التحقق من الهوية';

  @override
  String get acctKyeApproved => 'اتأكدت';

  @override
  String get acctKyePending => 'بتتراجع';

  @override
  String get acctKyeRejected => 'ما اتقبلتش';

  @override
  String get acctKyeMissing => 'ما اترفعتش';

  @override
  String get vrfTitleOwner => 'توثيق الشغل';

  @override
  String get vrfTitleCourier => 'توثيق الهوية';

  @override
  String get vrfLoadError => 'مقدرناش نحدّث حالة التوثيق.';

  @override
  String get vrfStateMissingTitle => 'ارفع مستنداتك';

  @override
  String vrfStateMissingOwner(int total) {
    return 'ارفع الـ$total مستندات عشان نوثّق شغلك وتبدأ تستقبل طلبات.';
  }

  @override
  String vrfStateMissingCourier(int total) {
    return 'ارفع الـ$total مستندات عشان نتأكد من هويتك.';
  }

  @override
  String vrfStateIncompleteTitle(int done, int total) {
    return 'اترفع $done من $total مستندات';
  }

  @override
  String get vrfStateIncompleteBody =>
      'المراجعة بتبدأ أول ما كل المستندات تترفع.';

  @override
  String get vrfStatePendingTitle => 'مستنداتك بتتراجع';

  @override
  String get vrfStatePendingBody =>
      'هنبلغك لما المراجعة تخلص. لسه تقدر تغيّر أي مستند.';

  @override
  String get vrfStateApprovedTitle => 'اتوثّقت';

  @override
  String get vrfStateApprovedBody => 'مستنداتك اتقبلت، ومقفولة دلوقتي.';

  @override
  String get vrfStateRejectedTitle => 'مستنداتك ما اتقبلتش';

  @override
  String vrfRejectedReason(String reason) {
    return 'ملاحظة المراجع: $reason';
  }

  @override
  String get vrfRejectedNoReason =>
      'مفيش سبب مكتوب. كلّم الدعم لو مش متأكد تغيّر إيه.';

  @override
  String get vrfRejectedHint =>
      'غيّر المستندات اللي محتاجة تتصلح. بترجع للمراجعة أول ما ترفع واحد.';

  @override
  String get vrfDocsHeader => 'المستندات';

  @override
  String vrfDocsCount(int done, int total) {
    return 'اترفع $done من $total';
  }

  @override
  String get vrfSlotIdFront => 'البطاقة، الوش';

  @override
  String get vrfSlotIdFrontHint => 'صورة واضحة لوش البطاقة أو الباسبور.';

  @override
  String get vrfSlotIdBack => 'البطاقة، الضهر';

  @override
  String get vrfSlotIdBackHint => 'صورة واضحة لضهر البطاقة.';

  @override
  String get vrfSlotSelfie => 'سيلفي بالبطاقة';

  @override
  String get vrfSlotSelfieHint => 'امسك البطاقة جنب وشك.';

  @override
  String get vrfSlotBusiness => 'السجل التجاري';

  @override
  String get vrfSlotBusinessHint =>
      'السجل التجاري أو البطاقة الضريبية. صورة أو PDF.';

  @override
  String get vrfSlotNeeded => 'مطلوب';

  @override
  String get vrfSlotUploaded => 'اترفع';

  @override
  String get vrfSlotInReview => 'بيتراجع';

  @override
  String get vrfSlotAccepted => 'اتقبل';

  @override
  String get vrfSlotNotAccepted => 'ما اتقبلش';

  @override
  String get vrfSlotUploading => 'بيترفع';

  @override
  String get vrfOnFilePhoto => 'فيه صورة مترفوعة';

  @override
  String get vrfOnFilePdf => 'فيه PDF مترفوع';

  @override
  String get vrfUpload => 'ارفع';

  @override
  String get vrfReplace => 'غيّر';

  @override
  String get vrfChooseAnother => 'اختار ملف تاني';

  @override
  String vrfUploadingFile(String name) {
    return 'بنرفع $name…';
  }

  @override
  String vrfUploadedNotice(String slot) {
    return 'اترفع: $slot.';
  }

  @override
  String get vrfSentForReview => 'كل المستندات اترفعت، وبتتراجع دلوقتي.';

  @override
  String vrfErrTooLarge(String size) {
    return 'الملف ده $size ميجا. الحد 10 ميجا.';
  }

  @override
  String get vrfErrEmpty => 'الملف ده فاضي. اختار ملف تاني.';

  @override
  String get vrfErrFormatPhoto => 'استخدم صورة JPG أو PNG.';

  @override
  String get vrfErrFormatDoc => 'استخدم صورة JPG أو PNG، أو ملف PDF.';

  @override
  String get vrfErrNotAllowed => 'الحساب ده مينفعش يرفع المستندات دي.';

  @override
  String get vrfErrPicker => 'مقدرناش نفتحه. جرّب اختيار تاني.';

  @override
  String get vrfErrUpload => 'مقدرناش نرفع الملف. اتأكد من النت وجرّب تاني.';

  @override
  String vrfSourceTitle(String slot) {
    return 'إضافة: $slot';
  }

  @override
  String get vrfSourceCamera => 'صوّر';

  @override
  String get vrfSourceGallery => 'اختار من الصور';

  @override
  String get vrfSourceFile => 'اختار ملف';

  @override
  String get vrfSourceFileHintPdf => 'JPG أو PNG أو PDF، لحد 10 ميجا';

  @override
  String get vrfSourceFileHintPhoto => 'JPG أو PNG، لحد 10 ميجا';

  @override
  String get vrfRulesOwner =>
      'الصور لازم تكون JPG أو PNG، لحد 10 ميجا للواحدة. السجل التجاري ممكن يكون PDF كمان.';

  @override
  String get vrfRulesCourier =>
      'الصور لازم تكون JPG أو PNG، لحد 10 ميجا للواحدة.';

  @override
  String get vrfLocked => 'المستندات المقبولة مينفعش تتغيّر.';

  @override
  String get acctSectionBusiness => 'شغلك';

  @override
  String get acctServiceSetup => 'إعداد الخدمة';

  @override
  String get acctPlan => 'الباقة';

  @override
  String get acctActivityLog => 'سجل النشاط';

  @override
  String get ownWalletTitle => 'المحفظة';

  @override
  String get ownWalletAvailable => 'متاح للسحب';

  @override
  String get ownWalletTotal => 'الرصيد الكلي';

  @override
  String get ownWalletHeld => 'محجوز للطلبات';

  @override
  String get ownWalletAddMoney => 'اشحن';

  @override
  String get ownWalletWithdraw => 'اسحب';

  @override
  String get ownWalletLoadError => 'مقدرناش نحمّل المحفظة.';

  @override
  String get ownWalletStale => 'مقدرناش نحدّث. دي آخر أرصدة اتحمّلت.';

  @override
  String get ownWalletPayouts => 'السحوبات';

  @override
  String get ownWalletPayoutsEmpty => 'مفيش سحوبات لسه.';

  @override
  String get ownWalletPayoutsError => 'مقدرناش نحمّل السحوبات.';

  @override
  String ownWalletPayoutReason(String reason) {
    return 'السبب: $reason';
  }

  @override
  String get ownPayoutRequested => 'اتطلب';

  @override
  String get ownPayoutApproved => 'اتوافق عليه';

  @override
  String get ownPayoutPaid => 'اتدفع';

  @override
  String get ownPayoutRejected => 'اترفض';

  @override
  String get ownPayoutUnknown => 'حالة مش معروفة';

  @override
  String get ownWalletRecent => 'آخر حركات الفلوس';

  @override
  String get ownWalletSeeAll => 'شوف الكل';

  @override
  String get ownWalletRecentEmpty => 'مفيش حركات فلوس لسه.';

  @override
  String get ownPlanTitle => 'الباقة';

  @override
  String get ownPlanYours => 'باقتك';

  @override
  String get ownPlanFree => 'مجانية';

  @override
  String get ownPlanPaid => 'مدفوعة';

  @override
  String get ownPlanPending => 'بتتراجع';

  @override
  String get ownPlanCancelled => 'ملغية';

  @override
  String get ownPlanUnknown => 'مش معروفة';

  @override
  String get ownPlanOpen => 'العملاء يقدروا يلاقوا شغلك ويحجزوا.';

  @override
  String ownPlanOpenUntil(String date) {
    return 'العملاء يقدروا يلاقوا شغلك ويحجزوا. شغالة لحد $date.';
  }

  @override
  String ownPlanExpired(String date) {
    return 'خلصت يوم $date. العملاء مش هيقدروا يلاقوا شغلك أو يحجزوا لحد ما تتجدد.';
  }

  @override
  String get ownPlanClosed =>
      'العملاء مش هيقدروا يلاقوا شغلك أو يحجزوا وانت على الباقة دي.';

  @override
  String get ownPlanPendingNote =>
      'طلب الترقية وصلنا. Quick Delivery هتكلمك عشان تفعّل الباقة المدفوعة.';

  @override
  String get ownPlanIncludes => 'الباقة المدفوعة فيها إيه';

  @override
  String get ownPlanFeatureListed => 'شغلك بيظهر للعملاء وبيستقبل حجوزات';

  @override
  String get ownPlanFeatureService => 'تجهّز خدمتك وتغيّر فيها';

  @override
  String get ownPlanFeatureTracking => 'مكان المندوب مباشر على طلباتك';

  @override
  String get ownPlanFeatureNoCommission => 'من غير عمولة على طلباتك';

  @override
  String get ownPlanChangeTitle => 'تغيير الباقة';

  @override
  String get ownPlanChangeBody =>
      'اطلب الباقة المدفوعة من هنا. Quick Delivery بتراجع كل طلب وبتكلمك.';

  @override
  String get ownPlanContactSupport => 'كلّم الدعم';

  @override
  String get ownPlanLoadError => 'مقدرناش نحمّل الباقة.';

  @override
  String get ownPlanRequestUpgrade => 'اطلب الترقية';

  @override
  String get ownPlanUpgradeTitle => 'تطلب الباقة المدفوعة؟';

  @override
  String get ownPlanUpgradeBody => 'Quick Delivery هتراجع طلبك وتكلمك.';

  @override
  String get ownPlanUpgradeSend => 'ابعت الطلب';

  @override
  String get ownPlanUpgradeSent => 'الطلب اتبعت. باقتك بتتراجع.';

  @override
  String get ownPlanDowngrade => 'حوّل للمجانية';

  @override
  String get ownPlanDowngradeTitle => 'تحوّل للباقة المجانية؟';

  @override
  String get ownPlanDowngradeBodyPaid =>
      'العملاء مش هيقدروا يلاقوا شغلك أو يحجزوا لحد ما ترجع للباقة المدفوعة.';

  @override
  String get ownPlanDowngradeBodyPending => 'ده هيلغي طلب الترقية.';

  @override
  String get ownPlanDowngraded => 'انت دلوقتي على الباقة المجانية.';

  @override
  String lnchMapsCopied(String coords) {
    return 'مقدرناش نفتح تطبيق خرايط. اتنسخ المكان: $coords.';
  }

  @override
  String lnchPhoneCopied(String phone) {
    return 'مقدرناش نفتح تطبيق الاتصال. اتنسخ الرقم: $phone.';
  }

  @override
  String get courCallRecipient => 'اتصل بالمستلم';

  @override
  String get bookAddressLabel => 'العنوان · اختياري';

  @override
  String get bookAddressHint => 'الشارع، العمارة، المنطقة';

  @override
  String get bookRecipientTitle => 'مين هيستلم؟';

  @override
  String get bookPassengerTitle => 'مين اللي هيركب؟';

  @override
  String get bookRecipientMe => 'أنا المستلم';

  @override
  String get bookPassengerMe => 'أنا اللي راكب';

  @override
  String get bookRecipientOther => 'حد تاني';

  @override
  String get bookRecipientName => 'الاسم · اختياري';

  @override
  String get bookRecipientNameHint => 'المندوب يسأل على مين؟';

  @override
  String get bookPassengerNameHint => 'السواق يسأل على مين؟';

  @override
  String get bookRecipientPhone => 'رقم التليفون · اختياري';

  @override
  String get bookRecipientNotes => 'ملاحظات · اختياري';

  @override
  String get bookRecipientNotesHint => 'مثلاً: كلّمه قبل ما توصل';

  @override
  String get bookRecipientPhoneHelp => 'بيظهر للمندوب بس وهو بيوصّل الطلب.';

  @override
  String get bookPackageTitle => 'الشحنة';

  @override
  String get bookPackageSize => 'الحجم';

  @override
  String get bookSizeNone => 'مش محدد';

  @override
  String get bookSizeSmall => 'صغيرة';

  @override
  String get bookSizeMedium => 'متوسطة';

  @override
  String get bookSizeLarge => 'كبيرة';

  @override
  String get bookPackageNotes => 'ملاحظات عن الشحنة · اختياري';

  @override
  String get bookPackageNotesHint => 'مثلاً: قابلة للكسر، براحة عليها';

  @override
  String get bookPackageNoPrice => 'الحجم مش بيغيّر السعر.';

  @override
  String bookErrTooLong(int max) {
    return 'اكتب $max حرف بالكتير.';
  }

  @override
  String bookErrAddressTooLong(int max) {
    return 'في عنوان طويل. اكتب $max حرف بالكتير.';
  }

  @override
  String get bookErrNoteTooLong => 'في علامة مميزة طويلة. قصّرها وجرّب تاني.';

  @override
  String get bookErrPhone =>
      'اكتب رقم موبايل مصري زي 01012345678، أو رقم دولي بكود الدولة.';

  @override
  String get bookErrSize => 'اختار صغيرة أو متوسطة أو كبيرة.';

  @override
  String get bookFixFields => 'راجع الخانات اللي عليها علامة.';

  @override
  String get tlPickedUp => 'المندوب استلم الطلب';

  @override
  String get tlPickedUpRide => 'السواق ركّبك';

  @override
  String get tlPickedUpRideOwner => 'السواق ركّب الراكب';

  @override
  String get tlArrived => 'وصل';

  @override
  String get tlCancelled => 'اتلغى';

  @override
  String get tlUnavailable => 'مكانش في مندوب فاضي';

  @override
  String get tlOwnRequested => 'العميل طلب';

  @override
  String tlOwnAccepted(String name) {
    return '$name قبل الطلب';
  }

  @override
  String get phaseToPickup => 'المندوب في الطريق يستلم طلبك';

  @override
  String get phaseToPickupRide => 'السواق في الطريق ليك';

  @override
  String get phasePickedUp => 'في الطريق ليك';

  @override
  String get phasePickedUpRide => 'في الطريق لوجهتك';

  @override
  String get phaseChipToPickup => 'رايح يستلم';

  @override
  String get phaseChipToPickupRide => 'رايح للراكب';

  @override
  String get phaseChipPickedUp => 'استلم الطلب';

  @override
  String get phaseChipPickedUpRide => 'الراكب ركب';

  @override
  String etaAround(String time) {
    return 'هيوصل حوالي $time';
  }

  @override
  String etaPickupAround(String time) {
    return 'عند مكان الاستلام حوالي $time';
  }

  @override
  String etaPickupAroundRide(String time) {
    return 'هيوصلك حوالي $time';
  }

  @override
  String get etaSoon => 'هيوصل في أي لحظة';

  @override
  String get etaPickupSoon => 'هيوصل لمكان الاستلام في أي لحظة';

  @override
  String get ordRecipient => 'المستلم';

  @override
  String get ordPassenger => 'الراكب';

  @override
  String get ordPackage => 'الشحنة';

  @override
  String get ordCallCourier => 'اتصل بالمندوب';

  @override
  String get ownTodayNoteDelivered =>
      'التسليم والكاش بيعدّوا الطلبات اللي اتسلمت النهارده.';

  @override
  String get ownTodayNoteMixed =>
      'التسليم والكاش بيعدّوا الطلبات اللي اتسلمت النهارده. الطلبات القديمة اللي من غير وقت تسليم بتتحسب بيوم ما اتطلبت.';

  @override
  String get ownRowDelivered => 'اتسلم';

  @override
  String get ownRowEta => 'الوقت المتوقع';

  @override
  String get ownCallRecipient => 'اتصل بالمستلم';

  @override
  String get ownCallCourier => 'اتصل بالمندوب';

  @override
  String get ownTimelineTitle => 'خطوات الطلب';

  @override
  String get ntfCancelRequestedTitle => 'مندوب طالب يلغي مهمة';

  @override
  String get ntfCancelExpiredTitle => 'وقت طلب الإلغاء خلص';

  @override
  String get ntfCancelResolvedTitle => 'اترد على طلب الإلغاء بتاعك';

  @override
  String get ntfJobOfferTitle => 'عرض مهمة جديد';

  @override
  String get ntfJobOfferBody => 'رد عليه من المهمة قبل ما الوقت يخلص.';

  @override
  String get ntfJobAlertTitle => 'مهمة جديدة';

  @override
  String get ntfKycApprovedTitle => 'التوثيق بتاعك اتقبل';

  @override
  String get ntfKycRejectedTitle => 'التوثيق بتاعك ما اتقبلش';

  @override
  String get vrfRejectedOpen => 'صلّح المستندات';

  @override
  String get updDownload => 'نزّل التحديث';

  @override
  String get roleUnsupportedTitle => 'الحساب ده مينفعش يستخدم التطبيق';

  @override
  String get roleUnsupportedBody =>
      'ادخل بحساب عميل أو صاحب شغل أو مندوب. حسابات الموظفين بتستخدم لوحة التحكم على الويب.';

  @override
  String get ownSvcPhotoSheetTitle => 'صورة الخدمة';

  @override
  String get ownSvcPhotoAdd => 'ضيف صورة';

  @override
  String get ownSvcPhotoReplace => 'غيّر الصورة';

  @override
  String get ownSvcPhotoRemove => 'شيل الصورة';

  @override
  String get ownSvcPhotoCamera => 'صوّر دلوقتي';

  @override
  String get ownSvcPhotoGallery => 'اختار من الصور';

  @override
  String ownSvcPhotoUploading(int percent) {
    return 'بنرفع الصورة… $percent٪';
  }

  @override
  String get ownSvcPhotoPending => 'الصورة جاهزة. هتتضاف لخدمتك لما تدوس احفظ.';

  @override
  String get ownSvcPhotoErrUnavailable =>
      'رفع الصور مش متاح دلوقتي. جرّب تاني بعدين.';

  @override
  String get ownSvcPhotoErrFormat => 'استخدم صورة JPEG أو PNG.';

  @override
  String get ownSvcPhotoErrTooLarge =>
      'الصورة دي أكبر من 5 ميجا. اختار صورة أصغر.';

  @override
  String get ownSvcPhotoErrRejected =>
      'مقدرناش نستخدم الصورة دي. جرّب صورة تانية.';

  @override
  String get ownSvcPhotoErrNetwork =>
      'الصورة مترفعتش. اتأكد من النت وجرّب تاني.';

  @override
  String get ownSvcPhotoErrRemove => 'مقدرناش نشيل الصورة. جرّب تاني.';
}
