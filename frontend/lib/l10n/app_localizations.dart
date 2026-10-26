import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @scheduleDayMon.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get scheduleDayMon;

  /// No description provided for @scheduleDayTue.
  ///
  /// In en, this message translates to:
  /// **'Tuesday'**
  String get scheduleDayTue;

  /// No description provided for @scheduleDayWed.
  ///
  /// In en, this message translates to:
  /// **'Wednesday'**
  String get scheduleDayWed;

  /// No description provided for @scheduleDayThu.
  ///
  /// In en, this message translates to:
  /// **'Thursday'**
  String get scheduleDayThu;

  /// No description provided for @scheduleDayFri.
  ///
  /// In en, this message translates to:
  /// **'Friday'**
  String get scheduleDayFri;

  /// No description provided for @scheduleDaySat.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get scheduleDaySat;

  /// No description provided for @scheduleDaySun.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get scheduleDaySun;

  /// No description provided for @otpFooterBrand.
  ///
  /// In en, this message translates to:
  /// **'Quick Delivery'**
  String get otpFooterBrand;

  /// No description provided for @reconciliationNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get reconciliationNote;

  /// No description provided for @employeeProposalRacedError.
  ///
  /// In en, this message translates to:
  /// **'The customer already sent a price — respond to it instead.'**
  String get employeeProposalRacedError;

  /// No description provided for @enumPaymentWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get enumPaymentWallet;

  /// No description provided for @enumRoleUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get enumRoleUser;

  /// No description provided for @enumTierFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get enumTierFree;

  /// No description provided for @enumTierPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get enumTierPaid;

  /// No description provided for @enumTierPendingPayment.
  ///
  /// In en, this message translates to:
  /// **'Pending payment'**
  String get enumTierPendingPayment;

  /// No description provided for @enumPayoutVodafoneCash.
  ///
  /// In en, this message translates to:
  /// **'Vodafone Cash'**
  String get enumPayoutVodafoneCash;

  /// No description provided for @enumTxnDeposit.
  ///
  /// In en, this message translates to:
  /// **'Deposit'**
  String get enumTxnDeposit;

  /// No description provided for @enumTxnEscrowLock.
  ///
  /// In en, this message translates to:
  /// **'Escrow lock'**
  String get enumTxnEscrowLock;

  /// No description provided for @enumTxnEscrowRelease.
  ///
  /// In en, this message translates to:
  /// **'Escrow release'**
  String get enumTxnEscrowRelease;

  /// No description provided for @enumTxnPlatformFee.
  ///
  /// In en, this message translates to:
  /// **'Platform fee'**
  String get enumTxnPlatformFee;

  /// No description provided for @enumTxnPayout.
  ///
  /// In en, this message translates to:
  /// **'Payout'**
  String get enumTxnPayout;

  /// No description provided for @enumTxnPayoutRefund.
  ///
  /// In en, this message translates to:
  /// **'Payout refund'**
  String get enumTxnPayoutRefund;

  /// No description provided for @enumTxnRefund.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get enumTxnRefund;

  /// No description provided for @enumTxnFeeDeduction.
  ///
  /// In en, this message translates to:
  /// **'Fee deduction'**
  String get enumTxnFeeDeduction;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusAwaitingPrice.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Price'**
  String get statusAwaitingPrice;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusPendingDispatch.
  ///
  /// In en, this message translates to:
  /// **'Finding Courier'**
  String get statusPendingDispatch;

  /// No description provided for @statusUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get statusUnavailable;

  /// No description provided for @serviceTemporarilyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The service is temporarily unavailable — nothing was changed. Please try again shortly.'**
  String get serviceTemporarilyUnavailable;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @statusReconciliationRequired.
  ///
  /// In en, this message translates to:
  /// **'Reconciliation Required'**
  String get statusReconciliationRequired;

  /// No description provided for @statusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get statusUnknown;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @tooltipNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get tooltipNotifications;

  /// No description provided for @payoutMethodBankTransfer.
  ///
  /// In en, this message translates to:
  /// **'Bank Transfer'**
  String get payoutMethodBankTransfer;

  /// No description provided for @payoutMethodInstapay.
  ///
  /// In en, this message translates to:
  /// **'InstaPay'**
  String get payoutMethodInstapay;

  /// No description provided for @codOptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash on delivery'**
  String get codOptionTitle;

  /// No description provided for @auditActionAccountSuspended.
  ///
  /// In en, this message translates to:
  /// **'Account suspended'**
  String get auditActionAccountSuspended;

  /// No description provided for @auditActionAccountReactivated.
  ///
  /// In en, this message translates to:
  /// **'Account reactivated'**
  String get auditActionAccountReactivated;

  /// No description provided for @auditActionKycReviewed.
  ///
  /// In en, this message translates to:
  /// **'Identity review completed'**
  String get auditActionKycReviewed;

  /// No description provided for @auditActionDocumentViewed.
  ///
  /// In en, this message translates to:
  /// **'Document viewed'**
  String get auditActionDocumentViewed;

  /// No description provided for @usernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Username is required'**
  String get usernameRequired;

  /// No description provided for @usernameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Username must be at least 3 characters'**
  String get usernameTooShort;

  /// No description provided for @usernameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Username must be at most 30 characters'**
  String get usernameTooLong;

  /// No description provided for @usernameInvalidChars.
  ///
  /// In en, this message translates to:
  /// **'Username contains invalid characters'**
  String get usernameInvalidChars;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get emailRequired;

  /// No description provided for @invalidEmailFormat.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get invalidEmailFormat;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get passwordRequired;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get passwordTooShort;

  /// No description provided for @passwordTooLong.
  ///
  /// In en, this message translates to:
  /// **'Password must be at most 72 bytes'**
  String get passwordTooLong;

  /// No description provided for @passwordTooCommon.
  ///
  /// In en, this message translates to:
  /// **'This password is too common — pick a less guessable one.'**
  String get passwordTooCommon;

  /// No description provided for @passwordTooWeak.
  ///
  /// In en, this message translates to:
  /// **'This password doesn\'t meet the security requirements.'**
  String get passwordTooWeak;

  /// No description provided for @userNotAuthenticatedError.
  ///
  /// In en, this message translates to:
  /// **'User not authenticated.'**
  String get userNotAuthenticatedError;

  /// No description provided for @unknownActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Unknown Action'**
  String get unknownActionLabel;

  /// No description provided for @roleOwnerLabel.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get roleOwnerLabel;

  /// No description provided for @roleEmployeeLabel.
  ///
  /// In en, this message translates to:
  /// **'Employee'**
  String get roleEmployeeLabel;

  /// No description provided for @reconciliationUnderDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance mismatch — under 70% of booked distance'**
  String get reconciliationUnderDistance;

  /// No description provided for @reconciliationUnrecordedEscrow.
  ///
  /// In en, this message translates to:
  /// **'Unrecorded escrow balance failure'**
  String get reconciliationUnrecordedEscrow;

  /// No description provided for @reconciliationImplausibleSpeed.
  ///
  /// In en, this message translates to:
  /// **'Implausible movement speed detected'**
  String get reconciliationImplausibleSpeed;

  /// No description provided for @reconciliationRequiredDefault.
  ///
  /// In en, this message translates to:
  /// **'Escrow reconciliation required for manual review'**
  String get reconciliationRequiredDefault;

  /// No description provided for @newDispatchAlertMessage.
  ///
  /// In en, this message translates to:
  /// **'New dispatch offer received. Refreshing available jobs...'**
  String get newDispatchAlertMessage;

  /// PAY-COD-ONLY: shown when an owner taps wallet top-up or payout while the backend has digital payments off.
  ///
  /// In en, this message translates to:
  /// **'Coming soon: wallet top-up and payouts are not available yet. Bookings are paid cash on delivery.'**
  String get digitalPaymentsComingSoon;

  /// FE-DS: job status chip labels (qdStatus*), sentence case, one mapping in lib/ui/components/qd_status_chip.dart.
  ///
  /// In en, this message translates to:
  /// **'Waiting for courier'**
  String get qdStatusPending;

  /// No description provided for @qdStatusPendingDispatch.
  ///
  /// In en, this message translates to:
  /// **'Finding a courier'**
  String get qdStatusPendingDispatch;

  /// No description provided for @qdStatusUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No courier available'**
  String get qdStatusUnavailable;

  /// No description provided for @qdStatusAwaitingPrice.
  ///
  /// In en, this message translates to:
  /// **'New price offered'**
  String get qdStatusAwaitingPrice;

  /// No description provided for @qdStatusAssigned.
  ///
  /// In en, this message translates to:
  /// **'Courier assigned'**
  String get qdStatusAssigned;

  /// No description provided for @qdStatusActive.
  ///
  /// In en, this message translates to:
  /// **'On the way'**
  String get qdStatusActive;

  /// No description provided for @qdStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get qdStatusCompleted;

  /// No description provided for @qdStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get qdStatusCancelled;

  /// No description provided for @qdStatusUnderReview.
  ///
  /// In en, this message translates to:
  /// **'Under review'**
  String get qdStatusUnderReview;

  /// No description provided for @qdStatusCancellationRequested.
  ///
  /// In en, this message translates to:
  /// **'Cancellation requested'**
  String get qdStatusCancellationRequested;

  /// No description provided for @qdStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown status'**
  String get qdStatusUnknown;

  /// No description provided for @qdComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get qdComingSoon;

  /// No description provided for @qdLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get qdLoading;

  /// No description provided for @qdErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get qdErrorTitle;

  /// No description provided for @qdErrorBody.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get qdErrorBody;

  /// No description provided for @qdTimeLeft.
  ///
  /// In en, this message translates to:
  /// **'{time} left'**
  String qdTimeLeft(String time);

  /// No description provided for @qdPickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get qdPickup;

  /// No description provided for @qdDropoff.
  ///
  /// In en, this message translates to:
  /// **'Drop-off'**
  String get qdDropoff;

  /// No description provided for @qdStepProgress.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String qdStepProgress(int current, int total);

  /// No description provided for @qdTimelineDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get qdTimelineDone;

  /// No description provided for @qdTimelineCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current step'**
  String get qdTimelineCurrent;

  /// No description provided for @qdTimelineUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get qdTimelineUpcoming;

  /// FE-DS: money template; amount is already formatted by QdMoney. Never use $ or a bare number.
  ///
  /// In en, this message translates to:
  /// **'EGP {amount}'**
  String qdMoneyAmount(String amount);

  /// No description provided for @qdMainNavigation.
  ///
  /// In en, this message translates to:
  /// **'Main navigation'**
  String get qdMainNavigation;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get custNavHome;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'My orders'**
  String get custNavOrders;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get custNavAccount;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Pick up from'**
  String get custPickupFrom;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Your current location'**
  String get custCurrentLocation;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Pinned location'**
  String get custPinnedLocation;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Choose a location'**
  String get custChooseLocation;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'What are you sending today?'**
  String get custHomeTitle;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Deliver an order'**
  String get custCatDelivery;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'From place to place in the city'**
  String get custCatDeliverySub;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Ship a parcel'**
  String get custCatShipping;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Between governorates'**
  String get custCatShippingSub;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Ride'**
  String get custCatRide;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'A car that takes you where you\'re going'**
  String get custCatRideSub;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'All services'**
  String get custAllServices;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get custServicesSection;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Ongoing order'**
  String get custOngoingOrder;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'No ongoing orders right now.'**
  String get custNoOngoing;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get custOrderFallback;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'{title} · {ref}'**
  String custOrderTitleRef(String title, String ref);

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get custTrack;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'To {place}'**
  String custToPlace(String place);

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your orders.'**
  String get custJobsLoadError;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No companies available} =1{1 company available} other{{count} companies available}}'**
  String custCompaniesCount(int count);

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Near {place} · up to {km} km'**
  String custNearPlace(String place, String km);

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get custSortLabel;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Nearest'**
  String get custSortNearest;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Cheapest'**
  String get custSortCheapest;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get custFilters;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get custOpen;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get custClosed;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Opens {when}'**
  String custOpensAt(String when);

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'{km} km from you'**
  String custKmAway(String km);

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'About {amount}'**
  String custAboutAmount(String amount);

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Finding your location…'**
  String get custLocating;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t get your location, so these companies are near the default area. Pick your area to see what\'s near you.'**
  String get custLocationOffBanner;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Pick area on map'**
  String get custPickArea;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'No companies nearby'**
  String get custNoCompaniesTitle;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Try a longer distance or another area.'**
  String get custNoCompaniesBody;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Change filters'**
  String get custChangeFilters;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get custFilterDistance;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'{km} km'**
  String custRadiusKm(String km);

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Search area'**
  String get custSearchArea;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Show results'**
  String get custShowResults;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Pickup place'**
  String get custPickupPlace;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Drop-off place'**
  String get custDropoffPlace;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Move the map until the pin is exactly on the place'**
  String get custPickerHint;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'A landmark for the courier · optional'**
  String get custNoteLabel;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'e.g. the building next to the pharmacy, 3rd floor'**
  String get custNoteHint;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Confirm place'**
  String get custConfirmPlace;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'My location'**
  String get custMyLocation;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Location is off, so we can\'t find you. Move the map and pick the place yourself.'**
  String get custLocationDenied;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Confirm order'**
  String get custConfirmOrder;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get custChange;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'From where to where?'**
  String get custRouteTitle;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Choose the drop-off place'**
  String get custChooseDropoff;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get custPriceTitle;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Order opening'**
  String get custBaseFare;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Per km'**
  String get custPerKm;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'{km} km × {rate}'**
  String custDistanceLine(String km, String rate);

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Estimate'**
  String get custEstimate;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Choose the drop-off place to see the estimate.'**
  String get custPriceNeedsDropoff;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'This is an estimate by straight-line distance. The price can change if the courier offers another price and you accept it.'**
  String get custPriceDisclaimer;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Cash to the courier'**
  String get custPayCash;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Electronic payment is coming soon'**
  String get custPayOnlineSoon;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Choose the drop-off place first'**
  String get custChooseDropoffFirst;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Order now'**
  String get custOrderNow;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t place your order. {reason}'**
  String custBookingFailed(String reason);

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'This company is closed now, so it can\'t take orders.'**
  String get custServiceClosed;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'My orders'**
  String get custOrdersTitle;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Order type'**
  String get custOrdersKind;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Ongoing · {count}'**
  String custTabOngoing(int count);

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Past'**
  String get custTabPast;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Cash on delivery'**
  String get custCashOnDelivery;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'No ongoing orders'**
  String get custNoOngoingTitle;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'No past orders yet'**
  String get custNoPastTitle;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Book a delivery, a parcel or a ride and it shows up here.'**
  String get custOrdersEmptyBody;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Browse services'**
  String get custBrowseServices;

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Today · {time}'**
  String custTodayAt(String time);

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'{date} · {time}'**
  String custDateAt(String date, String time);

  /// FE-CUST-1 redesigned customer screens.
  ///
  /// In en, this message translates to:
  /// **'Near you · up to {km} km'**
  String custNearYou(String km);

  /// FE-CUST-2 marketplace card price.
  ///
  /// In en, this message translates to:
  /// **'From {base} + {rate}/km'**
  String custFromPrice(String base, String rate);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Your order'**
  String get ordTitle;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your order'**
  String get ordLoadError;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t update your order. This is the last update we have.'**
  String get ordRefreshError;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'We can\'t show this order\'s status'**
  String get ordUnknownTitle;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Pull down to refresh. If it stays like this, contact support.'**
  String get ordUnknownBody;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Pickup from'**
  String get ordPickupFrom;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Delivery at'**
  String get ordDeliverTo;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Cash · estimated'**
  String get ordCashEstimate;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'You\'ll pay cash'**
  String get ordPayCash;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Paid cash'**
  String get ordPaidCash;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Not set yet'**
  String get ordPriceNotSet;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Your courier'**
  String get ordCourierFallback;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Chat with the courier'**
  String get ordChatCourier;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Order cancelled'**
  String get ordCancelledTitle;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'This order won\'t go ahead. You can order again any time.'**
  String get ordCancelledBody;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String ordCancelReason(String reason);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'The price offer ran out of time'**
  String get ordProposalExpiredTitle;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Nobody answered the price offer in time, so the order was cancelled. You can order again.'**
  String get ordProposalExpiredBody;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Your order is under review'**
  String get ordReviewTitle;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'The company is checking the trip before closing the order. Nothing is needed from you.'**
  String get ordReviewBody;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Amount on hold'**
  String get ordOnHold;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get chatYou;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'User {id}'**
  String chatUserFallback(String id);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get chatLive;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get chatConnecting;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Not connected, retrying'**
  String get chatOffline;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'You can\'t open this chat.'**
  String get chatDenied;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get chatEmptyTitle;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Send the courier any extra details about your order.'**
  String get chatEmptyBody;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Write a message'**
  String get chatHint;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t send the message. {error}'**
  String chatSendFailed(String error);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Looking for a courier'**
  String get ordSearchingTitle;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'We offer your order to couriers one by one until one accepts.'**
  String get ordSearchingBody;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'We offer your order to {company} couriers one by one until one accepts.'**
  String ordSearchingBodyCompany(String company);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'{name} is looking at your order'**
  String ordOfferedTitle(String name);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'A courier is looking at your order'**
  String get ordOfferedTitleNoName;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Got more details? Send them in the chat.'**
  String get ordOfferedSub;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get ordCancelOrder;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Cancel this order?'**
  String get ordCancelSheetTitle;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Tell the company why. A reason is required.'**
  String get ordCancelSheetBody;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get ordCancelReasonLabel;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Keep the order'**
  String get ordCancelKeep;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Your order was cancelled.'**
  String get ordCancelDone;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Your order was cancelled and the amount was refunded.'**
  String get ordCancelDoneRefunded;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'No courier available right now'**
  String get ordUnavailableTitle;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'All couriers are busy. You can send the same order again.'**
  String get ordUnavailableBody;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Order again'**
  String get ordRetryBooking;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'We sent your order again.'**
  String get ordRetryBooked;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'{name} offered a different price'**
  String ordProposalCourierTitle(String name);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'The courier offered a different price'**
  String get ordProposalCourierTitleNoName;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'You need to accept before the order starts.'**
  String get ordProposalCourierSub;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'You offered {price}'**
  String ordProposalMineTitle(String price);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the courier to answer.'**
  String get ordProposalMineSub;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Agree on the price'**
  String get ordProposalOpenTitle;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Send a price within the allowed range.'**
  String get ordProposalOpenSub;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Original price'**
  String get ordOriginalPrice;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Offered price'**
  String get ordOfferedPrice;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'{amount} more'**
  String ordPriceMore(String amount);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'{amount} less'**
  String ordPriceLess(String amount);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Same price'**
  String get ordPriceSame;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Offer expires in'**
  String get ordOfferExpiresIn;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'If time runs out without an answer, the order is cancelled and you can order again.'**
  String get ordOfferExpiryNote;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get ordDecline;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Accept {price}'**
  String ordAcceptPrice(String price);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Your price'**
  String get ordYourPrice;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Between {min} and {max}'**
  String ordPriceRange(String min, String max);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Enter a number, like 42.'**
  String get ordPriceInvalid;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Enter a price between {min} and {max}.'**
  String ordPriceOutOfRange(String min, String max);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Send offer'**
  String get ordSendOffer;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Your offer was sent.'**
  String get ordOfferSent;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'You accepted the price.'**
  String get ordAccepted;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'You declined the price.'**
  String get ordDeclined;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'The order changed: the other side already answered or its status moved on.'**
  String get ordStateChanged;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'The courier is working on your order'**
  String get ordActiveTitle;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Their location updates on the map as they move.'**
  String get ordActiveSub;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'You ordered'**
  String get ordStepOrdered;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'{name} accepted the order'**
  String ordStepAccepted(String name);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'The courier accepted the order'**
  String get ordStepAcceptedNoName;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'On the way'**
  String get ordStepOnTheWay;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get ordStepNow;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get ordStepDelivered;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Order steps'**
  String get ordSteps;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Problem? Open a complaint'**
  String get ordComplaint;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the courier\'s location'**
  String get ordMapWaiting;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting to live tracking…'**
  String get ordMapReconnecting;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'You can\'t follow this order on the map.'**
  String get ordMapDenied;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Map with the courier\'s position'**
  String get ordMapLabel;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get ordZoomIn;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get ordZoomOut;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Center the map'**
  String get ordRecenter;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Your order was delivered'**
  String get ordDeliveredTitle;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'You paid {price} cash'**
  String ordDeliveredPaidCash(String price);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'You paid {price}'**
  String ordDeliveredPaid(String price);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Rate {name}'**
  String ordRateCourier(String name);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Rate the courier'**
  String get ordRateCourierNoName;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Rate the company'**
  String get ordRateCompany;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Thanks, your rating was sent.'**
  String get ordRatedThanks;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'How was {name}?'**
  String rateQuestion(String name);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'How was the courier?'**
  String get rateQuestionCourier;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'How was the company?'**
  String get rateQuestionCompany;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get rateStars;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Your rating shows to the other side only after they rate you too. The comment goes to the company only.'**
  String get rateBlindNote;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Comment · optional'**
  String get rateComment;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Send rating'**
  String get rateSend;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get rateNotNow;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t send your rating. {error}'**
  String rateFailed(String error);

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'We can\'t tell who to rate for this order.'**
  String get rateIdentityError;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'The other side already rated you. Both ratings are visible now.'**
  String get rateOtherRated;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t check whether the other side rated you.'**
  String get rateOtherCheckFailed;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get rateClose;

  /// FE-CUST-2 redesigned order detail.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 star} other{{count} stars}}'**
  String rateStar(int count);

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get authSwitchLanguage;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Switch to Arabic'**
  String get authSwitchLanguageLabel;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Change the look'**
  String get authThemeLabel;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get authBack;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get authLoginTitle;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Sign in to order and follow your orders'**
  String get authLoginSubtitle;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'name@example.com'**
  String get authEmailHint;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get authEmailRequired;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Enter an email like name@example.com'**
  String get authEmailInvalid;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get authPasswordRequired;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Forgot your password?'**
  String get authForgotPassword;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'No account?'**
  String get authNoAccount;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Create one'**
  String get authCreateAccountLink;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get authSignupTitle;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Who are you?'**
  String get authRoleQuestion;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get authRoleCustomer;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'I want to send orders'**
  String get authRoleCustomerHint;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Business owner'**
  String get authRoleOwner;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'I have a company and couriers'**
  String get authRoleOwnerHint;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Couriers get their accounts from their business owner.'**
  String get authCourierNote;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get authNameLabel;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get authNameRequired;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'The name needs at least 3 letters'**
  String get authNameTooShort;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'The name can have at most 30 letters'**
  String get authNameTooLong;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Use letters, numbers, spaces or _ only'**
  String get authNameInvalid;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters, and not an easy one like 12345678'**
  String get authPasswordHelp;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Have an account?'**
  String get authHaveAccount;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignInLink;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get authOtpTitle;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to'**
  String get authOtpSentTo;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get authOtpLabel;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Enter all 6 digits'**
  String get authOtpIncomplete;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get authOtpConfirm;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t get it? You can send it again in'**
  String get authResendWait;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t get it?'**
  String get authResendPrompt;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Send the code again'**
  String get authResendNow;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'We sent you a new code.'**
  String get authCodeResent;

  /// FE-AUTH-ACCOUNT redesigned sign-in, sign-up and code screens.
  ///
  /// In en, this message translates to:
  /// **'Test mode: we filled in the code {otp} for you.'**
  String authDevOtp(String otp);

  /// FE-AUTH-ACCOUNT redesigned password reset.
  ///
  /// In en, this message translates to:
  /// **'Forgot your password?'**
  String get resetTitle;

  /// FE-AUTH-ACCOUNT redesigned password reset.
  ///
  /// In en, this message translates to:
  /// **'Enter your account email and we\'ll send you a code.'**
  String get resetEmailBody;

  /// FE-AUTH-ACCOUNT redesigned password reset.
  ///
  /// In en, this message translates to:
  /// **'Send the code'**
  String get resetSendCode;

  /// FE-AUTH-ACCOUNT redesigned password reset.
  ///
  /// In en, this message translates to:
  /// **'We sent a code to your email.'**
  String get resetCodeSent;

  /// FE-AUTH-ACCOUNT redesigned password reset.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get resetNewTitle;

  /// FE-AUTH-ACCOUNT redesigned password reset.
  ///
  /// In en, this message translates to:
  /// **'Choose a password you don\'t use anywhere else.'**
  String get resetNewBody;

  /// FE-AUTH-ACCOUNT redesigned password reset.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get resetNewLabel;

  /// FE-AUTH-ACCOUNT redesigned password reset.
  ///
  /// In en, this message translates to:
  /// **'Type it again'**
  String get resetConfirmLabel;

  /// FE-AUTH-ACCOUNT redesigned password reset.
  ///
  /// In en, this message translates to:
  /// **'The two passwords don\'t match'**
  String get resetMismatch;

  /// FE-AUTH-ACCOUNT redesigned password reset.
  ///
  /// In en, this message translates to:
  /// **'Save password'**
  String get resetSave;

  /// FE-AUTH-ACCOUNT redesigned password reset.
  ///
  /// In en, this message translates to:
  /// **'Your password was changed. Sign in with the new one.'**
  String get resetDone;

  /// FE-AUTH-ACCOUNT redesigned password reset.
  ///
  /// In en, this message translates to:
  /// **'This reset ran out of time. Start again to get a new code.'**
  String get resetExpired;

  /// FE-AUTH-ACCOUNT redesigned password reset.
  ///
  /// In en, this message translates to:
  /// **'Start again'**
  String get resetStartAgain;

  /// FE-AUTH-ACCOUNT redesigned password reset.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String resetStep(int current, int total);

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get acctEdit;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get acctSectionAccount;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get acctSectionApp;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get acctSectionSupport;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'My details'**
  String get acctMyDetails;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Saved addresses'**
  String get acctSavedAddresses;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get acctSecurity;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'2-step verification on'**
  String get acctTwoFactorOn;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'2-step verification off'**
  String get acctTwoFactorOff;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get acctWallet;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get acctLanguage;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get acctLangArabic;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get acctLangEnglish;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Same as the phone'**
  String get acctPhoneSetting;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get acctTheme;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get acctThemeLight;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get acctThemeDark;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get acctNotifications;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Support and complaints'**
  String get acctSupport;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get acctLogout;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Your account is suspended'**
  String get acctSuspendedTitle;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'You can\'t change your details for now. Contact support to know more.'**
  String get acctSuspendedDefault;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t refresh your account details.'**
  String get acctLoadError;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get acctPhoneLabel;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'01xxxxxxxxx'**
  String get acctPhoneHint;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get acctChangeEmail;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Change email'**
  String get acctChangeEmailLabel;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'To change it we send a code to the new email.'**
  String get acctEmailNote;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get acctSave;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Your details were saved.'**
  String get acctSaved;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Add an address'**
  String get acctAddAddress;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Edit address'**
  String get acctEditAddress;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get acctAddressLabel;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Building, street, area'**
  String get acctAddressHint;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Write the address'**
  String get acctAddressRequired;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'You can save up to 10 addresses'**
  String get acctAddressMax;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'{count} of 10'**
  String acctAddressCount(int count);

  /// FE-AUTH-ACCOUNT; FE-BE-GAPS saved addresses with coordinates.
  ///
  /// In en, this message translates to:
  /// **'Each address has a map pin, so it fills the pickup or drop-off in one tap when you book.'**
  String get acctAddressesNote;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'No saved addresses yet'**
  String get acctAddressesEmpty;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Save the places you order from often.'**
  String get acctAddressesEmptyBody;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Save address'**
  String get acctSaveAddress;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Delete {address}'**
  String acctDeleteAddress(String address);

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Address deleted.'**
  String get acctAddressDeleted;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get acctUndo;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'2-step verification'**
  String get acctTwoFactor;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'We send a code to your email every time you sign in.'**
  String get acctTwoFactorBody;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Turn off 2-step verification?'**
  String get acctTwoFactorOffTitle;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Anyone with your password could then sign in without a code.'**
  String get acctTwoFactorOffBody;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get acctTwoFactorTurnOff;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get acctCancel;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Confirm it\'s you'**
  String get acctPasswordTitle;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Enter your password to turn off 2-step verification.'**
  String get acctPasswordBody;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'That password isn\'t right.'**
  String get acctWrongPassword;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'2-step verification is on.'**
  String get acctTwoFactorOnDone;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'2-step verification is off.'**
  String get acctTwoFactorOffDone;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'New email'**
  String get acctNewEmailLabel;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Your email was changed.'**
  String get acctEmailChanged;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'This is already your email'**
  String get acctSameEmail;

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get acctClose;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get ntfTitle;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get ntfMarkAllRead;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get ntfClearAll;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Clear all notifications?'**
  String get ntfClearTitle;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'You can\'t get them back.'**
  String get ntfClearBody;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get ntfClear;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get ntfToday;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get ntfYesterday;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get ntfJustNow;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String ntfMinutesAgo(int count);

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'{count} h ago'**
  String ntfHoursAgo(int count);

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get ntfUnread;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Remove notification'**
  String get ntfDismiss;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Live: new notifications show up here'**
  String get ntfLive;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Not connected: new notifications may be late'**
  String get ntfOffline;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'We lost the live connection.'**
  String get ntfConnectError;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get ntfReconnect;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get ntfEmptyTitle;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'We\'ll tell you here when something happens with your orders.'**
  String get ntfEmptyBody;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your notifications.'**
  String get ntfLoadError;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Show older'**
  String get ntfShowOlder;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'A courier accepted your order'**
  String get ntfAcceptedTitle;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Follow it from the order page.'**
  String get ntfAcceptedBody;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'No courier is free right now'**
  String get ntfUnavailableTitle;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'You can order again from My orders.'**
  String get ntfUnavailableBody;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Your order was cancelled'**
  String get ntfCancelledTitle;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Open My orders for the details.'**
  String get ntfOrdersBody;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Your order was delivered'**
  String get ntfCompletedTitle;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Your complaint was resolved'**
  String get ntfTicketResolvedTitle;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Support joined your complaint'**
  String get ntfTicketAssignedTitle;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'Reply to them in the complaint chat.'**
  String get ntfTicketAssignedBody;

  /// FE-AUTH-ACCOUNT redesigned notifications (A-Notifs).
  ///
  /// In en, this message translates to:
  /// **'The review of your order is done'**
  String get ntfDisputeTitle;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get supTitle;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Open · {count}'**
  String supOpenTab(int count);

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get supResolvedTab;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a reply'**
  String get supStatusPending;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'With support'**
  String get supStatusAssigned;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get supStatusResolved;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get supStatusOpen;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'About order {ref} · {when}'**
  String supAboutOrder(String ref, String when);

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'General · {when}'**
  String supGeneral(String when);

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Resolution: {note}'**
  String supResolution(String note);

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Problem with an order?'**
  String get supHintTitle;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Pick the order and tell us what happened. The support team will answer you here.'**
  String get supHintBody;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'New complaint'**
  String get supNewComplaint;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'No resolved complaints yet'**
  String get supResolvedEmpty;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your complaints.'**
  String get supLoadError;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Which order?'**
  String get supOrderLabel;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Not about an order'**
  String get supNoOrderOption;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Loading your orders…'**
  String get supOrdersLoading;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your orders. You can still send it without one.'**
  String get supOrdersError;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get supSubjectLabel;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'In a few words'**
  String get supSubjectHint;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Write a subject'**
  String get supSubjectRequired;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'What happened?'**
  String get supDescriptionLabel;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Tell us the details'**
  String get supDescriptionHint;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Tell us what happened'**
  String get supDescriptionRequired;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Send complaint'**
  String get supSend;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'We got your complaint. Support will answer you in its chat.'**
  String get supSent;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Complaint {ref}'**
  String supComplaintRef(String ref);

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Write to support here. You can attach a photo or a PDF.'**
  String get supChatEmpty;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'This complaint is resolved.'**
  String get supResolvedBanner;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'A resolved complaint can\'t get new messages. Open a new one if you need to.'**
  String get supReadOnly;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Attach a photo or PDF'**
  String get supAttach;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'The file is empty.'**
  String get supFileEmpty;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'Files can be up to 10 MB.'**
  String get supFileTooBig;

  /// FE-AUTH-ACCOUNT redesigned support (A-Tickets) and ticket chat.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t send the file.'**
  String get supAttachFailed;

  /// FE-AUTH-ACCOUNT redesigned update-required screen.
  ///
  /// In en, this message translates to:
  /// **'Update the app'**
  String get updTitle;

  /// FE-AUTH-ACCOUNT redesigned update-required screen.
  ///
  /// In en, this message translates to:
  /// **'This version doesn\'t work anymore. Install the new one to keep using Quick Delivery.'**
  String get updBody;

  /// FE-AUTH-ACCOUNT redesigned update-required screen.
  ///
  /// In en, this message translates to:
  /// **'Installed version'**
  String get updInstalled;

  /// FE-AUTH-ACCOUNT redesigned update-required screen.
  ///
  /// In en, this message translates to:
  /// **'Oldest version that works'**
  String get updMinimum;

  /// FE-AUTH-ACCOUNT redesigned update-required screen.
  ///
  /// In en, this message translates to:
  /// **'Latest version'**
  String get updLatest;

  /// FE-AUTH-ACCOUNT redesigned update-required screen.
  ///
  /// In en, this message translates to:
  /// **'Download link'**
  String get updLinkLabel;

  /// FE-AUTH-ACCOUNT redesigned update-required screen.
  ///
  /// In en, this message translates to:
  /// **'Copy the download link'**
  String get updCopy;

  /// FE-AUTH-ACCOUNT redesigned update-required screen.
  ///
  /// In en, this message translates to:
  /// **'Link copied. Open it in your browser to install the new version.'**
  String get updCopied;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Courier {id}'**
  String ownCourierUnknown(String id);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get ownAgoNow;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 min ago} other{{count} min ago}}'**
  String ownAgoMinutes(int count);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 h ago} other{{count} h ago}}'**
  String ownAgoHours(int count);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get ownNotNow;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get ownRefresh;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Order {ref}'**
  String ownOrderTitle(String ref);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get ownOrderFallbackTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'This order isn\'t in your list anymore.'**
  String get ownOrderMissing;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'{name} wants to cancel this order'**
  String ownCancelReqTitle(String name);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'“{reason}”'**
  String ownCancelReqQuote(String reason);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'No reason given'**
  String get ownCancelReqNoReason;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Asked {ago}'**
  String ownCancelReqSince(String ago);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Keep order'**
  String get ownCancelReqKeep;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get ownCancelReqApprove;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Approve the cancellation?'**
  String get ownCancelReqApproveTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'The order will be cancelled and the customer will be told.'**
  String get ownCancelReqApproveBody;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Keep the order going?'**
  String get ownCancelReqKeepTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'{name} stays on the order and has to finish it.'**
  String ownCancelReqKeepBody(String name);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Cancellation approved. The order is cancelled.'**
  String get ownCancelReqApproved;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Request declined. The courier keeps the order.'**
  String get ownCancelReqDeclined;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'This request already changed, it may have run out. The order was refreshed.'**
  String get ownCancelReqConflict;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Distance looked short, review'**
  String get ownDistanceReviewTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'The trip tracked {actual} km of the {booked} km booked. The cash was still recorded.'**
  String ownDistanceReviewBody(String actual, String booked);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'See on the map'**
  String get ownSeeOnMap;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get ownRowCustomer;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Customer {id}'**
  String ownCustomerRef(String id);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Courier'**
  String get ownRowCourier;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Not assigned yet'**
  String get ownCourierNone;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get ownRowPayment;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Cash · {amount}'**
  String ownPayCash(String amount);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Cash · price not set yet'**
  String get ownPayCashNoPrice;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'{method} · {amount}'**
  String ownPayOther(String method, String amount);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Cash recorded'**
  String get ownRowCashRecorded;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Ordered'**
  String get ownRowOrdered;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Cancellation reason'**
  String get ownRowCancelReason;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get ownCancelOrder;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Keep the order'**
  String get ownCancelKeep;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Cancel this order?'**
  String get ownCancelSheetTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'The customer and the courier will be told. Write why you\'re cancelling.'**
  String get ownCancelSheetCod;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'The {amount} held for this order goes back to the customer. Write why you\'re cancelling.'**
  String ownCancelSheetHeld(String amount);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get ownCancelReasonLabel;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Order cancelled.'**
  String get ownCancelled;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Order cancelled. The held amount went back to the customer.'**
  String get ownCancelledRefunded;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get ownOrdersTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Order number or courier name'**
  String get ownOrdersSearchHint;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get ownClearSearch;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Order status'**
  String get ownOrdersKind;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Ongoing · {count}'**
  String ownTabOngoing(int count);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get ownTabDone;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get ownTabCancelled;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your orders.'**
  String get ownOrdersLoadError;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t refresh. You\'re seeing the last list we loaded.'**
  String get ownRefreshFailed;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'No order matches your search'**
  String get ownOrdersNoMatch;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'No ongoing orders'**
  String get ownNoOngoing;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'No finished orders yet'**
  String get ownNoDone;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'No cancelled orders'**
  String get ownNoCancelled;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Orders customers book with you show up here.'**
  String get ownOrdersEmptyBody;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Price offer: {proposed} instead of {price}'**
  String ownProposalLine(String proposed, String price);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Price offer: {proposed}'**
  String ownProposalOnly(String proposed);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Offered to {name}'**
  String ownOfferedTo(String name);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Payment review'**
  String get ownReconTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'The money for these orders is held because something didn\'t add up. Decide who gets it.'**
  String get ownReconIntro;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the orders to review.'**
  String get ownReconLoadError;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Nothing to review'**
  String get ownReconEmpty;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'With cash payment only'**
  String get ownReconCodTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'This screen will mostly stay empty until electronic payment starts.'**
  String get ownReconCodBody;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Amount held'**
  String get ownReconHeld;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Pay the courier'**
  String get ownReconPay;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Refund the customer'**
  String get ownReconRefund;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Pay the courier?'**
  String get ownReconPayTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Refund the customer?'**
  String get ownReconRefundTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'{amount} for order {ref} goes to {name}. This can\'t be undone.'**
  String ownReconPayBody(String amount, String ref, String name);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'{amount} for order {ref} goes back to the customer. This can\'t be undone.'**
  String ownReconRefundBody(String amount, String ref);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'the courier'**
  String get ownReconTheCourier;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Paid to the courier.'**
  String get ownReconPaid;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Refunded to the customer.'**
  String get ownReconRefunded;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t settle this order. Try again.'**
  String get ownReconFailed;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Distance shorter than expected'**
  String get ownReasonShortDistance;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Speed didn\'t add up'**
  String get ownReasonSpeed;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Held amount not recorded'**
  String get ownReasonUnrecorded;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Needs a review'**
  String get ownReasonOther;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get ownTeamTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'On the map'**
  String get ownOnTheMap;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Courier status'**
  String get ownTeamKind;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'All · {count}'**
  String ownTeamAll(int count);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get ownTeamActive;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Frozen'**
  String get ownTeamFrozen;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your team.'**
  String get ownTeamLoadError;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'No couriers yet'**
  String get ownTeamEmpty;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Add your couriers so they can sign in and take orders.'**
  String get ownTeamEmptyBody;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'No couriers here'**
  String get ownTeamNoneHere;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Add courier'**
  String get ownAddCourier;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'On a job'**
  String get ownStateOnJob;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get ownStateFree;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Frozen'**
  String get ownStateFrozen;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'On a job · {ref}'**
  String ownOnJobWith(String ref);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'No order right now'**
  String get ownNoOrderNow;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Can\'t sign in or get orders'**
  String get ownFrozenSubtitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'This courier isn\'t on your team anymore.'**
  String get ownEmployeeMissing;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get ownEmpOrders;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get ownEmpDelivered;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Counted from your latest orders in the app.'**
  String get ownEmpCountsNote;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'ID check'**
  String get ownEmpIdCheck;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get ownKyeApproved;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Under review'**
  String get ownKyePending;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get ownKyeRejected;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Documents missing'**
  String get ownKyeMissing;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Current order'**
  String get ownEmpCurrentOrder;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get ownEmpNone;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'All their orders'**
  String get ownEmpAllOrders;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Where they are on the map'**
  String get ownEmpOnMap;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Freeze account'**
  String get ownFreeze;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Unfreeze account'**
  String get ownUnfreeze;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'They\'re signed out at once and get no new orders. We\'ll ask for your password to confirm.'**
  String get ownFreezeHint;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'They can sign in and get orders again. We\'ll ask for your password to confirm.'**
  String get ownUnfreezeHint;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Freeze {name}\'s account?'**
  String ownFreezeTitle(String name);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Unfreeze {name}\'s account?'**
  String ownUnfreezeTitle(String name);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'They\'re signed out at once and get no new orders. Type your password to confirm.'**
  String get ownFreezeBody;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'They can sign in and get orders again. Type your password to confirm.'**
  String get ownUnfreezeBody;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Your password'**
  String get ownYourPassword;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Type your password.'**
  String get ownPasswordRequired;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'That password isn\'t right.'**
  String get ownPasswordWrong;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Your business documents must be approved first.'**
  String get ownToggleKybNeeded;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Managing couriers needs a paid plan.'**
  String get ownTogglePaidPlan;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s account is frozen.'**
  String ownFrozenDone(String name);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s account is active again.'**
  String ownUnfrozenDone(String name);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Add a courier'**
  String get ownAddTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'They sign in with this email and password.'**
  String get ownAddBody;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get ownAddUsername;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get ownAddEmail;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get ownAddPassword;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters.'**
  String get ownAddPasswordHelp;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Add courier'**
  String get ownAddSubmit;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'{name} was added. They can sign in now.'**
  String ownAdded(String name);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get ownTodayTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get ownNotifications;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load today\'s orders.'**
  String get ownTodayLoadError;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Ongoing now'**
  String get ownTileOngoing;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Delivered today'**
  String get ownTileDelivered;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Cash recorded today'**
  String get ownTileCash;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Delivered and cash count the orders placed today.'**
  String get ownTodayNote;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Counted from your latest {limit} orders, all from today. There may be more.'**
  String ownTodayNoteTruncated(int limit);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Needs you'**
  String get ownNeedsYou;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs you right now.'**
  String get ownNeedsNothing;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'{name} wants to cancel an order'**
  String ownNeedsRequestTitle(String name);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String ownNeedsReason(String reason);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Respond'**
  String get ownNeedsRespond;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 order needs a payment review} other{{count} orders need a payment review}}'**
  String ownNeedsReviewsTitle(int count);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'The distance or time didn\'t add up'**
  String get ownNeedsReviewsBody;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get ownNeedsReview;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Team now'**
  String get ownTeamNow;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get ownSeeAll;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'No couriers yet. Add them from the Team tab.'**
  String get ownTeamNowEmpty;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Your rating'**
  String get ownRatingTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'No ratings yet'**
  String get ownRatingNone;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'{average} · {count, plural, =1{1 rating} other{{count} ratings}}'**
  String ownRatingValue(String average, int count);

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Your business'**
  String get ownYourBusiness;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'All orders'**
  String get ownLinkAllOrders;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Service setup'**
  String get ownLinkServiceSetup;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get ownLinkWallet;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get ownLinkSubscription;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Activity and history'**
  String get ownLinkHistory;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Verify your business'**
  String get ownKybMissingTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Upload your business documents to start taking orders.'**
  String get ownKybMissingBody;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Upload documents'**
  String get ownKybUpload;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Your documents are under review'**
  String get ownKybPendingTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'We\'ll let you know when they\'re approved.'**
  String get ownKybPendingBody;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'View documents'**
  String get ownKybView;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Your documents were rejected'**
  String get ownKybRejectedTitle;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Upload them again to start taking orders.'**
  String get ownKybRejectedBody;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Upload again'**
  String get ownKybUploadAgain;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get ownNavToday;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get ownNavOrders;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get ownNavTeam;

  /// FE-OWNER-1 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get ownNavAccount;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Service setup'**
  String get ownSvcTitle;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get ownSvcSectionBusiness;

  /// FE-OWNER-2 redesigned owner screens; FE-BE-GAPS photo upload.
  ///
  /// In en, this message translates to:
  /// **'Customers see this photo on your card. JPEG or PNG, up to 5 MB.'**
  String get ownSvcPhotoNote;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Service name as customers see it'**
  String get ownSvcName;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Enter the service name'**
  String get ownSvcNameRequired;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get ownSvcKind;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get ownSvcKindDelivery;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Rides'**
  String get ownSvcKindTransport;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Shipping'**
  String get ownSvcKindShipping;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Place and coverage'**
  String get ownSvcSectionPlace;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Business location on the map'**
  String get ownSvcPlace;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get ownSvcPlaceMissing;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Set on the map'**
  String get ownSvcPlaceSet;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Business location'**
  String get ownSvcPickerTitle;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Written address'**
  String get ownSvcAddress;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Write at least 3 letters, or leave it empty'**
  String get ownSvcAddressShort;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'How far do you serve?'**
  String get ownSvcRadius;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'km'**
  String get ownSvcKm;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Enter a distance above 0'**
  String get ownSvcRadiusInvalid;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Working hours'**
  String get ownSvcSectionHours;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'No hours set: customers see you as open all the time.'**
  String get ownSvcHoursNone;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Set working hours'**
  String get ownSvcHoursSet;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Same every day'**
  String get ownSvcHoursSame;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Each day'**
  String get ownSvcHoursPerDay;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Opens'**
  String get ownSvcOpens;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Closes'**
  String get ownSvcCloses;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Day off'**
  String get ownSvcDayOff;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Remove hours'**
  String get ownSvcHoursRemove;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Opening and closing can\'t be the same time'**
  String get ownSvcHoursSameTime;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Pick both times'**
  String get ownSvcHoursMissing;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Pricing'**
  String get ownSvcSectionPricing;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Opening fee'**
  String get ownSvcBaseFee;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Per km'**
  String get ownSvcPerKm;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Enter 0 or more'**
  String get ownSvcPriceInvalid;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Example: a {km} km trip shows the customer {price}.'**
  String ownSvcExample(int km, String price);

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Enter both prices to see what a customer pays.'**
  String get ownSvcExampleEmpty;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get ownSvcSave;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Service saved'**
  String get ownSvcSaved;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Check the fields marked in red'**
  String get ownSvcFixErrors;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your service'**
  String get ownSvcLoadError;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Your business papers need to be approved before you can save the service.'**
  String get ownSvcErrKyb;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Saving the service needs an active plan.'**
  String get ownSvcErrPlan;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'This is unavailable right now. Try again in a bit.'**
  String get ownSvcErrUnavailable;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'EGP'**
  String get ownSvcCurrency;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Map of your couriers'**
  String get ownFleetMapLabel;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get ownFleetFilterLabel;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get ownFleetAll;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get ownFleetFree;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have access to this team map.'**
  String get ownFleetDenied;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Your couriers\' locations didn\'t load.'**
  String get ownFleetLoadError;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting to live locations…'**
  String get ownFleetReconnecting;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'No courier is sharing a location right now.'**
  String get ownFleetNobody;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get ownFleetRefresh;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'On the map: {total} · on a job: {onJob}'**
  String ownFleetSummary(int total, int onJob);

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Couriers show up here while they share their location.'**
  String get ownFleetSummaryNone;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Tap a courier to see their order.'**
  String get ownFleetTapHint;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Last update {ago}'**
  String ownFleetLastUpdate(String ago);

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get ownFleetClose;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Order {ref}'**
  String ownFleetOrderRef(String ref);

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Order {ref} · to {place}'**
  String ownFleetOrderTo(String ref, String place);

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Courier page'**
  String get ownFleetCourierPage;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Activity log'**
  String get ownLogTitle;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get ownLogTabActivity;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get ownLogTabMoney;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get ownLogPeriodLabel;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get ownLogPeriodAll;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get ownLogPeriodToday;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get ownLogPeriodWeek;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get ownLogActivityEmpty;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Courier actions and account changes show up here.'**
  String get ownLogActivityEmptyBody;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'No money movements yet'**
  String get ownLogMoneyEmpty;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Orders are paid in cash for now, so this stays empty until online payments start.'**
  String get ownLogMoneyEmptyBody;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this period'**
  String get ownLogNoneInPeriod;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get ownLogShowAll;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the activity'**
  String get ownLogActivityError;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the money movements'**
  String get ownLogMoneyError;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t refresh. This is the last list we loaded.'**
  String get ownLogStale;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get ownLogYou;

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'balance after {amount}'**
  String ownLogBalanceAfter(String amount);

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Money in, {amount}'**
  String ownLogMoneyIn(String amount);

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Money out, {amount}'**
  String ownLogMoneyOut(String amount);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get courNavTask;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'My jobs'**
  String get courNavJobs;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get courNavAccount;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Upload your documents so your account can be verified.'**
  String get courKyeMissing;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Your documents are waiting for review.'**
  String get courKyePending;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Your documents were not accepted: {reason}'**
  String courKyeRejected(String reason);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Your documents were not accepted. Upload them again.'**
  String get courKyeRejectedNoReason;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Upload documents'**
  String get courKyeUpload;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'View documents'**
  String get courKyeView;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Upload again'**
  String get courKyeReupload;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'You can\'t take orders right now'**
  String get courBlockedTitle;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Your account was suspended, so no orders will reach you.'**
  String get courBlockedSuspended;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Your account is paused, so no orders will reach you. Your company or Quick Delivery can turn it back on.'**
  String get courBlockedPaused;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get courBlockedReason;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Talk to your company owner, or contact support if you think this is a mistake.'**
  String get courBlockedWhat;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get courBlockedCheck;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your jobs.'**
  String get courLoadError;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get courRefresh;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'No task right now'**
  String get courIdleOnlineTitle;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'You\'re available. New orders show up here.'**
  String get courIdleOnlineBody;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'You\'re not available'**
  String get courIdleOfflineTitle;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Turn on availability to get new orders.'**
  String get courIdleOfflineBody;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Make me available'**
  String get courGoOnline;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'{km} km'**
  String courKm(String km);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Not set yet'**
  String get courPriceNotSet;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get courPackageSmall;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get courPackageMedium;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get courPackageLarge;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Package: {details}'**
  String courPackage(String details);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Map of the route and your location'**
  String get courMapLabel;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Drop-off not set yet'**
  String get courNoDestination;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get courChatTitle;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Messages with the customer about this order show here.'**
  String get courChatEmpty;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'A new task for you'**
  String get courOfferSubtitle;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'New order'**
  String get courOfferTitle;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'This offer has ended.'**
  String get courOfferExpired;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Pickup · {distance} from you'**
  String courPickupFromYou(String distance);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Drop-off · trip {distance}'**
  String courDropoffTrip(String distance);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'You\'ll collect cash'**
  String get courCashToCollect;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Order price'**
  String get courOrderPrice;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Ask the customer'**
  String get courAskCustomer;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get courDecline;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Accept the task'**
  String get courAccept;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Task accepted'**
  String get courOfferAccepted;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Offer declined'**
  String get courOfferDeclined;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'This offer is no longer available.'**
  String get courOfferGone;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Pickup recorded. Head to the drop-off.'**
  String get courPickedUpDone;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'This order is already marked as picked up.'**
  String get courPickupAlready;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'This order is no longer assigned to you.'**
  String get courNotYours;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Order delivered. Well done!'**
  String get courDelivered;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Request sent to your company owner.'**
  String get courCancelSent;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Your running tasks'**
  String get courOtherJobsTitle;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You have 1 more running task.} other{You have {count} more running tasks.}}'**
  String courOtherJobs(int count);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get courOtherJobsShow;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'I picked up the order'**
  String get courPickedUp;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Delivered, collected {amount}'**
  String courDeliveredCollected(String amount);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Delivered and collected the cash'**
  String get courDeliveredCash;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get courDeliveredPlain;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Open in maps'**
  String get courOpenInMaps;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Current task'**
  String get courCurrentTitle;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'You asked to cancel. Waiting for your company owner.'**
  String get courCancelPending;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Your company owner said no to cancelling. The task is still yours.'**
  String get courCancelRejected;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Can\'t finish? Request cancellation'**
  String get courRequestCancel;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Estimate: about {minutes} min to the pickup'**
  String courEtaPickup(int minutes);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Estimate: about {minutes} min to the drop-off'**
  String courEtaDropoff(int minutes);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Agreeing on the price'**
  String get courPhasePrice;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Going to pickup'**
  String get courPhaseToPickup;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Picked up'**
  String get courPhasePickedUp;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get courPhaseActive;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Customer sees your location'**
  String get courSharingLive;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Location is off'**
  String get courSharingOff;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Location isn\'t updating'**
  String get courSharingFailing;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Turning on location…'**
  String get courSharingStarting;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Turn on location'**
  String get courPermissionTitle;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'The customer and your company can\'t see where you are until you allow location.'**
  String get courPermissionBody;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get courOpenSettings;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Will pay {amount} cash'**
  String courWillPayCash(String amount);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Order price {amount}'**
  String courOrderPriceValue(String amount);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Chat with the customer'**
  String get courChatWithCustomer;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Notes: {notes}'**
  String courRecipientNotes(String notes);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Enter the amount you collected, like 42.'**
  String get courAmountInvalid;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Did you deliver the order?'**
  String get courCompleteTitle;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Confirm you handed it over and collected {amount} cash.'**
  String courCompleteCod(String amount);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Confirm you handed it over and collected the cash.'**
  String get courCompleteCodNoPrice;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Confirm you handed the order over.'**
  String get courCompleteNonCod;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'I collected a different amount'**
  String get courCompleteDifferent;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Amount collected'**
  String get courCompleteAmountLabel;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'In Egyptian pounds'**
  String get courCompleteAmountHelp;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Yes, I collected {amount}'**
  String courCompleteConfirmAmount(String amount);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Yes, I collected the cash'**
  String get courCompleteConfirmCash;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Yes, I delivered it'**
  String get courCompleteConfirm;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get courNotYet;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Your company sees the amount you confirm.'**
  String get courCompleteNote;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Request cancellation'**
  String get courCancelTitle;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Your company owner decides. Until they answer, the task stays yours.'**
  String get courCancelBody;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get courCancelSend;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Keep the task'**
  String get courCancelKeep;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Accept {price}?'**
  String courPriceAcceptTitle(String price);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'The trip starts right away at this price.'**
  String get courPriceAcceptBody;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Price sent. Waiting for the customer.'**
  String get courProposalSent;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Price accepted. The trip has started.'**
  String get courPriceAccepted;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Price declined.'**
  String get courPriceDeclined;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'The customer offers {price}'**
  String courPriceCustomerTitle(String price);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'The suggested price was {price}.'**
  String courPriceWas(String price);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'You offered {price}'**
  String courPriceMineTitle(String price);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the customer\'s answer.'**
  String get courPriceMineBody;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Propose your price'**
  String get courPriceProposeTitle;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'The suggested price is {price}. You can send one offer; the customer accepts or declines it.'**
  String courPriceProposeBody(String price);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the price to be agreed'**
  String get courPriceWaitingTitle;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Your price'**
  String get courPriceProposeLabel;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Between {min} and {max}'**
  String courPriceBounds(String min, String max);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'The price offer ran out of time.'**
  String get courPriceExpired;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Available for tasks'**
  String get courAvailableOn;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get courAvailableOff;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'We send your location to your company every minute.'**
  String get courAvailableOnBody;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'You won\'t get new orders.'**
  String get courAvailableOffBody;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Locked while a task is in progress.'**
  String get courAvailableLocked;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Tasks finished today'**
  String get courTodayDone;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Cash today, at order price'**
  String get courTodayCash;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Cash is the price of today\'s delivered cash orders; your company sees the amount you confirmed.'**
  String get courTodayCashNote;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Older orders have no finish time, so they count by the day they were created.'**
  String get courTodayByCreation;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get courFinishedHeader;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'To {place}'**
  String courToPlace(String place);

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get courPayCash;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'No finished tasks yet'**
  String get courNoFinishedTitle;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Tasks you deliver, and ones that get cancelled, show up here.'**
  String get courNoFinishedBody;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'No agreement on the price'**
  String get courReasonPriceDisagreement;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get acctVerification;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get acctKyeApproved;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Under review'**
  String get acctKyePending;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Not accepted'**
  String get acctKyeRejected;

  /// FE-COURIER redesigned courier screens.
  ///
  /// In en, this message translates to:
  /// **'Not uploaded'**
  String get acctKyeMissing;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Business verification'**
  String get vrfTitleOwner;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'ID verification'**
  String get vrfTitleCourier;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t refresh your verification status.'**
  String get vrfLoadError;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Upload your documents'**
  String get vrfStateMissingTitle;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Upload all {total} documents so we can verify your business and you can start taking orders.'**
  String vrfStateMissingOwner(int total);

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Upload all {total} documents so we can confirm who you are.'**
  String vrfStateMissingCourier(int total);

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} documents uploaded'**
  String vrfStateIncompleteTitle(int done, int total);

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Review starts once every document is uploaded.'**
  String get vrfStateIncompleteBody;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Your documents are under review'**
  String get vrfStatePendingTitle;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'We\'ll let you know when the review is done. You can still replace a document.'**
  String get vrfStatePendingBody;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get vrfStateApprovedTitle;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Your documents were accepted. They\'re locked now.'**
  String get vrfStateApprovedBody;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Your documents weren\'t accepted'**
  String get vrfStateRejectedTitle;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Reviewer\'s note: {reason}'**
  String vrfRejectedReason(String reason);

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'No reason was given. Contact support if you\'re not sure what to change.'**
  String get vrfRejectedNoReason;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Replace the documents that need fixing. They go back to review as soon as you upload one.'**
  String get vrfRejectedHint;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get vrfDocsHeader;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} uploaded'**
  String vrfDocsCount(int done, int total);

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'ID card, front'**
  String get vrfSlotIdFront;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'A clear photo of the front of your national ID or passport.'**
  String get vrfSlotIdFrontHint;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'ID card, back'**
  String get vrfSlotIdBack;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'A clear photo of the back of your national ID.'**
  String get vrfSlotIdBackHint;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Selfie with your ID'**
  String get vrfSlotSelfie;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Hold your ID card next to your face.'**
  String get vrfSlotSelfieHint;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Commercial register'**
  String get vrfSlotBusiness;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Commercial register or tax card. A photo or a PDF.'**
  String get vrfSlotBusinessHint;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Needed'**
  String get vrfSlotNeeded;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get vrfSlotUploaded;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Under review'**
  String get vrfSlotInReview;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get vrfSlotAccepted;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Not accepted'**
  String get vrfSlotNotAccepted;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get vrfSlotUploading;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Photo on file'**
  String get vrfOnFilePhoto;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'PDF on file'**
  String get vrfOnFilePdf;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get vrfUpload;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get vrfReplace;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Choose another file'**
  String get vrfChooseAnother;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Uploading {name}…'**
  String vrfUploadingFile(String name);

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'{slot} uploaded.'**
  String vrfUploadedNotice(String slot);

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'All documents uploaded. They\'re under review now.'**
  String get vrfSentForReview;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'This file is {size} MB. The limit is 10 MB.'**
  String vrfErrTooLarge(String size);

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'This file is empty. Choose another one.'**
  String get vrfErrEmpty;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Use a JPG or PNG photo.'**
  String get vrfErrFormatPhoto;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Use a JPG or PNG photo, or a PDF.'**
  String get vrfErrFormatDoc;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'This account can\'t upload these documents.'**
  String get vrfErrNotAllowed;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open that. Try another option.'**
  String get vrfErrPicker;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t upload the file. Check your connection and try again.'**
  String get vrfErrUpload;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Add: {slot}'**
  String vrfSourceTitle(String slot);

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get vrfSourceCamera;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Choose from photos'**
  String get vrfSourceGallery;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Choose a file'**
  String get vrfSourceFile;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'JPG, PNG or PDF, up to 10 MB'**
  String get vrfSourceFileHintPdf;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'JPG or PNG, up to 10 MB'**
  String get vrfSourceFileHintPhoto;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Photos must be JPG or PNG, up to 10 MB each. The commercial register can also be a PDF.'**
  String get vrfRulesOwner;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Photos must be JPG or PNG, up to 10 MB each.'**
  String get vrfRulesCourier;

  /// FE-OWNER-2b shared verification page (KYB / KYE).
  ///
  /// In en, this message translates to:
  /// **'Accepted documents can\'t be changed.'**
  String get vrfLocked;

  /// FE-OWNER-2b owner rows on the account page.
  ///
  /// In en, this message translates to:
  /// **'Your business'**
  String get acctSectionBusiness;

  /// FE-OWNER-2b owner rows on the account page.
  ///
  /// In en, this message translates to:
  /// **'Service setup'**
  String get acctServiceSetup;

  /// FE-OWNER-2b owner rows on the account page.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get acctPlan;

  /// FE-OWNER-2b owner rows on the account page.
  ///
  /// In en, this message translates to:
  /// **'Activity log'**
  String get acctActivityLog;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get ownWalletTitle;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Available to withdraw'**
  String get ownWalletAvailable;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Total balance'**
  String get ownWalletTotal;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Held for orders'**
  String get ownWalletHeld;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Add money'**
  String get ownWalletAddMoney;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get ownWalletWithdraw;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your wallet.'**
  String get ownWalletLoadError;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t refresh. These are the last balances we loaded.'**
  String get ownWalletStale;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Withdrawals'**
  String get ownWalletPayouts;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'No withdrawals yet.'**
  String get ownWalletPayoutsEmpty;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your withdrawals.'**
  String get ownWalletPayoutsError;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String ownWalletPayoutReason(String reason);

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get ownPayoutRequested;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get ownPayoutApproved;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get ownPayoutPaid;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get ownPayoutRejected;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Unknown status'**
  String get ownPayoutUnknown;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Recent money movements'**
  String get ownWalletRecent;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get ownWalletSeeAll;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'No money movements yet.'**
  String get ownWalletRecentEmpty;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get ownPlanTitle;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Your plan'**
  String get ownPlanYours;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get ownPlanFree;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get ownPlanPaid;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Under review'**
  String get ownPlanPending;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get ownPlanCancelled;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get ownPlanUnknown;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Customers can find and book your business.'**
  String get ownPlanOpen;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Customers can find and book your business. Active until {date}.'**
  String ownPlanOpenUntil(String date);

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Ended on {date}. Customers can\'t find or book your business until it\'s renewed.'**
  String ownPlanExpired(String date);

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Customers can\'t find or book your business on this plan.'**
  String get ownPlanClosed;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'We got your upgrade request. Quick Delivery will contact you to turn on the paid plan.'**
  String get ownPlanPendingNote;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'What the paid plan includes'**
  String get ownPlanIncludes;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Your business shows up for customers and takes bookings'**
  String get ownPlanFeatureListed;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Set up and change your service'**
  String get ownPlanFeatureService;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Live courier location on your orders'**
  String get ownPlanFeatureTracking;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'No commission on your orders'**
  String get ownPlanFeatureNoCommission;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Changing your plan'**
  String get ownPlanChangeTitle;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Ask for the paid plan here. Quick Delivery reviews each request and contacts you.'**
  String get ownPlanChangeBody;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get ownPlanContactSupport;

  /// FE-OWNER-2b read-only wallet and plan pages.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your plan.'**
  String get ownPlanLoadError;

  /// FE-OWNER-2b plan page: request upgrade / switch to free.
  ///
  /// In en, this message translates to:
  /// **'Request upgrade'**
  String get ownPlanRequestUpgrade;

  /// FE-OWNER-2b plan page: request upgrade / switch to free.
  ///
  /// In en, this message translates to:
  /// **'Request the paid plan?'**
  String get ownPlanUpgradeTitle;

  /// FE-OWNER-2b plan page: request upgrade / switch to free.
  ///
  /// In en, this message translates to:
  /// **'Quick Delivery will review your request and contact you.'**
  String get ownPlanUpgradeBody;

  /// FE-OWNER-2b plan page: request upgrade / switch to free.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get ownPlanUpgradeSend;

  /// FE-OWNER-2b plan page: request upgrade / switch to free.
  ///
  /// In en, this message translates to:
  /// **'Request sent. Your plan is under review.'**
  String get ownPlanUpgradeSent;

  /// FE-OWNER-2b plan page: request upgrade / switch to free.
  ///
  /// In en, this message translates to:
  /// **'Switch to free'**
  String get ownPlanDowngrade;

  /// FE-OWNER-2b plan page: request upgrade / switch to free.
  ///
  /// In en, this message translates to:
  /// **'Switch to the free plan?'**
  String get ownPlanDowngradeTitle;

  /// FE-OWNER-2b plan page: request upgrade / switch to free.
  ///
  /// In en, this message translates to:
  /// **'Customers won\'t be able to find or book your business until you\'re on the paid plan again.'**
  String get ownPlanDowngradeBodyPaid;

  /// FE-OWNER-2b plan page: request upgrade / switch to free.
  ///
  /// In en, this message translates to:
  /// **'This cancels your upgrade request.'**
  String get ownPlanDowngradeBodyPending;

  /// FE-OWNER-2b plan page: request upgrade / switch to free.
  ///
  /// In en, this message translates to:
  /// **'You\'re on the free plan now.'**
  String get ownPlanDowngraded;

  /// FE-V2-CONSUME: no maps app opened, the coordinates were copied instead.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open a maps app. Location copied: {coords}.'**
  String lnchMapsCopied(String coords);

  /// FE-V2-CONSUME: the dialer did not open, the number was copied instead.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the phone app. Number copied: {phone}.'**
  String lnchPhoneCopied(String phone);

  /// FE-V2-CONSUME courier: call button on the recipient card.
  ///
  /// In en, this message translates to:
  /// **'Call the recipient'**
  String get courCallRecipient;

  /// FE-V2-CONSUME picker: street address text field label.
  ///
  /// In en, this message translates to:
  /// **'Address · optional'**
  String get bookAddressLabel;

  /// FE-V2-CONSUME picker: street address hint.
  ///
  /// In en, this message translates to:
  /// **'Street, building, area'**
  String get bookAddressHint;

  /// FE-V2-CONSUME booking: recipient section title (delivery, shipping).
  ///
  /// In en, this message translates to:
  /// **'Who receives it?'**
  String get bookRecipientTitle;

  /// FE-V2-CONSUME booking: recipient section title for rides.
  ///
  /// In en, this message translates to:
  /// **'Who\'s riding?'**
  String get bookPassengerTitle;

  /// FE-V2-CONSUME booking: recipient toggle, default.
  ///
  /// In en, this message translates to:
  /// **'I\'m the recipient'**
  String get bookRecipientMe;

  /// FE-V2-CONSUME booking: passenger toggle, default (rides).
  ///
  /// In en, this message translates to:
  /// **'I\'m riding'**
  String get bookPassengerMe;

  /// FE-V2-CONSUME booking: recipient toggle, someone else.
  ///
  /// In en, this message translates to:
  /// **'Someone else'**
  String get bookRecipientOther;

  /// FE-V2-CONSUME booking: recipient name label.
  ///
  /// In en, this message translates to:
  /// **'Name · optional'**
  String get bookRecipientName;

  /// FE-V2-CONSUME booking: recipient name hint.
  ///
  /// In en, this message translates to:
  /// **'Who should the courier ask for?'**
  String get bookRecipientNameHint;

  /// FE-V2-CONSUME booking: passenger name hint (rides).
  ///
  /// In en, this message translates to:
  /// **'Who should the driver ask for?'**
  String get bookPassengerNameHint;

  /// FE-V2-CONSUME booking: recipient phone label.
  ///
  /// In en, this message translates to:
  /// **'Phone · optional'**
  String get bookRecipientPhone;

  /// FE-V2-CONSUME booking: recipient notes label.
  ///
  /// In en, this message translates to:
  /// **'Notes · optional'**
  String get bookRecipientNotes;

  /// FE-V2-CONSUME booking: recipient notes hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. call before you arrive'**
  String get bookRecipientNotesHint;

  /// FE-V2-CONSUME booking: recipient phone privacy helper (ADR-0028 §2.9).
  ///
  /// In en, this message translates to:
  /// **'Shared with the courier only while the order is on its way.'**
  String get bookRecipientPhoneHelp;

  /// FE-V2-CONSUME booking: package section title.
  ///
  /// In en, this message translates to:
  /// **'Package'**
  String get bookPackageTitle;

  /// FE-V2-CONSUME booking: package size chips label.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get bookPackageSize;

  /// FE-V2-CONSUME: package size not set.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get bookSizeNone;

  /// FE-V2-CONSUME: package size small.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get bookSizeSmall;

  /// FE-V2-CONSUME: package size medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get bookSizeMedium;

  /// FE-V2-CONSUME: package size large.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get bookSizeLarge;

  /// FE-V2-CONSUME booking: package notes label.
  ///
  /// In en, this message translates to:
  /// **'Package notes · optional'**
  String get bookPackageNotes;

  /// FE-V2-CONSUME booking: package notes hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. fragile, handle with care'**
  String get bookPackageNotesHint;

  /// FE-V2-CONSUME booking: package size is informational (ADR-0028 §2.7).
  ///
  /// In en, this message translates to:
  /// **'The size doesn\'t change the price.'**
  String get bookPackageNoPrice;

  /// FE-V2-CONSUME booking: field too long.
  ///
  /// In en, this message translates to:
  /// **'Use at most {max} characters.'**
  String bookErrTooLong(int max);

  /// FE-V2-CONSUME booking: a stop's address text is too long.
  ///
  /// In en, this message translates to:
  /// **'An address is too long. Use at most {max} characters.'**
  String bookErrAddressTooLong(int max);

  /// FE-V2-CONSUME booking: a stop's landmark note is too long for the server.
  ///
  /// In en, this message translates to:
  /// **'A landmark note is too long. Shorten it and try again.'**
  String get bookErrNoteTooLong;

  /// FE-V2-CONSUME booking: invalid recipient phone.
  ///
  /// In en, this message translates to:
  /// **'Enter an Egyptian mobile number like 01012345678, or an international number with its country code.'**
  String get bookErrPhone;

  /// FE-V2-CONSUME booking: invalid package size.
  ///
  /// In en, this message translates to:
  /// **'Choose small, medium or large.'**
  String get bookErrSize;

  /// FE-V2-CONSUME booking: banner when a field has an error.
  ///
  /// In en, this message translates to:
  /// **'Check the highlighted fields.'**
  String get bookFixFields;

  /// FE-V2-CONSUME timeline: picked-up step (delivery, shipping).
  ///
  /// In en, this message translates to:
  /// **'The courier picked up the order'**
  String get tlPickedUp;

  /// FE-V2-CONSUME timeline: picked-up step (rides).
  ///
  /// In en, this message translates to:
  /// **'The driver picked you up'**
  String get tlPickedUpRide;

  /// FE-V2-CONSUME owner timeline: picked-up step (rides).
  ///
  /// In en, this message translates to:
  /// **'The driver picked up the passenger'**
  String get tlPickedUpRideOwner;

  /// FE-V2-CONSUME timeline: last step for rides.
  ///
  /// In en, this message translates to:
  /// **'Arrived'**
  String get tlArrived;

  /// FE-V2-CONSUME timeline: cancelled step.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get tlCancelled;

  /// FE-V2-CONSUME timeline: unavailable step.
  ///
  /// In en, this message translates to:
  /// **'No courier was free'**
  String get tlUnavailable;

  /// FE-V2-CONSUME owner timeline: first step.
  ///
  /// In en, this message translates to:
  /// **'Customer ordered'**
  String get tlOwnRequested;

  /// FE-V2-CONSUME owner timeline: accepted step with the courier's name.
  ///
  /// In en, this message translates to:
  /// **'{name} accepted'**
  String tlOwnAccepted(String name);

  /// FE-V2-CONSUME customer: sub_status heading_to_pickup (delivery, shipping).
  ///
  /// In en, this message translates to:
  /// **'The courier is on the way to pick up your order'**
  String get phaseToPickup;

  /// FE-V2-CONSUME customer: sub_status heading_to_pickup (rides).
  ///
  /// In en, this message translates to:
  /// **'The driver is on the way to pick you up'**
  String get phaseToPickupRide;

  /// FE-V2-CONSUME customer: sub_status picked_up (delivery, shipping).
  ///
  /// In en, this message translates to:
  /// **'On the way to you'**
  String get phasePickedUp;

  /// FE-V2-CONSUME customer: sub_status picked_up (rides).
  ///
  /// In en, this message translates to:
  /// **'On the way to your destination'**
  String get phasePickedUpRide;

  /// FE-V2-CONSUME owner: sub_status chip heading_to_pickup.
  ///
  /// In en, this message translates to:
  /// **'Going to pickup'**
  String get phaseChipToPickup;

  /// FE-V2-CONSUME owner: sub_status chip heading_to_pickup (rides).
  ///
  /// In en, this message translates to:
  /// **'Going to passenger'**
  String get phaseChipToPickupRide;

  /// FE-V2-CONSUME owner: sub_status chip picked_up.
  ///
  /// In en, this message translates to:
  /// **'Picked up'**
  String get phaseChipPickedUp;

  /// FE-V2-CONSUME owner: sub_status chip picked_up (rides).
  ///
  /// In en, this message translates to:
  /// **'Passenger on board'**
  String get phaseChipPickedUpRide;

  /// FE-V2-CONSUME: ETA to the drop-off.
  ///
  /// In en, this message translates to:
  /// **'Arrives around {time}'**
  String etaAround(String time);

  /// FE-V2-CONSUME: ETA to the pickup.
  ///
  /// In en, this message translates to:
  /// **'At the pickup around {time}'**
  String etaPickupAround(String time);

  /// FE-V2-CONSUME: ETA to the passenger (rides).
  ///
  /// In en, this message translates to:
  /// **'Picks you up around {time}'**
  String etaPickupAroundRide(String time);

  /// FE-V2-CONSUME: ETA already passed, to the drop-off.
  ///
  /// In en, this message translates to:
  /// **'Should arrive any minute'**
  String get etaSoon;

  /// FE-V2-CONSUME: ETA already passed, to the pickup.
  ///
  /// In en, this message translates to:
  /// **'Should reach the pickup any minute'**
  String get etaPickupSoon;

  /// FE-V2-CONSUME order: recipient row label.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get ordRecipient;

  /// FE-V2-CONSUME order: recipient row label (rides).
  ///
  /// In en, this message translates to:
  /// **'Passenger'**
  String get ordPassenger;

  /// FE-V2-CONSUME order: package row label.
  ///
  /// In en, this message translates to:
  /// **'Package'**
  String get ordPackage;

  /// FE-V2-CONSUME customer: call button on the courier card.
  ///
  /// In en, this message translates to:
  /// **'Call the courier'**
  String get ordCallCourier;

  /// FE-V2-CONSUME owner Today: every completed order has a delivery time (status_history).
  ///
  /// In en, this message translates to:
  /// **'Delivered and cash count the orders delivered today.'**
  String get ownTodayNoteDelivered;

  /// FE-V2-CONSUME owner Today: some completed orders have no delivery time (legacy).
  ///
  /// In en, this message translates to:
  /// **'Delivered and cash count the orders delivered today. Older orders without a delivery time count on the day they were placed.'**
  String get ownTodayNoteMixed;

  /// FE-V2-CONSUME owner order detail: delivery time row.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get ownRowDelivered;

  /// FE-V2-CONSUME owner order detail: ETA row label.
  ///
  /// In en, this message translates to:
  /// **'Estimate'**
  String get ownRowEta;

  /// FE-V2-CONSUME owner order detail: call the recipient.
  ///
  /// In en, this message translates to:
  /// **'Call the recipient'**
  String get ownCallRecipient;

  /// FE-V2-CONSUME owner order detail: call the courier.
  ///
  /// In en, this message translates to:
  /// **'Call the courier'**
  String get ownCallCourier;

  /// FE-V2-CONSUME owner order detail: timeline section title.
  ///
  /// In en, this message translates to:
  /// **'Order steps'**
  String get ownTimelineTitle;

  /// FE-CLEANUP notifications: owner, cancellation requested.
  ///
  /// In en, this message translates to:
  /// **'A courier asked to cancel a job'**
  String get ntfCancelRequestedTitle;

  /// FE-CLEANUP notifications: owner, cancellation request expired.
  ///
  /// In en, this message translates to:
  /// **'A cancellation request ran out'**
  String get ntfCancelExpiredTitle;

  /// FE-CLEANUP notifications: courier, owner answered the cancellation request.
  ///
  /// In en, this message translates to:
  /// **'Your cancellation request was answered'**
  String get ntfCancelResolvedTitle;

  /// FE-CLEANUP notifications: courier, job offer.
  ///
  /// In en, this message translates to:
  /// **'New job offer'**
  String get ntfJobOfferTitle;

  /// FE-CLEANUP notifications: courier, job offer body.
  ///
  /// In en, this message translates to:
  /// **'Answer it from the Task tab before the time runs out.'**
  String get ntfJobOfferBody;

  /// FE-CLEANUP notifications: courier, dispatch alert.
  ///
  /// In en, this message translates to:
  /// **'New job'**
  String get ntfJobAlertTitle;

  /// FE-CLEANUP notifications: owner / courier, verification approved.
  ///
  /// In en, this message translates to:
  /// **'Your verification was approved'**
  String get ntfKycApprovedTitle;

  /// FE-CLEANUP notifications: owner / courier, verification rejected.
  ///
  /// In en, this message translates to:
  /// **'Your verification wasn\'t accepted'**
  String get ntfKycRejectedTitle;

  /// FE-CLEANUP verification-rejected dialog: opens the verification page.
  ///
  /// In en, this message translates to:
  /// **'Fix my documents'**
  String get vrfRejectedOpen;

  /// FE-CLEANUP update-required page: opens the download link.
  ///
  /// In en, this message translates to:
  /// **'Download the update'**
  String get updDownload;

  /// FE-CLEANUP page for a signed-in role the app has no screens for.
  ///
  /// In en, this message translates to:
  /// **'This account can\'t use the app'**
  String get roleUnsupportedTitle;

  /// FE-CLEANUP page for a signed-in role the app has no screens for.
  ///
  /// In en, this message translates to:
  /// **'Sign in with a customer, business or courier account. Staff accounts use the web console.'**
  String get roleUnsupportedBody;

  /// FE-BE-GAPS item 1: photo source sheet title.
  ///
  /// In en, this message translates to:
  /// **'Service photo'**
  String get ownSvcPhotoSheetTitle;

  /// FE-BE-GAPS item 1.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get ownSvcPhotoAdd;

  /// FE-BE-GAPS item 1.
  ///
  /// In en, this message translates to:
  /// **'Change photo'**
  String get ownSvcPhotoReplace;

  /// FE-BE-GAPS item 1.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get ownSvcPhotoRemove;

  /// FE-BE-GAPS item 1.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get ownSvcPhotoCamera;

  /// FE-BE-GAPS item 1.
  ///
  /// In en, this message translates to:
  /// **'Choose from photos'**
  String get ownSvcPhotoGallery;

  /// FE-BE-GAPS item 1: upload progress.
  ///
  /// In en, this message translates to:
  /// **'Uploading… {percent}%'**
  String ownSvcPhotoUploading(int percent);

  /// FE-BE-GAPS item 1: uploaded before the service exists.
  ///
  /// In en, this message translates to:
  /// **'Photo ready. It is added to your service when you tap Save.'**
  String get ownSvcPhotoPending;

  /// FE-BE-GAPS item 1: 503 / storage not ready.
  ///
  /// In en, this message translates to:
  /// **'Photo upload is unavailable right now. Try again later.'**
  String get ownSvcPhotoErrUnavailable;

  /// FE-BE-GAPS item 1.
  ///
  /// In en, this message translates to:
  /// **'Use a JPEG or PNG photo.'**
  String get ownSvcPhotoErrFormat;

  /// FE-BE-GAPS item 1.
  ///
  /// In en, this message translates to:
  /// **'This photo is over 5 MB. Choose a smaller one.'**
  String get ownSvcPhotoErrTooLarge;

  /// FE-BE-GAPS item 1: server 400.
  ///
  /// In en, this message translates to:
  /// **'This photo couldn\'t be used. Try another one.'**
  String get ownSvcPhotoErrRejected;

  /// FE-BE-GAPS item 1.
  ///
  /// In en, this message translates to:
  /// **'The photo wasn\'t uploaded. Check your connection and try again.'**
  String get ownSvcPhotoErrNetwork;

  /// FE-BE-GAPS item 1.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t remove the photo. Try again.'**
  String get ownSvcPhotoErrRemove;

  /// FE-BE-GAPS item 3: saved address label chooser.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get addrLabelTitle;

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get addrLabelHome;

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get addrLabelWork;

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get addrLabelOther;

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'Name this place'**
  String get addrLabelCustom;

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'e.g. Mum\'s house, the gym'**
  String get addrLabelCustomHint;

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'Place on the map'**
  String get addrPin;

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get addrPinMissing;

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'Pinned on the map'**
  String get addrPinSet;

  /// FE-BE-GAPS item 3: picker title.
  ///
  /// In en, this message translates to:
  /// **'Pin the place'**
  String get addrPinTitle;

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'Choose or write a name'**
  String get addrErrLabel;

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'Use at most {max} characters'**
  String addrErrTooLong(int max);

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'Pin the place on the map'**
  String get addrErrPin;

  /// FE-BE-GAPS item 3: old string-only addresses.
  ///
  /// In en, this message translates to:
  /// **'Not on the map yet'**
  String get addrLegacyTitle;

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'These older addresses have no map pin. Pin one to use it when you book.'**
  String get addrLegacyBody;

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'Pin it'**
  String get addrLegacyPin;

  /// FE-BE-GAPS item 3: button semantics.
  ///
  /// In en, this message translates to:
  /// **'Pin {address} on the map'**
  String addrLegacyPinFor(String address);

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'Older addresses will be removed'**
  String get addrDropLegacyTitle;

  /// FE-BE-GAPS item 3: the server rebuilds frequent_addresses from saved_addresses.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 older address without a map pin will be removed when you save. Pin it first to keep it.} other{{count} older addresses without a map pin will be removed when you save. Pin them first to keep them.}}'**
  String addrDropLegacyBody(int count);

  /// FE-BE-GAPS item 3.
  ///
  /// In en, this message translates to:
  /// **'Save anyway'**
  String get addrDropLegacyConfirm;

  /// FE-BE-GAPS item 3: picker list.
  ///
  /// In en, this message translates to:
  /// **'Saved places'**
  String get custSavedPlaces;

  /// FE-BE-GAPS item 3: legacy string chosen in the picker.
  ///
  /// In en, this message translates to:
  /// **'No map pin yet: move the map to it, then confirm'**
  String get custSavedNeedsPin;

  /// FE-BE-GAPS item 3: chip semantics.
  ///
  /// In en, this message translates to:
  /// **'Use {label}: {address}'**
  String custSavedUse(String label, String address);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
