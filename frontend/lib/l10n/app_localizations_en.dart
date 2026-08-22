// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get submit => 'Submit';

  @override
  String get confirm => 'Confirm';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

  @override
  String get search => 'Search';

  @override
  String get loading => 'Loading...';

  @override
  String get comingSoon => 'Coming Soon';

  @override
  String get navHome => 'Home';

  @override
  String get navServices => 'Services';

  @override
  String get navHistory => 'History';

  @override
  String get navSettings => 'Settings';

  @override
  String get navEmployees => 'Employees';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'System';

  @override
  String get langAuto => 'Auto (System)';

  @override
  String get langEnglish => 'English';

  @override
  String get langArabic => 'العربية (مصر)';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsAppearanceSub => 'Customize application look and feel';

  @override
  String get settingsThemeMode => 'Theme Mode';

  @override
  String get settingsPreferences => 'Preferences';

  @override
  String get settingsPreferencesSub => 'App display and regional options';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsAccountSection => 'Account';

  @override
  String get settingsAccountSectionSub => 'Profile and user details';

  @override
  String get settingsMyAccount => 'My Account';

  @override
  String get settingsMyAccountSub => 'Account details & preferences';

  @override
  String get settingsOwnerConfig => 'Owner Configuration';

  @override
  String get settingsOwnerConfigSub => 'Business management settings';

  @override
  String get settingsSupport => 'Support & Help';

  @override
  String get settingsSupportSub => 'Get assistance or submit issues';

  @override
  String get settingsCustomerService => 'Customer Service';

  @override
  String get settingsCustomerServiceSub =>
      'Contact support & submit complaint tickets';

  @override
  String get settingsLogout => 'LOG OUT';

  @override
  String get myAccountTitle => 'My Account';

  @override
  String get myAccountHeader => 'Account Details';

  @override
  String get myAccountHeaderSub =>
      'Manage personal details and saved addresses';

  @override
  String get myAccountEmailLabel => 'Email Address (Read-Only)';

  @override
  String get myAccountEmailHint => 'Your email address';

  @override
  String get myAccountEmailNote =>
      'Your email address can be updated via OTP verification.';

  @override
  String get changeEmailButton => 'Change Email';

  @override
  String get enterNewEmailPrompt =>
      'Enter your new email address. A verification code will be sent to it.';

  @override
  String get newEmailLabel => 'New Email Address';

  @override
  String get sendVerificationCode => 'Send Code';

  @override
  String get confirmEmailChangeButton => 'Verify & Update Email';

  @override
  String get emailChangeSuccess => 'Email address updated successfully';

  @override
  String get invalidEmailError => 'Please enter a valid email address';

  @override
  String get enterOtpPrompt =>
      'Enter the 6-digit verification code sent to your new email.';

  @override
  String get myAccountUsernameLabel => 'Username';

  @override
  String get myAccountUsernameHint => 'Enter username';

  @override
  String get myAccountUsernameReq => 'Username is required.';

  @override
  String get myAccountPhoneLabel => 'Phone Number';

  @override
  String get myAccountPhoneHint => '+201012345678';

  @override
  String get myAccountAddressesHeader => 'Frequent Addresses';

  @override
  String get myAccountAddressesSub =>
      'Save quick locations for faster booking (max 10).';

  @override
  String get myAccountNewAddressLabel => 'New Address';

  @override
  String get myAccountNewAddressHint => 'e.g. 123 Nile St, Cairo';

  @override
  String get myAccountAddButton => 'ADD';

  @override
  String get myAccountNoAddresses => 'No saved addresses yet.';

  @override
  String get myAccountMaxAddressesError =>
      'Cannot add more than 10 frequent addresses.';

  @override
  String get myAccountSaveButton => 'SAVE PROFILE';

  @override
  String get myAccountSuccessMsg => 'Profile updated successfully';

  @override
  String get ownerConfigTitle => 'Owner Configuration';

  @override
  String get ownerConfigHeader => 'Business Details';

  @override
  String get ownerConfigHeaderSub =>
      'Update business parameters and service terms';

  @override
  String get ownerConfigNameLabel => 'Business Name';

  @override
  String get ownerConfigNameHint => 'e.g. Quick Delivery Services';

  @override
  String get ownerConfigNameReq => 'Business name is required.';

  @override
  String get ownerConfigCategoryLabel => 'Category';

  @override
  String get ownerConfigAddressLabel => 'Address';

  @override
  String get ownerConfigAddressHint => 'e.g. 456 Nile St, Cairo';

  @override
  String get ownerConfigHoursLabel => 'Working Hours';

  @override
  String get ownerConfigHoursHint => 'e.g. 8:00 AM - 10:00 PM';

  @override
  String get ownerConfigRadiusLabel => 'Coverage Radius (KM)';

  @override
  String get ownerConfigRadiusHint => 'e.g. 25.0';

  @override
  String get ownerConfigRadiusReq => 'Enter a valid radius > 0.';

  @override
  String get ownerConfigBasePriceLabel => 'Base Price (\$)';

  @override
  String get ownerConfigBasePriceHint => 'e.g. 10.00';

  @override
  String get ownerConfigBasePriceReq => 'Base price must be >= 0.';

  @override
  String get ownerConfigPricePerKmLabel => 'Price per KM (\$)';

  @override
  String get ownerConfigPricePerKmHint => 'e.g. 1.50';

  @override
  String get ownerConfigPricePerKmReq => 'Price per KM must be >= 0.';

  @override
  String get ownerConfigPhotoUrlLabel => 'Photo URL';

  @override
  String get ownerConfigPhotoUrlHint => 'https://example.com/logo.png';

  @override
  String get ownerConfigLocationLabel => 'Business Location';

  @override
  String get ownerConfigLocationReq =>
      'Please select your business location on the map.';

  @override
  String get customerMarketplaceFilterNearby => 'Nearby Only';

  @override
  String get ownerConfigSaveButton => 'SAVE CONFIGURATION';

  @override
  String get ownerConfigSuccessMsg =>
      'Owner configuration updated successfully';

  @override
  String get loginTitle => 'Welcome Back';

  @override
  String get loginSubtitle => 'Log in to manage your services';

  @override
  String get loginEmailLabel => 'Email Address';

  @override
  String get loginEmailHint => 'name@example.com';

  @override
  String get loginEmailReq => 'Email is required.';

  @override
  String get loginEmailInvalid => 'Enter a valid email address.';

  @override
  String get loginPasswordLabel => 'Password';

  @override
  String get loginPasswordHint => 'Enter your password';

  @override
  String get loginPasswordReq => 'Password is required.';

  @override
  String get loginSubmitButton => 'SIGN IN';

  @override
  String get loginForgotPassword => 'Forgot password?';

  @override
  String get loginNoAccount => 'Don\'t have an account?';

  @override
  String get loginSignUp => 'Sign Up';

  @override
  String get signupTitle => 'Create Account';

  @override
  String get signupSubtitle => 'Join Quick Delivery today';

  @override
  String get signupUsernameLabel => 'Username';

  @override
  String get signupUsernameHint => 'johndoe';

  @override
  String get signupUsernameReq => 'Please enter a username';

  @override
  String get signupEmailLabel => 'Email Address';

  @override
  String get signupEmailHint => 'name@example.com';

  @override
  String get signupPasswordLabel => 'Password';

  @override
  String get signupPasswordHint => 'At least 6 characters';

  @override
  String get signupConfirmPasswordLabel => 'Confirm Password';

  @override
  String get signupConfirmPasswordHint => 'Re-enter password';

  @override
  String get signupPasswordMismatch => 'Passwords do not match.';

  @override
  String get signupRoleLabel => 'Account Type';

  @override
  String get signupRoleCustomer => 'Customer';

  @override
  String get signupRoleOwner => 'Business Owner';

  @override
  String get signupSubmitButton => 'CREATE ACCOUNT';

  @override
  String get signupHasAccount => 'Already have an account?';

  @override
  String get signupSignIn => 'Sign In';

  @override
  String get otpTitle => 'Two-Factor Verification';

  @override
  String get otpSubtitle => 'Enter the 6-digit code sent to your email';

  @override
  String get otpCodeLabel => '6-Digit OTP Code';

  @override
  String get otpSubmitButton => 'VERIFY CODE';

  @override
  String get otpResendButton => 'RESEND CODE';

  @override
  String get forgotPasswordTitle => 'Reset Password';

  @override
  String get forgotPasswordSubtitle => 'Enter your email and new credentials';

  @override
  String get forgotPasswordSubmitButton => 'RESET PASSWORD';

  @override
  String get customerHomeGreeting => 'Welcome back,';

  @override
  String get customerHomeSub => 'What service do you need today?';

  @override
  String get customerHomeQuickAccess => 'Services';

  @override
  String get customerHomeCatDelivery => 'Delivery';

  @override
  String get customerHomeCatRide => 'Ride';

  @override
  String get customerHomeCatShipping => 'Shipping';

  @override
  String get customerHomeCatBrowseAll => 'Browse All';

  @override
  String get customerHomeRecentActivity => 'Recent Activity';

  @override
  String get customerHomeQuickBookBanner => 'Need a quick delivery?';

  @override
  String get customerHomeQuickBookBtn => 'BOOK NOW';

  @override
  String get customerMarketplaceTitle => 'Explore Services';

  @override
  String get customerMarketplaceSearchHint => 'Search services...';

  @override
  String get customerMarketplaceFilterCategory => 'Category';

  @override
  String get customerMarketplaceFilterRadius => 'Max Distance (KM)';

  @override
  String get customerMarketplaceChooseMap => 'Choose Location on Map';

  @override
  String get customerMarketplaceBookBtn => 'BOOK SERVICE';

  @override
  String get customerMarketplaceCodNote =>
      'Note: COD (Cash on Delivery) is enforced during beta.';

  @override
  String get customerJobsTitle => 'My Orders';

  @override
  String get customerJobsSub => 'Track and manage your delivery history.';

  @override
  String get customerJobsSearchHint => 'Search by Order ID, Location...';

  @override
  String get customerJobsInvoiceAvailable => 'Invoice Available';

  @override
  String get customerJobsInTransit => 'In Transit';

  @override
  String get customerJobsOrderPlaced => 'Order Placed';

  @override
  String get customerJobsPayment => 'Payment';

  @override
  String get customerJobsPrice => 'Price';

  @override
  String get customerJobsReason => 'Reason';

  @override
  String get customerJobsOrder => 'Order #';

  @override
  String get customerJobsEmpty => 'No Orders Found';

  @override
  String get customerJobsEmptyDescription =>
      'You haven\'t placed any orders yet. Explore services in the marketplace to get started.';

  @override
  String get customerJobsViewDetails => 'View Details';

  @override
  String get jobStatusTitle => 'Order Status';

  @override
  String get jobStatusPending => 'Pending';

  @override
  String get jobStatusActive => 'Active';

  @override
  String get jobStatusCompleted => 'Completed';

  @override
  String get jobStatusCancelled => 'Cancelled';

  @override
  String get jobStatusCancelBtn => 'Cancel Order';

  @override
  String get jobStatusOpenTicketBtn => 'Open Complaint Ticket';

  @override
  String get jobStatusCounterOfferTitle => 'Price Counter-Offer';

  @override
  String get jobStatusCounterOfferSubmit => 'Propose Counter Price';

  @override
  String get ownerHomeGreeting => 'Dashboard';

  @override
  String get ownerHomeKycAlert =>
      'Your KYC verification is pending admin approval.';

  @override
  String get ownerHomeMetricsWallet => 'Wallet Balance';

  @override
  String get ownerHomeMetricsSubscription => 'Subscription Tier';

  @override
  String get ownerHomeEntryWallet => 'Manage Wallet';

  @override
  String get ownerHomeEntryService => 'Service Configuration';

  @override
  String get ownerHistoryTitle => 'History & Audit Logs';

  @override
  String get ownerHistoryTabAudit => 'Audit Log';

  @override
  String get ownerHistoryTabJobs => 'Jobs';

  @override
  String get ownerHistoryTabLedger => 'Ledger';

  @override
  String get ownerFleetMapTitle => 'Fleet Map';

  @override
  String get customerJobMapTitle => 'Live Tracking';

  @override
  String get employeeJobsTitle => 'Assigned Jobs';

  @override
  String get employeeJobsCompleteBtn => 'Complete Job';

  @override
  String get employeeJobsVerifyDocsBtn => 'KYC Documents';

  @override
  String get employeeJobsChatBtn => 'Chat with Customer';

  @override
  String get employeeJobsCashConfirmTitle => 'Confirm Cash Collection';

  @override
  String get employeeJobsCashConfirmMsg =>
      'Did you collect cash from the customer for this COD job?';

  @override
  String get employeeScreenTitle => 'Manage Workers';

  @override
  String get employeeRegisterHeader => 'Register New Worker';

  @override
  String get employeeFreezeBtn => 'Freeze';

  @override
  String get employeeUnfreezeBtn => 'Activate';

  @override
  String get chatTitle => 'Job Chat';

  @override
  String get chatTypeHint => 'Type a message...';

  @override
  String get chatSendBtn => 'Send';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsAll => 'All';

  @override
  String get notificationsJobs => 'Jobs';

  @override
  String get notificationsSystem => 'System';

  @override
  String get notificationsAlerts => 'Alerts';

  @override
  String get notificationsClear => 'Clear All';

  @override
  String get kycTitle => 'Document Verification';

  @override
  String get kycRejectionBanner => 'Your documents were rejected. Reason:';

  @override
  String get kycApprovedBadge => 'Approved';

  @override
  String get kybKyeReviewTitle => 'KYC Review Queue';

  @override
  String get kybKyeApproveBtn => 'Approve';

  @override
  String get kybKyeRejectBtn => 'Reject';

  @override
  String get walletTitle => 'Owner Wallet';

  @override
  String get walletTotalBalance => 'Total Balance';

  @override
  String get walletWithdrawable => 'Withdrawable';

  @override
  String get walletEscrow => 'In Escrow';

  @override
  String get walletDepositBtn => 'Deposit Funds';

  @override
  String get reconciliationTitle => 'Escrow Reconciliation';

  @override
  String get reconciliationReleaseBtn => 'Release Funds';

  @override
  String get reconciliationRefundBtn => 'Refund Customer';

  @override
  String get ratingTitle => 'Rate Service';

  @override
  String get ratingSubmitBtn => 'SUBMIT RATING';

  @override
  String get subscriptionTitle => 'Subscription Plans';

  @override
  String get subscriptionFree => 'Free Tier';

  @override
  String get subscriptionPro => 'Professional Tier';

  @override
  String get locationPickerTitle => 'Choose Location on Map';

  @override
  String get locationPickerUseMyLocation => 'Use My Location';

  @override
  String get locationPickerConfirmBtn => 'Confirm Location';

  @override
  String get ticketSubjectReq => 'Subject is required.';

  @override
  String get ticketDescriptionReq => 'Issue details are required.';

  @override
  String get liveCourierTracking => 'Live Courier Tracking';

  @override
  String get subscriptionPlansTitle => 'Subscription Plans';

  @override
  String get fleetLiveMapTitle => 'Fleet Live Map';

  @override
  String get pendingKybKyeSubmissions => 'Pending KYB/KYE Submissions';

  @override
  String reviewCompletedSuccess(String username) {
    return 'Review completed successfully for $username.';
  }

  @override
  String get reconciliationReviewTitle => 'Escrow Reconciliation Review';

  @override
  String get tooltipRefreshQueue => 'Refresh Queue';

  @override
  String get reconciliationEmptyTitle => 'No jobs pending reconciliation';

  @override
  String get reconciliationEmptyDesc =>
      'All escrow transactions are healthy. No flagged jobs require manual review.';

  @override
  String get reconciliationFailureReason => 'Failure Reason';

  @override
  String get reconciliationNote => 'Note';

  @override
  String get reconciliationLockedEscrow => 'Locked Escrow';

  @override
  String get reconciliationEmployeeId => 'Employee ID';

  @override
  String get reconciliationCustomerId => 'Customer ID';

  @override
  String get reconciliationServiceId => 'Service ID';

  @override
  String get reconciliationRefundCustomer => 'Refund to Customer';

  @override
  String get reconciliationReleaseEmployee => 'Release to Employee';

  @override
  String reconciliationConfirmTitle(String actionLabel) {
    return 'Confirm $actionLabel';
  }

  @override
  String reconciliationConfirmMessage(
      String actionLabel, String jobId, String amount, String targetRole) {
    return 'Are you sure you want to $actionLabel for Job #$jobId?\n\nThis will transfer $amount Credits back to the $targetRole. Real funds will be moved.';
  }

  @override
  String get reconciliationSuccessRelease =>
      'Escrow resolved: funds released to employee/tenant';

  @override
  String get reconciliationSuccessRefund =>
      'Escrow resolved: funds refunded to customer';

  @override
  String get reconciliationFailed => 'Failed to resolve reconciliation';

  @override
  String get roleEmployeeTenant => 'employee/tenant';

  @override
  String get roleCustomer => 'customer';

  @override
  String get docViewerTitle => 'Document Viewer';

  @override
  String get docTabIdFront => 'Front ID';

  @override
  String get docTabIdBack => 'Back ID';

  @override
  String get docTabSelfie => 'Selfie';

  @override
  String get docTabBusinessProof => 'Business Proof';

  @override
  String get docLoadingPreview => 'Loading document preview...';

  @override
  String get docNotProvided => 'Document not provided for this submission.';

  @override
  String get docFailedLoad => 'Failed to load document preview';

  @override
  String get docPdfPreviewTitle => 'PDF Document Preview';

  @override
  String docFileSize(int size) {
    return 'File Size: $size bytes';
  }

  @override
  String get docDecodeError => 'Failed to decode image bytes.';

  @override
  String get docNoDocument => 'No document loaded.';

  @override
  String get docRejectionReasonLabel => 'Rejection Reason / Notes';

  @override
  String get docRejectionReasonHint =>
      'Explain why this submission is being rejected...';

  @override
  String get docRejectionReasonReq => 'Rejection reason is required.';

  @override
  String get docConfirmReject => 'Confirm Reject';

  @override
  String chatFailedSend(String error) {
    return 'Failed to send message: $error';
  }

  @override
  String get filterSortPrice => 'Price';

  @override
  String get filterSortNone => 'None';

  @override
  String bookingFailed(String error) {
    return 'Booking Failed: $error';
  }

  @override
  String actionLoggedSuccess(String action) {
    return 'Action logged successfully: \"$action\"';
  }

  @override
  String get jobMarkedCompletedSuccess =>
      'Job marked as completed successfully!';

  @override
  String get quickDeliveryDashboard => 'Quick Delivery Dashboard';

  @override
  String get forgotPasswordSentMsg =>
      'A password reset code has been sent if an account exists.';

  @override
  String get counterOfferSuccessMsg => 'Counter-offer submitted successfully!';

  @override
  String get kycTakeCamera => 'Take Photo with Camera';

  @override
  String get kycChooseGallery => 'Choose Image from Gallery';

  @override
  String get kycSelectPdf => 'Select PDF Document';

  @override
  String get otpResendSuccessMsg =>
      'A new OTP code has been sent successfully.';

  @override
  String get ratingIdentityError =>
      'Error: Cannot determine other party identity.';

  @override
  String get ratingSuccessMsg => 'Blind rating submitted successfully!';

  @override
  String ratingFailed(String error) {
    return 'Error: $error';
  }

  @override
  String get unauthenticatedMsg => 'Unauthenticated';

  @override
  String get serviceCreatedSuccess => 'Service created successfully!';

  @override
  String serviceCreateFailed(String error) {
    return 'Failed to create service: $error';
  }

  @override
  String cancelJobHeader(String jobId) {
    return 'Cancel Job #$jobId';
  }

  @override
  String get cancelJobKeep => 'Keep Job';

  @override
  String get cancelJobConfirm => 'Confirm Cancel';

  @override
  String get locationPermissionDeniedDefault =>
      'Location permission denied. Defaulting to Cairo.';

  @override
  String locationFetchError(String error) {
    return 'Error fetching location: $error';
  }

  @override
  String get settingsKycRowTitle => 'Identity Verification (KYC)';

  @override
  String get settingsKycSubtitleDefault =>
      'Verify your account identity and documents';

  @override
  String get settingsKycSubtitleRejected =>
      'Verification Rejected - Action Required';

  @override
  String get settingsKycSubtitlePending => 'Verification Pending Approval';

  @override
  String get ownerHomeTabTitleDashboard => 'Quick Delivery Owner Dashboard';

  @override
  String get ownerHomeTabTitleWorkers => 'Manage Workers';

  @override
  String get ownerHomeTabTitleHistory => 'History & Audit Logs';

  @override
  String ownerHomeWelcomeUser(String name) {
    return 'Welcome back, $name!';
  }

  @override
  String ownerHomeAccountId(String id) {
    return 'Account ID: $id';
  }

  @override
  String get ownerHomeProfileInfo => 'Profile Information';

  @override
  String get ownerHomeLabelUsername => 'Username';

  @override
  String get ownerHomeLabelEmail => 'Email';

  @override
  String get ownerHomeLabelRole => 'Role';

  @override
  String get ownerHomeTooltipReviewQueue => 'KYB/KYE Review Queue';

  @override
  String get ownerHomeTooltipEscrowReconciliation => 'Escrow Reconciliation';

  @override
  String get ownerHomeTooltipNotifications => 'Notifications';

  @override
  String get ownerHomeTooltipSettings => 'Settings';

  @override
  String get ownerHomeNavHome => 'Home';

  @override
  String get ownerHomeNavEmployees => 'Employees';

  @override
  String get ownerHomeNavHistory => 'History';

  @override
  String get ownerHomeNavSettings => 'Settings';

  @override
  String ownerHomeTenantId(String id) {
    return 'Tenant Owner ID: $id';
  }

  @override
  String ownerHomeCreditsAmount(String amount) {
    return '$amount Credits';
  }

  @override
  String get ownerHomeSubTitle => 'Subscription';

  @override
  String get ownerHomeRosterTitle => 'Roster';

  @override
  String get ownerHomeEmployeesSub => 'Employees';

  @override
  String get ownerHomeEscrowTitle => 'Escrow';

  @override
  String get ownerHomeReviewQueueSub => 'Review Queue';

  @override
  String get ownerHomeMyWallet => 'My Wallet';

  @override
  String get ownerHomeWalletSub => 'Ledger & balance';

  @override
  String get ownerHomeServices => 'Services';

  @override
  String get ownerHomeServicesSub => 'Rates & config';

  @override
  String get ownerHomeServiceReputation => 'Your Service Reputation';

  @override
  String get ownerHomeOwnerJobs => 'Owner Jobs';

  @override
  String get ownerHomeNoJobsTitle => 'No Owner Jobs Found';

  @override
  String get ownerHomeNoJobsDesc =>
      'You currently have no jobs registered under your tenant account.';

  @override
  String ownerHomeJobId(String id) {
    return 'Job #$id';
  }

  @override
  String ownerHomePaymentInfo(String method, String escrowInfo) {
    return 'Payment: $method$escrowInfo';
  }

  @override
  String get ownerHomeCancelJob => 'Cancel Job';

  @override
  String get ownerHomeJobCancelledEscrowRefunded =>
      'Job cancelled successfully. Escrow refunded to wallet.';

  @override
  String get ownerHomeJobCancelled => 'Job cancelled successfully.';

  @override
  String get ownerHistoryTabActivity => 'Activity';

  @override
  String get ownerHistoryNoActivityTitle => 'No Employee Activity Found';

  @override
  String get ownerHistoryNoActivityDesc =>
      'No tenant audit log events recorded yet.';

  @override
  String ownerHistoryActorId(String id) {
    return 'Actor: $id';
  }

  @override
  String get ownerHistoryNoJobsTitle => 'No Completed Jobs Found';

  @override
  String get ownerHistoryNoJobsDesc =>
      'No completed or cancelled jobs recorded for your tenant.';

  @override
  String ownerHistoryCancellationReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get ownerHistoryNoLedgerTitle => 'No Ledger Entries Found';

  @override
  String get ownerHistoryNoLedgerDesc =>
      'No wallet transaction history recorded yet.';

  @override
  String ownerHistoryBalanceAfter(String amount, String jobInfo) {
    return 'Balance after: \$$amount$jobInfo';
  }

  @override
  String get employeeJobsTooltipVerification => 'Verification Documents';

  @override
  String employeeJobsJobId(String id) {
    return 'Job #$id';
  }

  @override
  String get employeeJobsSuggestionArrivedPickup => 'Arrived at Pickup';

  @override
  String get employeeJobsSuggestionInRoute => 'Job in Route';

  @override
  String get employeeJobsSuggestionArrivedDestination =>
      'Arrived at Destination';

  @override
  String get employeeJobsSuggestionCompleted => 'Job Completed';

  @override
  String get employeeJobsSimulatorTitle => 'Log Service Event';

  @override
  String get employeeJobsSimulatorDesc =>
      'Log status updates and service events directly into the tenant audit trail.';

  @override
  String get employeeJobsSimulatorLabel => 'Service Event Action';

  @override
  String get employeeJobsSimulatorHint =>
      'e.g., Arrived at Pickup, Job in Route';

  @override
  String get employeeJobsSimulatorValidation =>
      'Please enter or select a service event to log';

  @override
  String get employeeJobsSimulateButton => 'Log Service Event';

  @override
  String get employeeJobsSectionAssigned => 'Your Assigned Jobs';

  @override
  String get employeeJobsLoading => 'Loading assigned jobs...';

  @override
  String get employeeJobsNoJobsTitle => 'No Jobs Assigned';

  @override
  String get employeeJobsNoJobsDesc => 'No jobs currently assigned to you.';

  @override
  String get employeeJobsWelcomeGreeting => 'Welcome back!';

  @override
  String employeeJobsLoggedInAs(String name) {
    return 'Logged in as: $name';
  }

  @override
  String get employeeJobsGpsLive => 'GPS Live';

  @override
  String get employeeJobsGpsOff => 'GPS Off';

  @override
  String get employeeJobsConfirmCodTitle =>
      'Confirm Cash Collection & Complete';

  @override
  String employeeJobsConfirmCodMessage(String amount, String jobId) {
    return 'Confirm you have physically collected the cash payment of \$$amount (COD) from the customer.\n\nThis will deduct the platform fee from the owner\'s wallet and mark Job #$jobId as completed.';
  }

  @override
  String employeeJobsConfirmNonCodMessage(String jobId) {
    return 'Are you sure you want to mark Job #$jobId as completed?';
  }

  @override
  String get employeeJobsConfirmCodButton =>
      'Confirm Cash Collected & Complete';

  @override
  String get employeeJobsConfirmNonCodButton => 'Complete Job';

  @override
  String get employeeJobsDestinationCoordinates => 'Destination Coordinates';

  @override
  String get employeeJobsLabelCustomer => 'Customer';

  @override
  String get employeeJobsLabelPayment => 'Payment';

  @override
  String get employeeJobsLabelEscrow => 'Escrow';

  @override
  String employeeJobsCancellationReason(String reason) {
    return 'Cancellation Reason: $reason';
  }

  @override
  String get employeeJobsLocationPermissionTitle =>
      'Location Permission Required';

  @override
  String get employeeJobsLocationPermissionDesc =>
      'Location sharing is required to share your live delivery progress with the customer.';

  @override
  String get employeeJobsOpenAppSettings => 'Open App Settings';

  @override
  String get employeeJobsSharingLiveLocation => 'Sharing live location';

  @override
  String get employeeJobsChatButton => 'Chat';

  @override
  String get employeeJobsCompleteJobButton => 'Complete Job';

  @override
  String get planFreeBasic => 'Free Basic Plan';

  @override
  String get planProfessionalPaid => 'Professional Paid Plan';

  @override
  String get walletLoading => 'Loading wallet...';

  @override
  String get walletLockedEscrow => 'Locked (Escrow)';

  @override
  String get walletTransactionLedger => 'Transaction Ledger';

  @override
  String get walletNoTransactions => 'No transactions recorded yet.';

  @override
  String get walletAmountCredits => 'Amount (Credits)';

  @override
  String get cancelJobReasonLabel => 'Cancellation Reason *';

  @override
  String get cancelJobReasonHint =>
      'e.g. Customer requested cancellation / Change of plans';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusActive => 'Active';

  @override
  String get statusAwaitingPrice => 'Awaiting Price';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusPendingApproval => 'Pending Approval';

  @override
  String get statusApproved => 'Approved';

  @override
  String get statusRejected => 'Rejected';

  @override
  String get statusUnverified => 'Unverified';

  @override
  String get statusReconciliationRequired => 'Reconciliation Required';

  @override
  String get statusUnknown => 'Unknown';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get customerOrdersLoading => 'Loading orders...';

  @override
  String get tooltipNotifications => 'Notifications';

  @override
  String get tooltipRefreshList => 'Refresh List';

  @override
  String get tooltipRefreshStatus => 'Refresh Status';

  @override
  String get tooltipToggleTheme => 'Toggle Theme Mode';

  @override
  String get tooltipToggleLanguage => 'Toggle Language';

  @override
  String get tooltipDismiss => 'Dismiss';

  @override
  String get tooltipPickImage => 'Pick Image';

  @override
  String get tooltipClose => 'Close';

  @override
  String get tooltipOpenChat => 'Open chat';

  @override
  String get tooltipRemoveAddress => 'Remove address';

  @override
  String get tooltipZoomIn => 'Zoom in';

  @override
  String get tooltipZoomOut => 'Zoom out';

  @override
  String get tooltipRecenter => 'Recenter map';

  @override
  String get sortByLabel => 'Sort By';

  @override
  String get searchingServices => 'Searching services...';

  @override
  String get noServicesNearby => 'No services found nearby.';

  @override
  String get paymentMethodLabel => 'Payment Method';

  @override
  String get registeredEmployees => 'Registered Employees';

  @override
  String get loadingEmployeeList => 'Loading employee list...';

  @override
  String get noEmployeesRegistered => 'No Employees Registered';

  @override
  String get registerNewEmployee => 'Register New Employee';

  @override
  String get employeeUsernameLabel => 'Employee Username';

  @override
  String get employeeUsernameHint => 'e.g. driver_john';

  @override
  String get employeeEmailLabel => 'Employee Email';

  @override
  String get employeeEmailHint => 'e.g. john@company.com';

  @override
  String get employeePasswordLabel => 'Employee Password';

  @override
  String get employeePasswordHint => 'At least 6 characters';

  @override
  String get employeeRegisteredTitle => 'Employee Registered';

  @override
  String get freezeUnfreezeWorker => 'Freeze / Unfreeze Worker';

  @override
  String get confirmOwnerPassword => 'Confirm Owner Password';

  @override
  String get workerStatusUpdated => 'Worker Status Updated';

  @override
  String get loadingAuditTrail => 'Loading audit trail...';

  @override
  String get noAuditEventsTitle => 'No audit events recorded';

  @override
  String get noAuditEventsDesc => 'No audit events recorded for this tenant.';

  @override
  String get liveTrackingTitle => 'Live Tracking';

  @override
  String get stepRequestPlaced => 'Request Placed';

  @override
  String get stepWaitingApproval => 'Waiting for operator approval';

  @override
  String get stepWorkerDispatched => 'Worker Dispatched';

  @override
  String get stepJobCompleted => 'Job Completed';

  @override
  String get stepCompletedSuccessfully => 'Delivery completed successfully';

  @override
  String get jobDetailsTitle => 'Job Details';

  @override
  String get priceNegotiationTitle => 'Price Negotiation';

  @override
  String negotiationHintExample(String price) {
    return 'e.g. $price';
  }

  @override
  String get accessDeniedTitle => 'Access Denied';

  @override
  String get loadingPendingSubmissions => 'Loading pending submissions...';

  @override
  String get noPendingSubmissions => 'No Pending Submissions';

  @override
  String rejectionReasonMessage(String reason) {
    return 'Rejection Reason: $reason';
  }

  @override
  String get ratingFeatureUnbiased => 'Unbiased Reviews';

  @override
  String get ratingFeatureTrust => 'Trust Shield';

  @override
  String get ratingFeatureWindow => '24h Window';

  @override
  String get privateFeedbackLabel => 'Private Feedback (Optional)';

  @override
  String get privateFeedbackHint => 'What went well? What could be improved?';

  @override
  String get loadingStatus => 'Loading status...';

  @override
  String get loadingServices => 'Loading services...';

  @override
  String get noServicesConfigured => 'No Services Configured';

  @override
  String get noServicesDescription =>
      'No services configured yet.\nTap the + button to create a service.';

  @override
  String get addService => 'Add Service';

  @override
  String get kycPending => 'KYC Pending';

  @override
  String get serviceNameLabel => 'Service Name';

  @override
  String get categoryLabel => 'Category';

  @override
  String get basePriceLabel => 'Base Price (\$)';

  @override
  String get ratePerKmLabel => 'Rate per KM (\$)';

  @override
  String get latitudeLabel => 'Latitude';

  @override
  String get longitudeLabel => 'Longitude';

  @override
  String get statusRequested => 'Requested';

  @override
  String get statusPaid => 'Paid';

  @override
  String get payoutWithdrawButton => 'Request Payout';

  @override
  String get payoutDialogTitle => 'Request Payout';

  @override
  String get payoutDialogDescription =>
      'Request a withdrawal from your withdrawable balance to your bank account or InstaPay.';

  @override
  String get payoutMethodLabel => 'Payout Method';

  @override
  String get payoutMethodBankTransfer => 'Bank Transfer';

  @override
  String get payoutMethodInstapay => 'InstaPay';

  @override
  String get payoutAccountDetailsLabel => 'Account Details';

  @override
  String get payoutAccountDetailsBankHint =>
      'IBAN (e.g. EG123456789012345678901234567)';

  @override
  String get payoutAccountDetailsInstapayHint =>
      'InstaPay Mobile / Address (e.g. 01012345678)';

  @override
  String get payoutConfirmTitle => 'Confirm Payout Request';

  @override
  String payoutConfirmMessage(String amount, String method) {
    return 'Are you sure you want to request a payout of $amount credits via $method? The requested amount will be held from your withdrawable balance until processed.';
  }

  @override
  String get payoutSuccessMessage => 'Payout request submitted successfully.';

  @override
  String get payoutHistoryTitle => 'Payout Requests History';

  @override
  String get payoutHistoryEmpty => 'No payout requests submitted yet.';

  @override
  String get payoutErrorAmountExceeds =>
      'Amount exceeds current withdrawable balance.';

  @override
  String get payoutErrorAmountInvalid =>
      'Please enter a valid amount greater than 0.';

  @override
  String get payoutErrorDetailsRequired => 'Account details are required.';

  @override
  String get payoutRejectionReasonLabel => 'Rejection Reason:';

  @override
  String get chatStatusLive => 'Live';

  @override
  String get chatStatusDisconnected => 'Disconnected';

  @override
  String chatJobTag(String shortId) {
    return 'Job #$shortId';
  }

  @override
  String get chatDirectChannel => 'Direct Real-time Channel';

  @override
  String chatAccessDeniedJob(String jobId) {
    return 'Access Denied: You are not authorized to view or join the chat for Job #$jobId.';
  }

  @override
  String get customerHomeWhereDeliver => 'Where to deliver?';

  @override
  String get customerHomeSearchHint => 'Enter destination or pickup area...';

  @override
  String get commonOrigin => 'Origin';

  @override
  String get commonDestination => 'Destination';

  @override
  String get courierAssignedLabel => 'Courier: Assigned';

  @override
  String get findingCourierLabel => 'Finding Courier...';

  @override
  String paymentMethodLine(String method) {
    return 'Payment: $method';
  }

  @override
  String get mapPickupBadge => 'Pickup';

  @override
  String get waitingCourierUpdates => 'Waiting for courier location updates...';

  @override
  String get reconnectingTrackingStream =>
      'Reconnecting live tracking stream...';

  @override
  String get filterAll => 'All';

  @override
  String distanceAwayLine(String distance) {
    return '$distance km away';
  }

  @override
  String pricingBreakdownLine(String base, String perKm) {
    return 'Base: $base + $perKm/km';
  }

  @override
  String estPriceLine(String price) {
    return 'Est. Price: $price';
  }

  @override
  String get chooseSearchLocation => 'Choose Search Location';

  @override
  String get confirmBookingTitle => 'Confirm Booking';

  @override
  String categoryLine(String category) {
    return 'Category: $category';
  }

  @override
  String get pickupDistanceLabel => 'Pickup Distance:';

  @override
  String kmUnitLine(String distance) {
    return '$distance km';
  }

  @override
  String get estimatedTotalLabel => 'Estimated Total:';

  @override
  String get codOptionTitle => 'Cash on Delivery (COD)';

  @override
  String get codOptionSubtitle =>
      'Pay in cash directly to the driver upon arrival';

  @override
  String get betaEscrowNote =>
      'Note: Escrow payments and wallet deductions are currently deferred for this beta launch.';

  @override
  String get noRatingsLabel => 'No ratings';

  @override
  String reasonLine(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get recentActivityHeader => 'Recent Activity';

  @override
  String get employeeHistorySubtitle => 'Completed and cancelled jobs.';

  @override
  String get employeeManageSubtitle => 'Manage delivery personnel and status.';

  @override
  String get employeeSearchHint => 'Search workers by name or email...';

  @override
  String get employeeFrozenStatus => 'Frozen';

  @override
  String get noWorkersMatchFilter => 'No workers found matching your filter.';

  @override
  String workerIdBadge(String id) {
    return 'ID: #QD-$id';
  }

  @override
  String get targetStatusLabel => 'Target Status';

  @override
  String get secureVerificationNote =>
      'Required for secure out-of-band operations verification.';

  @override
  String clientIpLine(String ip) {
    return 'IP: $ip';
  }

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
  String get passwordTooShort => 'Password must be at least 6 characters';

  @override
  String get employeeEmailRequired => 'Employee email is required';

  @override
  String get ownerPasswordRequired =>
      'Owner password is required to re-authenticate';

  @override
  String get enterOtp6Digits => 'Enter 6-digit OTP code';

  @override
  String get otpExactly6Digits => 'OTP must be exactly 6 digits';

  @override
  String devOtpBanner(String otp) {
    return 'Dev OTP Code: $otp';
  }

  @override
  String devOtpAutoFilled(String otp) {
    return 'Dev Mode: Auto-populated OTP \'$otp\' from response.';
  }

  @override
  String get enterpriseTrustNote => 'Secured by Enterprise Trust Protocol';

  @override
  String get jobsTrendChipMock => '+12% vs last week';

  @override
  String get activeFleetMetricLabel => 'ACTIVE FLEET';

  @override
  String get quickConfigSubtitle =>
      'Configure business profile, rates & coverage';

  @override
  String get urgentActionsHeader => 'Urgent Actions';

  @override
  String get vehicleMaintenanceTitle => 'Vehicle Maintenance Required';

  @override
  String get vehicleMaintenanceDesc =>
      'Van #402 reported engine warning. Schedule service immediately.';

  @override
  String get scheduleAction => 'Schedule';

  @override
  String get pendingReconciliationsHeader => 'Pending Reconciliations';

  @override
  String get reconciliationPendingDesc =>
      'Driver shifts from yesterday awaiting escrow settlement.';

  @override
  String get reviewAction => 'Review';

  @override
  String get fleetOverviewHeader => 'Fleet Overview';

  @override
  String get activeZoneLabel => 'Active Zone';

  @override
  String get downtownCoverageLabel => 'Downtown Metro Coverage';

  @override
  String get trackJobHeroTitle => 'Track Job';

  @override
  String get trackJobHeroSubtitle => 'View real-time location on map';

  @override
  String get fulfillmentProgressHeader => 'Fulfillment Progress';

  @override
  String get stepRequestQueuedSub => 'Request placed & queued';

  @override
  String get stepAssignedTitle => 'Assigned';

  @override
  String get matchingCourierLabel => 'Matching courier...';

  @override
  String assignedToLine(String name) {
    return 'Assigned to $name';
  }

  @override
  String get courierAssignedShort => 'Courier assigned';

  @override
  String get stepInTransitSub => 'Package on route to destination';

  @override
  String get stepDeliveredOkSub => 'Delivered successfully';

  @override
  String get stepPendingDeliverySub => 'Pending delivery';

  @override
  String get itineraryHeader => 'Itinerary';

  @override
  String get pickupStageBadge => 'PICKUP';

  @override
  String get originCustomerLocation => 'Origin / Customer Location';

  @override
  String get dropoffStageBadge => 'DROPOFF';

  @override
  String get deliveryDestinationLabel => 'Delivery Destination';

  @override
  String get paymentSectionHeader => 'Payment';

  @override
  String get totalFareLabel => 'Total Fare';

  @override
  String get verifiedCourierDriver => 'Verified Courier Driver';

  @override
  String cancellationReasonLine(String reason) {
    return 'Cancellation Reason: $reason';
  }

  @override
  String get negotiationExpiredBanner =>
      'Negotiation Window Expired (5-min limit lapsed)';

  @override
  String get incomingProposalCard => 'Incoming Proposal';

  @override
  String proposalByLine(String role) {
    return 'by $role';
  }

  @override
  String get proposalRoleCustomer => 'Customer';

  @override
  String get proposalRoleDriverEmployee => 'Driver / Employee';

  @override
  String get proposedFareLabel => 'Proposed Fare:';

  @override
  String get comparisonPrefix => 'Comparison:';

  @override
  String get vsSystemPrice => 'vs System Price';

  @override
  String get waitingProposalResponse =>
      'Waiting for response to your proposal...';

  @override
  String get submitCounterOfferBtn => 'Submit Counter-Offer';

  @override
  String allowedBoundLine(String min, String max) {
    return 'Allowed bound: $min – $max (±50%)';
  }

  @override
  String get verificationStatusCardTitle => 'Verification Status';

  @override
  String get documentsLockedMessage =>
      'Documents are locked because your account is approved.';

  @override
  String get removeSelectionAction => 'Remove selection';

  @override
  String get requiredDocsHeader => 'Required Verification Documents';

  @override
  String get kycOwnerDocsSub =>
      'Owners must upload all 4 documents (ID Front, ID Back, Selfie, Business Proof).';

  @override
  String get kycEmployeeDocsSub =>
      'Employees must upload all 3 documents (ID Front, ID Back, Selfie).';

  @override
  String get profileInfoCardTitle => 'Profile Information';

  @override
  String get sectionBusinessIdentity => 'Business Identity';

  @override
  String get sectionBusinessIdentitySub => 'Company details and classification';

  @override
  String get sectionLocationOperations => 'Location & Operations';

  @override
  String get sectionLocationOperationsSub =>
      'Headquarters and coverage boundary';

  @override
  String get sectionPricingStructure => 'Pricing Structure';

  @override
  String get sectionPricingStructureSub => 'Base fare and distance-based fees';

  @override
  String get estDelivery10kmLabel => 'Est. 10KM Delivery:';

  @override
  String get fleetFilterAllFleet => 'All Fleet';

  @override
  String get fleetFilterOnRoute => 'On Route';

  @override
  String get fleetFilterIdle => 'Idle';

  @override
  String get noEmployeesTransmitting =>
      'No active employees transmitting location.';

  @override
  String assignedJobLine(String jobId) {
    return 'Assigned Job: #$jobId';
  }

  @override
  String get ownerJobsSearchHint => 'Search by Job ID, customer, or reason...';

  @override
  String get noJobsMatchFilter => 'No jobs found matching your filter.';

  @override
  String get reconQueueSearchHint =>
      'Search queue by Job ID, customer, driver...';

  @override
  String get reconFilterDistance => 'Distance';

  @override
  String get reconFilterTimeSpeed => 'Time / Speed';

  @override
  String get reconFilterOther => 'Other';

  @override
  String get noReconMatchFilter => 'No reconciliation jobs match your filter.';

  @override
  String deliveryIdTag(String id) {
    return 'Delivery ID: #QD-$id';
  }

  @override
  String get howWasDeliveryQuestion => 'How was your delivery?';

  @override
  String get ratingsBlindExplanation =>
      'Ratings are blind. Neither party will see the other\'s feedback until both have submitted.';

  @override
  String get feedbackExperienceHint => 'Tell us more about your experience...';

  @override
  String get feedbackLockedInTitle => 'Feedback Locked In!';

  @override
  String get bothRatingsVisibleDesc =>
      'The other party has submitted their rating. Both feedbacks are now visible under profile summary.';

  @override
  String get waitingOtherPartyTitle => 'Waiting for other party...';

  @override
  String get otherPartyNotRatedDesc =>
      'The other party has not yet rated this transaction. Your ratings will remain hidden until they submit.';

  @override
  String get unbiasedRatingDesc =>
      'Preventing retaliatory or social-pressure ratings.';

  @override
  String get reliabilityRanksDesc =>
      'Ratings directly impact platform reliability ranks.';

  @override
  String get windowDeadlineDesc =>
      'Submit within 24 hours to ensure your score counts.';

  @override
  String get serviceMgmtHeader => 'Service Management';

  @override
  String get serviceMgmtSubtitle =>
      'Configure and monitor active logistics services.';

  @override
  String get verificationRequiredHeader => 'Verification Required';

  @override
  String get kycRequiredDesc =>
      'Please complete KYC verification to create new services or modify existing ones.';

  @override
  String get baseRateBadge => 'BASE RATE';

  @override
  String get perKmBadge => 'PER KM';

  @override
  String serviceLocationLine(String lat, String lon) {
    return 'Location: ($lat, $lon)';
  }

  @override
  String get subscriptionManageDesc =>
      'Manage your operational tier. Upgrade to unlock live driver tracking, advanced pricing metrics, and priority enterprise support.';

  @override
  String get yourCurrentPlanBadge => 'YOUR CURRENT PLAN';

  @override
  String get pendingActivationNote =>
      'Pending activation. Please contact support to complete payment.';

  @override
  String get availablePlansHeader => 'Available Plans';

  @override
  String get freeTierDesc => 'Essential tools for independent operators.';

  @override
  String get proTierDesc =>
      'Complete suite for fleet managers and growing businesses.';

  @override
  String get billedMonthlyNote => 'Billed monthly. Cancel anytime.';

  @override
  String get recommendedBadge => 'RECOMMENDED';

  @override
  String platformFeeLine(String fee) {
    return 'Platform fee: $fee%';
  }

  @override
  String get walletMyWalletTitle => 'My Wallet';

  @override
  String get walletCorporateSubtitle =>
      'Manage corporate finances and payouts.';

  @override
  String get availableBalanceBadge => 'AVAILABLE BALANCE';

  @override
  String get balanceTrendChipMock => '+8.4% vs last mo';

  @override
  String totalPortfolioLine(String amount) {
    return 'Total Portfolio: $amount Credits';
  }

  @override
  String creditsAmountLine(String amount) {
    return '$amount Credits';
  }

  @override
  String ledgerJobLine(String jobId) {
    return 'Job: $jobId';
  }

  @override
  String ledgerBalanceLine(String balance) {
    return 'Bal: $balance';
  }

  @override
  String get cancelReasonRequiredLong =>
      'Please provide a reason for cancelling this job. A valid cancellation reason is required.';

  @override
  String get createNewServiceTitle => 'Create New Service';

  @override
  String referenceIdLine(String ref) {
    return 'Reference ID: #$ref';
  }

  @override
  String get depositFundsTitle => 'Deposit Funds';

  @override
  String get depositDialogDesc =>
      'Enter the amount in credits to deposit to your wallet.';

  @override
  String get amountRequired => 'Amount is required';

  @override
  String get positiveNumberRequired => 'Please enter a valid positive number';

  @override
  String get basePriceRequired => 'Base price is required';

  @override
  String get invalidPriceValue => 'Invalid price';

  @override
  String get rateRequired => 'Rate is required';

  @override
  String get invalidRateValue => 'Invalid rate';

  @override
  String get fieldRequiredGeneric => 'Required';

  @override
  String get latRangeMessage => 'Must be between -90 and 90';

  @override
  String get lonRangeMessage => 'Must be between -180 and 180';

  @override
  String otpSentToEmail(String email) {
    return 'Enter the 6-digit verification code sent to $email.';
  }

  @override
  String get devModeOtpLabel => 'Dev Mode OTP';

  @override
  String verificationCodeLine(String code) {
    return 'Verification code: $code';
  }

  @override
  String get verificationCodeLabel => 'Verification Code';

  @override
  String get verificationCodeRequired => 'Verification code is required';

  @override
  String accountDetailsLine(String account) {
    return 'Account: $account';
  }

  @override
  String get verifiedServiceScoreLabel => 'Verified Service Score';

  @override
  String basedOnRatingsLine(String count) {
    return 'Based on $count ratings';
  }

  @override
  String get employeeSetActiveStatus => 'Set account to Active (Unfreeze)';

  @override
  String get employeeSetFrozenStatus => 'Set account to Frozen (Suspended)';

  @override
  String get stepInTransitTitle => 'In Transit';

  @override
  String get findNearbyCouriers => 'Find Nearby Couriers';

  @override
  String get confirmAndRequestBtn => 'Confirm & Request';

  @override
  String get auditTrailTabLabel => 'Audit Trail';

  @override
  String get registerEmployeeBtn => 'Register Employee';

  @override
  String get rateYourExperienceCta => 'Rate Your Experience';

  @override
  String get openComplaintTicketBtn => 'Open a Complaint Ticket';

  @override
  String get backToDirectoryBtn => 'Back to Directory';

  @override
  String get acceptProposalBtn => 'Accept Proposal';

  @override
  String get declineProposalBtn => 'Decline';

  @override
  String get replaceDocumentBtn => 'Replace Document';

  @override
  String get uploadDocumentBtn => 'Upload Document';

  @override
  String get createActionLabel => 'Create';

  @override
  String get backToStatusBtn => 'Back to Status';

  @override
  String get bookNowBtn => 'Book';

  @override
  String get subFreeFeatureMatching => 'Basic delivery matching';

  @override
  String get subFreeFeatureRouting => 'Standard routing optimization';

  @override
  String get subFreeFeatureCod => 'Cash on Delivery (COD) bookings';

  @override
  String get subFreeFeatureSupport => 'Community support';

  @override
  String get subProFeatureTracking => 'Live worker location tracking';

  @override
  String get subProFeatureDispatch => 'Priority dispatch routing';

  @override
  String get subProFeaturePricing => 'Access to advanced pricing metrics';

  @override
  String get subProEmployeeSuite => 'Full employee management suite';

  @override
  String get subProDedicatedSupport => 'Premium 24/7 dedicated support';

  @override
  String get subProFeatureTrackingUnlock =>
      'Unlocks live worker location tracking';
}
