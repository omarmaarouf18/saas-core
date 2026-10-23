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
  String get navHome => 'Home';

  @override
  String get navServices => 'Services';

  @override
  String get navHistory => 'History';

  @override
  String get navSettings => 'Settings';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'System';

  @override
  String get langAuto => 'System default';

  @override
  String get langEnglish => 'English';

  @override
  String get langArabic => 'عربي مصري';

  @override
  String get settingsTitle => 'Settings';

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
  String get myAccountEmailLabel => 'Email address';

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
      'Save quick locations for faster booking, max 10.';

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
  String get myAccountAddressRequired => 'Type an address first, then tap ADD.';

  @override
  String get myAccountAddressRemoved => 'Address removed.';

  @override
  String get undoAction => 'Undo';

  @override
  String get myAccountSaveButton => 'SAVE PROFILE';

  @override
  String get myAccountSuccessMsg => 'Profile updated successfully';

  @override
  String get accountStatusSuspendedTitle => 'Account Suspended';

  @override
  String get accountStatusSuspendedDefaultReason =>
      'Your account has been suspended by an administrator. Please contact support for more information.';

  @override
  String get accountStatusActiveBadge => 'Active';

  @override
  String get accountStatusSuspendedBadge => 'Suspended';

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
  String get ownerConfigRadiusLabel => 'Coverage radius';

  @override
  String get ownerConfigRadiusHint => 'e.g. 25.0';

  @override
  String get ownerConfigRadiusReq => 'Enter a valid radius > 0.';

  @override
  String get ownerConfigAddressInvalid =>
      'Enter a valid address with at least 3 characters.';

  @override
  String get ownerConfigHoursInvalid =>
      'Enter valid working hours, e.g. 8:00 AM - 10:00 PM.';

  @override
  String get scheduleTitle => 'Weekly Schedule';

  @override
  String get scheduleSubtitle =>
      'Tell customers when you\'re open. Leave unset to stay listed as always open.';

  @override
  String get scheduleSetBtn => 'Set working hours';

  @override
  String get scheduleRemoveBtn => 'Remove hours';

  @override
  String get scheduleModeSameDaily => 'Same every day';

  @override
  String get scheduleModePerDay => 'Different per day';

  @override
  String get scheduleOpenLabel => 'Opens';

  @override
  String get scheduleCloseLabel => 'Closes';

  @override
  String get scheduleOffLabel => 'Off';

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
  String get outOfServiceBadge => 'Out of Service';

  @override
  String outOfServiceReopensAt(String time) {
    return 'Out of Service — opens $time';
  }

  @override
  String get ownerConfigBasePriceLabel => 'Base price';

  @override
  String get ownerConfigBasePriceHint => 'e.g. 10.00';

  @override
  String get ownerConfigBasePriceReq => 'Base price must be >= 0.';

  @override
  String get ownerConfigPricePerKmLabel => 'Price per km';

  @override
  String get ownerConfigPricePerKmHint => 'e.g. 1.50';

  @override
  String get ownerConfigPricePerKmReq => 'Price per KM must be >= 0.';

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
  String get signupPasswordHint => 'At least 8 characters';

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
  String get otpFooterBrand => 'Quick Delivery';

  @override
  String get otpFooterNote => 'Never share your verification code with anyone.';

  @override
  String get forgotPasswordTitle => 'Reset Password';

  @override
  String get forgotPasswordSubtitle => 'Enter your email and new credentials';

  @override
  String get forgotPasswordSubmitButton => 'RESET PASSWORD';

  @override
  String get forgotPasswordStep1Subtitle =>
      'Enter your account email — we\'ll send a verification code.';

  @override
  String get forgotPasswordSendCodeButton => 'SEND CODE';

  @override
  String get newPasswordSubtitle => 'Choose your new password.';

  @override
  String get resetSessionExpiredMsg =>
      'This reset session has expired. Please restart from the email step to get a new code.';

  @override
  String get resetBackToEmailStep => 'Back to email step';

  @override
  String get resetBackToCodeStep => 'Back to code step';

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
  String get customerHomeQuickBookBtn => 'BOOK NOW';

  @override
  String get customerMarketplaceTitle => 'Explore Services';

  @override
  String get customerMarketplaceFilterCategory => 'Category';

  @override
  String get customerMarketplaceFilterRadius => 'Max distance';

  @override
  String get unitKm => 'km';

  @override
  String get customerMarketplaceChooseMap => 'Choose Location on Map';

  @override
  String get applyFiltersBtn => 'Apply Filters';

  @override
  String get clearFiltersBtn => 'Clear Filters';

  @override
  String get adjustFiltersDesc =>
      'Try adjusting your search query or status filter.';

  @override
  String get customerJobsTitle => 'My Orders';

  @override
  String get customerJobsSub => 'Track and manage your delivery history.';

  @override
  String get customerJobsSearchHint => 'Search by Order ID, Location...';

  @override
  String get customerJobsInTransit => 'In Transit';

  @override
  String get customerJobsPrice => 'Price';

  @override
  String get customerJobsOrder => 'Order #';

  @override
  String get customerJobsEmpty => 'No Orders Found';

  @override
  String get customerJobsEmptyDescription =>
      'You haven\'t placed any orders yet. Explore services in the marketplace to get started.';

  @override
  String get jobStatusTitle => 'Order Status';

  @override
  String get jobStatusOpenTicketBtn => 'Open Complaint Ticket';

  @override
  String get ownerHistoryTitle => 'History & Audit Logs';

  @override
  String get ownerHistoryTabJobs => 'Jobs';

  @override
  String get ownerHistoryTabLedger => 'Ledger';

  @override
  String get employeeJobsTitle => 'Assigned Jobs';

  @override
  String get employeeScreenTitle => 'Manage Workers';

  @override
  String get chatTitle => 'Job Chat';

  @override
  String get chatTypeHint => 'Type a message...';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsClear => 'Clear All';

  @override
  String get walletTotalBalance => 'Total';

  @override
  String get walletWithdrawable => 'Available';

  @override
  String get ratingTitle => 'Rate Service';

  @override
  String get ratingSubmitBtn => 'SUBMIT RATING';

  @override
  String get locationPickerUseMyLocation => 'Use My Location';

  @override
  String get locationPickerConfirmBtn => 'Confirm Location';

  @override
  String get locationNoteLabel => 'Landmark note · optional';

  @override
  String get locationNoteHint =>
      'e.g. next to Ahmed\'s kiosk, 3rd floor — helps your driver find you';

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
  String get reconciliationReviewTitle => 'Escrow Reconciliation Review';

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
  String cancelJobHeader(String jobId) {
    return 'Cancel Job #$jobId';
  }

  @override
  String get cancelJobKeep => 'Keep Job';

  @override
  String get cancelJobConfirm => 'Confirm Cancel';

  @override
  String get cancelRequestHeader => 'Request Cancellation';

  @override
  String get cancelRequestBodyLong =>
      'Please provide a reason for requesting cancellation. Your request will be sent to the business owner for approval — the job stays active until they respond.';

  @override
  String get cancelRequestConfirm => 'Send Request';

  @override
  String get cancelRequestPendingBanner =>
      'Cancellation requested — waiting for owner approval.';

  @override
  String get employeePricePendingTitle => 'Waiting for fare confirmation';

  @override
  String employeePricePendingBody(Object price) {
    return 'Proposed fare $price — the trip starts automatically once the fare is accepted. Completing is only possible on an active trip.';
  }

  @override
  String employeePricePendingExpiry(Object remaining) {
    return 'Request expires in $remaining — then it is cancelled automatically.';
  }

  @override
  String get employeePriceAcceptConfirmTitle => 'Accept this fare?';

  @override
  String employeePriceAcceptConfirmMessage(Object price) {
    return 'Accept the proposed fare $price? The trip will start immediately and can then be completed. This is a financial commitment.';
  }

  @override
  String get employeeProposePriceTitle => 'Propose a Fare';

  @override
  String get employeeProposePriceBody =>
      'Suggest your fare — the customer accepts or declines it. One proposal per trip, within the allowed bound.';

  @override
  String get employeeProposeSuccessMsg =>
      'Price proposal sent — waiting for the customer.';

  @override
  String get employeeProposalRacedError =>
      'The customer already sent a price — respond to it instead.';

  @override
  String get cancelRequestRejectedBanner =>
      'The business owner declined your cancellation request. You remain assigned to this job.';

  @override
  String get cancelRequestSentMsg =>
      'Cancellation request sent to the business owner.';

  @override
  String get employeeRequestCancelButton => 'Request Cancellation';

  @override
  String get ownerCancelRequestTitle => 'Employee requested cancellation';

  @override
  String get ownerCancelRequestApprove => 'Approve Cancellation';

  @override
  String get ownerCancelRequestDecline => 'Decline Request';

  @override
  String get ownerCancelRequestResolved => 'Request resolved.';

  @override
  String get ownerCancelRequestApproveConfirmTitle => 'Approve Cancellation?';

  @override
  String get ownerCancelRequestApproveConfirmMessage =>
      'Approving this cancellation request will cancel the job and trigger a full refund of any escrowed funds to the customer.';

  @override
  String get ownerCancelRequestDeclineConfirmTitle =>
      'Decline Cancellation Request?';

  @override
  String get ownerCancelRequestDeclineConfirmMessage =>
      'Declining this request will keep the job active with the courier currently assigned.';

  @override
  String get ownerCancelRequestApproved =>
      'Cancellation request approved. Job cancelled and escrow refunded.';

  @override
  String get ownerCancelRequestDeclined =>
      'Cancellation request declined. Courier remains assigned.';

  @override
  String get locationPermissionDeniedDefault =>
      'Location permission denied. Defaulting to Cairo.';

  @override
  String locationFetchError(String error) {
    return 'Error fetching location: $error';
  }

  @override
  String get settingsKycRowTitle => 'Identity verification';

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
  String get ownerHomeServiceReputation => 'Your Service Reputation';

  @override
  String get ownerHomeOwnerJobs => 'Owner Jobs';

  @override
  String get ownerHomeNoJobsTitle => 'No Owner Jobs Found';

  @override
  String get ownerHomeNoJobsDesc =>
      'You currently have no jobs registered under your tenant account.';

  @override
  String get ownerHomeViewAllJobs => 'VIEW ALL JOBS';

  @override
  String get ownerHomeFleetSub => 'Track couriers live';

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
  String get ownerHomeJobCancelled => 'Job cancelled successfully.';

  @override
  String get ownerHomeJobCancelledEscrowRefunded =>
      'Job cancelled successfully. Escrow refunded to wallet.';

  @override
  String ownerCancelJobEscrowWarning(String amount) {
    return 'Cancelling this job will immediately refund \$$amount from locked escrow back to the customer\'s wallet. Please provide a reason for cancellation:';
  }

  @override
  String get ownerCancelJobPlainWarning =>
      'Cancelling this job will stop all delivery activity immediately. Please provide a reason for cancellation:';

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
    return 'Confirm you have physically collected the cash payment of \$$amount from the customer.\n\nThis will mark Job #$jobId as completed.';
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
  String get walletLockedEscrow => 'Locked';

  @override
  String get walletTransactionLedger => 'Transaction Ledger';

  @override
  String get walletNoTransactions => 'No transactions recorded yet.';

  @override
  String get walletAmountCredits => 'Amount';

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
  String get statusPendingDispatch => 'Finding Courier';

  @override
  String get statusUnavailable => 'Unavailable';

  @override
  String get serviceTemporarilyUnavailable =>
      'The service is temporarily unavailable — nothing was changed. Please try again shortly.';

  @override
  String get incomingJobOffer => 'Incoming Job Offer';

  @override
  String get acceptOffer => 'Accept Offer';

  @override
  String get declineOffer => 'Decline';

  @override
  String get chatWithCustomer => 'Chat with Customer';

  @override
  String get courierFoundReviewing =>
      'Courier found, reviewing your request...';

  @override
  String get earlyChatAvailableHint =>
      'You can chat with the courier while they review your order.';

  @override
  String offerExpiresIn(int seconds) {
    return 'Expires in ${seconds}s';
  }

  @override
  String get allCouriersBusyTitle =>
      'All couriers are currently busy right now';

  @override
  String get allCouriersBusyDesc =>
      'All couriers in your area are currently occupied or unavailable. Please try again shortly.';

  @override
  String get retryBookingAction => 'Try Again';

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
  String get employeesLoadFailed => 'Couldn\'t load your employees right now.';

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
  String get employeePasswordHint => 'At least 8 characters';

  @override
  String get freezeUnfreezeWorker => 'Freeze / Unfreeze Worker';

  @override
  String get confirmOwnerPassword => 'Confirm Owner Password';

  @override
  String get loadingAuditTrail => 'Loading audit trail...';

  @override
  String get noAuditEventsTitle => 'No audit events recorded';

  @override
  String get noAuditEventsDesc => 'No audit events recorded for this tenant.';

  @override
  String get priceNegotiationTitle => 'Price Negotiation';

  @override
  String negotiationHintExample(String price) {
    return 'e.g. $price';
  }

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
  String get privateFeedbackLabel => 'Private feedback · optional';

  @override
  String get loadingStatus => 'Loading status...';

  @override
  String get kycRejectedDialogTitle => 'Verification Rejected';

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
      'IBAN, e.g. EG123456789012345678901234567';

  @override
  String get payoutAccountDetailsInstapayHint =>
      'InstaPay mobile number or address, e.g. 01012345678';

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
  String get customerHomeSearchHint => 'Tap to set your pickup location';

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
  String get mapDropoffBadge => 'Dropoff';

  @override
  String get mapYouAreHereBadge => 'You';

  @override
  String get employeeLiveMapTitle => 'Live Trip Map';

  @override
  String get employeeTrackTripBtn => 'View Live Map';

  @override
  String get employeeWaitingSelfPosition => 'Waiting for your GPS position…';

  @override
  String get employeeMapLocationDenied =>
      'Location permission denied — your live position won\'t show, but pickup and dropoff still do.';

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
  String workingHoursLine(String hours) {
    return 'Hours: $hours';
  }

  @override
  String coverageRadiusLine(String radius) {
    return 'Coverage: $radius km';
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
  String get codOptionTitle => 'Cash on delivery';

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
      'Negotiation window expired, 5-minute limit lapsed';

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
    return 'Allowed bound: $min – $max, ±50%';
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
      'Owners must upload all 4 documents: identity card front, identity card back, selfie, business proof.';

  @override
  String get kycEmployeeDocsSub =>
      'Employees must upload all 3 documents: identity card front, identity card back, selfie.';

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
  String get ratingStatusCheckFailed =>
      'Couldn\'t check whether the other party rated yet. Retry to reload.';

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
  String get walletMyWalletTitle => 'My Wallet';

  @override
  String get walletCorporateSubtitle =>
      'Manage corporate finances and payouts.';

  @override
  String get availableBalanceBadge => 'BALANCE';

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
  String get employeeSetActiveStatus => 'Account active';

  @override
  String get employeeSetFrozenStatus => 'Account frozen';

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
  String get backToStatusBtn => 'Back to Status';

  @override
  String get bookNowBtn => 'Book';

  @override
  String get subFreeFeatureMatching => 'Basic delivery matching';

  @override
  String get subFreeFeatureRouting => 'Standard routing optimization';

  @override
  String get subFreeFeatureCod => 'Cash on delivery bookings';

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

  @override
  String get customerHomeTileDeliveryDesc =>
      'Fast on-demand delivery for orders, packages, and essentials.';

  @override
  String get customerHomeTileRideDesc =>
      'Local ride booking, moving transport, and courier transport.';

  @override
  String get customerHomeTileShippingDesc =>
      'Book shipping for parcels and goods with GPS-tracked settlement.';

  @override
  String get customerHomeTileCleaningDesc =>
      'On-demand home cleaning, maintenance, and handyman services.';

  @override
  String get customerHomeTileBrowseAllDesc =>
      'Browse all available home services and delivery options.';

  @override
  String get browseServicesBtn => 'Browse Services';

  @override
  String get marketplaceEmptyHint =>
      'Try broadening your search radius or changing your coordinates.';

  @override
  String get refreshHistoryBtn => 'Refresh History';

  @override
  String get refreshJobsBtn => 'Refresh Jobs';

  @override
  String get employeeRegisterIntro =>
      'Register your first employee account using the form below.';

  @override
  String get addWorkerAction => 'Add Worker';

  @override
  String get refreshAuditLogBtn => 'Refresh Audit Log';

  @override
  String get manageServicesAction => 'Manage Services';

  @override
  String get backToHomeBtn => 'Back to Home';

  @override
  String get refreshQueueBtn => 'Refresh Queue';

  @override
  String get walletPayoutEmptyHint =>
      'Submitted payout requests will appear here with processing status.';

  @override
  String get walletLedgerEmptyHint =>
      'Your transaction history will appear here once deposits or charges occur.';

  @override
  String get refreshWalletBtn => 'Refresh Wallet';

  @override
  String get expressDeliveryFallbackLabel => 'Express Delivery';

  @override
  String get inTransitLiveTitle => 'In Transit - Live Courier Tracking';

  @override
  String get liveRouteTrackingActive => 'Live Route Tracking Active';

  @override
  String get pickupLocationLabel => 'Pickup Location';

  @override
  String get orderDispatchedLabel => 'Order Dispatched';

  @override
  String get clientAddressConfirmedLabel => 'Client Address Confirmed';

  @override
  String get standardRouteLabel => 'Standard Route';

  @override
  String get routeLoggedLabel => 'Route Logged';

  @override
  String get routeDestinationNotSetYet => 'Destination not set yet';

  @override
  String get workerStatusChangedSuccessMsg => 'Successfully changed status.';

  @override
  String get freezeWorkerBtn => 'Freeze Worker';

  @override
  String get unfreezeWorkerBtn => 'Unfreeze Worker';

  @override
  String get freezeWorkerConfirmTitle => 'Freeze Worker Account?';

  @override
  String freezeWorkerConfirmMessage(String email) {
    return 'Freezing $email will immediately block their login and hide them from active dispatch. You can unfreeze them at any time from this screen.';
  }

  @override
  String get unfreezeWorkerConfirmTitle => 'Unfreeze Worker Account?';

  @override
  String unfreezeWorkerConfirmMessage(String email) {
    return 'Unfreezing $email will immediately restore their login access and allow them to receive new dispatches.';
  }

  @override
  String get passwordResetSuccessMsg =>
      'Password reset successfully! You can now log in with your new password.';

  @override
  String get enterValidNumberError => 'Enter a valid number';

  @override
  String get priceProposalAcceptedMsg =>
      'Price proposal accepted! Job is now active.';

  @override
  String get priceProposalDeclinedMsg =>
      'Price proposal declined. Job cancelled.';

  @override
  String get courierDriverLabel => 'Courier Driver';

  @override
  String get assignedCourierLabel => 'Assigned Courier';

  @override
  String get originalSystemPriceLabel => 'Original System Price';

  @override
  String get agreedPriceLabel => 'Agreed Price';

  @override
  String get selectFileSourceTitle => 'Select File Source';

  @override
  String get selectImageSourceTitle => 'Select Image Source';

  @override
  String kycInvalidFormatDocs(String slot) {
    return 'Invalid file format. Only JPEG, PNG, and PDF files are allowed for $slot.';
  }

  @override
  String kycInvalidFormatImages(String slot) {
    return 'Invalid file format. Only JPEG and PNG image files are allowed for $slot.';
  }

  @override
  String get kycApprovedBanner =>
      'Your account verification has been approved by administrators. Your account is fully active.';

  @override
  String get kycPendingBanner =>
      'All required documents have been uploaded and are pending super admin review.';

  @override
  String get kycRejectedBanner =>
      'Your document submission was rejected. Please review the reason below and re-upload the corrected documents.';

  @override
  String get kycUploadAllBanner =>
      'Please upload all required verification documents below to complete identity verification.';

  @override
  String get ownerKybTitle => 'Owner verification';

  @override
  String get employeeKyeTitle => 'Employee verification';

  @override
  String get idFrontTitle => 'Identity card front';

  @override
  String get idFrontDesc =>
      'Clear photo of the front side of your National ID or Passport.';

  @override
  String get idBackTitle => 'Identity card back';

  @override
  String get idBackDesc => 'Clear photo of the back side of your National ID.';

  @override
  String get selfieTitle => 'Selfie Photo';

  @override
  String get selfieDesc => 'Selfie holding your ID card next to your face.';

  @override
  String get businessProofTitle => 'Business Proof / Commercial Register';

  @override
  String get businessProofDesc =>
      'Official commercial register or tax registration document in PDF, JPEG, or PNG format.';

  @override
  String get userProfileTitle => 'User Profile';

  @override
  String get syncPausedOfflineMsg =>
      'Sync paused. Showing offline notifications.';

  @override
  String get systemStatusOperationalMsg => 'System Status: Operational.';

  @override
  String get userNotAuthenticatedError => 'User not authenticated.';

  @override
  String get noLocationSelectedLabel => 'No location selected';

  @override
  String get unknownActionLabel => 'Unknown Action';

  @override
  String get clientOwnerRoleLabel => 'Client / Owner';

  @override
  String get quickDeliveryUserFallback => 'Quick Delivery User';

  @override
  String get subscriptionUpdatedSuccessMsg =>
      'Subscription updated successfully!';

  @override
  String get activePlanLabel => 'Active Plan';

  @override
  String get downgradeToFreeBtn => 'Downgrade to Free';

  @override
  String get subscriptionDowngradeConfirmTitle => 'Downgrade to Free?';

  @override
  String get subscriptionDowngradeConfirmMessage =>
      'You will immediately lose Pro features: live driver tracking, dispatch, advanced pricing, and the employee suite.';

  @override
  String get awaitingPaymentLabel => 'Awaiting Payment';

  @override
  String get upgradeToProfessionalBtn => 'Upgrade to Professional';

  @override
  String get subscriptionUpgradeConfirmTitle => 'Upgrade to Professional?';

  @override
  String get subscriptionUpgradeConfirmMessage =>
      'You will be charged \$19.99/month starting immediately, unlocking live tracking, dispatch, and the employee suite.';

  @override
  String get appUpdateRequiredTitle => 'App Update Required';

  @override
  String get mandatoryUpdateBody =>
      'A mandatory app update is available. Please update Quick Delivery to continue using the service.';

  @override
  String get whatsNewSecurityItem =>
      'Enhanced security protocols for order and delivery tracking.';

  @override
  String get whatsNewRoutingItem =>
      'Optimized routing algorithms for faster deliveries.';

  @override
  String get whatsNewBugFixesItem =>
      'Critical bug fixes and stability improvements.';

  @override
  String get installedVersionLabel => 'Installed Version';

  @override
  String get minimumRequiredLabel => 'Minimum Required';

  @override
  String get latestAvailableLabel => 'Latest Available';

  @override
  String get updateCannotContinueBody =>
      'You cannot continue using the app until this update is installed.';

  @override
  String get updateNowBtn => 'Update Now';

  @override
  String get searchServicesTooltip => 'Search services';

  @override
  String get marketplaceFiltersTooltip => 'More filters';

  @override
  String get jobCardDetailsToggle => 'Details';

  @override
  String ratingStarSemantic(int n) {
    return 'Rate $n of 5 stars';
  }

  @override
  String otpDigitSemantic(int index, int length) {
    return 'PIN digit $index of $length';
  }

  @override
  String get whatsNewTitle => 'What\'s new:';

  @override
  String get specialistRoleLabel => 'Specialist';

  @override
  String get jobMapInTransitTitle => 'In Transit - Live Courier Tracking';

  @override
  String get jobMapLiveTrackingActive => 'Live Route Tracking Active';

  @override
  String get roleOwnerLabel => 'Owner';

  @override
  String get inProgressLabel => 'In Progress';

  @override
  String get roleEmployeeLabel => 'Employee';

  @override
  String get notificationsAll => 'All';

  @override
  String get notificationsJobs => 'Jobs';

  @override
  String get notificationsSystem => 'System';

  @override
  String get notificationsAlerts => 'Alerts';

  @override
  String get confirmActionDefault => 'Confirm';

  @override
  String get cancelActionDefault => 'Cancel';

  @override
  String get depositMaxLimitError =>
      'Maximum single deposit is 1,000,000 credits';

  @override
  String get verifyNewEmailBtn => 'Verify New Email';

  @override
  String get enterCompleteOtpError => 'Enter complete 6-digit code';

  @override
  String get listEmptyTitle => 'No items found';

  @override
  String get listEmptyBody => 'There are no items to display at this time.';

  @override
  String get confirmPayoutBtn => 'Confirm Payout';

  @override
  String get continueActionLabel => 'Continue';

  @override
  String get kycUploadedStatus => 'Uploaded';

  @override
  String get defaultErrorTitle => 'Error occurred';

  @override
  String get backActionLabel => 'Back';

  @override
  String depositSuccessMessage(String amount) {
    return 'Successfully deposited $amount credits.';
  }

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
  String customerWithId(String id) {
    return 'Customer: $id';
  }

  @override
  String employeeRegisteredSuccess(String username, String id) {
    return 'Successfully created employee account:\nUsername: $username\nID: $id';
  }

  @override
  String priceRangeError(String min, String max) {
    return 'Price must be between \$$min and \$$max';
  }

  @override
  String get jobStateChangedError =>
      'Job state changed — the other party already acted or status changed.';

  @override
  String fileSizeExceededError(String size) {
    return 'File size exceeds maximum allowed size of 10MB, got ${size}MB.';
  }

  @override
  String documentOnFile(String filename) {
    return 'Document on file: $filename';
  }

  @override
  String get notificationsJobsTag => 'JOB ALERT';

  @override
  String get notificationsAlertsTag => 'ALERT';

  @override
  String get notificationsSystemTag => 'SYSTEM';

  @override
  String get notificationsDefaultTag => 'NOTIFICATION';

  @override
  String get notificationsToday => 'TODAY';

  @override
  String get notificationsYesterday => 'YESTERDAY';

  @override
  String get notificationsEarlier => 'EARLIER';

  @override
  String ticketSubmittedSuccess(String id) {
    return 'Ticket submitted successfully! Ticket ID: $id';
  }

  @override
  String get estimatedPriceCourierNotice =>
      'Estimated based on store address. Final fare is calculated from the assigned courier\'s location once accepted.';

  @override
  String get retryBookingSuccess => 'New booking created, matching courier...';

  @override
  String get matchingCourierSubtitle => 'Finding nearest available courier...';

  @override
  String get supportTicketsTitle => 'Support Tickets';

  @override
  String get supportTicketsSubtitle => 'Track and review your inquiries';

  @override
  String get settingsSupportTickets => 'Support Tickets';

  @override
  String get settingsSupportTicketsSub =>
      'View past inquiries and resolution status';

  @override
  String get createTicketFab => 'New Ticket';

  @override
  String get emptyTicketsTitle => 'No support tickets yet';

  @override
  String get emptyTicketsDesc =>
      'Need help? Open a new complaint or inquiry ticket.';

  @override
  String get openNewTicketBtn => 'Open New Ticket';

  @override
  String get ticketFilterAll => 'All';

  @override
  String get ticketFilterOpen => 'Open';

  @override
  String get ticketFilterResolved => 'Resolved';

  @override
  String get statusResolved => 'Resolved';

  @override
  String get statusAssigned => 'Assigned';

  @override
  String ticketChatTitle(String id) {
    return 'Ticket #$id';
  }

  @override
  String get ticketChatSubtitle => 'Customer Support';

  @override
  String get ticketResolvedBannerTitle => 'Ticket Resolved';

  @override
  String get ticketResolvedBannerMsg =>
      'This ticket has been marked as resolved by customer support.';

  @override
  String get ticketResolutionNote => 'Resolution Note';

  @override
  String get ticketInputClosed =>
      'This ticket is resolved and closed for new messages.';

  @override
  String ticketAssignedAgent(String agent) {
    return 'Assigned Agent: $agent';
  }

  @override
  String get ticketPendingAgent => 'Waiting for agent assignment...';

  @override
  String ticketContextJob(String id) {
    return 'Related to Job #$id';
  }

  @override
  String get viewTicketAction => 'View Ticket';

  @override
  String get courierAvailabilityTitle => 'Courier Availability';

  @override
  String get courierStatusOnline => 'Online';

  @override
  String get courierStatusOffline => 'Offline';

  @override
  String get courierStatusActiveJobLock =>
      'Availability locked during active job';

  @override
  String get courierStatusAcceptingDispatch =>
      'Accepting new delivery requests';

  @override
  String get courierStatusNotAcceptingDispatch =>
      'Not accepting new delivery requests';

  @override
  String get destinationLocationLabel => 'Destination Location';

  @override
  String get choosePickupLocationBtn => 'Choose Pickup on Map';

  @override
  String get chooseDestinationLocationBtn => 'Choose Destination on Map';

  @override
  String get changePickupLocationBtn => 'Change Pickup';

  @override
  String get changeDestinationLocationBtn => 'Change Destination';

  @override
  String get tripDistanceLabel => 'Trip Distance:';

  @override
  String get selectDestinationPrompt =>
      'Select a destination on the map to calculate trip distance and price estimate.';

  @override
  String get destinationRequiredError =>
      'Please choose a destination on the map before booking.';

  @override
  String get estimatedPriceTripNotice =>
      'Estimated price is based on the actual trip distance from pickup to destination.';

  @override
  String get settingsSecurity => 'Security';

  @override
  String get settingsSecuritySub =>
      'Two-factor authentication and login protection';

  @override
  String get settingsTwoFactorAuth => 'Two-Factor Authentication';

  @override
  String get settingsTwoFactorAuthSub =>
      'Require a 6-digit verification code when logging in';

  @override
  String get disableTwoFactorConfirmTitle =>
      'Disable Two-Factor Authentication?';

  @override
  String get disableTwoFactorConfirmBody =>
      'Disabling 2FA reduces your account security. Anyone with your password will be able to log in without an OTP verification step.';

  @override
  String get disableTwoFactorConfirmAction => 'Disable 2FA';

  @override
  String get disableTwoFactorPasswordTitle => 'Confirm Password';

  @override
  String get disableTwoFactorPasswordBody =>
      'Please enter your account password to confirm disabling two-factor authentication.';

  @override
  String get disableTwoFactorPasswordError =>
      'Incorrect password. 2FA was not disabled.';

  @override
  String get twoFactorDisabledSuccess => 'Two-factor authentication disabled';

  @override
  String get twoFactorEnabledSuccess => 'Two-factor authentication enabled';

  @override
  String get ratingSubmittedSuccess => 'Rating Submitted';

  @override
  String get newDispatchAlertMessage =>
      'New dispatch offer received. Refreshing available jobs...';

  @override
  String get freezeWorkerSubtitle =>
      'Manage worker account status, login access, and dispatch availability';

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
  String get custEstimatedPrice => 'Estimated price';

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
  String get acctSoon => 'Soon';

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
      'Customers see the first letter of your service name for now. Photo upload is coming.';

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
  String get ownSvcErrPartial =>
      'The service was created but some details weren\'t saved. Tap save again.';

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
  String courCoordsCopied(String coords) {
    return 'Location copied: $coords. Paste it into your maps app.';
  }

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
  String courPhoneCopied(String phone) {
    return 'Number copied: $phone. Paste it into your phone app to call.';
  }

  @override
  String courWillPayCash(String amount) {
    return 'Will pay $amount cash';
  }

  @override
  String courOrderPriceValue(String amount) {
    return 'Order price $amount';
  }

  @override
  String get courCopyPhone => 'Copy the phone number';

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
}
