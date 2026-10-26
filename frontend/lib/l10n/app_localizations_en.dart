// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

  @override
  String get search => 'Search';

  @override
  String get loading => 'Loading...';

  @override
  String get scheduleDayMon => 'Monday';

  @override
  String get scheduleDayTue => 'Tuesday';

  @override
  String get scheduleDayWed => 'Wednesday';

  @override
  String get scheduleDayThu => 'Thursday';

  @override
  String get scheduleDayFri => 'Friday';

  @override
  String get scheduleDaySat => 'Saturday';

  @override
  String get scheduleDaySun => 'Sunday';

  @override
  String get otpFooterBrand => 'Quick Delivery';

  @override
  String get reconciliationNote => 'Note';

  @override
  String get employeeProposalRacedError =>
      'The customer already sent a price — respond to it instead.';

  @override
  String get enumPaymentWallet => 'Wallet';

  @override
  String get enumRoleUser => 'User';

  @override
  String get enumTierFree => 'Free';

  @override
  String get enumTierPaid => 'Paid';

  @override
  String get enumTierPendingPayment => 'Pending payment';

  @override
  String get enumPayoutVodafoneCash => 'Vodafone Cash';

  @override
  String get enumTxnDeposit => 'Deposit';

  @override
  String get enumTxnEscrowLock => 'Escrow lock';

  @override
  String get enumTxnEscrowRelease => 'Escrow release';

  @override
  String get enumTxnPlatformFee => 'Platform fee';

  @override
  String get enumTxnPayout => 'Payout';

  @override
  String get enumTxnPayoutRefund => 'Payout refund';

  @override
  String get enumTxnRefund => 'Refund';

  @override
  String get enumTxnFeeDeduction => 'Fee deduction';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusActive => 'Active';

  @override
  String get statusAwaitingPrice => 'Awaiting Price';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusPendingDispatch => 'Finding Courier';

  @override
  String get statusUnavailable => 'Unavailable';

  @override
  String get serviceTemporarilyUnavailable =>
      'The service is temporarily unavailable — nothing was changed. Please try again shortly.';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusReconciliationRequired => 'Reconciliation Required';

  @override
  String get statusUnknown => 'Unknown';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get tooltipNotifications => 'Notifications';

  @override
  String get payoutMethodBankTransfer => 'Bank Transfer';

  @override
  String get payoutMethodInstapay => 'InstaPay';

  @override
  String get codOptionTitle => 'Cash on delivery';

  @override
  String get auditActionAccountSuspended => 'Account suspended';

  @override
  String get auditActionAccountReactivated => 'Account reactivated';

  @override
  String get auditActionKycReviewed => 'Identity review completed';

  @override
  String get auditActionDocumentViewed => 'Document viewed';

  @override
  String get usernameRequired => 'Username is required';

  @override
  String get usernameTooShort => 'Username must be at least 3 characters';

  @override
  String get usernameTooLong => 'Username must be at most 30 characters';

  @override
  String get usernameInvalidChars => 'Username contains invalid characters';

  @override
  String get emailRequired => 'Email is required';

  @override
  String get invalidEmailFormat => 'Please enter a valid email';

  @override
  String get passwordRequired => 'Password is required';

  @override
  String get passwordTooShort => 'Password must be at least 8 characters';

  @override
  String get passwordTooLong => 'Password must be at most 72 bytes';

  @override
  String get passwordTooCommon =>
      'This password is too common — pick a less guessable one.';

  @override
  String get passwordTooWeak =>
      'This password doesn\'t meet the security requirements.';

  @override
  String get userNotAuthenticatedError => 'User not authenticated.';

  @override
  String get unknownActionLabel => 'Unknown Action';

  @override
  String get roleOwnerLabel => 'Owner';

  @override
  String get roleEmployeeLabel => 'Employee';

  @override
  String get reconciliationUnderDistance =>
      'Distance mismatch — under 70% of booked distance';

  @override
  String get reconciliationUnrecordedEscrow =>
      'Unrecorded escrow balance failure';

  @override
  String get reconciliationImplausibleSpeed =>
      'Implausible movement speed detected';

  @override
  String get reconciliationRequiredDefault =>
      'Escrow reconciliation required for manual review';

  @override
  String get newDispatchAlertMessage =>
      'New dispatch offer received. Refreshing available jobs...';

  @override
  String get digitalPaymentsComingSoon =>
      'Coming soon: wallet top-up and payouts are not available yet. Bookings are paid cash on delivery.';

  @override
  String get qdStatusPending => 'Waiting for courier';

  @override
  String get qdStatusPendingDispatch => 'Finding a courier';

  @override
  String get qdStatusUnavailable => 'No courier available';

  @override
  String get qdStatusAwaitingPrice => 'New price offered';

  @override
  String get qdStatusAssigned => 'Courier assigned';

  @override
  String get qdStatusActive => 'On the way';

  @override
  String get qdStatusCompleted => 'Delivered';

  @override
  String get qdStatusCancelled => 'Cancelled';

  @override
  String get qdStatusUnderReview => 'Under review';

  @override
  String get qdStatusCancellationRequested => 'Cancellation requested';

  @override
  String get qdStatusUnknown => 'Unknown status';

  @override
  String get qdComingSoon => 'Coming soon';

  @override
  String get qdLoading => 'Loading';

  @override
  String get qdErrorTitle => 'Something went wrong';

  @override
  String get qdErrorBody => 'Check your connection and try again.';

  @override
  String qdTimeLeft(String time) {
    return '$time left';
  }

  @override
  String get qdPickup => 'Pickup';

  @override
  String get qdDropoff => 'Drop-off';

  @override
  String qdStepProgress(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get qdTimelineDone => 'Done';

  @override
  String get qdTimelineCurrent => 'Current step';

  @override
  String get qdTimelineUpcoming => 'Not yet';

  @override
  String qdMoneyAmount(String amount) {
    return 'EGP $amount';
  }

  @override
  String get qdMainNavigation => 'Main navigation';

  @override
  String get custNavHome => 'Home';

  @override
  String get custNavOrders => 'My orders';

  @override
  String get custNavAccount => 'Account';

  @override
  String get custPickupFrom => 'Pick up from';

  @override
  String get custCurrentLocation => 'Your current location';

  @override
  String get custPinnedLocation => 'Pinned location';

  @override
  String get custChooseLocation => 'Choose a location';

  @override
  String get custHomeTitle => 'What are you sending today?';

  @override
  String get custCatDelivery => 'Deliver an order';

  @override
  String get custCatDeliverySub => 'From place to place in the city';

  @override
  String get custCatShipping => 'Ship a parcel';

  @override
  String get custCatShippingSub => 'Between governorates';

  @override
  String get custCatRide => 'Ride';

  @override
  String get custCatRideSub => 'A car that takes you where you\'re going';

  @override
  String get custAllServices => 'All services';

  @override
  String get custServicesSection => 'Services';

  @override
  String get custOngoingOrder => 'Ongoing order';

  @override
  String get custNoOngoing => 'No ongoing orders right now.';

  @override
  String get custOrderFallback => 'Order';

  @override
  String custOrderTitleRef(String title, String ref) {
    return '$title · $ref';
  }

  @override
  String get custTrack => 'Details';

  @override
  String custToPlace(String place) {
    return 'To $place';
  }

  @override
  String get custJobsLoadError => 'We couldn\'t load your orders.';

  @override
  String custCompaniesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count companies available',
      one: '1 company available',
      zero: 'No companies available',
    );
    return '$_temp0';
  }

  @override
  String custNearPlace(String place, String km) {
    return 'Near $place · up to $km km';
  }

  @override
  String get custSortLabel => 'Sort';

  @override
  String get custSortNearest => 'Nearest';

  @override
  String get custSortCheapest => 'Cheapest';

  @override
  String get custFilters => 'Filters';

  @override
  String get custOpen => 'Open';

  @override
  String get custClosed => 'Closed';

  @override
  String custOpensAt(String when) {
    return 'Opens $when';
  }

  @override
  String custKmAway(String km) {
    return '$km km from you';
  }

  @override
  String custAboutAmount(String amount) {
    return 'About $amount';
  }

  @override
  String get custLocating => 'Finding your location…';

  @override
  String get custLocationOffBanner =>
      'We couldn\'t get your location, so these companies are near the default area. Pick your area to see what\'s near you.';

  @override
  String get custPickArea => 'Pick area on map';

  @override
  String get custNoCompaniesTitle => 'No companies nearby';

  @override
  String get custNoCompaniesBody => 'Try a longer distance or another area.';

  @override
  String get custChangeFilters => 'Change filters';

  @override
  String get custFilterDistance => 'Distance';

  @override
  String custRadiusKm(String km) {
    return '$km km';
  }

  @override
  String get custSearchArea => 'Search area';

  @override
  String get custShowResults => 'Show results';

  @override
  String get custPickupPlace => 'Pickup place';

  @override
  String get custDropoffPlace => 'Drop-off place';

  @override
  String get custPickerHint =>
      'Move the map until the pin is exactly on the place';

  @override
  String get custNoteLabel => 'A landmark for the courier · optional';

  @override
  String get custNoteHint =>
      'e.g. the building next to the pharmacy, 3rd floor';

  @override
  String get custConfirmPlace => 'Confirm place';

  @override
  String get custMyLocation => 'My location';

  @override
  String get custLocationDenied =>
      'Location is off, so we can\'t find you. Move the map and pick the place yourself.';

  @override
  String get custConfirmOrder => 'Confirm order';

  @override
  String get custChange => 'Change';

  @override
  String get custRouteTitle => 'From where to where?';

  @override
  String get custChooseDropoff => 'Choose the drop-off place';

  @override
  String get custPriceTitle => 'Price';

  @override
  String get custBaseFare => 'Order opening';

  @override
  String get custPerKm => 'Per km';

  @override
  String custDistanceLine(String km, String rate) {
    return '$km km × $rate';
  }

  @override
  String get custEstimate => 'Estimate';

  @override
  String get custPriceNeedsDropoff =>
      'Choose the drop-off place to see the estimate.';

  @override
  String get custPriceDisclaimer =>
      'This is an estimate by straight-line distance. The price can change if the courier offers another price and you accept it.';

  @override
  String get custPayCash => 'Cash to the courier';

  @override
  String get custPayOnlineSoon => 'Electronic payment is coming soon';

  @override
  String get custChooseDropoffFirst => 'Choose the drop-off place first';

  @override
  String get custOrderNow => 'Order now';

  @override
  String custBookingFailed(String reason) {
    return 'We couldn\'t place your order. $reason';
  }

  @override
  String get custServiceClosed =>
      'This company is closed now, so it can\'t take orders.';

  @override
  String get custOrdersTitle => 'My orders';

  @override
  String get custOrdersKind => 'Order type';

  @override
  String custTabOngoing(int count) {
    return 'Ongoing · $count';
  }

  @override
  String get custTabPast => 'Past';

  @override
  String get custCashOnDelivery => 'Cash on delivery';

  @override
  String get custNoOngoingTitle => 'No ongoing orders';

  @override
  String get custNoPastTitle => 'No past orders yet';

  @override
  String get custOrdersEmptyBody =>
      'Book a delivery, a parcel or a ride and it shows up here.';

  @override
  String get custBrowseServices => 'Browse services';

  @override
  String custTodayAt(String time) {
    return 'Today · $time';
  }

  @override
  String custDateAt(String date, String time) {
    return '$date · $time';
  }

  @override
  String custNearYou(String km) {
    return 'Near you · up to $km km';
  }

  @override
  String custFromPrice(String base, String rate) {
    return 'From $base + $rate/km';
  }

  @override
  String get ordTitle => 'Your order';

  @override
  String get ordLoadError => 'We couldn\'t load your order';

  @override
  String get ordRefreshError =>
      'We couldn\'t update your order. This is the last update we have.';

  @override
  String get ordUnknownTitle => 'We can\'t show this order\'s status';

  @override
  String get ordUnknownBody =>
      'Pull down to refresh. If it stays like this, contact support.';

  @override
  String get ordPickupFrom => 'Pickup from';

  @override
  String get ordDeliverTo => 'Delivery at';

  @override
  String get ordCashEstimate => 'Cash · estimated';

  @override
  String get ordPayCash => 'You\'ll pay cash';

  @override
  String get ordPaidCash => 'Paid cash';

  @override
  String get ordPriceNotSet => 'Not set yet';

  @override
  String get ordCourierFallback => 'Your courier';

  @override
  String get ordChatCourier => 'Chat with the courier';

  @override
  String get ordCancelledTitle => 'Order cancelled';

  @override
  String get ordCancelledBody =>
      'This order won\'t go ahead. You can order again any time.';

  @override
  String ordCancelReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get ordProposalExpiredTitle => 'The price offer ran out of time';

  @override
  String get ordProposalExpiredBody =>
      'Nobody answered the price offer in time, so the order was cancelled. You can order again.';

  @override
  String get ordReviewTitle => 'Your order is under review';

  @override
  String get ordReviewBody =>
      'The company is checking the trip before closing the order. Nothing is needed from you.';

  @override
  String get ordOnHold => 'Amount on hold';

  @override
  String get chatYou => 'You';

  @override
  String chatUserFallback(String id) {
    return 'User $id';
  }

  @override
  String get chatLive => 'Connected';

  @override
  String get chatConnecting => 'Connecting…';

  @override
  String get chatOffline => 'Not connected, retrying';

  @override
  String get chatDenied => 'You can\'t open this chat.';

  @override
  String get chatEmptyTitle => 'No messages yet';

  @override
  String get chatEmptyBody =>
      'Send the courier any extra details about your order.';

  @override
  String get chatHint => 'Write a message';

  @override
  String get chatSend => 'Send';

  @override
  String chatSendFailed(String error) {
    return 'We couldn\'t send the message. $error';
  }

  @override
  String get ordSearchingTitle => 'Looking for a courier';

  @override
  String get ordSearchingBody =>
      'We offer your order to couriers one by one until one accepts.';

  @override
  String ordSearchingBodyCompany(String company) {
    return 'We offer your order to $company couriers one by one until one accepts.';
  }

  @override
  String ordOfferedTitle(String name) {
    return '$name is looking at your order';
  }

  @override
  String get ordOfferedTitleNoName => 'A courier is looking at your order';

  @override
  String get ordOfferedSub => 'Got more details? Send them in the chat.';

  @override
  String get ordCancelOrder => 'Cancel order';

  @override
  String get ordCancelSheetTitle => 'Cancel this order?';

  @override
  String get ordCancelSheetBody =>
      'Tell the company why. A reason is required.';

  @override
  String get ordCancelReasonLabel => 'Reason';

  @override
  String get ordCancelKeep => 'Keep the order';

  @override
  String get ordCancelDone => 'Your order was cancelled.';

  @override
  String get ordCancelDoneRefunded =>
      'Your order was cancelled and the amount was refunded.';

  @override
  String get ordUnavailableTitle => 'No courier available right now';

  @override
  String get ordUnavailableBody =>
      'All couriers are busy. You can send the same order again.';

  @override
  String get ordRetryBooking => 'Order again';

  @override
  String get ordRetryBooked => 'We sent your order again.';

  @override
  String ordProposalCourierTitle(String name) {
    return '$name offered a different price';
  }

  @override
  String get ordProposalCourierTitleNoName =>
      'The courier offered a different price';

  @override
  String get ordProposalCourierSub =>
      'You need to accept before the order starts.';

  @override
  String ordProposalMineTitle(String price) {
    return 'You offered $price';
  }

  @override
  String get ordProposalMineSub => 'Waiting for the courier to answer.';

  @override
  String get ordProposalOpenTitle => 'Agree on the price';

  @override
  String get ordProposalOpenSub => 'Send a price within the allowed range.';

  @override
  String get ordOriginalPrice => 'Original price';

  @override
  String get ordOfferedPrice => 'Offered price';

  @override
  String ordPriceMore(String amount) {
    return '$amount more';
  }

  @override
  String ordPriceLess(String amount) {
    return '$amount less';
  }

  @override
  String get ordPriceSame => 'Same price';

  @override
  String get ordOfferExpiresIn => 'Offer expires in';

  @override
  String get ordOfferExpiryNote =>
      'If time runs out without an answer, the order is cancelled and you can order again.';

  @override
  String get ordDecline => 'Decline';

  @override
  String ordAcceptPrice(String price) {
    return 'Accept $price';
  }

  @override
  String get ordYourPrice => 'Your price';

  @override
  String ordPriceRange(String min, String max) {
    return 'Between $min and $max';
  }

  @override
  String get ordPriceInvalid => 'Enter a number, like 42.';

  @override
  String ordPriceOutOfRange(String min, String max) {
    return 'Enter a price between $min and $max.';
  }

  @override
  String get ordSendOffer => 'Send offer';

  @override
  String get ordOfferSent => 'Your offer was sent.';

  @override
  String get ordAccepted => 'You accepted the price.';

  @override
  String get ordDeclined => 'You declined the price.';

  @override
  String get ordStateChanged =>
      'The order changed: the other side already answered or its status moved on.';

  @override
  String get ordActiveTitle => 'The courier is working on your order';

  @override
  String get ordActiveSub => 'Their location updates on the map as they move.';

  @override
  String get ordStepOrdered => 'You ordered';

  @override
  String ordStepAccepted(String name) {
    return '$name accepted the order';
  }

  @override
  String get ordStepAcceptedNoName => 'The courier accepted the order';

  @override
  String get ordStepOnTheWay => 'On the way';

  @override
  String get ordStepNow => 'Now';

  @override
  String get ordStepDelivered => 'Delivered';

  @override
  String get ordSteps => 'Order steps';

  @override
  String get ordComplaint => 'Problem? Open a complaint';

  @override
  String get ordMapWaiting => 'Waiting for the courier\'s location';

  @override
  String get ordMapReconnecting => 'Reconnecting to live tracking…';

  @override
  String get ordMapDenied => 'You can\'t follow this order on the map.';

  @override
  String get ordMapLabel => 'Map with the courier\'s position';

  @override
  String get ordZoomIn => 'Zoom in';

  @override
  String get ordZoomOut => 'Zoom out';

  @override
  String get ordRecenter => 'Center the map';

  @override
  String get ordDeliveredTitle => 'Your order was delivered';

  @override
  String ordDeliveredPaidCash(String price) {
    return 'You paid $price cash';
  }

  @override
  String ordDeliveredPaid(String price) {
    return 'You paid $price';
  }

  @override
  String ordRateCourier(String name) {
    return 'Rate $name';
  }

  @override
  String get ordRateCourierNoName => 'Rate the courier';

  @override
  String get ordRateCompany => 'Rate the company';

  @override
  String get ordRatedThanks => 'Thanks, your rating was sent.';

  @override
  String rateQuestion(String name) {
    return 'How was $name?';
  }

  @override
  String get rateQuestionCourier => 'How was the courier?';

  @override
  String get rateQuestionCompany => 'How was the company?';

  @override
  String get rateStars => 'Rating';

  @override
  String get rateBlindNote =>
      'Your rating shows to the other side only after they rate you too. The comment goes to the company only.';

  @override
  String get rateComment => 'Comment · optional';

  @override
  String get rateSend => 'Send rating';

  @override
  String get rateNotNow => 'Not now';

  @override
  String rateFailed(String error) {
    return 'We couldn\'t send your rating. $error';
  }

  @override
  String get rateIdentityError => 'We can\'t tell who to rate for this order.';

  @override
  String get rateOtherRated =>
      'The other side already rated you. Both ratings are visible now.';

  @override
  String get rateOtherCheckFailed =>
      'We couldn\'t check whether the other side rated you.';

  @override
  String get rateClose => 'Close';

  @override
  String rateStar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stars',
      one: '1 star',
    );
    return '$_temp0';
  }

  @override
  String get authSwitchLanguage => 'العربية';

  @override
  String get authSwitchLanguageLabel => 'Switch to Arabic';

  @override
  String get authThemeLabel => 'Change the look';

  @override
  String get authBack => 'Back';

  @override
  String get authLoginTitle => 'Welcome';

  @override
  String get authLoginSubtitle => 'Sign in to order and follow your orders';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authEmailHint => 'name@example.com';

  @override
  String get authEmailRequired => 'Enter your email';

  @override
  String get authEmailInvalid => 'Enter an email like name@example.com';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authPasswordRequired => 'Enter your password';

  @override
  String get authForgotPassword => 'Forgot your password?';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authNoAccount => 'No account?';

  @override
  String get authCreateAccountLink => 'Create one';

  @override
  String get authSignupTitle => 'New account';

  @override
  String get authRoleQuestion => 'Who are you?';

  @override
  String get authRoleCustomer => 'Customer';

  @override
  String get authRoleCustomerHint => 'I want to send orders';

  @override
  String get authRoleOwner => 'Business owner';

  @override
  String get authRoleOwnerHint => 'I have a company and couriers';

  @override
  String get authCourierNote =>
      'Couriers get their accounts from their business owner.';

  @override
  String get authNameLabel => 'Name';

  @override
  String get authNameRequired => 'Enter your name';

  @override
  String get authNameTooShort => 'The name needs at least 3 letters';

  @override
  String get authNameTooLong => 'The name can have at most 30 letters';

  @override
  String get authNameInvalid => 'Use letters, numbers, spaces or _ only';

  @override
  String get authPasswordHelp =>
      'At least 8 characters, and not an easy one like 12345678';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authHaveAccount => 'Have an account?';

  @override
  String get authSignInLink => 'Sign in';

  @override
  String get authOtpTitle => 'Enter the code';

  @override
  String get authOtpSentTo => 'We sent a 6-digit code to';

  @override
  String get authOtpLabel => 'Verification code';

  @override
  String get authOtpIncomplete => 'Enter all 6 digits';

  @override
  String get authOtpConfirm => 'Confirm';

  @override
  String get authResendWait => 'Didn\'t get it? You can send it again in';

  @override
  String get authResendPrompt => 'Didn\'t get it?';

  @override
  String get authResendNow => 'Send the code again';

  @override
  String get authCodeResent => 'We sent you a new code.';

  @override
  String authDevOtp(String otp) {
    return 'Test mode: we filled in the code $otp for you.';
  }

  @override
  String get resetTitle => 'Forgot your password?';

  @override
  String get resetEmailBody =>
      'Enter your account email and we\'ll send you a code.';

  @override
  String get resetSendCode => 'Send the code';

  @override
  String get resetCodeSent => 'We sent a code to your email.';

  @override
  String get resetNewTitle => 'New password';

  @override
  String get resetNewBody => 'Choose a password you don\'t use anywhere else.';

  @override
  String get resetNewLabel => 'New password';

  @override
  String get resetConfirmLabel => 'Type it again';

  @override
  String get resetMismatch => 'The two passwords don\'t match';

  @override
  String get resetSave => 'Save password';

  @override
  String get resetDone =>
      'Your password was changed. Sign in with the new one.';

  @override
  String get resetExpired =>
      'This reset ran out of time. Start again to get a new code.';

  @override
  String get resetStartAgain => 'Start again';

  @override
  String resetStep(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get acctEdit => 'Edit';

  @override
  String get acctSectionAccount => 'Account';

  @override
  String get acctSectionApp => 'App';

  @override
  String get acctSectionSupport => 'Support';

  @override
  String get acctMyDetails => 'My details';

  @override
  String get acctSavedAddresses => 'Saved addresses';

  @override
  String get acctSecurity => 'Security';

  @override
  String get acctTwoFactorOn => '2-step verification on';

  @override
  String get acctTwoFactorOff => '2-step verification off';

  @override
  String get acctWallet => 'Wallet';

  @override
  String get acctLanguage => 'Language';

  @override
  String get acctLangArabic => 'العربية';

  @override
  String get acctLangEnglish => 'English';

  @override
  String get acctPhoneSetting => 'Same as the phone';

  @override
  String get acctTheme => 'Appearance';

  @override
  String get acctThemeLight => 'Light';

  @override
  String get acctThemeDark => 'Dark';

  @override
  String get acctNotifications => 'Notifications';

  @override
  String get acctSupport => 'Support and complaints';

  @override
  String get acctLogout => 'Sign out';

  @override
  String get acctSuspendedTitle => 'Your account is suspended';

  @override
  String get acctSuspendedDefault =>
      'You can\'t change your details for now. Contact support to know more.';

  @override
  String get acctLoadError => 'We couldn\'t refresh your account details.';

  @override
  String get acctPhoneLabel => 'Phone';

  @override
  String get acctPhoneHint => '01xxxxxxxxx';

  @override
  String get acctChangeEmail => 'Change';

  @override
  String get acctChangeEmailLabel => 'Change email';

  @override
  String get acctEmailNote => 'To change it we send a code to the new email.';

  @override
  String get acctSave => 'Save';

  @override
  String get acctSaved => 'Your details were saved.';

  @override
  String get acctAddAddress => 'Add an address';

  @override
  String get acctEditAddress => 'Edit address';

  @override
  String get acctAddressLabel => 'Address';

  @override
  String get acctAddressHint => 'Building, street, area';

  @override
  String get acctAddressRequired => 'Write the address';

  @override
  String get acctAddressMax => 'You can save up to 10 addresses';

  @override
  String acctAddressCount(int count) {
    return '$count of 10';
  }

  @override
  String get acctAddressesNote =>
      'Addresses are saved as text, without a map pin.';

  @override
  String get acctAddressesEmpty => 'No saved addresses yet';

  @override
  String get acctAddressesEmptyBody => 'Save the places you order from often.';

  @override
  String get acctSaveAddress => 'Save address';

  @override
  String acctDeleteAddress(String address) {
    return 'Delete $address';
  }

  @override
  String get acctAddressDeleted => 'Address deleted.';

  @override
  String get acctUndo => 'Undo';

  @override
  String get acctTwoFactor => '2-step verification';

  @override
  String get acctTwoFactorBody =>
      'We send a code to your email every time you sign in.';

  @override
  String get acctTwoFactorOffTitle => 'Turn off 2-step verification?';

  @override
  String get acctTwoFactorOffBody =>
      'Anyone with your password could then sign in without a code.';

  @override
  String get acctTwoFactorTurnOff => 'Turn off';

  @override
  String get acctCancel => 'Cancel';

  @override
  String get acctPasswordTitle => 'Confirm it\'s you';

  @override
  String get acctPasswordBody =>
      'Enter your password to turn off 2-step verification.';

  @override
  String get acctWrongPassword => 'That password isn\'t right.';

  @override
  String get acctTwoFactorOnDone => '2-step verification is on.';

  @override
  String get acctTwoFactorOffDone => '2-step verification is off.';

  @override
  String get acctNewEmailLabel => 'New email';

  @override
  String get acctEmailChanged => 'Your email was changed.';

  @override
  String get acctSameEmail => 'This is already your email';

  @override
  String get acctClose => 'Close';

  @override
  String get ntfTitle => 'Notifications';

  @override
  String get ntfMarkAllRead => 'Mark all read';

  @override
  String get ntfClearAll => 'Clear all';

  @override
  String get ntfClearTitle => 'Clear all notifications?';

  @override
  String get ntfClearBody => 'You can\'t get them back.';

  @override
  String get ntfClear => 'Clear';

  @override
  String get ntfToday => 'Today';

  @override
  String get ntfYesterday => 'Yesterday';

  @override
  String get ntfJustNow => 'Just now';

  @override
  String ntfMinutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String ntfHoursAgo(int count) {
    return '$count h ago';
  }

  @override
  String get ntfUnread => 'Unread';

  @override
  String get ntfDismiss => 'Remove notification';

  @override
  String get ntfLive => 'Live: new notifications show up here';

  @override
  String get ntfOffline => 'Not connected: new notifications may be late';

  @override
  String get ntfConnectError => 'We lost the live connection.';

  @override
  String get ntfReconnect => 'Reconnect';

  @override
  String get ntfEmptyTitle => 'No notifications yet';

  @override
  String get ntfEmptyBody =>
      'We\'ll tell you here when something happens with your orders.';

  @override
  String get ntfLoadError => 'We couldn\'t load your notifications.';

  @override
  String get ntfShowOlder => 'Show older';

  @override
  String get ntfAcceptedTitle => 'A courier accepted your order';

  @override
  String get ntfAcceptedBody => 'Follow it from the order page.';

  @override
  String get ntfUnavailableTitle => 'No courier is free right now';

  @override
  String get ntfUnavailableBody => 'You can order again from My orders.';

  @override
  String get ntfCancelledTitle => 'Your order was cancelled';

  @override
  String get ntfOrdersBody => 'Open My orders for the details.';

  @override
  String get ntfCompletedTitle => 'Your order was delivered';

  @override
  String get ntfTicketResolvedTitle => 'Your complaint was resolved';

  @override
  String get ntfTicketAssignedTitle => 'Support joined your complaint';

  @override
  String get ntfTicketAssignedBody => 'Reply to them in the complaint chat.';

  @override
  String get ntfDisputeTitle => 'The review of your order is done';

  @override
  String get supTitle => 'Support';

  @override
  String supOpenTab(int count) {
    return 'Open · $count';
  }

  @override
  String get supResolvedTab => 'Resolved';

  @override
  String get supStatusPending => 'Waiting for a reply';

  @override
  String get supStatusAssigned => 'With support';

  @override
  String get supStatusResolved => 'Resolved';

  @override
  String get supStatusOpen => 'Open';

  @override
  String supAboutOrder(String ref, String when) {
    return 'About order $ref · $when';
  }

  @override
  String supGeneral(String when) {
    return 'General · $when';
  }

  @override
  String supResolution(String note) {
    return 'Resolution: $note';
  }

  @override
  String get supHintTitle => 'Problem with an order?';

  @override
  String get supHintBody =>
      'Pick the order and tell us what happened. The support team will answer you here.';

  @override
  String get supNewComplaint => 'New complaint';

  @override
  String get supResolvedEmpty => 'No resolved complaints yet';

  @override
  String get supLoadError => 'We couldn\'t load your complaints.';

  @override
  String get supOrderLabel => 'Which order?';

  @override
  String get supNoOrderOption => 'Not about an order';

  @override
  String get supOrdersLoading => 'Loading your orders…';

  @override
  String get supOrdersError =>
      'We couldn\'t load your orders. You can still send it without one.';

  @override
  String get supSubjectLabel => 'Subject';

  @override
  String get supSubjectHint => 'In a few words';

  @override
  String get supSubjectRequired => 'Write a subject';

  @override
  String get supDescriptionLabel => 'What happened?';

  @override
  String get supDescriptionHint => 'Tell us the details';

  @override
  String get supDescriptionRequired => 'Tell us what happened';

  @override
  String get supSend => 'Send complaint';

  @override
  String get supSent =>
      'We got your complaint. Support will answer you in its chat.';

  @override
  String supComplaintRef(String ref) {
    return 'Complaint $ref';
  }

  @override
  String get supChatEmpty =>
      'Write to support here. You can attach a photo or a PDF.';

  @override
  String get supResolvedBanner => 'This complaint is resolved.';

  @override
  String get supReadOnly =>
      'A resolved complaint can\'t get new messages. Open a new one if you need to.';

  @override
  String get supAttach => 'Attach a photo or PDF';

  @override
  String get supFileEmpty => 'The file is empty.';

  @override
  String get supFileTooBig => 'Files can be up to 10 MB.';

  @override
  String get supAttachFailed => 'We couldn\'t send the file.';

  @override
  String get updTitle => 'Update the app';

  @override
  String get updBody =>
      'This version doesn\'t work anymore. Install the new one to keep using Quick Delivery.';

  @override
  String get updInstalled => 'Installed version';

  @override
  String get updMinimum => 'Oldest version that works';

  @override
  String get updLatest => 'Latest version';

  @override
  String get updLinkLabel => 'Download link';

  @override
  String get updCopy => 'Copy the download link';

  @override
  String get updCopied =>
      'Link copied. Open it in your browser to install the new version.';

  @override
  String ownCourierUnknown(String id) {
    return 'Courier $id';
  }

  @override
  String get ownAgoNow => 'just now';

  @override
  String ownAgoMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count min ago',
      one: '1 min ago',
    );
    return '$_temp0';
  }

  @override
  String ownAgoHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count h ago',
      one: '1 h ago',
    );
    return '$_temp0';
  }

  @override
  String get ownNotNow => 'Not now';

  @override
  String get ownRefresh => 'Refresh';

  @override
  String ownOrderTitle(String ref) {
    return 'Order $ref';
  }

  @override
  String get ownOrderFallbackTitle => 'Order';

  @override
  String get ownOrderMissing => 'This order isn\'t in your list anymore.';

  @override
  String ownCancelReqTitle(String name) {
    return '$name wants to cancel this order';
  }

  @override
  String ownCancelReqQuote(String reason) {
    return '“$reason”';
  }

  @override
  String get ownCancelReqNoReason => 'No reason given';

  @override
  String ownCancelReqSince(String ago) {
    return 'Asked $ago';
  }

  @override
  String get ownCancelReqKeep => 'Keep order';

  @override
  String get ownCancelReqApprove => 'Approve';

  @override
  String get ownCancelReqApproveTitle => 'Approve the cancellation?';

  @override
  String get ownCancelReqApproveBody =>
      'The order will be cancelled and the customer will be told.';

  @override
  String get ownCancelReqKeepTitle => 'Keep the order going?';

  @override
  String ownCancelReqKeepBody(String name) {
    return '$name stays on the order and has to finish it.';
  }

  @override
  String get ownCancelReqApproved =>
      'Cancellation approved. The order is cancelled.';

  @override
  String get ownCancelReqDeclined =>
      'Request declined. The courier keeps the order.';

  @override
  String get ownCancelReqConflict =>
      'This request already changed, it may have run out. The order was refreshed.';

  @override
  String get ownDistanceReviewTitle => 'Distance looked short, review';

  @override
  String ownDistanceReviewBody(String actual, String booked) {
    return 'The trip tracked $actual km of the $booked km booked. The cash was still recorded.';
  }

  @override
  String get ownSeeOnMap => 'See on the map';

  @override
  String get ownRowCustomer => 'Customer';

  @override
  String ownCustomerRef(String id) {
    return 'Customer $id';
  }

  @override
  String get ownRowCourier => 'Courier';

  @override
  String get ownCourierNone => 'Not assigned yet';

  @override
  String get ownRowPayment => 'Payment';

  @override
  String ownPayCash(String amount) {
    return 'Cash · $amount';
  }

  @override
  String get ownPayCashNoPrice => 'Cash · price not set yet';

  @override
  String ownPayOther(String method, String amount) {
    return '$method · $amount';
  }

  @override
  String get ownRowCashRecorded => 'Cash recorded';

  @override
  String get ownRowOrdered => 'Ordered';

  @override
  String get ownRowCancelReason => 'Cancellation reason';

  @override
  String get ownCancelOrder => 'Cancel order';

  @override
  String get ownCancelKeep => 'Keep the order';

  @override
  String get ownCancelSheetTitle => 'Cancel this order?';

  @override
  String get ownCancelSheetCod =>
      'The customer and the courier will be told. Write why you\'re cancelling.';

  @override
  String ownCancelSheetHeld(String amount) {
    return 'The $amount held for this order goes back to the customer. Write why you\'re cancelling.';
  }

  @override
  String get ownCancelReasonLabel => 'Reason';

  @override
  String get ownCancelled => 'Order cancelled.';

  @override
  String get ownCancelledRefunded =>
      'Order cancelled. The held amount went back to the customer.';

  @override
  String get ownOrdersTitle => 'Orders';

  @override
  String get ownOrdersSearchHint => 'Order number or courier name';

  @override
  String get ownClearSearch => 'Clear search';

  @override
  String get ownOrdersKind => 'Order status';

  @override
  String ownTabOngoing(int count) {
    return 'Ongoing · $count';
  }

  @override
  String get ownTabDone => 'Done';

  @override
  String get ownTabCancelled => 'Cancelled';

  @override
  String get ownOrdersLoadError => 'Couldn\'t load your orders.';

  @override
  String get ownRefreshFailed =>
      'Couldn\'t refresh. You\'re seeing the last list we loaded.';

  @override
  String get ownOrdersNoMatch => 'No order matches your search';

  @override
  String get ownNoOngoing => 'No ongoing orders';

  @override
  String get ownNoDone => 'No finished orders yet';

  @override
  String get ownNoCancelled => 'No cancelled orders';

  @override
  String get ownOrdersEmptyBody =>
      'Orders customers book with you show up here.';

  @override
  String ownProposalLine(String proposed, String price) {
    return 'Price offer: $proposed instead of $price';
  }

  @override
  String ownProposalOnly(String proposed) {
    return 'Price offer: $proposed';
  }

  @override
  String ownOfferedTo(String name) {
    return 'Offered to $name';
  }

  @override
  String get ownReconTitle => 'Payment review';

  @override
  String get ownReconIntro =>
      'The money for these orders is held because something didn\'t add up. Decide who gets it.';

  @override
  String get ownReconLoadError => 'Couldn\'t load the orders to review.';

  @override
  String get ownReconEmpty => 'Nothing to review';

  @override
  String get ownReconCodTitle => 'With cash payment only';

  @override
  String get ownReconCodBody =>
      'This screen will mostly stay empty until electronic payment starts.';

  @override
  String get ownReconHeld => 'Amount held';

  @override
  String get ownReconPay => 'Pay the courier';

  @override
  String get ownReconRefund => 'Refund the customer';

  @override
  String get ownReconPayTitle => 'Pay the courier?';

  @override
  String get ownReconRefundTitle => 'Refund the customer?';

  @override
  String ownReconPayBody(String amount, String ref, String name) {
    return '$amount for order $ref goes to $name. This can\'t be undone.';
  }

  @override
  String ownReconRefundBody(String amount, String ref) {
    return '$amount for order $ref goes back to the customer. This can\'t be undone.';
  }

  @override
  String get ownReconTheCourier => 'the courier';

  @override
  String get ownReconPaid => 'Paid to the courier.';

  @override
  String get ownReconRefunded => 'Refunded to the customer.';

  @override
  String get ownReconFailed => 'Couldn\'t settle this order. Try again.';

  @override
  String get ownReasonShortDistance => 'Distance shorter than expected';

  @override
  String get ownReasonSpeed => 'Speed didn\'t add up';

  @override
  String get ownReasonUnrecorded => 'Held amount not recorded';

  @override
  String get ownReasonOther => 'Needs a review';

  @override
  String get ownTeamTitle => 'Team';

  @override
  String get ownOnTheMap => 'On the map';

  @override
  String get ownTeamKind => 'Courier status';

  @override
  String ownTeamAll(int count) {
    return 'All · $count';
  }

  @override
  String get ownTeamActive => 'Active';

  @override
  String get ownTeamFrozen => 'Frozen';

  @override
  String get ownTeamLoadError => 'Couldn\'t load your team.';

  @override
  String get ownTeamEmpty => 'No couriers yet';

  @override
  String get ownTeamEmptyBody =>
      'Add your couriers so they can sign in and take orders.';

  @override
  String get ownTeamNoneHere => 'No couriers here';

  @override
  String get ownAddCourier => 'Add courier';

  @override
  String get ownStateOnJob => 'On a job';

  @override
  String get ownStateFree => 'Free';

  @override
  String get ownStateFrozen => 'Frozen';

  @override
  String ownOnJobWith(String ref) {
    return 'On a job · $ref';
  }

  @override
  String get ownNoOrderNow => 'No order right now';

  @override
  String get ownFrozenSubtitle => 'Can\'t sign in or get orders';

  @override
  String get ownEmployeeMissing => 'This courier isn\'t on your team anymore.';

  @override
  String get ownEmpOrders => 'Orders';

  @override
  String get ownEmpDelivered => 'Delivered';

  @override
  String get ownEmpCountsNote => 'Counted from your latest orders in the app.';

  @override
  String get ownEmpIdCheck => 'ID check';

  @override
  String get ownKyeApproved => 'Approved';

  @override
  String get ownKyePending => 'Under review';

  @override
  String get ownKyeRejected => 'Rejected';

  @override
  String get ownKyeMissing => 'Documents missing';

  @override
  String get ownEmpCurrentOrder => 'Current order';

  @override
  String get ownEmpNone => 'None';

  @override
  String get ownEmpAllOrders => 'All their orders';

  @override
  String get ownEmpOnMap => 'Where they are on the map';

  @override
  String get ownFreeze => 'Freeze account';

  @override
  String get ownUnfreeze => 'Unfreeze account';

  @override
  String get ownFreezeHint =>
      'They\'re signed out at once and get no new orders. We\'ll ask for your password to confirm.';

  @override
  String get ownUnfreezeHint =>
      'They can sign in and get orders again. We\'ll ask for your password to confirm.';

  @override
  String ownFreezeTitle(String name) {
    return 'Freeze $name\'s account?';
  }

  @override
  String ownUnfreezeTitle(String name) {
    return 'Unfreeze $name\'s account?';
  }

  @override
  String get ownFreezeBody =>
      'They\'re signed out at once and get no new orders. Type your password to confirm.';

  @override
  String get ownUnfreezeBody =>
      'They can sign in and get orders again. Type your password to confirm.';

  @override
  String get ownYourPassword => 'Your password';

  @override
  String get ownPasswordRequired => 'Type your password.';

  @override
  String get ownPasswordWrong => 'That password isn\'t right.';

  @override
  String get ownToggleKybNeeded =>
      'Your business documents must be approved first.';

  @override
  String get ownTogglePaidPlan => 'Managing couriers needs a paid plan.';

  @override
  String ownFrozenDone(String name) {
    return '$name\'s account is frozen.';
  }

  @override
  String ownUnfrozenDone(String name) {
    return '$name\'s account is active again.';
  }

  @override
  String get ownAddTitle => 'Add a courier';

  @override
  String get ownAddBody => 'They sign in with this email and password.';

  @override
  String get ownAddUsername => 'Name';

  @override
  String get ownAddEmail => 'Email';

  @override
  String get ownAddPassword => 'Password';

  @override
  String get ownAddPasswordHelp => 'At least 8 characters.';

  @override
  String get ownAddSubmit => 'Add courier';

  @override
  String ownAdded(String name) {
    return '$name was added. They can sign in now.';
  }

  @override
  String get ownTodayTitle => 'Today';

  @override
  String get ownNotifications => 'Notifications';

  @override
  String get ownTodayLoadError => 'Couldn\'t load today\'s orders.';

  @override
  String get ownTileOngoing => 'Ongoing now';

  @override
  String get ownTileDelivered => 'Delivered today';

  @override
  String get ownTileCash => 'Cash recorded today';

  @override
  String get ownTodayNote =>
      'Delivered and cash count the orders placed today.';

  @override
  String ownTodayNoteTruncated(int limit) {
    return 'Counted from your latest $limit orders, all from today. There may be more.';
  }

  @override
  String get ownNeedsYou => 'Needs you';

  @override
  String get ownNeedsNothing => 'Nothing needs you right now.';

  @override
  String ownNeedsRequestTitle(String name) {
    return '$name wants to cancel an order';
  }

  @override
  String ownNeedsReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get ownNeedsRespond => 'Respond';

  @override
  String ownNeedsReviewsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count orders need a payment review',
      one: '1 order needs a payment review',
    );
    return '$_temp0';
  }

  @override
  String get ownNeedsReviewsBody => 'The distance or time didn\'t add up';

  @override
  String get ownNeedsReview => 'Review';

  @override
  String get ownTeamNow => 'Team now';

  @override
  String get ownSeeAll => 'All';

  @override
  String get ownTeamNowEmpty => 'No couriers yet. Add them from the Team tab.';

  @override
  String get ownRatingTitle => 'Your rating';

  @override
  String get ownRatingNone => 'No ratings yet';

  @override
  String ownRatingValue(String average, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ratings',
      one: '1 rating',
    );
    return '$average · $_temp0';
  }

  @override
  String get ownYourBusiness => 'Your business';

  @override
  String get ownLinkAllOrders => 'All orders';

  @override
  String get ownLinkServiceSetup => 'Service setup';

  @override
  String get ownLinkWallet => 'Wallet';

  @override
  String get ownLinkSubscription => 'Subscription';

  @override
  String get ownLinkHistory => 'Activity and history';

  @override
  String get ownKybMissingTitle => 'Verify your business';

  @override
  String get ownKybMissingBody =>
      'Upload your business documents to start taking orders.';

  @override
  String get ownKybUpload => 'Upload documents';

  @override
  String get ownKybPendingTitle => 'Your documents are under review';

  @override
  String get ownKybPendingBody => 'We\'ll let you know when they\'re approved.';

  @override
  String get ownKybView => 'View documents';

  @override
  String get ownKybRejectedTitle => 'Your documents were rejected';

  @override
  String get ownKybRejectedBody => 'Upload them again to start taking orders.';

  @override
  String get ownKybUploadAgain => 'Upload again';

  @override
  String get ownNavToday => 'Today';

  @override
  String get ownNavOrders => 'Orders';

  @override
  String get ownNavTeam => 'Team';

  @override
  String get ownNavAccount => 'Account';

  @override
  String get ownSvcTitle => 'Service setup';

  @override
  String get ownSvcSectionBusiness => 'Service';

  @override
  String get ownSvcPhotoNote =>
      'Customers see this photo on your card. JPEG or PNG, up to 5 MB.';

  @override
  String get ownSvcName => 'Service name as customers see it';

  @override
  String get ownSvcNameRequired => 'Enter the service name';

  @override
  String get ownSvcKind => 'Type';

  @override
  String get ownSvcKindDelivery => 'Delivery';

  @override
  String get ownSvcKindTransport => 'Rides';

  @override
  String get ownSvcKindShipping => 'Shipping';

  @override
  String get ownSvcSectionPlace => 'Place and coverage';

  @override
  String get ownSvcPlace => 'Business location on the map';

  @override
  String get ownSvcPlaceMissing => 'Required';

  @override
  String get ownSvcPlaceSet => 'Set on the map';

  @override
  String get ownSvcPickerTitle => 'Business location';

  @override
  String get ownSvcAddress => 'Written address';

  @override
  String get ownSvcAddressShort =>
      'Write at least 3 letters, or leave it empty';

  @override
  String get ownSvcRadius => 'How far do you serve?';

  @override
  String get ownSvcKm => 'km';

  @override
  String get ownSvcRadiusInvalid => 'Enter a distance above 0';

  @override
  String get ownSvcSectionHours => 'Working hours';

  @override
  String get ownSvcHoursNone =>
      'No hours set: customers see you as open all the time.';

  @override
  String get ownSvcHoursSet => 'Set working hours';

  @override
  String get ownSvcHoursSame => 'Same every day';

  @override
  String get ownSvcHoursPerDay => 'Each day';

  @override
  String get ownSvcOpens => 'Opens';

  @override
  String get ownSvcCloses => 'Closes';

  @override
  String get ownSvcDayOff => 'Day off';

  @override
  String get ownSvcHoursRemove => 'Remove hours';

  @override
  String get ownSvcHoursSameTime =>
      'Opening and closing can\'t be the same time';

  @override
  String get ownSvcHoursMissing => 'Pick both times';

  @override
  String get ownSvcSectionPricing => 'Pricing';

  @override
  String get ownSvcBaseFee => 'Opening fee';

  @override
  String get ownSvcPerKm => 'Per km';

  @override
  String get ownSvcPriceInvalid => 'Enter 0 or more';

  @override
  String ownSvcExample(int km, String price) {
    return 'Example: a $km km trip shows the customer $price.';
  }

  @override
  String get ownSvcExampleEmpty =>
      'Enter both prices to see what a customer pays.';

  @override
  String get ownSvcSave => 'Save';

  @override
  String get ownSvcSaved => 'Service saved';

  @override
  String get ownSvcFixErrors => 'Check the fields marked in red';

  @override
  String get ownSvcLoadError => 'We couldn\'t load your service';

  @override
  String get ownSvcErrKyb =>
      'Your business papers need to be approved before you can save the service.';

  @override
  String get ownSvcErrPlan => 'Saving the service needs an active plan.';

  @override
  String get ownSvcErrUnavailable =>
      'This is unavailable right now. Try again in a bit.';

  @override
  String get ownSvcCurrency => 'EGP';

  @override
  String get ownFleetMapLabel => 'Map of your couriers';

  @override
  String get ownFleetFilterLabel => 'Show';

  @override
  String get ownFleetAll => 'All';

  @override
  String get ownFleetFree => 'Free';

  @override
  String get ownFleetDenied => 'You don\'t have access to this team map.';

  @override
  String get ownFleetLoadError => 'Your couriers\' locations didn\'t load.';

  @override
  String get ownFleetReconnecting => 'Reconnecting to live locations…';

  @override
  String get ownFleetNobody => 'No courier is sharing a location right now.';

  @override
  String get ownFleetRefresh => 'Refresh';

  @override
  String ownFleetSummary(int total, int onJob) {
    return 'On the map: $total · on a job: $onJob';
  }

  @override
  String get ownFleetSummaryNone =>
      'Couriers show up here while they share their location.';

  @override
  String get ownFleetTapHint => 'Tap a courier to see their order.';

  @override
  String ownFleetLastUpdate(String ago) {
    return 'Last update $ago';
  }

  @override
  String get ownFleetClose => 'Close';

  @override
  String ownFleetOrderRef(String ref) {
    return 'Order $ref';
  }

  @override
  String ownFleetOrderTo(String ref, String place) {
    return 'Order $ref · to $place';
  }

  @override
  String get ownFleetCourierPage => 'Courier page';

  @override
  String get ownLogTitle => 'Activity log';

  @override
  String get ownLogTabActivity => 'Activity';

  @override
  String get ownLogTabMoney => 'Money';

  @override
  String get ownLogPeriodLabel => 'Period';

  @override
  String get ownLogPeriodAll => 'All';

  @override
  String get ownLogPeriodToday => 'Today';

  @override
  String get ownLogPeriodWeek => '7 days';

  @override
  String get ownLogActivityEmpty => 'No activity yet';

  @override
  String get ownLogActivityEmptyBody =>
      'Courier actions and account changes show up here.';

  @override
  String get ownLogMoneyEmpty => 'No money movements yet';

  @override
  String get ownLogMoneyEmptyBody =>
      'Orders are paid in cash for now, so this stays empty until online payments start.';

  @override
  String get ownLogNoneInPeriod => 'Nothing in this period';

  @override
  String get ownLogShowAll => 'Show all';

  @override
  String get ownLogActivityError => 'We couldn\'t load the activity';

  @override
  String get ownLogMoneyError => 'We couldn\'t load the money movements';

  @override
  String get ownLogStale =>
      'Couldn\'t refresh. This is the last list we loaded.';

  @override
  String get ownLogYou => 'You';

  @override
  String ownLogBalanceAfter(String amount) {
    return 'balance after $amount';
  }

  @override
  String ownLogMoneyIn(String amount) {
    return 'Money in, $amount';
  }

  @override
  String ownLogMoneyOut(String amount) {
    return 'Money out, $amount';
  }

  @override
  String get courNavTask => 'Task';

  @override
  String get courNavJobs => 'My jobs';

  @override
  String get courNavAccount => 'Account';

  @override
  String get courKyeMissing =>
      'Upload your documents so your account can be verified.';

  @override
  String get courKyePending => 'Your documents are waiting for review.';

  @override
  String courKyeRejected(String reason) {
    return 'Your documents were not accepted: $reason';
  }

  @override
  String get courKyeRejectedNoReason =>
      'Your documents were not accepted. Upload them again.';

  @override
  String get courKyeUpload => 'Upload documents';

  @override
  String get courKyeView => 'View documents';

  @override
  String get courKyeReupload => 'Upload again';

  @override
  String get courBlockedTitle => 'You can\'t take orders right now';

  @override
  String get courBlockedSuspended =>
      'Your account was suspended, so no orders will reach you.';

  @override
  String get courBlockedPaused =>
      'Your account is paused, so no orders will reach you. Your company or Quick Delivery can turn it back on.';

  @override
  String get courBlockedReason => 'Reason';

  @override
  String get courBlockedWhat =>
      'Talk to your company owner, or contact support if you think this is a mistake.';

  @override
  String get courBlockedCheck => 'Check again';

  @override
  String get courLoadError => 'Couldn\'t load your jobs.';

  @override
  String get courRefresh => 'Refresh';

  @override
  String get courIdleOnlineTitle => 'No task right now';

  @override
  String get courIdleOnlineBody =>
      'You\'re available. New orders show up here.';

  @override
  String get courIdleOfflineTitle => 'You\'re not available';

  @override
  String get courIdleOfflineBody => 'Turn on availability to get new orders.';

  @override
  String get courGoOnline => 'Make me available';

  @override
  String courKm(String km) {
    return '$km km';
  }

  @override
  String get courPriceNotSet => 'Not set yet';

  @override
  String get courPackageSmall => 'Small';

  @override
  String get courPackageMedium => 'Medium';

  @override
  String get courPackageLarge => 'Large';

  @override
  String courPackage(String details) {
    return 'Package: $details';
  }

  @override
  String get courMapLabel => 'Map of the route and your location';

  @override
  String get courNoDestination => 'Drop-off not set yet';

  @override
  String get courChatTitle => 'Customer';

  @override
  String get courChatEmpty =>
      'Messages with the customer about this order show here.';

  @override
  String get courOfferSubtitle => 'A new task for you';

  @override
  String get courOfferTitle => 'New order';

  @override
  String get courOfferExpired => 'This offer has ended.';

  @override
  String courPickupFromYou(String distance) {
    return 'Pickup · $distance from you';
  }

  @override
  String courDropoffTrip(String distance) {
    return 'Drop-off · trip $distance';
  }

  @override
  String get courCashToCollect => 'You\'ll collect cash';

  @override
  String get courOrderPrice => 'Order price';

  @override
  String get courAskCustomer => 'Ask the customer';

  @override
  String get courDecline => 'Decline';

  @override
  String get courAccept => 'Accept the task';

  @override
  String get courOfferAccepted => 'Task accepted';

  @override
  String get courOfferDeclined => 'Offer declined';

  @override
  String get courOfferGone => 'This offer is no longer available.';

  @override
  String get courPickedUpDone => 'Pickup recorded. Head to the drop-off.';

  @override
  String get courPickupAlready => 'This order is already marked as picked up.';

  @override
  String get courNotYours => 'This order is no longer assigned to you.';

  @override
  String get courDelivered => 'Order delivered. Well done!';

  @override
  String get courCancelSent => 'Request sent to your company owner.';

  @override
  String get courOtherJobsTitle => 'Your running tasks';

  @override
  String courOtherJobs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You have $count more running tasks.',
      one: 'You have 1 more running task.',
    );
    return '$_temp0';
  }

  @override
  String get courOtherJobsShow => 'Show';

  @override
  String get courPickedUp => 'I picked up the order';

  @override
  String courDeliveredCollected(String amount) {
    return 'Delivered, collected $amount';
  }

  @override
  String get courDeliveredCash => 'Delivered and collected the cash';

  @override
  String get courDeliveredPlain => 'Delivered';

  @override
  String get courOpenInMaps => 'Open in maps';

  @override
  String get courCurrentTitle => 'Current task';

  @override
  String get courCancelPending =>
      'You asked to cancel. Waiting for your company owner.';

  @override
  String get courCancelRejected =>
      'Your company owner said no to cancelling. The task is still yours.';

  @override
  String get courRequestCancel => 'Can\'t finish? Request cancellation';

  @override
  String courEtaPickup(int minutes) {
    return 'Estimate: about $minutes min to the pickup';
  }

  @override
  String courEtaDropoff(int minutes) {
    return 'Estimate: about $minutes min to the drop-off';
  }

  @override
  String get courPhasePrice => 'Agreeing on the price';

  @override
  String get courPhaseToPickup => 'Going to pickup';

  @override
  String get courPhasePickedUp => 'Picked up';

  @override
  String get courPhaseActive => 'In progress';

  @override
  String get courSharingLive => 'Customer sees your location';

  @override
  String get courSharingOff => 'Location is off';

  @override
  String get courSharingFailing => 'Location isn\'t updating';

  @override
  String get courSharingStarting => 'Turning on location…';

  @override
  String get courPermissionTitle => 'Turn on location';

  @override
  String get courPermissionBody =>
      'The customer and your company can\'t see where you are until you allow location.';

  @override
  String get courOpenSettings => 'Open settings';

  @override
  String courWillPayCash(String amount) {
    return 'Will pay $amount cash';
  }

  @override
  String courOrderPriceValue(String amount) {
    return 'Order price $amount';
  }

  @override
  String get courChatWithCustomer => 'Chat with the customer';

  @override
  String courRecipientNotes(String notes) {
    return 'Notes: $notes';
  }

  @override
  String get courAmountInvalid => 'Enter the amount you collected, like 42.';

  @override
  String get courCompleteTitle => 'Did you deliver the order?';

  @override
  String courCompleteCod(String amount) {
    return 'Confirm you handed it over and collected $amount cash.';
  }

  @override
  String get courCompleteCodNoPrice =>
      'Confirm you handed it over and collected the cash.';

  @override
  String get courCompleteNonCod => 'Confirm you handed the order over.';

  @override
  String get courCompleteDifferent => 'I collected a different amount';

  @override
  String get courCompleteAmountLabel => 'Amount collected';

  @override
  String get courCompleteAmountHelp => 'In Egyptian pounds';

  @override
  String courCompleteConfirmAmount(String amount) {
    return 'Yes, I collected $amount';
  }

  @override
  String get courCompleteConfirmCash => 'Yes, I collected the cash';

  @override
  String get courCompleteConfirm => 'Yes, I delivered it';

  @override
  String get courNotYet => 'Not yet';

  @override
  String get courCompleteNote => 'Your company sees the amount you confirm.';

  @override
  String get courCancelTitle => 'Request cancellation';

  @override
  String get courCancelBody =>
      'Your company owner decides. Until they answer, the task stays yours.';

  @override
  String get courCancelSend => 'Send request';

  @override
  String get courCancelKeep => 'Keep the task';

  @override
  String courPriceAcceptTitle(String price) {
    return 'Accept $price?';
  }

  @override
  String get courPriceAcceptBody => 'The trip starts right away at this price.';

  @override
  String get courProposalSent => 'Price sent. Waiting for the customer.';

  @override
  String get courPriceAccepted => 'Price accepted. The trip has started.';

  @override
  String get courPriceDeclined => 'Price declined.';

  @override
  String courPriceCustomerTitle(String price) {
    return 'The customer offers $price';
  }

  @override
  String courPriceWas(String price) {
    return 'The suggested price was $price.';
  }

  @override
  String courPriceMineTitle(String price) {
    return 'You offered $price';
  }

  @override
  String get courPriceMineBody => 'Waiting for the customer\'s answer.';

  @override
  String get courPriceProposeTitle => 'Propose your price';

  @override
  String courPriceProposeBody(String price) {
    return 'The suggested price is $price. You can send one offer; the customer accepts or declines it.';
  }

  @override
  String get courPriceWaitingTitle => 'Waiting for the price to be agreed';

  @override
  String get courPriceProposeLabel => 'Your price';

  @override
  String courPriceBounds(String min, String max) {
    return 'Between $min and $max';
  }

  @override
  String get courPriceExpired => 'The price offer ran out of time.';

  @override
  String get courAvailableOn => 'Available for tasks';

  @override
  String get courAvailableOff => 'Not available';

  @override
  String get courAvailableOnBody =>
      'We send your location to your company every minute.';

  @override
  String get courAvailableOffBody => 'You won\'t get new orders.';

  @override
  String get courAvailableLocked => 'Locked while a task is in progress.';

  @override
  String get courTodayDone => 'Tasks finished today';

  @override
  String get courTodayCash => 'Cash today, at order price';

  @override
  String get courTodayCashNote =>
      'Cash is the price of today\'s delivered cash orders; your company sees the amount you confirmed.';

  @override
  String get courTodayByCreation =>
      'Older orders have no finish time, so they count by the day they were created.';

  @override
  String get courFinishedHeader => 'Finished';

  @override
  String courToPlace(String place) {
    return 'To $place';
  }

  @override
  String get courPayCash => 'Cash';

  @override
  String get courNoFinishedTitle => 'No finished tasks yet';

  @override
  String get courNoFinishedBody =>
      'Tasks you deliver, and ones that get cancelled, show up here.';

  @override
  String get courReasonPriceDisagreement => 'No agreement on the price';

  @override
  String get acctVerification => 'Verification';

  @override
  String get acctKyeApproved => 'Verified';

  @override
  String get acctKyePending => 'Under review';

  @override
  String get acctKyeRejected => 'Not accepted';

  @override
  String get acctKyeMissing => 'Not uploaded';

  @override
  String get vrfTitleOwner => 'Business verification';

  @override
  String get vrfTitleCourier => 'ID verification';

  @override
  String get vrfLoadError => 'Couldn\'t refresh your verification status.';

  @override
  String get vrfStateMissingTitle => 'Upload your documents';

  @override
  String vrfStateMissingOwner(int total) {
    return 'Upload all $total documents so we can verify your business and you can start taking orders.';
  }

  @override
  String vrfStateMissingCourier(int total) {
    return 'Upload all $total documents so we can confirm who you are.';
  }

  @override
  String vrfStateIncompleteTitle(int done, int total) {
    return '$done of $total documents uploaded';
  }

  @override
  String get vrfStateIncompleteBody =>
      'Review starts once every document is uploaded.';

  @override
  String get vrfStatePendingTitle => 'Your documents are under review';

  @override
  String get vrfStatePendingBody =>
      'We\'ll let you know when the review is done. You can still replace a document.';

  @override
  String get vrfStateApprovedTitle => 'Verified';

  @override
  String get vrfStateApprovedBody =>
      'Your documents were accepted. They\'re locked now.';

  @override
  String get vrfStateRejectedTitle => 'Your documents weren\'t accepted';

  @override
  String vrfRejectedReason(String reason) {
    return 'Reviewer\'s note: $reason';
  }

  @override
  String get vrfRejectedNoReason =>
      'No reason was given. Contact support if you\'re not sure what to change.';

  @override
  String get vrfRejectedHint =>
      'Replace the documents that need fixing. They go back to review as soon as you upload one.';

  @override
  String get vrfDocsHeader => 'Documents';

  @override
  String vrfDocsCount(int done, int total) {
    return '$done of $total uploaded';
  }

  @override
  String get vrfSlotIdFront => 'ID card, front';

  @override
  String get vrfSlotIdFrontHint =>
      'A clear photo of the front of your national ID or passport.';

  @override
  String get vrfSlotIdBack => 'ID card, back';

  @override
  String get vrfSlotIdBackHint =>
      'A clear photo of the back of your national ID.';

  @override
  String get vrfSlotSelfie => 'Selfie with your ID';

  @override
  String get vrfSlotSelfieHint => 'Hold your ID card next to your face.';

  @override
  String get vrfSlotBusiness => 'Commercial register';

  @override
  String get vrfSlotBusinessHint =>
      'Commercial register or tax card. A photo or a PDF.';

  @override
  String get vrfSlotNeeded => 'Needed';

  @override
  String get vrfSlotUploaded => 'Uploaded';

  @override
  String get vrfSlotInReview => 'Under review';

  @override
  String get vrfSlotAccepted => 'Accepted';

  @override
  String get vrfSlotNotAccepted => 'Not accepted';

  @override
  String get vrfSlotUploading => 'Uploading';

  @override
  String get vrfOnFilePhoto => 'Photo on file';

  @override
  String get vrfOnFilePdf => 'PDF on file';

  @override
  String get vrfUpload => 'Upload';

  @override
  String get vrfReplace => 'Replace';

  @override
  String get vrfChooseAnother => 'Choose another file';

  @override
  String vrfUploadingFile(String name) {
    return 'Uploading $name…';
  }

  @override
  String vrfUploadedNotice(String slot) {
    return '$slot uploaded.';
  }

  @override
  String get vrfSentForReview =>
      'All documents uploaded. They\'re under review now.';

  @override
  String vrfErrTooLarge(String size) {
    return 'This file is $size MB. The limit is 10 MB.';
  }

  @override
  String get vrfErrEmpty => 'This file is empty. Choose another one.';

  @override
  String get vrfErrFormatPhoto => 'Use a JPG or PNG photo.';

  @override
  String get vrfErrFormatDoc => 'Use a JPG or PNG photo, or a PDF.';

  @override
  String get vrfErrNotAllowed => 'This account can\'t upload these documents.';

  @override
  String get vrfErrPicker => 'Couldn\'t open that. Try another option.';

  @override
  String get vrfErrUpload =>
      'Couldn\'t upload the file. Check your connection and try again.';

  @override
  String vrfSourceTitle(String slot) {
    return 'Add: $slot';
  }

  @override
  String get vrfSourceCamera => 'Take a photo';

  @override
  String get vrfSourceGallery => 'Choose from photos';

  @override
  String get vrfSourceFile => 'Choose a file';

  @override
  String get vrfSourceFileHintPdf => 'JPG, PNG or PDF, up to 10 MB';

  @override
  String get vrfSourceFileHintPhoto => 'JPG or PNG, up to 10 MB';

  @override
  String get vrfRulesOwner =>
      'Photos must be JPG or PNG, up to 10 MB each. The commercial register can also be a PDF.';

  @override
  String get vrfRulesCourier => 'Photos must be JPG or PNG, up to 10 MB each.';

  @override
  String get vrfLocked => 'Accepted documents can\'t be changed.';

  @override
  String get acctSectionBusiness => 'Your business';

  @override
  String get acctServiceSetup => 'Service setup';

  @override
  String get acctPlan => 'Plan';

  @override
  String get acctActivityLog => 'Activity log';

  @override
  String get ownWalletTitle => 'Wallet';

  @override
  String get ownWalletAvailable => 'Available to withdraw';

  @override
  String get ownWalletTotal => 'Total balance';

  @override
  String get ownWalletHeld => 'Held for orders';

  @override
  String get ownWalletAddMoney => 'Add money';

  @override
  String get ownWalletWithdraw => 'Withdraw';

  @override
  String get ownWalletLoadError => 'Couldn\'t load your wallet.';

  @override
  String get ownWalletStale =>
      'Couldn\'t refresh. These are the last balances we loaded.';

  @override
  String get ownWalletPayouts => 'Withdrawals';

  @override
  String get ownWalletPayoutsEmpty => 'No withdrawals yet.';

  @override
  String get ownWalletPayoutsError => 'Couldn\'t load your withdrawals.';

  @override
  String ownWalletPayoutReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get ownPayoutRequested => 'Requested';

  @override
  String get ownPayoutApproved => 'Approved';

  @override
  String get ownPayoutPaid => 'Paid';

  @override
  String get ownPayoutRejected => 'Rejected';

  @override
  String get ownPayoutUnknown => 'Unknown status';

  @override
  String get ownWalletRecent => 'Recent money movements';

  @override
  String get ownWalletSeeAll => 'See all';

  @override
  String get ownWalletRecentEmpty => 'No money movements yet.';

  @override
  String get ownPlanTitle => 'Plan';

  @override
  String get ownPlanYours => 'Your plan';

  @override
  String get ownPlanFree => 'Free';

  @override
  String get ownPlanPaid => 'Paid';

  @override
  String get ownPlanPending => 'Under review';

  @override
  String get ownPlanCancelled => 'Cancelled';

  @override
  String get ownPlanUnknown => 'Unknown';

  @override
  String get ownPlanOpen => 'Customers can find and book your business.';

  @override
  String ownPlanOpenUntil(String date) {
    return 'Customers can find and book your business. Active until $date.';
  }

  @override
  String ownPlanExpired(String date) {
    return 'Ended on $date. Customers can\'t find or book your business until it\'s renewed.';
  }

  @override
  String get ownPlanClosed =>
      'Customers can\'t find or book your business on this plan.';

  @override
  String get ownPlanPendingNote =>
      'We got your upgrade request. Quick Delivery will contact you to turn on the paid plan.';

  @override
  String get ownPlanIncludes => 'What the paid plan includes';

  @override
  String get ownPlanFeatureListed =>
      'Your business shows up for customers and takes bookings';

  @override
  String get ownPlanFeatureService => 'Set up and change your service';

  @override
  String get ownPlanFeatureTracking => 'Live courier location on your orders';

  @override
  String get ownPlanFeatureNoCommission => 'No commission on your orders';

  @override
  String get ownPlanChangeTitle => 'Changing your plan';

  @override
  String get ownPlanChangeBody =>
      'Ask for the paid plan here. Quick Delivery reviews each request and contacts you.';

  @override
  String get ownPlanContactSupport => 'Contact support';

  @override
  String get ownPlanLoadError => 'Couldn\'t load your plan.';

  @override
  String get ownPlanRequestUpgrade => 'Request upgrade';

  @override
  String get ownPlanUpgradeTitle => 'Request the paid plan?';

  @override
  String get ownPlanUpgradeBody =>
      'Quick Delivery will review your request and contact you.';

  @override
  String get ownPlanUpgradeSend => 'Send request';

  @override
  String get ownPlanUpgradeSent => 'Request sent. Your plan is under review.';

  @override
  String get ownPlanDowngrade => 'Switch to free';

  @override
  String get ownPlanDowngradeTitle => 'Switch to the free plan?';

  @override
  String get ownPlanDowngradeBodyPaid =>
      'Customers won\'t be able to find or book your business until you\'re on the paid plan again.';

  @override
  String get ownPlanDowngradeBodyPending =>
      'This cancels your upgrade request.';

  @override
  String get ownPlanDowngraded => 'You\'re on the free plan now.';

  @override
  String lnchMapsCopied(String coords) {
    return 'Couldn\'t open a maps app. Location copied: $coords.';
  }

  @override
  String lnchPhoneCopied(String phone) {
    return 'Couldn\'t open the phone app. Number copied: $phone.';
  }

  @override
  String get courCallRecipient => 'Call the recipient';

  @override
  String get bookAddressLabel => 'Address · optional';

  @override
  String get bookAddressHint => 'Street, building, area';

  @override
  String get bookRecipientTitle => 'Who receives it?';

  @override
  String get bookPassengerTitle => 'Who\'s riding?';

  @override
  String get bookRecipientMe => 'I\'m the recipient';

  @override
  String get bookPassengerMe => 'I\'m riding';

  @override
  String get bookRecipientOther => 'Someone else';

  @override
  String get bookRecipientName => 'Name · optional';

  @override
  String get bookRecipientNameHint => 'Who should the courier ask for?';

  @override
  String get bookPassengerNameHint => 'Who should the driver ask for?';

  @override
  String get bookRecipientPhone => 'Phone · optional';

  @override
  String get bookRecipientNotes => 'Notes · optional';

  @override
  String get bookRecipientNotesHint => 'e.g. call before you arrive';

  @override
  String get bookRecipientPhoneHelp =>
      'Shared with the courier only while the order is on its way.';

  @override
  String get bookPackageTitle => 'Package';

  @override
  String get bookPackageSize => 'Size';

  @override
  String get bookSizeNone => 'Not specified';

  @override
  String get bookSizeSmall => 'Small';

  @override
  String get bookSizeMedium => 'Medium';

  @override
  String get bookSizeLarge => 'Large';

  @override
  String get bookPackageNotes => 'Package notes · optional';

  @override
  String get bookPackageNotesHint => 'e.g. fragile, handle with care';

  @override
  String get bookPackageNoPrice => 'The size doesn\'t change the price.';

  @override
  String bookErrTooLong(int max) {
    return 'Use at most $max characters.';
  }

  @override
  String bookErrAddressTooLong(int max) {
    return 'An address is too long. Use at most $max characters.';
  }

  @override
  String get bookErrNoteTooLong =>
      'A landmark note is too long. Shorten it and try again.';

  @override
  String get bookErrPhone =>
      'Enter an Egyptian mobile number like 01012345678, or an international number with its country code.';

  @override
  String get bookErrSize => 'Choose small, medium or large.';

  @override
  String get bookFixFields => 'Check the highlighted fields.';

  @override
  String get tlPickedUp => 'The courier picked up the order';

  @override
  String get tlPickedUpRide => 'The driver picked you up';

  @override
  String get tlPickedUpRideOwner => 'The driver picked up the passenger';

  @override
  String get tlArrived => 'Arrived';

  @override
  String get tlCancelled => 'Cancelled';

  @override
  String get tlUnavailable => 'No courier was free';

  @override
  String get tlOwnRequested => 'Customer ordered';

  @override
  String tlOwnAccepted(String name) {
    return '$name accepted';
  }

  @override
  String get phaseToPickup => 'The courier is on the way to pick up your order';

  @override
  String get phaseToPickupRide => 'The driver is on the way to pick you up';

  @override
  String get phasePickedUp => 'On the way to you';

  @override
  String get phasePickedUpRide => 'On the way to your destination';

  @override
  String get phaseChipToPickup => 'Going to pickup';

  @override
  String get phaseChipToPickupRide => 'Going to passenger';

  @override
  String get phaseChipPickedUp => 'Picked up';

  @override
  String get phaseChipPickedUpRide => 'Passenger on board';

  @override
  String etaAround(String time) {
    return 'Arrives around $time';
  }

  @override
  String etaPickupAround(String time) {
    return 'At the pickup around $time';
  }

  @override
  String etaPickupAroundRide(String time) {
    return 'Picks you up around $time';
  }

  @override
  String get etaSoon => 'Should arrive any minute';

  @override
  String get etaPickupSoon => 'Should reach the pickup any minute';

  @override
  String get ordRecipient => 'Recipient';

  @override
  String get ordPassenger => 'Passenger';

  @override
  String get ordPackage => 'Package';

  @override
  String get ordCallCourier => 'Call the courier';

  @override
  String get ownTodayNoteDelivered =>
      'Delivered and cash count the orders delivered today.';

  @override
  String get ownTodayNoteMixed =>
      'Delivered and cash count the orders delivered today. Older orders without a delivery time count on the day they were placed.';

  @override
  String get ownRowDelivered => 'Delivered';

  @override
  String get ownRowEta => 'Estimate';

  @override
  String get ownCallRecipient => 'Call the recipient';

  @override
  String get ownCallCourier => 'Call the courier';

  @override
  String get ownTimelineTitle => 'Order steps';

  @override
  String get ntfCancelRequestedTitle => 'A courier asked to cancel a job';

  @override
  String get ntfCancelExpiredTitle => 'A cancellation request ran out';

  @override
  String get ntfCancelResolvedTitle => 'Your cancellation request was answered';

  @override
  String get ntfJobOfferTitle => 'New job offer';

  @override
  String get ntfJobOfferBody =>
      'Answer it from the Task tab before the time runs out.';

  @override
  String get ntfJobAlertTitle => 'New job';

  @override
  String get ntfKycApprovedTitle => 'Your verification was approved';

  @override
  String get ntfKycRejectedTitle => 'Your verification wasn\'t accepted';

  @override
  String get vrfRejectedOpen => 'Fix my documents';

  @override
  String get updDownload => 'Download the update';

  @override
  String get roleUnsupportedTitle => 'This account can\'t use the app';

  @override
  String get roleUnsupportedBody =>
      'Sign in with a customer, business or courier account. Staff accounts use the web console.';

  @override
  String get ownSvcPhotoSheetTitle => 'Service photo';

  @override
  String get ownSvcPhotoAdd => 'Add photo';

  @override
  String get ownSvcPhotoReplace => 'Change photo';

  @override
  String get ownSvcPhotoRemove => 'Remove photo';

  @override
  String get ownSvcPhotoCamera => 'Take a photo';

  @override
  String get ownSvcPhotoGallery => 'Choose from photos';

  @override
  String ownSvcPhotoUploading(int percent) {
    return 'Uploading… $percent%';
  }

  @override
  String get ownSvcPhotoPending =>
      'Photo ready. It is added to your service when you tap Save.';

  @override
  String get ownSvcPhotoErrUnavailable =>
      'Photo upload is unavailable right now. Try again later.';

  @override
  String get ownSvcPhotoErrFormat => 'Use a JPEG or PNG photo.';

  @override
  String get ownSvcPhotoErrTooLarge =>
      'This photo is over 5 MB. Choose a smaller one.';

  @override
  String get ownSvcPhotoErrRejected =>
      'This photo couldn\'t be used. Try another one.';

  @override
  String get ownSvcPhotoErrNetwork =>
      'The photo wasn\'t uploaded. Check your connection and try again.';

  @override
  String get ownSvcPhotoErrRemove =>
      'We couldn\'t remove the photo. Try again.';
}
