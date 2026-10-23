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

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

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

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navServices.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get navServices;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @langAuto.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get langAuto;

  /// No description provided for @langEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @langArabic.
  ///
  /// In en, this message translates to:
  /// **'عربي مصري'**
  String get langArabic;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsThemeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get settingsThemeMode;

  /// No description provided for @settingsPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settingsPreferences;

  /// No description provided for @settingsPreferencesSub.
  ///
  /// In en, this message translates to:
  /// **'App display and regional options'**
  String get settingsPreferencesSub;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsAccountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccountSection;

  /// No description provided for @settingsAccountSectionSub.
  ///
  /// In en, this message translates to:
  /// **'Profile and user details'**
  String get settingsAccountSectionSub;

  /// No description provided for @settingsMyAccount.
  ///
  /// In en, this message translates to:
  /// **'My Account'**
  String get settingsMyAccount;

  /// No description provided for @settingsMyAccountSub.
  ///
  /// In en, this message translates to:
  /// **'Account details & preferences'**
  String get settingsMyAccountSub;

  /// No description provided for @settingsOwnerConfig.
  ///
  /// In en, this message translates to:
  /// **'Owner Configuration'**
  String get settingsOwnerConfig;

  /// No description provided for @settingsOwnerConfigSub.
  ///
  /// In en, this message translates to:
  /// **'Business management settings'**
  String get settingsOwnerConfigSub;

  /// No description provided for @settingsSupport.
  ///
  /// In en, this message translates to:
  /// **'Support & Help'**
  String get settingsSupport;

  /// No description provided for @settingsSupportSub.
  ///
  /// In en, this message translates to:
  /// **'Get assistance or submit issues'**
  String get settingsSupportSub;

  /// No description provided for @settingsCustomerService.
  ///
  /// In en, this message translates to:
  /// **'Customer Service'**
  String get settingsCustomerService;

  /// No description provided for @settingsCustomerServiceSub.
  ///
  /// In en, this message translates to:
  /// **'Contact support & submit complaint tickets'**
  String get settingsCustomerServiceSub;

  /// No description provided for @settingsLogout.
  ///
  /// In en, this message translates to:
  /// **'LOG OUT'**
  String get settingsLogout;

  /// No description provided for @myAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'My Account'**
  String get myAccountTitle;

  /// No description provided for @myAccountHeader.
  ///
  /// In en, this message translates to:
  /// **'Account Details'**
  String get myAccountHeader;

  /// No description provided for @myAccountHeaderSub.
  ///
  /// In en, this message translates to:
  /// **'Manage personal details and saved addresses'**
  String get myAccountHeaderSub;

  /// No description provided for @myAccountEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get myAccountEmailLabel;

  /// No description provided for @myAccountEmailHint.
  ///
  /// In en, this message translates to:
  /// **'Your email address'**
  String get myAccountEmailHint;

  /// No description provided for @myAccountEmailNote.
  ///
  /// In en, this message translates to:
  /// **'Your email address can be updated via OTP verification.'**
  String get myAccountEmailNote;

  /// No description provided for @changeEmailButton.
  ///
  /// In en, this message translates to:
  /// **'Change Email'**
  String get changeEmailButton;

  /// No description provided for @enterNewEmailPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter your new email address. A verification code will be sent to it.'**
  String get enterNewEmailPrompt;

  /// No description provided for @newEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'New Email Address'**
  String get newEmailLabel;

  /// No description provided for @sendVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Send Code'**
  String get sendVerificationCode;

  /// No description provided for @confirmEmailChangeButton.
  ///
  /// In en, this message translates to:
  /// **'Verify & Update Email'**
  String get confirmEmailChangeButton;

  /// No description provided for @emailChangeSuccess.
  ///
  /// In en, this message translates to:
  /// **'Email address updated successfully'**
  String get emailChangeSuccess;

  /// No description provided for @invalidEmailError.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get invalidEmailError;

  /// No description provided for @myAccountUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get myAccountUsernameLabel;

  /// No description provided for @myAccountUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter username'**
  String get myAccountUsernameHint;

  /// No description provided for @myAccountUsernameReq.
  ///
  /// In en, this message translates to:
  /// **'Username is required.'**
  String get myAccountUsernameReq;

  /// No description provided for @myAccountPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get myAccountPhoneLabel;

  /// No description provided for @myAccountPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'+201012345678'**
  String get myAccountPhoneHint;

  /// No description provided for @myAccountAddressesHeader.
  ///
  /// In en, this message translates to:
  /// **'Frequent Addresses'**
  String get myAccountAddressesHeader;

  /// No description provided for @myAccountAddressesSub.
  ///
  /// In en, this message translates to:
  /// **'Save quick locations for faster booking, max 10.'**
  String get myAccountAddressesSub;

  /// No description provided for @myAccountNewAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'New Address'**
  String get myAccountNewAddressLabel;

  /// No description provided for @myAccountNewAddressHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 123 Nile St, Cairo'**
  String get myAccountNewAddressHint;

  /// No description provided for @myAccountAddButton.
  ///
  /// In en, this message translates to:
  /// **'ADD'**
  String get myAccountAddButton;

  /// No description provided for @myAccountNoAddresses.
  ///
  /// In en, this message translates to:
  /// **'No saved addresses yet.'**
  String get myAccountNoAddresses;

  /// No description provided for @myAccountMaxAddressesError.
  ///
  /// In en, this message translates to:
  /// **'Cannot add more than 10 frequent addresses.'**
  String get myAccountMaxAddressesError;

  /// No description provided for @myAccountAddressRequired.
  ///
  /// In en, this message translates to:
  /// **'Type an address first, then tap ADD.'**
  String get myAccountAddressRequired;

  /// No description provided for @myAccountAddressRemoved.
  ///
  /// In en, this message translates to:
  /// **'Address removed.'**
  String get myAccountAddressRemoved;

  /// No description provided for @undoAction.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undoAction;

  /// No description provided for @myAccountSaveButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE PROFILE'**
  String get myAccountSaveButton;

  /// No description provided for @myAccountSuccessMsg.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully'**
  String get myAccountSuccessMsg;

  /// No description provided for @accountStatusSuspendedTitle.
  ///
  /// In en, this message translates to:
  /// **'Account Suspended'**
  String get accountStatusSuspendedTitle;

  /// No description provided for @accountStatusSuspendedDefaultReason.
  ///
  /// In en, this message translates to:
  /// **'Your account has been suspended by an administrator. Please contact support for more information.'**
  String get accountStatusSuspendedDefaultReason;

  /// No description provided for @accountStatusActiveBadge.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get accountStatusActiveBadge;

  /// No description provided for @accountStatusSuspendedBadge.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get accountStatusSuspendedBadge;

  /// No description provided for @ownerConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Owner Configuration'**
  String get ownerConfigTitle;

  /// No description provided for @ownerConfigHeader.
  ///
  /// In en, this message translates to:
  /// **'Business Details'**
  String get ownerConfigHeader;

  /// No description provided for @ownerConfigHeaderSub.
  ///
  /// In en, this message translates to:
  /// **'Update business parameters and service terms'**
  String get ownerConfigHeaderSub;

  /// No description provided for @ownerConfigNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Business Name'**
  String get ownerConfigNameLabel;

  /// No description provided for @ownerConfigNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Quick Delivery Services'**
  String get ownerConfigNameHint;

  /// No description provided for @ownerConfigNameReq.
  ///
  /// In en, this message translates to:
  /// **'Business name is required.'**
  String get ownerConfigNameReq;

  /// No description provided for @ownerConfigCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get ownerConfigCategoryLabel;

  /// No description provided for @ownerConfigAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get ownerConfigAddressLabel;

  /// No description provided for @ownerConfigAddressHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 456 Nile St, Cairo'**
  String get ownerConfigAddressHint;

  /// No description provided for @ownerConfigHoursLabel.
  ///
  /// In en, this message translates to:
  /// **'Working Hours'**
  String get ownerConfigHoursLabel;

  /// No description provided for @ownerConfigHoursHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 8:00 AM - 10:00 PM'**
  String get ownerConfigHoursHint;

  /// No description provided for @ownerConfigRadiusLabel.
  ///
  /// In en, this message translates to:
  /// **'Coverage radius'**
  String get ownerConfigRadiusLabel;

  /// No description provided for @ownerConfigRadiusHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 25.0'**
  String get ownerConfigRadiusHint;

  /// No description provided for @ownerConfigRadiusReq.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid radius > 0.'**
  String get ownerConfigRadiusReq;

  /// No description provided for @ownerConfigAddressInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid address with at least 3 characters.'**
  String get ownerConfigAddressInvalid;

  /// No description provided for @ownerConfigHoursInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter valid working hours, e.g. 8:00 AM - 10:00 PM.'**
  String get ownerConfigHoursInvalid;

  /// No description provided for @scheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly Schedule'**
  String get scheduleTitle;

  /// No description provided for @scheduleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell customers when you\'re open. Leave unset to stay listed as always open.'**
  String get scheduleSubtitle;

  /// No description provided for @scheduleSetBtn.
  ///
  /// In en, this message translates to:
  /// **'Set working hours'**
  String get scheduleSetBtn;

  /// No description provided for @scheduleRemoveBtn.
  ///
  /// In en, this message translates to:
  /// **'Remove hours'**
  String get scheduleRemoveBtn;

  /// No description provided for @scheduleModeSameDaily.
  ///
  /// In en, this message translates to:
  /// **'Same every day'**
  String get scheduleModeSameDaily;

  /// No description provided for @scheduleModePerDay.
  ///
  /// In en, this message translates to:
  /// **'Different per day'**
  String get scheduleModePerDay;

  /// No description provided for @scheduleOpenLabel.
  ///
  /// In en, this message translates to:
  /// **'Opens'**
  String get scheduleOpenLabel;

  /// No description provided for @scheduleCloseLabel.
  ///
  /// In en, this message translates to:
  /// **'Closes'**
  String get scheduleCloseLabel;

  /// No description provided for @scheduleOffLabel.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get scheduleOffLabel;

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

  /// No description provided for @outOfServiceBadge.
  ///
  /// In en, this message translates to:
  /// **'Out of Service'**
  String get outOfServiceBadge;

  /// No description provided for @outOfServiceReopensAt.
  ///
  /// In en, this message translates to:
  /// **'Out of Service — opens {time}'**
  String outOfServiceReopensAt(String time);

  /// No description provided for @ownerConfigBasePriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Base price'**
  String get ownerConfigBasePriceLabel;

  /// No description provided for @ownerConfigBasePriceHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 10.00'**
  String get ownerConfigBasePriceHint;

  /// No description provided for @ownerConfigBasePriceReq.
  ///
  /// In en, this message translates to:
  /// **'Base price must be >= 0.'**
  String get ownerConfigBasePriceReq;

  /// No description provided for @ownerConfigPricePerKmLabel.
  ///
  /// In en, this message translates to:
  /// **'Price per km'**
  String get ownerConfigPricePerKmLabel;

  /// No description provided for @ownerConfigPricePerKmHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1.50'**
  String get ownerConfigPricePerKmHint;

  /// No description provided for @ownerConfigPricePerKmReq.
  ///
  /// In en, this message translates to:
  /// **'Price per KM must be >= 0.'**
  String get ownerConfigPricePerKmReq;

  /// No description provided for @ownerConfigPhotoUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://example.com/logo.png'**
  String get ownerConfigPhotoUrlHint;

  /// No description provided for @ownerConfigLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Business Location'**
  String get ownerConfigLocationLabel;

  /// No description provided for @ownerConfigLocationReq.
  ///
  /// In en, this message translates to:
  /// **'Please select your business location on the map.'**
  String get ownerConfigLocationReq;

  /// No description provided for @customerMarketplaceFilterNearby.
  ///
  /// In en, this message translates to:
  /// **'Nearby Only'**
  String get customerMarketplaceFilterNearby;

  /// No description provided for @ownerConfigSaveButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE CONFIGURATION'**
  String get ownerConfigSaveButton;

  /// No description provided for @ownerConfigSuccessMsg.
  ///
  /// In en, this message translates to:
  /// **'Owner configuration updated successfully'**
  String get ownerConfigSuccessMsg;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Log in to manage your services'**
  String get loginSubtitle;

  /// No description provided for @loginEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get loginEmailLabel;

  /// No description provided for @loginEmailHint.
  ///
  /// In en, this message translates to:
  /// **'name@example.com'**
  String get loginEmailHint;

  /// No description provided for @loginEmailReq.
  ///
  /// In en, this message translates to:
  /// **'Email is required.'**
  String get loginEmailReq;

  /// No description provided for @loginEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get loginEmailInvalid;

  /// No description provided for @loginPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPasswordLabel;

  /// No description provided for @loginPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get loginPasswordHint;

  /// No description provided for @loginPasswordReq.
  ///
  /// In en, this message translates to:
  /// **'Password is required.'**
  String get loginPasswordReq;

  /// No description provided for @loginSubmitButton.
  ///
  /// In en, this message translates to:
  /// **'SIGN IN'**
  String get loginSubmitButton;

  /// No description provided for @loginForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get loginForgotPassword;

  /// No description provided for @loginNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get loginNoAccount;

  /// No description provided for @loginSignUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get loginSignUp;

  /// No description provided for @signupTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get signupTitle;

  /// No description provided for @signupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Join Quick Delivery today'**
  String get signupSubtitle;

  /// No description provided for @signupUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get signupUsernameLabel;

  /// No description provided for @signupUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'johndoe'**
  String get signupUsernameHint;

  /// No description provided for @signupUsernameReq.
  ///
  /// In en, this message translates to:
  /// **'Please enter a username'**
  String get signupUsernameReq;

  /// No description provided for @signupEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get signupEmailLabel;

  /// No description provided for @signupEmailHint.
  ///
  /// In en, this message translates to:
  /// **'name@example.com'**
  String get signupEmailHint;

  /// No description provided for @signupPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get signupPasswordLabel;

  /// No description provided for @signupPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get signupPasswordHint;

  /// No description provided for @signupConfirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get signupConfirmPasswordLabel;

  /// No description provided for @signupConfirmPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Re-enter password'**
  String get signupConfirmPasswordHint;

  /// No description provided for @signupPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get signupPasswordMismatch;

  /// No description provided for @signupRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Account Type'**
  String get signupRoleLabel;

  /// No description provided for @signupRoleCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get signupRoleCustomer;

  /// No description provided for @signupRoleOwner.
  ///
  /// In en, this message translates to:
  /// **'Business Owner'**
  String get signupRoleOwner;

  /// No description provided for @signupSubmitButton.
  ///
  /// In en, this message translates to:
  /// **'CREATE ACCOUNT'**
  String get signupSubmitButton;

  /// No description provided for @signupHasAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get signupHasAccount;

  /// No description provided for @signupSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signupSignIn;

  /// No description provided for @otpTitle.
  ///
  /// In en, this message translates to:
  /// **'Two-Factor Verification'**
  String get otpTitle;

  /// No description provided for @otpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code sent to your email'**
  String get otpSubtitle;

  /// No description provided for @otpCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'6-Digit OTP Code'**
  String get otpCodeLabel;

  /// No description provided for @otpSubmitButton.
  ///
  /// In en, this message translates to:
  /// **'VERIFY CODE'**
  String get otpSubmitButton;

  /// No description provided for @otpResendButton.
  ///
  /// In en, this message translates to:
  /// **'RESEND CODE'**
  String get otpResendButton;

  /// No description provided for @otpFooterBrand.
  ///
  /// In en, this message translates to:
  /// **'Quick Delivery'**
  String get otpFooterBrand;

  /// No description provided for @otpFooterNote.
  ///
  /// In en, this message translates to:
  /// **'Never share your verification code with anyone.'**
  String get otpFooterNote;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get forgotPasswordTitle;

  /// No description provided for @forgotPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and new credentials'**
  String get forgotPasswordSubtitle;

  /// No description provided for @forgotPasswordSubmitButton.
  ///
  /// In en, this message translates to:
  /// **'RESET PASSWORD'**
  String get forgotPasswordSubmitButton;

  /// No description provided for @forgotPasswordStep1Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your account email — we\'ll send a verification code.'**
  String get forgotPasswordStep1Subtitle;

  /// No description provided for @forgotPasswordSendCodeButton.
  ///
  /// In en, this message translates to:
  /// **'SEND CODE'**
  String get forgotPasswordSendCodeButton;

  /// No description provided for @newPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your new password.'**
  String get newPasswordSubtitle;

  /// No description provided for @resetSessionExpiredMsg.
  ///
  /// In en, this message translates to:
  /// **'This reset session has expired. Please restart from the email step to get a new code.'**
  String get resetSessionExpiredMsg;

  /// No description provided for @resetBackToEmailStep.
  ///
  /// In en, this message translates to:
  /// **'Back to email step'**
  String get resetBackToEmailStep;

  /// No description provided for @resetBackToCodeStep.
  ///
  /// In en, this message translates to:
  /// **'Back to code step'**
  String get resetBackToCodeStep;

  /// No description provided for @customerHomeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Welcome back,'**
  String get customerHomeGreeting;

  /// No description provided for @customerHomeSub.
  ///
  /// In en, this message translates to:
  /// **'What service do you need today?'**
  String get customerHomeSub;

  /// No description provided for @customerHomeQuickAccess.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get customerHomeQuickAccess;

  /// No description provided for @customerHomeCatDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get customerHomeCatDelivery;

  /// No description provided for @customerHomeCatRide.
  ///
  /// In en, this message translates to:
  /// **'Ride'**
  String get customerHomeCatRide;

  /// No description provided for @customerHomeCatShipping.
  ///
  /// In en, this message translates to:
  /// **'Shipping'**
  String get customerHomeCatShipping;

  /// No description provided for @customerHomeCatBrowseAll.
  ///
  /// In en, this message translates to:
  /// **'Browse All'**
  String get customerHomeCatBrowseAll;

  /// No description provided for @customerHomeRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get customerHomeRecentActivity;

  /// No description provided for @customerHomeQuickBookBtn.
  ///
  /// In en, this message translates to:
  /// **'BOOK NOW'**
  String get customerHomeQuickBookBtn;

  /// No description provided for @customerMarketplaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Explore Services'**
  String get customerMarketplaceTitle;

  /// No description provided for @customerMarketplaceFilterCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get customerMarketplaceFilterCategory;

  /// No description provided for @customerMarketplaceFilterRadius.
  ///
  /// In en, this message translates to:
  /// **'Max distance'**
  String get customerMarketplaceFilterRadius;

  /// No description provided for @unitKm.
  ///
  /// In en, this message translates to:
  /// **'km'**
  String get unitKm;

  /// No description provided for @customerMarketplaceChooseMap.
  ///
  /// In en, this message translates to:
  /// **'Choose Location on Map'**
  String get customerMarketplaceChooseMap;

  /// No description provided for @applyFiltersBtn.
  ///
  /// In en, this message translates to:
  /// **'Apply Filters'**
  String get applyFiltersBtn;

  /// No description provided for @clearFiltersBtn.
  ///
  /// In en, this message translates to:
  /// **'Clear Filters'**
  String get clearFiltersBtn;

  /// No description provided for @adjustFiltersDesc.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting your search query or status filter.'**
  String get adjustFiltersDesc;

  /// No description provided for @customerJobsTitle.
  ///
  /// In en, this message translates to:
  /// **'My Orders'**
  String get customerJobsTitle;

  /// No description provided for @customerJobsSub.
  ///
  /// In en, this message translates to:
  /// **'Track and manage your delivery history.'**
  String get customerJobsSub;

  /// No description provided for @customerJobsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by Order ID, Location...'**
  String get customerJobsSearchHint;

  /// No description provided for @customerJobsInTransit.
  ///
  /// In en, this message translates to:
  /// **'In Transit'**
  String get customerJobsInTransit;

  /// No description provided for @customerJobsPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get customerJobsPrice;

  /// No description provided for @customerJobsOrder.
  ///
  /// In en, this message translates to:
  /// **'Order #'**
  String get customerJobsOrder;

  /// No description provided for @customerJobsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No Orders Found'**
  String get customerJobsEmpty;

  /// No description provided for @customerJobsEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t placed any orders yet. Explore services in the marketplace to get started.'**
  String get customerJobsEmptyDescription;

  /// No description provided for @jobStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Order Status'**
  String get jobStatusTitle;

  /// No description provided for @jobStatusOpenTicketBtn.
  ///
  /// In en, this message translates to:
  /// **'Open Complaint Ticket'**
  String get jobStatusOpenTicketBtn;

  /// No description provided for @ownerHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'History & Audit Logs'**
  String get ownerHistoryTitle;

  /// No description provided for @ownerHistoryTabJobs.
  ///
  /// In en, this message translates to:
  /// **'Jobs'**
  String get ownerHistoryTabJobs;

  /// No description provided for @ownerHistoryTabLedger.
  ///
  /// In en, this message translates to:
  /// **'Ledger'**
  String get ownerHistoryTabLedger;

  /// No description provided for @employeeJobsTitle.
  ///
  /// In en, this message translates to:
  /// **'Assigned Jobs'**
  String get employeeJobsTitle;

  /// No description provided for @employeeScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Workers'**
  String get employeeScreenTitle;

  /// No description provided for @chatTitle.
  ///
  /// In en, this message translates to:
  /// **'Job Chat'**
  String get chatTitle;

  /// No description provided for @chatTypeHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get chatTypeHint;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get notificationsClear;

  /// No description provided for @walletTotalBalance.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get walletTotalBalance;

  /// No description provided for @walletWithdrawable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get walletWithdrawable;

  /// No description provided for @ratingTitle.
  ///
  /// In en, this message translates to:
  /// **'Rate Service'**
  String get ratingTitle;

  /// No description provided for @ratingSubmitBtn.
  ///
  /// In en, this message translates to:
  /// **'SUBMIT RATING'**
  String get ratingSubmitBtn;

  /// No description provided for @locationPickerUseMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Use My Location'**
  String get locationPickerUseMyLocation;

  /// No description provided for @locationPickerConfirmBtn.
  ///
  /// In en, this message translates to:
  /// **'Confirm Location'**
  String get locationPickerConfirmBtn;

  /// No description provided for @locationNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Landmark note · optional'**
  String get locationNoteLabel;

  /// No description provided for @locationNoteHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. next to Ahmed\'s kiosk, 3rd floor — helps your driver find you'**
  String get locationNoteHint;

  /// No description provided for @ticketSubjectReq.
  ///
  /// In en, this message translates to:
  /// **'Subject is required.'**
  String get ticketSubjectReq;

  /// No description provided for @ticketDescriptionReq.
  ///
  /// In en, this message translates to:
  /// **'Issue details are required.'**
  String get ticketDescriptionReq;

  /// No description provided for @liveCourierTracking.
  ///
  /// In en, this message translates to:
  /// **'Live Courier Tracking'**
  String get liveCourierTracking;

  /// No description provided for @subscriptionPlansTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription Plans'**
  String get subscriptionPlansTitle;

  /// No description provided for @fleetLiveMapTitle.
  ///
  /// In en, this message translates to:
  /// **'Fleet Live Map'**
  String get fleetLiveMapTitle;

  /// No description provided for @reconciliationReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Escrow Reconciliation Review'**
  String get reconciliationReviewTitle;

  /// No description provided for @reconciliationEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No jobs pending reconciliation'**
  String get reconciliationEmptyTitle;

  /// No description provided for @reconciliationEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'All escrow transactions are healthy. No flagged jobs require manual review.'**
  String get reconciliationEmptyDesc;

  /// No description provided for @reconciliationFailureReason.
  ///
  /// In en, this message translates to:
  /// **'Failure Reason'**
  String get reconciliationFailureReason;

  /// No description provided for @reconciliationNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get reconciliationNote;

  /// No description provided for @reconciliationLockedEscrow.
  ///
  /// In en, this message translates to:
  /// **'Locked Escrow'**
  String get reconciliationLockedEscrow;

  /// No description provided for @reconciliationEmployeeId.
  ///
  /// In en, this message translates to:
  /// **'Employee ID'**
  String get reconciliationEmployeeId;

  /// No description provided for @reconciliationCustomerId.
  ///
  /// In en, this message translates to:
  /// **'Customer ID'**
  String get reconciliationCustomerId;

  /// No description provided for @reconciliationServiceId.
  ///
  /// In en, this message translates to:
  /// **'Service ID'**
  String get reconciliationServiceId;

  /// No description provided for @reconciliationRefundCustomer.
  ///
  /// In en, this message translates to:
  /// **'Refund to Customer'**
  String get reconciliationRefundCustomer;

  /// No description provided for @reconciliationReleaseEmployee.
  ///
  /// In en, this message translates to:
  /// **'Release to Employee'**
  String get reconciliationReleaseEmployee;

  /// No description provided for @reconciliationConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm {actionLabel}'**
  String reconciliationConfirmTitle(String actionLabel);

  /// No description provided for @reconciliationConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to {actionLabel} for Job #{jobId}?\n\nThis will transfer {amount} Credits back to the {targetRole}. Real funds will be moved.'**
  String reconciliationConfirmMessage(
      String actionLabel, String jobId, String amount, String targetRole);

  /// No description provided for @reconciliationSuccessRelease.
  ///
  /// In en, this message translates to:
  /// **'Escrow resolved: funds released to employee/tenant'**
  String get reconciliationSuccessRelease;

  /// No description provided for @reconciliationSuccessRefund.
  ///
  /// In en, this message translates to:
  /// **'Escrow resolved: funds refunded to customer'**
  String get reconciliationSuccessRefund;

  /// No description provided for @reconciliationFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to resolve reconciliation'**
  String get reconciliationFailed;

  /// No description provided for @roleEmployeeTenant.
  ///
  /// In en, this message translates to:
  /// **'employee/tenant'**
  String get roleEmployeeTenant;

  /// No description provided for @roleCustomer.
  ///
  /// In en, this message translates to:
  /// **'customer'**
  String get roleCustomer;

  /// No description provided for @chatFailedSend.
  ///
  /// In en, this message translates to:
  /// **'Failed to send message: {error}'**
  String chatFailedSend(String error);

  /// No description provided for @filterSortPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get filterSortPrice;

  /// No description provided for @filterSortNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get filterSortNone;

  /// No description provided for @bookingFailed.
  ///
  /// In en, this message translates to:
  /// **'Booking Failed: {error}'**
  String bookingFailed(String error);

  /// No description provided for @actionLoggedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Action logged successfully: \"{action}\"'**
  String actionLoggedSuccess(String action);

  /// No description provided for @jobMarkedCompletedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Job marked as completed successfully!'**
  String get jobMarkedCompletedSuccess;

  /// No description provided for @quickDeliveryDashboard.
  ///
  /// In en, this message translates to:
  /// **'Quick Delivery Dashboard'**
  String get quickDeliveryDashboard;

  /// No description provided for @forgotPasswordSentMsg.
  ///
  /// In en, this message translates to:
  /// **'A password reset code has been sent if an account exists.'**
  String get forgotPasswordSentMsg;

  /// No description provided for @counterOfferSuccessMsg.
  ///
  /// In en, this message translates to:
  /// **'Counter-offer submitted successfully!'**
  String get counterOfferSuccessMsg;

  /// No description provided for @kycTakeCamera.
  ///
  /// In en, this message translates to:
  /// **'Take Photo with Camera'**
  String get kycTakeCamera;

  /// No description provided for @kycChooseGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose Image from Gallery'**
  String get kycChooseGallery;

  /// No description provided for @kycSelectPdf.
  ///
  /// In en, this message translates to:
  /// **'Select PDF Document'**
  String get kycSelectPdf;

  /// No description provided for @otpResendSuccessMsg.
  ///
  /// In en, this message translates to:
  /// **'A new OTP code has been sent successfully.'**
  String get otpResendSuccessMsg;

  /// No description provided for @ratingIdentityError.
  ///
  /// In en, this message translates to:
  /// **'Error: Cannot determine other party identity.'**
  String get ratingIdentityError;

  /// No description provided for @ratingSuccessMsg.
  ///
  /// In en, this message translates to:
  /// **'Blind rating submitted successfully!'**
  String get ratingSuccessMsg;

  /// No description provided for @ratingFailed.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String ratingFailed(String error);

  /// No description provided for @cancelJobHeader.
  ///
  /// In en, this message translates to:
  /// **'Cancel Job #{jobId}'**
  String cancelJobHeader(String jobId);

  /// No description provided for @cancelJobKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep Job'**
  String get cancelJobKeep;

  /// No description provided for @cancelJobConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm Cancel'**
  String get cancelJobConfirm;

  /// No description provided for @cancelRequestHeader.
  ///
  /// In en, this message translates to:
  /// **'Request Cancellation'**
  String get cancelRequestHeader;

  /// No description provided for @cancelRequestBodyLong.
  ///
  /// In en, this message translates to:
  /// **'Please provide a reason for requesting cancellation. Your request will be sent to the business owner for approval — the job stays active until they respond.'**
  String get cancelRequestBodyLong;

  /// No description provided for @cancelRequestConfirm.
  ///
  /// In en, this message translates to:
  /// **'Send Request'**
  String get cancelRequestConfirm;

  /// No description provided for @cancelRequestPendingBanner.
  ///
  /// In en, this message translates to:
  /// **'Cancellation requested — waiting for owner approval.'**
  String get cancelRequestPendingBanner;

  /// No description provided for @employeePricePendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for fare confirmation'**
  String get employeePricePendingTitle;

  /// No description provided for @employeePricePendingBody.
  ///
  /// In en, this message translates to:
  /// **'Proposed fare {price} — the trip starts automatically once the fare is accepted. Completing is only possible on an active trip.'**
  String employeePricePendingBody(Object price);

  /// No description provided for @employeePricePendingExpiry.
  ///
  /// In en, this message translates to:
  /// **'Request expires in {remaining} — then it is cancelled automatically.'**
  String employeePricePendingExpiry(Object remaining);

  /// No description provided for @employeePriceAcceptConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Accept this fare?'**
  String get employeePriceAcceptConfirmTitle;

  /// No description provided for @employeePriceAcceptConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Accept the proposed fare {price}? The trip will start immediately and can then be completed. This is a financial commitment.'**
  String employeePriceAcceptConfirmMessage(Object price);

  /// No description provided for @employeeProposePriceTitle.
  ///
  /// In en, this message translates to:
  /// **'Propose a Fare'**
  String get employeeProposePriceTitle;

  /// No description provided for @employeeProposePriceBody.
  ///
  /// In en, this message translates to:
  /// **'Suggest your fare — the customer accepts or declines it. One proposal per trip, within the allowed bound.'**
  String get employeeProposePriceBody;

  /// No description provided for @employeeProposeSuccessMsg.
  ///
  /// In en, this message translates to:
  /// **'Price proposal sent — waiting for the customer.'**
  String get employeeProposeSuccessMsg;

  /// No description provided for @employeeProposalRacedError.
  ///
  /// In en, this message translates to:
  /// **'The customer already sent a price — respond to it instead.'**
  String get employeeProposalRacedError;

  /// No description provided for @cancelRequestRejectedBanner.
  ///
  /// In en, this message translates to:
  /// **'The business owner declined your cancellation request. You remain assigned to this job.'**
  String get cancelRequestRejectedBanner;

  /// No description provided for @cancelRequestSentMsg.
  ///
  /// In en, this message translates to:
  /// **'Cancellation request sent to the business owner.'**
  String get cancelRequestSentMsg;

  /// No description provided for @employeeRequestCancelButton.
  ///
  /// In en, this message translates to:
  /// **'Request Cancellation'**
  String get employeeRequestCancelButton;

  /// No description provided for @ownerCancelRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Employee requested cancellation'**
  String get ownerCancelRequestTitle;

  /// No description provided for @ownerCancelRequestApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve Cancellation'**
  String get ownerCancelRequestApprove;

  /// No description provided for @ownerCancelRequestDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline Request'**
  String get ownerCancelRequestDecline;

  /// No description provided for @ownerCancelRequestResolved.
  ///
  /// In en, this message translates to:
  /// **'Request resolved.'**
  String get ownerCancelRequestResolved;

  /// No description provided for @ownerCancelRequestApproveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve Cancellation?'**
  String get ownerCancelRequestApproveConfirmTitle;

  /// No description provided for @ownerCancelRequestApproveConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Approving this cancellation request will cancel the job and trigger a full refund of any escrowed funds to the customer.'**
  String get ownerCancelRequestApproveConfirmMessage;

  /// No description provided for @ownerCancelRequestDeclineConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Decline Cancellation Request?'**
  String get ownerCancelRequestDeclineConfirmTitle;

  /// No description provided for @ownerCancelRequestDeclineConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Declining this request will keep the job active with the courier currently assigned.'**
  String get ownerCancelRequestDeclineConfirmMessage;

  /// No description provided for @ownerCancelRequestApproved.
  ///
  /// In en, this message translates to:
  /// **'Cancellation request approved. Job cancelled and escrow refunded.'**
  String get ownerCancelRequestApproved;

  /// No description provided for @ownerCancelRequestDeclined.
  ///
  /// In en, this message translates to:
  /// **'Cancellation request declined. Courier remains assigned.'**
  String get ownerCancelRequestDeclined;

  /// No description provided for @locationPermissionDeniedDefault.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied. Defaulting to Cairo.'**
  String get locationPermissionDeniedDefault;

  /// No description provided for @locationFetchError.
  ///
  /// In en, this message translates to:
  /// **'Error fetching location: {error}'**
  String locationFetchError(String error);

  /// No description provided for @settingsKycRowTitle.
  ///
  /// In en, this message translates to:
  /// **'Identity verification'**
  String get settingsKycRowTitle;

  /// No description provided for @settingsKycSubtitleDefault.
  ///
  /// In en, this message translates to:
  /// **'Verify your account identity and documents'**
  String get settingsKycSubtitleDefault;

  /// No description provided for @settingsKycSubtitleRejected.
  ///
  /// In en, this message translates to:
  /// **'Verification Rejected - Action Required'**
  String get settingsKycSubtitleRejected;

  /// No description provided for @settingsKycSubtitlePending.
  ///
  /// In en, this message translates to:
  /// **'Verification Pending Approval'**
  String get settingsKycSubtitlePending;

  /// No description provided for @ownerHomeTabTitleDashboard.
  ///
  /// In en, this message translates to:
  /// **'Quick Delivery Owner Dashboard'**
  String get ownerHomeTabTitleDashboard;

  /// No description provided for @ownerHomeTabTitleWorkers.
  ///
  /// In en, this message translates to:
  /// **'Manage Workers'**
  String get ownerHomeTabTitleWorkers;

  /// No description provided for @ownerHomeWelcomeUser.
  ///
  /// In en, this message translates to:
  /// **'Welcome back, {name}!'**
  String ownerHomeWelcomeUser(String name);

  /// No description provided for @ownerHomeAccountId.
  ///
  /// In en, this message translates to:
  /// **'Account ID: {id}'**
  String ownerHomeAccountId(String id);

  /// No description provided for @ownerHomeProfileInfo.
  ///
  /// In en, this message translates to:
  /// **'Profile Information'**
  String get ownerHomeProfileInfo;

  /// No description provided for @ownerHomeLabelUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get ownerHomeLabelUsername;

  /// No description provided for @ownerHomeLabelEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get ownerHomeLabelEmail;

  /// No description provided for @ownerHomeLabelRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get ownerHomeLabelRole;

  /// No description provided for @ownerHomeTooltipEscrowReconciliation.
  ///
  /// In en, this message translates to:
  /// **'Escrow Reconciliation'**
  String get ownerHomeTooltipEscrowReconciliation;

  /// No description provided for @ownerHomeTooltipNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get ownerHomeTooltipNotifications;

  /// No description provided for @ownerHomeTooltipSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get ownerHomeTooltipSettings;

  /// No description provided for @ownerHomeNavHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get ownerHomeNavHome;

  /// No description provided for @ownerHomeNavEmployees.
  ///
  /// In en, this message translates to:
  /// **'Employees'**
  String get ownerHomeNavEmployees;

  /// No description provided for @ownerHomeNavHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get ownerHomeNavHistory;

  /// No description provided for @ownerHomeNavSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get ownerHomeNavSettings;

  /// No description provided for @ownerHomeTenantId.
  ///
  /// In en, this message translates to:
  /// **'Tenant Owner ID: {id}'**
  String ownerHomeTenantId(String id);

  /// No description provided for @ownerHomeCreditsAmount.
  ///
  /// In en, this message translates to:
  /// **'{amount} Credits'**
  String ownerHomeCreditsAmount(String amount);

  /// No description provided for @ownerHomeSubTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get ownerHomeSubTitle;

  /// No description provided for @ownerHomeRosterTitle.
  ///
  /// In en, this message translates to:
  /// **'Roster'**
  String get ownerHomeRosterTitle;

  /// No description provided for @ownerHomeEmployeesSub.
  ///
  /// In en, this message translates to:
  /// **'Employees'**
  String get ownerHomeEmployeesSub;

  /// No description provided for @ownerHomeEscrowTitle.
  ///
  /// In en, this message translates to:
  /// **'Escrow'**
  String get ownerHomeEscrowTitle;

  /// No description provided for @ownerHomeReviewQueueSub.
  ///
  /// In en, this message translates to:
  /// **'Review Queue'**
  String get ownerHomeReviewQueueSub;

  /// No description provided for @ownerHomeMyWallet.
  ///
  /// In en, this message translates to:
  /// **'My Wallet'**
  String get ownerHomeMyWallet;

  /// No description provided for @ownerHomeWalletSub.
  ///
  /// In en, this message translates to:
  /// **'Ledger & balance'**
  String get ownerHomeWalletSub;

  /// No description provided for @ownerHomeServiceReputation.
  ///
  /// In en, this message translates to:
  /// **'Your Service Reputation'**
  String get ownerHomeServiceReputation;

  /// No description provided for @ownerHomeOwnerJobs.
  ///
  /// In en, this message translates to:
  /// **'Owner Jobs'**
  String get ownerHomeOwnerJobs;

  /// No description provided for @ownerHomeNoJobsTitle.
  ///
  /// In en, this message translates to:
  /// **'No Owner Jobs Found'**
  String get ownerHomeNoJobsTitle;

  /// No description provided for @ownerHomeNoJobsDesc.
  ///
  /// In en, this message translates to:
  /// **'You currently have no jobs registered under your tenant account.'**
  String get ownerHomeNoJobsDesc;

  /// No description provided for @ownerHomeViewAllJobs.
  ///
  /// In en, this message translates to:
  /// **'VIEW ALL JOBS'**
  String get ownerHomeViewAllJobs;

  /// No description provided for @ownerHomeFleetSub.
  ///
  /// In en, this message translates to:
  /// **'Track couriers live'**
  String get ownerHomeFleetSub;

  /// No description provided for @ownerHomeJobId.
  ///
  /// In en, this message translates to:
  /// **'Job #{id}'**
  String ownerHomeJobId(String id);

  /// No description provided for @ownerHomePaymentInfo.
  ///
  /// In en, this message translates to:
  /// **'Payment: {method}{escrowInfo}'**
  String ownerHomePaymentInfo(String method, String escrowInfo);

  /// No description provided for @ownerHomeCancelJob.
  ///
  /// In en, this message translates to:
  /// **'Cancel Job'**
  String get ownerHomeCancelJob;

  /// No description provided for @ownerHomeJobCancelled.
  ///
  /// In en, this message translates to:
  /// **'Job cancelled successfully.'**
  String get ownerHomeJobCancelled;

  /// No description provided for @ownerHomeJobCancelledEscrowRefunded.
  ///
  /// In en, this message translates to:
  /// **'Job cancelled successfully. Escrow refunded to wallet.'**
  String get ownerHomeJobCancelledEscrowRefunded;

  /// No description provided for @ownerCancelJobEscrowWarning.
  ///
  /// In en, this message translates to:
  /// **'Cancelling this job will immediately refund \${amount} from locked escrow back to the customer\'s wallet. Please provide a reason for cancellation:'**
  String ownerCancelJobEscrowWarning(String amount);

  /// No description provided for @ownerCancelJobPlainWarning.
  ///
  /// In en, this message translates to:
  /// **'Cancelling this job will stop all delivery activity immediately. Please provide a reason for cancellation:'**
  String get ownerCancelJobPlainWarning;

  /// No description provided for @ownerHistoryTabActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get ownerHistoryTabActivity;

  /// No description provided for @ownerHistoryNoActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'No Employee Activity Found'**
  String get ownerHistoryNoActivityTitle;

  /// No description provided for @ownerHistoryNoActivityDesc.
  ///
  /// In en, this message translates to:
  /// **'No tenant audit log events recorded yet.'**
  String get ownerHistoryNoActivityDesc;

  /// No description provided for @ownerHistoryActorId.
  ///
  /// In en, this message translates to:
  /// **'Actor: {id}'**
  String ownerHistoryActorId(String id);

  /// No description provided for @ownerHistoryNoJobsTitle.
  ///
  /// In en, this message translates to:
  /// **'No Completed Jobs Found'**
  String get ownerHistoryNoJobsTitle;

  /// No description provided for @ownerHistoryNoJobsDesc.
  ///
  /// In en, this message translates to:
  /// **'No completed or cancelled jobs recorded for your tenant.'**
  String get ownerHistoryNoJobsDesc;

  /// No description provided for @ownerHistoryCancellationReason.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String ownerHistoryCancellationReason(String reason);

  /// No description provided for @ownerHistoryNoLedgerTitle.
  ///
  /// In en, this message translates to:
  /// **'No Ledger Entries Found'**
  String get ownerHistoryNoLedgerTitle;

  /// No description provided for @ownerHistoryNoLedgerDesc.
  ///
  /// In en, this message translates to:
  /// **'No wallet transaction history recorded yet.'**
  String get ownerHistoryNoLedgerDesc;

  /// No description provided for @ownerHistoryBalanceAfter.
  ///
  /// In en, this message translates to:
  /// **'Balance after: \${amount}{jobInfo}'**
  String ownerHistoryBalanceAfter(String amount, String jobInfo);

  /// No description provided for @employeeJobsTooltipVerification.
  ///
  /// In en, this message translates to:
  /// **'Verification Documents'**
  String get employeeJobsTooltipVerification;

  /// No description provided for @employeeJobsJobId.
  ///
  /// In en, this message translates to:
  /// **'Job #{id}'**
  String employeeJobsJobId(String id);

  /// No description provided for @employeeJobsSuggestionArrivedPickup.
  ///
  /// In en, this message translates to:
  /// **'Arrived at Pickup'**
  String get employeeJobsSuggestionArrivedPickup;

  /// No description provided for @employeeJobsSuggestionInRoute.
  ///
  /// In en, this message translates to:
  /// **'Job in Route'**
  String get employeeJobsSuggestionInRoute;

  /// No description provided for @employeeJobsSuggestionArrivedDestination.
  ///
  /// In en, this message translates to:
  /// **'Arrived at Destination'**
  String get employeeJobsSuggestionArrivedDestination;

  /// No description provided for @employeeJobsSuggestionCompleted.
  ///
  /// In en, this message translates to:
  /// **'Job Completed'**
  String get employeeJobsSuggestionCompleted;

  /// No description provided for @employeeJobsSimulatorTitle.
  ///
  /// In en, this message translates to:
  /// **'Log Service Event'**
  String get employeeJobsSimulatorTitle;

  /// No description provided for @employeeJobsSimulatorDesc.
  ///
  /// In en, this message translates to:
  /// **'Log status updates and service events directly into the tenant audit trail.'**
  String get employeeJobsSimulatorDesc;

  /// No description provided for @employeeJobsSimulatorLabel.
  ///
  /// In en, this message translates to:
  /// **'Service Event Action'**
  String get employeeJobsSimulatorLabel;

  /// No description provided for @employeeJobsSimulatorHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Arrived at Pickup, Job in Route'**
  String get employeeJobsSimulatorHint;

  /// No description provided for @employeeJobsSimulatorValidation.
  ///
  /// In en, this message translates to:
  /// **'Please enter or select a service event to log'**
  String get employeeJobsSimulatorValidation;

  /// No description provided for @employeeJobsSimulateButton.
  ///
  /// In en, this message translates to:
  /// **'Log Service Event'**
  String get employeeJobsSimulateButton;

  /// No description provided for @employeeJobsSectionAssigned.
  ///
  /// In en, this message translates to:
  /// **'Your Assigned Jobs'**
  String get employeeJobsSectionAssigned;

  /// No description provided for @employeeJobsNoJobsTitle.
  ///
  /// In en, this message translates to:
  /// **'No Jobs Assigned'**
  String get employeeJobsNoJobsTitle;

  /// No description provided for @employeeJobsNoJobsDesc.
  ///
  /// In en, this message translates to:
  /// **'No jobs currently assigned to you.'**
  String get employeeJobsNoJobsDesc;

  /// No description provided for @employeeJobsWelcomeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Welcome back!'**
  String get employeeJobsWelcomeGreeting;

  /// No description provided for @employeeJobsLoggedInAs.
  ///
  /// In en, this message translates to:
  /// **'Logged in as: {name}'**
  String employeeJobsLoggedInAs(String name);

  /// No description provided for @employeeJobsGpsLive.
  ///
  /// In en, this message translates to:
  /// **'GPS Live'**
  String get employeeJobsGpsLive;

  /// No description provided for @employeeJobsGpsOff.
  ///
  /// In en, this message translates to:
  /// **'GPS Off'**
  String get employeeJobsGpsOff;

  /// No description provided for @employeeJobsConfirmCodTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Cash Collection & Complete'**
  String get employeeJobsConfirmCodTitle;

  /// No description provided for @employeeJobsConfirmCodMessage.
  ///
  /// In en, this message translates to:
  /// **'Confirm you have physically collected the cash payment of \${amount} from the customer.\n\nThis will mark Job #{jobId} as completed.'**
  String employeeJobsConfirmCodMessage(String amount, String jobId);

  /// No description provided for @employeeJobsConfirmNonCodMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to mark Job #{jobId} as completed?'**
  String employeeJobsConfirmNonCodMessage(String jobId);

  /// No description provided for @employeeJobsConfirmCodButton.
  ///
  /// In en, this message translates to:
  /// **'Confirm Cash Collected & Complete'**
  String get employeeJobsConfirmCodButton;

  /// No description provided for @employeeJobsConfirmNonCodButton.
  ///
  /// In en, this message translates to:
  /// **'Complete Job'**
  String get employeeJobsConfirmNonCodButton;

  /// No description provided for @employeeJobsDestinationCoordinates.
  ///
  /// In en, this message translates to:
  /// **'Destination Coordinates'**
  String get employeeJobsDestinationCoordinates;

  /// No description provided for @employeeJobsLabelCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get employeeJobsLabelCustomer;

  /// No description provided for @employeeJobsLabelPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get employeeJobsLabelPayment;

  /// No description provided for @employeeJobsLabelEscrow.
  ///
  /// In en, this message translates to:
  /// **'Escrow'**
  String get employeeJobsLabelEscrow;

  /// No description provided for @employeeJobsCancellationReason.
  ///
  /// In en, this message translates to:
  /// **'Cancellation Reason: {reason}'**
  String employeeJobsCancellationReason(String reason);

  /// No description provided for @employeeJobsLocationPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Location Permission Required'**
  String get employeeJobsLocationPermissionTitle;

  /// No description provided for @employeeJobsLocationPermissionDesc.
  ///
  /// In en, this message translates to:
  /// **'Location sharing is required to share your live delivery progress with the customer.'**
  String get employeeJobsLocationPermissionDesc;

  /// No description provided for @employeeJobsOpenAppSettings.
  ///
  /// In en, this message translates to:
  /// **'Open App Settings'**
  String get employeeJobsOpenAppSettings;

  /// No description provided for @employeeJobsSharingLiveLocation.
  ///
  /// In en, this message translates to:
  /// **'Sharing live location'**
  String get employeeJobsSharingLiveLocation;

  /// No description provided for @employeeJobsChatButton.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get employeeJobsChatButton;

  /// No description provided for @employeeJobsCompleteJobButton.
  ///
  /// In en, this message translates to:
  /// **'Complete Job'**
  String get employeeJobsCompleteJobButton;

  /// No description provided for @planFreeBasic.
  ///
  /// In en, this message translates to:
  /// **'Free Basic Plan'**
  String get planFreeBasic;

  /// No description provided for @planProfessionalPaid.
  ///
  /// In en, this message translates to:
  /// **'Professional Paid Plan'**
  String get planProfessionalPaid;

  /// No description provided for @walletLockedEscrow.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get walletLockedEscrow;

  /// No description provided for @walletTransactionLedger.
  ///
  /// In en, this message translates to:
  /// **'Transaction Ledger'**
  String get walletTransactionLedger;

  /// No description provided for @walletNoTransactions.
  ///
  /// In en, this message translates to:
  /// **'No transactions recorded yet.'**
  String get walletNoTransactions;

  /// No description provided for @walletAmountCredits.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get walletAmountCredits;

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

  /// No description provided for @cancelJobReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Cancellation Reason *'**
  String get cancelJobReasonLabel;

  /// No description provided for @cancelJobReasonHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Customer requested cancellation / Change of plans'**
  String get cancelJobReasonHint;

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

  /// No description provided for @incomingJobOffer.
  ///
  /// In en, this message translates to:
  /// **'Incoming Job Offer'**
  String get incomingJobOffer;

  /// No description provided for @acceptOffer.
  ///
  /// In en, this message translates to:
  /// **'Accept Offer'**
  String get acceptOffer;

  /// No description provided for @declineOffer.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get declineOffer;

  /// No description provided for @chatWithCustomer.
  ///
  /// In en, this message translates to:
  /// **'Chat with Customer'**
  String get chatWithCustomer;

  /// No description provided for @courierFoundReviewing.
  ///
  /// In en, this message translates to:
  /// **'Courier found, reviewing your request...'**
  String get courierFoundReviewing;

  /// No description provided for @earlyChatAvailableHint.
  ///
  /// In en, this message translates to:
  /// **'You can chat with the courier while they review your order.'**
  String get earlyChatAvailableHint;

  /// No description provided for @offerExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in {seconds}s'**
  String offerExpiresIn(int seconds);

  /// No description provided for @allCouriersBusyTitle.
  ///
  /// In en, this message translates to:
  /// **'All couriers are currently busy right now'**
  String get allCouriersBusyTitle;

  /// No description provided for @allCouriersBusyDesc.
  ///
  /// In en, this message translates to:
  /// **'All couriers in your area are currently occupied or unavailable. Please try again shortly.'**
  String get allCouriersBusyDesc;

  /// No description provided for @retryBookingAction.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get retryBookingAction;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @statusPendingApproval.
  ///
  /// In en, this message translates to:
  /// **'Pending Approval'**
  String get statusPendingApproval;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApproved;

  /// No description provided for @statusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get statusRejected;

  /// No description provided for @statusUnverified.
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get statusUnverified;

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

  /// No description provided for @customerOrdersLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading orders...'**
  String get customerOrdersLoading;

  /// No description provided for @tooltipNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get tooltipNotifications;

  /// No description provided for @tooltipRefreshList.
  ///
  /// In en, this message translates to:
  /// **'Refresh List'**
  String get tooltipRefreshList;

  /// No description provided for @tooltipRefreshStatus.
  ///
  /// In en, this message translates to:
  /// **'Refresh Status'**
  String get tooltipRefreshStatus;

  /// No description provided for @tooltipToggleTheme.
  ///
  /// In en, this message translates to:
  /// **'Toggle Theme Mode'**
  String get tooltipToggleTheme;

  /// No description provided for @tooltipToggleLanguage.
  ///
  /// In en, this message translates to:
  /// **'Toggle Language'**
  String get tooltipToggleLanguage;

  /// No description provided for @tooltipDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get tooltipDismiss;

  /// No description provided for @tooltipPickImage.
  ///
  /// In en, this message translates to:
  /// **'Pick Image'**
  String get tooltipPickImage;

  /// No description provided for @tooltipClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get tooltipClose;

  /// No description provided for @tooltipOpenChat.
  ///
  /// In en, this message translates to:
  /// **'Open chat'**
  String get tooltipOpenChat;

  /// No description provided for @tooltipRemoveAddress.
  ///
  /// In en, this message translates to:
  /// **'Remove address'**
  String get tooltipRemoveAddress;

  /// No description provided for @tooltipZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get tooltipZoomIn;

  /// No description provided for @tooltipZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get tooltipZoomOut;

  /// No description provided for @tooltipRecenter.
  ///
  /// In en, this message translates to:
  /// **'Recenter map'**
  String get tooltipRecenter;

  /// No description provided for @sortByLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort By'**
  String get sortByLabel;

  /// No description provided for @noServicesNearby.
  ///
  /// In en, this message translates to:
  /// **'No services found nearby.'**
  String get noServicesNearby;

  /// No description provided for @paymentMethodLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get paymentMethodLabel;

  /// No description provided for @registeredEmployees.
  ///
  /// In en, this message translates to:
  /// **'Registered Employees'**
  String get registeredEmployees;

  /// No description provided for @loadingEmployeeList.
  ///
  /// In en, this message translates to:
  /// **'Loading employee list...'**
  String get loadingEmployeeList;

  /// No description provided for @noEmployeesRegistered.
  ///
  /// In en, this message translates to:
  /// **'No Employees Registered'**
  String get noEmployeesRegistered;

  /// No description provided for @employeesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your employees right now.'**
  String get employeesLoadFailed;

  /// No description provided for @registerNewEmployee.
  ///
  /// In en, this message translates to:
  /// **'Register New Employee'**
  String get registerNewEmployee;

  /// No description provided for @employeeUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Employee Username'**
  String get employeeUsernameLabel;

  /// No description provided for @employeeUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. driver_john'**
  String get employeeUsernameHint;

  /// No description provided for @employeeEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Employee Email'**
  String get employeeEmailLabel;

  /// No description provided for @employeeEmailHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. john@company.com'**
  String get employeeEmailHint;

  /// No description provided for @employeePasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Employee Password'**
  String get employeePasswordLabel;

  /// No description provided for @employeePasswordHint.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get employeePasswordHint;

  /// No description provided for @freezeUnfreezeWorker.
  ///
  /// In en, this message translates to:
  /// **'Freeze / Unfreeze Worker'**
  String get freezeUnfreezeWorker;

  /// No description provided for @confirmOwnerPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Owner Password'**
  String get confirmOwnerPassword;

  /// No description provided for @loadingAuditTrail.
  ///
  /// In en, this message translates to:
  /// **'Loading audit trail...'**
  String get loadingAuditTrail;

  /// No description provided for @noAuditEventsTitle.
  ///
  /// In en, this message translates to:
  /// **'No audit events recorded'**
  String get noAuditEventsTitle;

  /// No description provided for @noAuditEventsDesc.
  ///
  /// In en, this message translates to:
  /// **'No audit events recorded for this tenant.'**
  String get noAuditEventsDesc;

  /// No description provided for @priceNegotiationTitle.
  ///
  /// In en, this message translates to:
  /// **'Price Negotiation'**
  String get priceNegotiationTitle;

  /// No description provided for @negotiationHintExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. {price}'**
  String negotiationHintExample(String price);

  /// No description provided for @rejectionReasonMessage.
  ///
  /// In en, this message translates to:
  /// **'Rejection Reason: {reason}'**
  String rejectionReasonMessage(String reason);

  /// No description provided for @ratingFeatureUnbiased.
  ///
  /// In en, this message translates to:
  /// **'Unbiased Reviews'**
  String get ratingFeatureUnbiased;

  /// No description provided for @ratingFeatureTrust.
  ///
  /// In en, this message translates to:
  /// **'Trust Shield'**
  String get ratingFeatureTrust;

  /// No description provided for @ratingFeatureWindow.
  ///
  /// In en, this message translates to:
  /// **'24h Window'**
  String get ratingFeatureWindow;

  /// No description provided for @privateFeedbackLabel.
  ///
  /// In en, this message translates to:
  /// **'Private feedback · optional'**
  String get privateFeedbackLabel;

  /// No description provided for @loadingStatus.
  ///
  /// In en, this message translates to:
  /// **'Loading status...'**
  String get loadingStatus;

  /// No description provided for @kycRejectedDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification Rejected'**
  String get kycRejectedDialogTitle;

  /// No description provided for @statusRequested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get statusRequested;

  /// No description provided for @statusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get statusPaid;

  /// No description provided for @payoutWithdrawButton.
  ///
  /// In en, this message translates to:
  /// **'Request Payout'**
  String get payoutWithdrawButton;

  /// No description provided for @payoutDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Request Payout'**
  String get payoutDialogTitle;

  /// No description provided for @payoutDialogDescription.
  ///
  /// In en, this message translates to:
  /// **'Request a withdrawal from your withdrawable balance to your bank account or InstaPay.'**
  String get payoutDialogDescription;

  /// No description provided for @payoutMethodLabel.
  ///
  /// In en, this message translates to:
  /// **'Payout Method'**
  String get payoutMethodLabel;

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

  /// No description provided for @payoutAccountDetailsLabel.
  ///
  /// In en, this message translates to:
  /// **'Account Details'**
  String get payoutAccountDetailsLabel;

  /// No description provided for @payoutAccountDetailsBankHint.
  ///
  /// In en, this message translates to:
  /// **'IBAN, e.g. EG123456789012345678901234567'**
  String get payoutAccountDetailsBankHint;

  /// No description provided for @payoutAccountDetailsInstapayHint.
  ///
  /// In en, this message translates to:
  /// **'InstaPay mobile number or address, e.g. 01012345678'**
  String get payoutAccountDetailsInstapayHint;

  /// No description provided for @payoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Payout Request'**
  String get payoutConfirmTitle;

  /// No description provided for @payoutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to request a payout of {amount} credits via {method}? The requested amount will be held from your withdrawable balance until processed.'**
  String payoutConfirmMessage(String amount, String method);

  /// No description provided for @payoutSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Payout request submitted successfully.'**
  String get payoutSuccessMessage;

  /// No description provided for @payoutHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Payout Requests History'**
  String get payoutHistoryTitle;

  /// No description provided for @payoutHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No payout requests submitted yet.'**
  String get payoutHistoryEmpty;

  /// No description provided for @payoutErrorAmountExceeds.
  ///
  /// In en, this message translates to:
  /// **'Amount exceeds current withdrawable balance.'**
  String get payoutErrorAmountExceeds;

  /// No description provided for @payoutErrorAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid amount greater than 0.'**
  String get payoutErrorAmountInvalid;

  /// No description provided for @payoutErrorDetailsRequired.
  ///
  /// In en, this message translates to:
  /// **'Account details are required.'**
  String get payoutErrorDetailsRequired;

  /// No description provided for @payoutRejectionReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Rejection Reason:'**
  String get payoutRejectionReasonLabel;

  /// No description provided for @chatStatusLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get chatStatusLive;

  /// No description provided for @chatStatusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get chatStatusDisconnected;

  /// No description provided for @chatJobTag.
  ///
  /// In en, this message translates to:
  /// **'Job #{shortId}'**
  String chatJobTag(String shortId);

  /// No description provided for @chatDirectChannel.
  ///
  /// In en, this message translates to:
  /// **'Direct Real-time Channel'**
  String get chatDirectChannel;

  /// No description provided for @chatAccessDeniedJob.
  ///
  /// In en, this message translates to:
  /// **'Access Denied: You are not authorized to view or join the chat for Job #{jobId}.'**
  String chatAccessDeniedJob(String jobId);

  /// No description provided for @customerHomeWhereDeliver.
  ///
  /// In en, this message translates to:
  /// **'Where to deliver?'**
  String get customerHomeWhereDeliver;

  /// No description provided for @customerHomeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to set your pickup location'**
  String get customerHomeSearchHint;

  /// No description provided for @commonOrigin.
  ///
  /// In en, this message translates to:
  /// **'Origin'**
  String get commonOrigin;

  /// No description provided for @commonDestination.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get commonDestination;

  /// No description provided for @courierAssignedLabel.
  ///
  /// In en, this message translates to:
  /// **'Courier: Assigned'**
  String get courierAssignedLabel;

  /// No description provided for @findingCourierLabel.
  ///
  /// In en, this message translates to:
  /// **'Finding Courier...'**
  String get findingCourierLabel;

  /// No description provided for @paymentMethodLine.
  ///
  /// In en, this message translates to:
  /// **'Payment: {method}'**
  String paymentMethodLine(String method);

  /// No description provided for @mapPickupBadge.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get mapPickupBadge;

  /// No description provided for @mapDropoffBadge.
  ///
  /// In en, this message translates to:
  /// **'Dropoff'**
  String get mapDropoffBadge;

  /// No description provided for @mapYouAreHereBadge.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get mapYouAreHereBadge;

  /// No description provided for @employeeLiveMapTitle.
  ///
  /// In en, this message translates to:
  /// **'Live Trip Map'**
  String get employeeLiveMapTitle;

  /// No description provided for @employeeTrackTripBtn.
  ///
  /// In en, this message translates to:
  /// **'View Live Map'**
  String get employeeTrackTripBtn;

  /// No description provided for @employeeWaitingSelfPosition.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your GPS position…'**
  String get employeeWaitingSelfPosition;

  /// No description provided for @employeeMapLocationDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied — your live position won\'t show, but pickup and dropoff still do.'**
  String get employeeMapLocationDenied;

  /// No description provided for @waitingCourierUpdates.
  ///
  /// In en, this message translates to:
  /// **'Waiting for courier location updates...'**
  String get waitingCourierUpdates;

  /// No description provided for @reconnectingTrackingStream.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting live tracking stream...'**
  String get reconnectingTrackingStream;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @distanceAwayLine.
  ///
  /// In en, this message translates to:
  /// **'{distance} km away'**
  String distanceAwayLine(String distance);

  /// No description provided for @pricingBreakdownLine.
  ///
  /// In en, this message translates to:
  /// **'Base: {base} + {perKm}/km'**
  String pricingBreakdownLine(String base, String perKm);

  /// No description provided for @estPriceLine.
  ///
  /// In en, this message translates to:
  /// **'Est. Price: {price}'**
  String estPriceLine(String price);

  /// No description provided for @workingHoursLine.
  ///
  /// In en, this message translates to:
  /// **'Hours: {hours}'**
  String workingHoursLine(String hours);

  /// No description provided for @coverageRadiusLine.
  ///
  /// In en, this message translates to:
  /// **'Coverage: {radius} km'**
  String coverageRadiusLine(String radius);

  /// No description provided for @chooseSearchLocation.
  ///
  /// In en, this message translates to:
  /// **'Choose Search Location'**
  String get chooseSearchLocation;

  /// No description provided for @confirmBookingTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Booking'**
  String get confirmBookingTitle;

  /// No description provided for @categoryLine.
  ///
  /// In en, this message translates to:
  /// **'Category: {category}'**
  String categoryLine(String category);

  /// No description provided for @pickupDistanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Pickup Distance:'**
  String get pickupDistanceLabel;

  /// No description provided for @kmUnitLine.
  ///
  /// In en, this message translates to:
  /// **'{distance} km'**
  String kmUnitLine(String distance);

  /// No description provided for @estimatedTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Estimated Total:'**
  String get estimatedTotalLabel;

  /// No description provided for @codOptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash on delivery'**
  String get codOptionTitle;

  /// No description provided for @codOptionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pay in cash directly to the driver upon arrival'**
  String get codOptionSubtitle;

  /// No description provided for @betaEscrowNote.
  ///
  /// In en, this message translates to:
  /// **'Note: Escrow payments and wallet deductions are currently deferred for this beta launch.'**
  String get betaEscrowNote;

  /// No description provided for @noRatingsLabel.
  ///
  /// In en, this message translates to:
  /// **'No ratings'**
  String get noRatingsLabel;

  /// No description provided for @reasonLine.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String reasonLine(String reason);

  /// No description provided for @recentActivityHeader.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get recentActivityHeader;

  /// No description provided for @employeeHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Completed and cancelled jobs.'**
  String get employeeHistorySubtitle;

  /// No description provided for @employeeManageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage delivery personnel and status.'**
  String get employeeManageSubtitle;

  /// No description provided for @employeeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search workers by name or email...'**
  String get employeeSearchHint;

  /// No description provided for @employeeFrozenStatus.
  ///
  /// In en, this message translates to:
  /// **'Frozen'**
  String get employeeFrozenStatus;

  /// No description provided for @noWorkersMatchFilter.
  ///
  /// In en, this message translates to:
  /// **'No workers found matching your filter.'**
  String get noWorkersMatchFilter;

  /// No description provided for @workerIdBadge.
  ///
  /// In en, this message translates to:
  /// **'ID: #QD-{id}'**
  String workerIdBadge(String id);

  /// No description provided for @targetStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Target Status'**
  String get targetStatusLabel;

  /// No description provided for @secureVerificationNote.
  ///
  /// In en, this message translates to:
  /// **'Required for secure out-of-band operations verification.'**
  String get secureVerificationNote;

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

  /// No description provided for @employeeEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Employee email is required'**
  String get employeeEmailRequired;

  /// No description provided for @ownerPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Owner password is required to re-authenticate'**
  String get ownerPasswordRequired;

  /// No description provided for @enterOtp6Digits.
  ///
  /// In en, this message translates to:
  /// **'Enter 6-digit OTP code'**
  String get enterOtp6Digits;

  /// No description provided for @otpExactly6Digits.
  ///
  /// In en, this message translates to:
  /// **'OTP must be exactly 6 digits'**
  String get otpExactly6Digits;

  /// No description provided for @devOtpBanner.
  ///
  /// In en, this message translates to:
  /// **'Dev OTP Code: {otp}'**
  String devOtpBanner(String otp);

  /// No description provided for @devOtpAutoFilled.
  ///
  /// In en, this message translates to:
  /// **'Dev Mode: Auto-populated OTP \'{otp}\' from response.'**
  String devOtpAutoFilled(String otp);

  /// No description provided for @enterpriseTrustNote.
  ///
  /// In en, this message translates to:
  /// **'Secured by Enterprise Trust Protocol'**
  String get enterpriseTrustNote;

  /// No description provided for @activeFleetMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE FLEET'**
  String get activeFleetMetricLabel;

  /// No description provided for @quickConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure business profile, rates & coverage'**
  String get quickConfigSubtitle;

  /// No description provided for @urgentActionsHeader.
  ///
  /// In en, this message translates to:
  /// **'Urgent Actions'**
  String get urgentActionsHeader;

  /// No description provided for @vehicleMaintenanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Maintenance Required'**
  String get vehicleMaintenanceTitle;

  /// No description provided for @vehicleMaintenanceDesc.
  ///
  /// In en, this message translates to:
  /// **'Van #402 reported engine warning. Schedule service immediately.'**
  String get vehicleMaintenanceDesc;

  /// No description provided for @scheduleAction.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get scheduleAction;

  /// No description provided for @pendingReconciliationsHeader.
  ///
  /// In en, this message translates to:
  /// **'Pending Reconciliations'**
  String get pendingReconciliationsHeader;

  /// No description provided for @reconciliationPendingDesc.
  ///
  /// In en, this message translates to:
  /// **'Driver shifts from yesterday awaiting escrow settlement.'**
  String get reconciliationPendingDesc;

  /// No description provided for @reviewAction.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewAction;

  /// No description provided for @fleetOverviewHeader.
  ///
  /// In en, this message translates to:
  /// **'Fleet Overview'**
  String get fleetOverviewHeader;

  /// No description provided for @activeZoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Active Zone'**
  String get activeZoneLabel;

  /// No description provided for @downtownCoverageLabel.
  ///
  /// In en, this message translates to:
  /// **'Downtown Metro Coverage'**
  String get downtownCoverageLabel;

  /// No description provided for @trackJobHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Track Job'**
  String get trackJobHeroTitle;

  /// No description provided for @trackJobHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View real-time location on map'**
  String get trackJobHeroSubtitle;

  /// No description provided for @fulfillmentProgressHeader.
  ///
  /// In en, this message translates to:
  /// **'Fulfillment Progress'**
  String get fulfillmentProgressHeader;

  /// No description provided for @stepRequestQueuedSub.
  ///
  /// In en, this message translates to:
  /// **'Request placed & queued'**
  String get stepRequestQueuedSub;

  /// No description provided for @stepAssignedTitle.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get stepAssignedTitle;

  /// No description provided for @matchingCourierLabel.
  ///
  /// In en, this message translates to:
  /// **'Matching courier...'**
  String get matchingCourierLabel;

  /// No description provided for @assignedToLine.
  ///
  /// In en, this message translates to:
  /// **'Assigned to {name}'**
  String assignedToLine(String name);

  /// No description provided for @courierAssignedShort.
  ///
  /// In en, this message translates to:
  /// **'Courier assigned'**
  String get courierAssignedShort;

  /// No description provided for @stepInTransitSub.
  ///
  /// In en, this message translates to:
  /// **'Package on route to destination'**
  String get stepInTransitSub;

  /// No description provided for @stepDeliveredOkSub.
  ///
  /// In en, this message translates to:
  /// **'Delivered successfully'**
  String get stepDeliveredOkSub;

  /// No description provided for @stepPendingDeliverySub.
  ///
  /// In en, this message translates to:
  /// **'Pending delivery'**
  String get stepPendingDeliverySub;

  /// No description provided for @itineraryHeader.
  ///
  /// In en, this message translates to:
  /// **'Itinerary'**
  String get itineraryHeader;

  /// No description provided for @pickupStageBadge.
  ///
  /// In en, this message translates to:
  /// **'PICKUP'**
  String get pickupStageBadge;

  /// No description provided for @originCustomerLocation.
  ///
  /// In en, this message translates to:
  /// **'Origin / Customer Location'**
  String get originCustomerLocation;

  /// No description provided for @dropoffStageBadge.
  ///
  /// In en, this message translates to:
  /// **'DROPOFF'**
  String get dropoffStageBadge;

  /// No description provided for @deliveryDestinationLabel.
  ///
  /// In en, this message translates to:
  /// **'Delivery Destination'**
  String get deliveryDestinationLabel;

  /// No description provided for @paymentSectionHeader.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get paymentSectionHeader;

  /// No description provided for @totalFareLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Fare'**
  String get totalFareLabel;

  /// No description provided for @verifiedCourierDriver.
  ///
  /// In en, this message translates to:
  /// **'Verified Courier Driver'**
  String get verifiedCourierDriver;

  /// No description provided for @cancellationReasonLine.
  ///
  /// In en, this message translates to:
  /// **'Cancellation Reason: {reason}'**
  String cancellationReasonLine(String reason);

  /// No description provided for @negotiationExpiredBanner.
  ///
  /// In en, this message translates to:
  /// **'Negotiation window expired, 5-minute limit lapsed'**
  String get negotiationExpiredBanner;

  /// No description provided for @incomingProposalCard.
  ///
  /// In en, this message translates to:
  /// **'Incoming Proposal'**
  String get incomingProposalCard;

  /// No description provided for @proposalByLine.
  ///
  /// In en, this message translates to:
  /// **'by {role}'**
  String proposalByLine(String role);

  /// No description provided for @proposalRoleCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get proposalRoleCustomer;

  /// No description provided for @proposalRoleDriverEmployee.
  ///
  /// In en, this message translates to:
  /// **'Driver / Employee'**
  String get proposalRoleDriverEmployee;

  /// No description provided for @proposedFareLabel.
  ///
  /// In en, this message translates to:
  /// **'Proposed Fare:'**
  String get proposedFareLabel;

  /// No description provided for @comparisonPrefix.
  ///
  /// In en, this message translates to:
  /// **'Comparison:'**
  String get comparisonPrefix;

  /// No description provided for @vsSystemPrice.
  ///
  /// In en, this message translates to:
  /// **'vs System Price'**
  String get vsSystemPrice;

  /// No description provided for @waitingProposalResponse.
  ///
  /// In en, this message translates to:
  /// **'Waiting for response to your proposal...'**
  String get waitingProposalResponse;

  /// No description provided for @submitCounterOfferBtn.
  ///
  /// In en, this message translates to:
  /// **'Submit Counter-Offer'**
  String get submitCounterOfferBtn;

  /// No description provided for @allowedBoundLine.
  ///
  /// In en, this message translates to:
  /// **'Allowed bound: {min} – {max}, ±50%'**
  String allowedBoundLine(String min, String max);

  /// No description provided for @verificationStatusCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification Status'**
  String get verificationStatusCardTitle;

  /// No description provided for @documentsLockedMessage.
  ///
  /// In en, this message translates to:
  /// **'Documents are locked because your account is approved.'**
  String get documentsLockedMessage;

  /// No description provided for @removeSelectionAction.
  ///
  /// In en, this message translates to:
  /// **'Remove selection'**
  String get removeSelectionAction;

  /// No description provided for @requiredDocsHeader.
  ///
  /// In en, this message translates to:
  /// **'Required Verification Documents'**
  String get requiredDocsHeader;

  /// No description provided for @kycOwnerDocsSub.
  ///
  /// In en, this message translates to:
  /// **'Owners must upload all 4 documents: identity card front, identity card back, selfie, business proof.'**
  String get kycOwnerDocsSub;

  /// No description provided for @kycEmployeeDocsSub.
  ///
  /// In en, this message translates to:
  /// **'Employees must upload all 3 documents: identity card front, identity card back, selfie.'**
  String get kycEmployeeDocsSub;

  /// No description provided for @profileInfoCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile Information'**
  String get profileInfoCardTitle;

  /// No description provided for @sectionBusinessIdentity.
  ///
  /// In en, this message translates to:
  /// **'Business Identity'**
  String get sectionBusinessIdentity;

  /// No description provided for @sectionBusinessIdentitySub.
  ///
  /// In en, this message translates to:
  /// **'Company details and classification'**
  String get sectionBusinessIdentitySub;

  /// No description provided for @sectionLocationOperations.
  ///
  /// In en, this message translates to:
  /// **'Location & Operations'**
  String get sectionLocationOperations;

  /// No description provided for @sectionLocationOperationsSub.
  ///
  /// In en, this message translates to:
  /// **'Headquarters and coverage boundary'**
  String get sectionLocationOperationsSub;

  /// No description provided for @sectionPricingStructure.
  ///
  /// In en, this message translates to:
  /// **'Pricing Structure'**
  String get sectionPricingStructure;

  /// No description provided for @sectionPricingStructureSub.
  ///
  /// In en, this message translates to:
  /// **'Base fare and distance-based fees'**
  String get sectionPricingStructureSub;

  /// No description provided for @estDelivery10kmLabel.
  ///
  /// In en, this message translates to:
  /// **'Est. 10KM Delivery:'**
  String get estDelivery10kmLabel;

  /// No description provided for @fleetFilterAllFleet.
  ///
  /// In en, this message translates to:
  /// **'All Fleet'**
  String get fleetFilterAllFleet;

  /// No description provided for @fleetFilterOnRoute.
  ///
  /// In en, this message translates to:
  /// **'On Route'**
  String get fleetFilterOnRoute;

  /// No description provided for @fleetFilterIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get fleetFilterIdle;

  /// No description provided for @noEmployeesTransmitting.
  ///
  /// In en, this message translates to:
  /// **'No active employees transmitting location.'**
  String get noEmployeesTransmitting;

  /// No description provided for @assignedJobLine.
  ///
  /// In en, this message translates to:
  /// **'Assigned Job: #{jobId}'**
  String assignedJobLine(String jobId);

  /// No description provided for @ownerJobsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by Job ID, customer, or reason...'**
  String get ownerJobsSearchHint;

  /// No description provided for @noJobsMatchFilter.
  ///
  /// In en, this message translates to:
  /// **'No jobs found matching your filter.'**
  String get noJobsMatchFilter;

  /// No description provided for @reconQueueSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search queue by Job ID, customer, driver...'**
  String get reconQueueSearchHint;

  /// No description provided for @reconFilterDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get reconFilterDistance;

  /// No description provided for @reconFilterTimeSpeed.
  ///
  /// In en, this message translates to:
  /// **'Time / Speed'**
  String get reconFilterTimeSpeed;

  /// No description provided for @reconFilterOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get reconFilterOther;

  /// No description provided for @noReconMatchFilter.
  ///
  /// In en, this message translates to:
  /// **'No reconciliation jobs match your filter.'**
  String get noReconMatchFilter;

  /// No description provided for @deliveryIdTag.
  ///
  /// In en, this message translates to:
  /// **'Delivery ID: #QD-{id}'**
  String deliveryIdTag(String id);

  /// No description provided for @howWasDeliveryQuestion.
  ///
  /// In en, this message translates to:
  /// **'How was your delivery?'**
  String get howWasDeliveryQuestion;

  /// No description provided for @ratingsBlindExplanation.
  ///
  /// In en, this message translates to:
  /// **'Ratings are blind. Neither party will see the other\'s feedback until both have submitted.'**
  String get ratingsBlindExplanation;

  /// No description provided for @feedbackExperienceHint.
  ///
  /// In en, this message translates to:
  /// **'Tell us more about your experience...'**
  String get feedbackExperienceHint;

  /// No description provided for @feedbackLockedInTitle.
  ///
  /// In en, this message translates to:
  /// **'Feedback Locked In!'**
  String get feedbackLockedInTitle;

  /// No description provided for @bothRatingsVisibleDesc.
  ///
  /// In en, this message translates to:
  /// **'The other party has submitted their rating. Both feedbacks are now visible under profile summary.'**
  String get bothRatingsVisibleDesc;

  /// No description provided for @waitingOtherPartyTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for other party...'**
  String get waitingOtherPartyTitle;

  /// No description provided for @otherPartyNotRatedDesc.
  ///
  /// In en, this message translates to:
  /// **'The other party has not yet rated this transaction. Your ratings will remain hidden until they submit.'**
  String get otherPartyNotRatedDesc;

  /// No description provided for @ratingStatusCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check whether the other party rated yet. Retry to reload.'**
  String get ratingStatusCheckFailed;

  /// No description provided for @unbiasedRatingDesc.
  ///
  /// In en, this message translates to:
  /// **'Preventing retaliatory or social-pressure ratings.'**
  String get unbiasedRatingDesc;

  /// No description provided for @reliabilityRanksDesc.
  ///
  /// In en, this message translates to:
  /// **'Ratings directly impact platform reliability ranks.'**
  String get reliabilityRanksDesc;

  /// No description provided for @windowDeadlineDesc.
  ///
  /// In en, this message translates to:
  /// **'Submit within 24 hours to ensure your score counts.'**
  String get windowDeadlineDesc;

  /// No description provided for @subscriptionManageDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage your operational tier. Upgrade to unlock live driver tracking, advanced pricing metrics, and priority enterprise support.'**
  String get subscriptionManageDesc;

  /// No description provided for @yourCurrentPlanBadge.
  ///
  /// In en, this message translates to:
  /// **'YOUR CURRENT PLAN'**
  String get yourCurrentPlanBadge;

  /// No description provided for @pendingActivationNote.
  ///
  /// In en, this message translates to:
  /// **'Pending activation. Please contact support to complete payment.'**
  String get pendingActivationNote;

  /// No description provided for @availablePlansHeader.
  ///
  /// In en, this message translates to:
  /// **'Available Plans'**
  String get availablePlansHeader;

  /// No description provided for @freeTierDesc.
  ///
  /// In en, this message translates to:
  /// **'Essential tools for independent operators.'**
  String get freeTierDesc;

  /// No description provided for @proTierDesc.
  ///
  /// In en, this message translates to:
  /// **'Complete suite for fleet managers and growing businesses.'**
  String get proTierDesc;

  /// No description provided for @billedMonthlyNote.
  ///
  /// In en, this message translates to:
  /// **'Billed monthly. Cancel anytime.'**
  String get billedMonthlyNote;

  /// No description provided for @recommendedBadge.
  ///
  /// In en, this message translates to:
  /// **'RECOMMENDED'**
  String get recommendedBadge;

  /// No description provided for @walletMyWalletTitle.
  ///
  /// In en, this message translates to:
  /// **'My Wallet'**
  String get walletMyWalletTitle;

  /// No description provided for @walletCorporateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage corporate finances and payouts.'**
  String get walletCorporateSubtitle;

  /// No description provided for @availableBalanceBadge.
  ///
  /// In en, this message translates to:
  /// **'BALANCE'**
  String get availableBalanceBadge;

  /// No description provided for @totalPortfolioLine.
  ///
  /// In en, this message translates to:
  /// **'Total Portfolio: {amount} Credits'**
  String totalPortfolioLine(String amount);

  /// No description provided for @creditsAmountLine.
  ///
  /// In en, this message translates to:
  /// **'{amount} Credits'**
  String creditsAmountLine(String amount);

  /// No description provided for @ledgerJobLine.
  ///
  /// In en, this message translates to:
  /// **'Job: {jobId}'**
  String ledgerJobLine(String jobId);

  /// No description provided for @ledgerBalanceLine.
  ///
  /// In en, this message translates to:
  /// **'Bal: {balance}'**
  String ledgerBalanceLine(String balance);

  /// No description provided for @cancelReasonRequiredLong.
  ///
  /// In en, this message translates to:
  /// **'Please provide a reason for cancelling this job. A valid cancellation reason is required.'**
  String get cancelReasonRequiredLong;

  /// No description provided for @referenceIdLine.
  ///
  /// In en, this message translates to:
  /// **'Reference ID: #{ref}'**
  String referenceIdLine(String ref);

  /// No description provided for @depositFundsTitle.
  ///
  /// In en, this message translates to:
  /// **'Deposit Funds'**
  String get depositFundsTitle;

  /// No description provided for @depositDialogDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter the amount in credits to deposit to your wallet.'**
  String get depositDialogDesc;

  /// No description provided for @amountRequired.
  ///
  /// In en, this message translates to:
  /// **'Amount is required'**
  String get amountRequired;

  /// No description provided for @positiveNumberRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid positive number'**
  String get positiveNumberRequired;

  /// No description provided for @otpSentToEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit verification code sent to {email}.'**
  String otpSentToEmail(String email);

  /// No description provided for @devModeOtpLabel.
  ///
  /// In en, this message translates to:
  /// **'Dev Mode OTP'**
  String get devModeOtpLabel;

  /// No description provided for @verificationCodeLine.
  ///
  /// In en, this message translates to:
  /// **'Verification code: {code}'**
  String verificationCodeLine(String code);

  /// No description provided for @verificationCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Verification Code'**
  String get verificationCodeLabel;

  /// No description provided for @verificationCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Verification code is required'**
  String get verificationCodeRequired;

  /// No description provided for @accountDetailsLine.
  ///
  /// In en, this message translates to:
  /// **'Account: {account}'**
  String accountDetailsLine(String account);

  /// No description provided for @verifiedServiceScoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Verified Service Score'**
  String get verifiedServiceScoreLabel;

  /// No description provided for @basedOnRatingsLine.
  ///
  /// In en, this message translates to:
  /// **'Based on {count} ratings'**
  String basedOnRatingsLine(String count);

  /// No description provided for @employeeSetActiveStatus.
  ///
  /// In en, this message translates to:
  /// **'Account active'**
  String get employeeSetActiveStatus;

  /// No description provided for @employeeSetFrozenStatus.
  ///
  /// In en, this message translates to:
  /// **'Account frozen'**
  String get employeeSetFrozenStatus;

  /// No description provided for @stepInTransitTitle.
  ///
  /// In en, this message translates to:
  /// **'In Transit'**
  String get stepInTransitTitle;

  /// No description provided for @findNearbyCouriers.
  ///
  /// In en, this message translates to:
  /// **'Find Nearby Couriers'**
  String get findNearbyCouriers;

  /// No description provided for @confirmAndRequestBtn.
  ///
  /// In en, this message translates to:
  /// **'Confirm & Request'**
  String get confirmAndRequestBtn;

  /// No description provided for @auditTrailTabLabel.
  ///
  /// In en, this message translates to:
  /// **'Audit Trail'**
  String get auditTrailTabLabel;

  /// No description provided for @registerEmployeeBtn.
  ///
  /// In en, this message translates to:
  /// **'Register Employee'**
  String get registerEmployeeBtn;

  /// No description provided for @rateYourExperienceCta.
  ///
  /// In en, this message translates to:
  /// **'Rate Your Experience'**
  String get rateYourExperienceCta;

  /// No description provided for @openComplaintTicketBtn.
  ///
  /// In en, this message translates to:
  /// **'Open a Complaint Ticket'**
  String get openComplaintTicketBtn;

  /// No description provided for @backToDirectoryBtn.
  ///
  /// In en, this message translates to:
  /// **'Back to Directory'**
  String get backToDirectoryBtn;

  /// No description provided for @acceptProposalBtn.
  ///
  /// In en, this message translates to:
  /// **'Accept Proposal'**
  String get acceptProposalBtn;

  /// No description provided for @declineProposalBtn.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get declineProposalBtn;

  /// No description provided for @replaceDocumentBtn.
  ///
  /// In en, this message translates to:
  /// **'Replace Document'**
  String get replaceDocumentBtn;

  /// No description provided for @uploadDocumentBtn.
  ///
  /// In en, this message translates to:
  /// **'Upload Document'**
  String get uploadDocumentBtn;

  /// No description provided for @backToStatusBtn.
  ///
  /// In en, this message translates to:
  /// **'Back to Status'**
  String get backToStatusBtn;

  /// No description provided for @bookNowBtn.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get bookNowBtn;

  /// No description provided for @subFreeFeatureMatching.
  ///
  /// In en, this message translates to:
  /// **'Basic delivery matching'**
  String get subFreeFeatureMatching;

  /// No description provided for @subFreeFeatureRouting.
  ///
  /// In en, this message translates to:
  /// **'Standard routing optimization'**
  String get subFreeFeatureRouting;

  /// No description provided for @subFreeFeatureCod.
  ///
  /// In en, this message translates to:
  /// **'Cash on delivery bookings'**
  String get subFreeFeatureCod;

  /// No description provided for @subFreeFeatureSupport.
  ///
  /// In en, this message translates to:
  /// **'Community support'**
  String get subFreeFeatureSupport;

  /// No description provided for @subProFeatureTracking.
  ///
  /// In en, this message translates to:
  /// **'Live worker location tracking'**
  String get subProFeatureTracking;

  /// No description provided for @subProFeatureDispatch.
  ///
  /// In en, this message translates to:
  /// **'Priority dispatch routing'**
  String get subProFeatureDispatch;

  /// No description provided for @subProFeaturePricing.
  ///
  /// In en, this message translates to:
  /// **'Access to advanced pricing metrics'**
  String get subProFeaturePricing;

  /// No description provided for @subProEmployeeSuite.
  ///
  /// In en, this message translates to:
  /// **'Full employee management suite'**
  String get subProEmployeeSuite;

  /// No description provided for @subProDedicatedSupport.
  ///
  /// In en, this message translates to:
  /// **'Premium 24/7 dedicated support'**
  String get subProDedicatedSupport;

  /// No description provided for @subProFeatureTrackingUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlocks live worker location tracking'**
  String get subProFeatureTrackingUnlock;

  /// No description provided for @customerHomeTileDeliveryDesc.
  ///
  /// In en, this message translates to:
  /// **'Fast on-demand delivery for orders, packages, and essentials.'**
  String get customerHomeTileDeliveryDesc;

  /// No description provided for @customerHomeTileRideDesc.
  ///
  /// In en, this message translates to:
  /// **'Local ride booking, moving transport, and courier transport.'**
  String get customerHomeTileRideDesc;

  /// No description provided for @customerHomeTileShippingDesc.
  ///
  /// In en, this message translates to:
  /// **'Book shipping for parcels and goods with GPS-tracked settlement.'**
  String get customerHomeTileShippingDesc;

  /// No description provided for @customerHomeTileCleaningDesc.
  ///
  /// In en, this message translates to:
  /// **'On-demand home cleaning, maintenance, and handyman services.'**
  String get customerHomeTileCleaningDesc;

  /// No description provided for @customerHomeTileBrowseAllDesc.
  ///
  /// In en, this message translates to:
  /// **'Browse all available home services and delivery options.'**
  String get customerHomeTileBrowseAllDesc;

  /// No description provided for @browseServicesBtn.
  ///
  /// In en, this message translates to:
  /// **'Browse Services'**
  String get browseServicesBtn;

  /// No description provided for @marketplaceEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Try broadening your search radius or changing your coordinates.'**
  String get marketplaceEmptyHint;

  /// No description provided for @refreshHistoryBtn.
  ///
  /// In en, this message translates to:
  /// **'Refresh History'**
  String get refreshHistoryBtn;

  /// No description provided for @refreshJobsBtn.
  ///
  /// In en, this message translates to:
  /// **'Refresh Jobs'**
  String get refreshJobsBtn;

  /// No description provided for @employeeRegisterIntro.
  ///
  /// In en, this message translates to:
  /// **'Register your first employee account using the form below.'**
  String get employeeRegisterIntro;

  /// No description provided for @addWorkerAction.
  ///
  /// In en, this message translates to:
  /// **'Add Worker'**
  String get addWorkerAction;

  /// No description provided for @refreshAuditLogBtn.
  ///
  /// In en, this message translates to:
  /// **'Refresh Audit Log'**
  String get refreshAuditLogBtn;

  /// No description provided for @manageServicesAction.
  ///
  /// In en, this message translates to:
  /// **'Manage Services'**
  String get manageServicesAction;

  /// No description provided for @backToHomeBtn.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get backToHomeBtn;

  /// No description provided for @refreshQueueBtn.
  ///
  /// In en, this message translates to:
  /// **'Refresh Queue'**
  String get refreshQueueBtn;

  /// No description provided for @walletPayoutEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Submitted payout requests will appear here with processing status.'**
  String get walletPayoutEmptyHint;

  /// No description provided for @walletLedgerEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Your transaction history will appear here once deposits or charges occur.'**
  String get walletLedgerEmptyHint;

  /// No description provided for @refreshWalletBtn.
  ///
  /// In en, this message translates to:
  /// **'Refresh Wallet'**
  String get refreshWalletBtn;

  /// No description provided for @expressDeliveryFallbackLabel.
  ///
  /// In en, this message translates to:
  /// **'Express Delivery'**
  String get expressDeliveryFallbackLabel;

  /// No description provided for @inTransitLiveTitle.
  ///
  /// In en, this message translates to:
  /// **'In Transit - Live Courier Tracking'**
  String get inTransitLiveTitle;

  /// No description provided for @liveRouteTrackingActive.
  ///
  /// In en, this message translates to:
  /// **'Live Route Tracking Active'**
  String get liveRouteTrackingActive;

  /// No description provided for @pickupLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Pickup Location'**
  String get pickupLocationLabel;

  /// No description provided for @orderDispatchedLabel.
  ///
  /// In en, this message translates to:
  /// **'Order Dispatched'**
  String get orderDispatchedLabel;

  /// No description provided for @clientAddressConfirmedLabel.
  ///
  /// In en, this message translates to:
  /// **'Client Address Confirmed'**
  String get clientAddressConfirmedLabel;

  /// No description provided for @standardRouteLabel.
  ///
  /// In en, this message translates to:
  /// **'Standard Route'**
  String get standardRouteLabel;

  /// No description provided for @routeLoggedLabel.
  ///
  /// In en, this message translates to:
  /// **'Route Logged'**
  String get routeLoggedLabel;

  /// No description provided for @routeDestinationNotSetYet.
  ///
  /// In en, this message translates to:
  /// **'Destination not set yet'**
  String get routeDestinationNotSetYet;

  /// No description provided for @workerStatusChangedSuccessMsg.
  ///
  /// In en, this message translates to:
  /// **'Successfully changed status.'**
  String get workerStatusChangedSuccessMsg;

  /// No description provided for @freezeWorkerBtn.
  ///
  /// In en, this message translates to:
  /// **'Freeze Worker'**
  String get freezeWorkerBtn;

  /// No description provided for @unfreezeWorkerBtn.
  ///
  /// In en, this message translates to:
  /// **'Unfreeze Worker'**
  String get unfreezeWorkerBtn;

  /// No description provided for @freezeWorkerConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Freeze Worker Account?'**
  String get freezeWorkerConfirmTitle;

  /// No description provided for @freezeWorkerConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Freezing {email} will immediately block their login and hide them from active dispatch. You can unfreeze them at any time from this screen.'**
  String freezeWorkerConfirmMessage(String email);

  /// No description provided for @unfreezeWorkerConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Unfreeze Worker Account?'**
  String get unfreezeWorkerConfirmTitle;

  /// No description provided for @unfreezeWorkerConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Unfreezing {email} will immediately restore their login access and allow them to receive new dispatches.'**
  String unfreezeWorkerConfirmMessage(String email);

  /// No description provided for @passwordResetSuccessMsg.
  ///
  /// In en, this message translates to:
  /// **'Password reset successfully! You can now log in with your new password.'**
  String get passwordResetSuccessMsg;

  /// No description provided for @enterValidNumberError.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number'**
  String get enterValidNumberError;

  /// No description provided for @priceProposalAcceptedMsg.
  ///
  /// In en, this message translates to:
  /// **'Price proposal accepted! Job is now active.'**
  String get priceProposalAcceptedMsg;

  /// No description provided for @priceProposalDeclinedMsg.
  ///
  /// In en, this message translates to:
  /// **'Price proposal declined. Job cancelled.'**
  String get priceProposalDeclinedMsg;

  /// No description provided for @courierDriverLabel.
  ///
  /// In en, this message translates to:
  /// **'Courier Driver'**
  String get courierDriverLabel;

  /// No description provided for @assignedCourierLabel.
  ///
  /// In en, this message translates to:
  /// **'Assigned Courier'**
  String get assignedCourierLabel;

  /// No description provided for @originalSystemPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Original System Price'**
  String get originalSystemPriceLabel;

  /// No description provided for @agreedPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Agreed Price'**
  String get agreedPriceLabel;

  /// No description provided for @selectFileSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Select File Source'**
  String get selectFileSourceTitle;

  /// No description provided for @selectImageSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Image Source'**
  String get selectImageSourceTitle;

  /// No description provided for @kycInvalidFormatDocs.
  ///
  /// In en, this message translates to:
  /// **'Invalid file format. Only JPEG, PNG, and PDF files are allowed for {slot}.'**
  String kycInvalidFormatDocs(String slot);

  /// No description provided for @kycInvalidFormatImages.
  ///
  /// In en, this message translates to:
  /// **'Invalid file format. Only JPEG and PNG image files are allowed for {slot}.'**
  String kycInvalidFormatImages(String slot);

  /// No description provided for @kycApprovedBanner.
  ///
  /// In en, this message translates to:
  /// **'Your account verification has been approved by administrators. Your account is fully active.'**
  String get kycApprovedBanner;

  /// No description provided for @kycPendingBanner.
  ///
  /// In en, this message translates to:
  /// **'All required documents have been uploaded and are pending super admin review.'**
  String get kycPendingBanner;

  /// No description provided for @kycRejectedBanner.
  ///
  /// In en, this message translates to:
  /// **'Your document submission was rejected. Please review the reason below and re-upload the corrected documents.'**
  String get kycRejectedBanner;

  /// No description provided for @kycUploadAllBanner.
  ///
  /// In en, this message translates to:
  /// **'Please upload all required verification documents below to complete identity verification.'**
  String get kycUploadAllBanner;

  /// No description provided for @ownerKybTitle.
  ///
  /// In en, this message translates to:
  /// **'Owner verification'**
  String get ownerKybTitle;

  /// No description provided for @employeeKyeTitle.
  ///
  /// In en, this message translates to:
  /// **'Employee verification'**
  String get employeeKyeTitle;

  /// No description provided for @idFrontTitle.
  ///
  /// In en, this message translates to:
  /// **'Identity card front'**
  String get idFrontTitle;

  /// No description provided for @idFrontDesc.
  ///
  /// In en, this message translates to:
  /// **'Clear photo of the front side of your National ID or Passport.'**
  String get idFrontDesc;

  /// No description provided for @idBackTitle.
  ///
  /// In en, this message translates to:
  /// **'Identity card back'**
  String get idBackTitle;

  /// No description provided for @idBackDesc.
  ///
  /// In en, this message translates to:
  /// **'Clear photo of the back side of your National ID.'**
  String get idBackDesc;

  /// No description provided for @selfieTitle.
  ///
  /// In en, this message translates to:
  /// **'Selfie Photo'**
  String get selfieTitle;

  /// No description provided for @selfieDesc.
  ///
  /// In en, this message translates to:
  /// **'Selfie holding your ID card next to your face.'**
  String get selfieDesc;

  /// No description provided for @businessProofTitle.
  ///
  /// In en, this message translates to:
  /// **'Business Proof / Commercial Register'**
  String get businessProofTitle;

  /// No description provided for @businessProofDesc.
  ///
  /// In en, this message translates to:
  /// **'Official commercial register or tax registration document in PDF, JPEG, or PNG format.'**
  String get businessProofDesc;

  /// No description provided for @userProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'User Profile'**
  String get userProfileTitle;

  /// No description provided for @syncPausedOfflineMsg.
  ///
  /// In en, this message translates to:
  /// **'Sync paused. Showing offline notifications.'**
  String get syncPausedOfflineMsg;

  /// No description provided for @systemStatusOperationalMsg.
  ///
  /// In en, this message translates to:
  /// **'System Status: Operational.'**
  String get systemStatusOperationalMsg;

  /// No description provided for @userNotAuthenticatedError.
  ///
  /// In en, this message translates to:
  /// **'User not authenticated.'**
  String get userNotAuthenticatedError;

  /// No description provided for @noLocationSelectedLabel.
  ///
  /// In en, this message translates to:
  /// **'No location selected'**
  String get noLocationSelectedLabel;

  /// No description provided for @unknownActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Unknown Action'**
  String get unknownActionLabel;

  /// No description provided for @clientOwnerRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Client / Owner'**
  String get clientOwnerRoleLabel;

  /// No description provided for @quickDeliveryUserFallback.
  ///
  /// In en, this message translates to:
  /// **'Quick Delivery User'**
  String get quickDeliveryUserFallback;

  /// No description provided for @subscriptionUpdatedSuccessMsg.
  ///
  /// In en, this message translates to:
  /// **'Subscription updated successfully!'**
  String get subscriptionUpdatedSuccessMsg;

  /// No description provided for @activePlanLabel.
  ///
  /// In en, this message translates to:
  /// **'Active Plan'**
  String get activePlanLabel;

  /// No description provided for @downgradeToFreeBtn.
  ///
  /// In en, this message translates to:
  /// **'Downgrade to Free'**
  String get downgradeToFreeBtn;

  /// No description provided for @subscriptionDowngradeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Downgrade to Free?'**
  String get subscriptionDowngradeConfirmTitle;

  /// No description provided for @subscriptionDowngradeConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'You will immediately lose Pro features: live driver tracking, dispatch, advanced pricing, and the employee suite.'**
  String get subscriptionDowngradeConfirmMessage;

  /// No description provided for @awaitingPaymentLabel.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Payment'**
  String get awaitingPaymentLabel;

  /// No description provided for @upgradeToProfessionalBtn.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Professional'**
  String get upgradeToProfessionalBtn;

  /// No description provided for @subscriptionUpgradeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Professional?'**
  String get subscriptionUpgradeConfirmTitle;

  /// No description provided for @subscriptionUpgradeConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'You will be charged \$19.99/month starting immediately, unlocking live tracking, dispatch, and the employee suite.'**
  String get subscriptionUpgradeConfirmMessage;

  /// No description provided for @appUpdateRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'App Update Required'**
  String get appUpdateRequiredTitle;

  /// No description provided for @mandatoryUpdateBody.
  ///
  /// In en, this message translates to:
  /// **'A mandatory app update is available. Please update Quick Delivery to continue using the service.'**
  String get mandatoryUpdateBody;

  /// No description provided for @whatsNewSecurityItem.
  ///
  /// In en, this message translates to:
  /// **'Enhanced security protocols for order and delivery tracking.'**
  String get whatsNewSecurityItem;

  /// No description provided for @whatsNewRoutingItem.
  ///
  /// In en, this message translates to:
  /// **'Optimized routing algorithms for faster deliveries.'**
  String get whatsNewRoutingItem;

  /// No description provided for @whatsNewBugFixesItem.
  ///
  /// In en, this message translates to:
  /// **'Critical bug fixes and stability improvements.'**
  String get whatsNewBugFixesItem;

  /// No description provided for @installedVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Installed Version'**
  String get installedVersionLabel;

  /// No description provided for @minimumRequiredLabel.
  ///
  /// In en, this message translates to:
  /// **'Minimum Required'**
  String get minimumRequiredLabel;

  /// No description provided for @latestAvailableLabel.
  ///
  /// In en, this message translates to:
  /// **'Latest Available'**
  String get latestAvailableLabel;

  /// No description provided for @updateCannotContinueBody.
  ///
  /// In en, this message translates to:
  /// **'You cannot continue using the app until this update is installed.'**
  String get updateCannotContinueBody;

  /// No description provided for @updateNowBtn.
  ///
  /// In en, this message translates to:
  /// **'Update Now'**
  String get updateNowBtn;

  /// No description provided for @searchServicesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search services'**
  String get searchServicesTooltip;

  /// No description provided for @marketplaceFiltersTooltip.
  ///
  /// In en, this message translates to:
  /// **'More filters'**
  String get marketplaceFiltersTooltip;

  /// No description provided for @jobCardDetailsToggle.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get jobCardDetailsToggle;

  /// No description provided for @ratingStarSemantic.
  ///
  /// In en, this message translates to:
  /// **'Rate {n} of 5 stars'**
  String ratingStarSemantic(int n);

  /// No description provided for @otpDigitSemantic.
  ///
  /// In en, this message translates to:
  /// **'PIN digit {index} of {length}'**
  String otpDigitSemantic(int index, int length);

  /// No description provided for @whatsNewTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s new:'**
  String get whatsNewTitle;

  /// No description provided for @specialistRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Specialist'**
  String get specialistRoleLabel;

  /// No description provided for @jobMapInTransitTitle.
  ///
  /// In en, this message translates to:
  /// **'In Transit - Live Courier Tracking'**
  String get jobMapInTransitTitle;

  /// No description provided for @jobMapLiveTrackingActive.
  ///
  /// In en, this message translates to:
  /// **'Live Route Tracking Active'**
  String get jobMapLiveTrackingActive;

  /// No description provided for @roleOwnerLabel.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get roleOwnerLabel;

  /// No description provided for @inProgressLabel.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get inProgressLabel;

  /// No description provided for @roleEmployeeLabel.
  ///
  /// In en, this message translates to:
  /// **'Employee'**
  String get roleEmployeeLabel;

  /// No description provided for @notificationsAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get notificationsAll;

  /// No description provided for @notificationsJobs.
  ///
  /// In en, this message translates to:
  /// **'Jobs'**
  String get notificationsJobs;

  /// No description provided for @notificationsSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get notificationsSystem;

  /// No description provided for @notificationsAlerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get notificationsAlerts;

  /// No description provided for @confirmActionDefault.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmActionDefault;

  /// No description provided for @cancelActionDefault.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelActionDefault;

  /// No description provided for @depositMaxLimitError.
  ///
  /// In en, this message translates to:
  /// **'Maximum single deposit is 1,000,000 credits'**
  String get depositMaxLimitError;

  /// No description provided for @verifyNewEmailBtn.
  ///
  /// In en, this message translates to:
  /// **'Verify New Email'**
  String get verifyNewEmailBtn;

  /// No description provided for @enterCompleteOtpError.
  ///
  /// In en, this message translates to:
  /// **'Enter complete 6-digit code'**
  String get enterCompleteOtpError;

  /// No description provided for @listEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No items found'**
  String get listEmptyTitle;

  /// No description provided for @listEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'There are no items to display at this time.'**
  String get listEmptyBody;

  /// No description provided for @confirmPayoutBtn.
  ///
  /// In en, this message translates to:
  /// **'Confirm Payout'**
  String get confirmPayoutBtn;

  /// No description provided for @continueActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueActionLabel;

  /// No description provided for @kycUploadedStatus.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get kycUploadedStatus;

  /// No description provided for @defaultErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Error occurred'**
  String get defaultErrorTitle;

  /// No description provided for @backActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backActionLabel;

  /// Success message when funds deposit completes
  ///
  /// In en, this message translates to:
  /// **'Successfully deposited {amount} credits.'**
  String depositSuccessMessage(String amount);

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

  /// Customer label with user ID
  ///
  /// In en, this message translates to:
  /// **'Customer: {id}'**
  String customerWithId(String id);

  /// Success snackbar message when an employee is registered
  ///
  /// In en, this message translates to:
  /// **'Successfully created employee account:\nUsername: {username}\nID: {id}'**
  String employeeRegisteredSuccess(String username, String id);

  /// Error message when counter offer price is out of range
  ///
  /// In en, this message translates to:
  /// **'Price must be between \${min} and \${max}'**
  String priceRangeError(String min, String max);

  /// No description provided for @jobStateChangedError.
  ///
  /// In en, this message translates to:
  /// **'Job state changed — the other party already acted or status changed.'**
  String get jobStateChangedError;

  /// Validation error when uploaded file is larger than 10MB
  ///
  /// In en, this message translates to:
  /// **'File size exceeds maximum allowed size of 10MB, got {size}MB.'**
  String fileSizeExceededError(String size);

  /// Indicator that a document is already uploaded and on file
  ///
  /// In en, this message translates to:
  /// **'Document on file: {filename}'**
  String documentOnFile(String filename);

  /// No description provided for @notificationsJobsTag.
  ///
  /// In en, this message translates to:
  /// **'JOB ALERT'**
  String get notificationsJobsTag;

  /// No description provided for @notificationsAlertsTag.
  ///
  /// In en, this message translates to:
  /// **'ALERT'**
  String get notificationsAlertsTag;

  /// No description provided for @notificationsSystemTag.
  ///
  /// In en, this message translates to:
  /// **'SYSTEM'**
  String get notificationsSystemTag;

  /// No description provided for @notificationsDefaultTag.
  ///
  /// In en, this message translates to:
  /// **'NOTIFICATION'**
  String get notificationsDefaultTag;

  /// No description provided for @notificationsToday.
  ///
  /// In en, this message translates to:
  /// **'TODAY'**
  String get notificationsToday;

  /// No description provided for @notificationsYesterday.
  ///
  /// In en, this message translates to:
  /// **'YESTERDAY'**
  String get notificationsYesterday;

  /// No description provided for @notificationsEarlier.
  ///
  /// In en, this message translates to:
  /// **'EARLIER'**
  String get notificationsEarlier;

  /// Success notification when a support ticket is created
  ///
  /// In en, this message translates to:
  /// **'Ticket submitted successfully! Ticket ID: {id}'**
  String ticketSubmittedSuccess(String id);

  /// No description provided for @estimatedPriceCourierNotice.
  ///
  /// In en, this message translates to:
  /// **'Estimated based on store address. Final fare is calculated from the assigned courier\'s location once accepted.'**
  String get estimatedPriceCourierNotice;

  /// No description provided for @retryBookingSuccess.
  ///
  /// In en, this message translates to:
  /// **'New booking created, matching courier...'**
  String get retryBookingSuccess;

  /// No description provided for @matchingCourierSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Finding nearest available courier...'**
  String get matchingCourierSubtitle;

  /// No description provided for @supportTicketsTitle.
  ///
  /// In en, this message translates to:
  /// **'Support Tickets'**
  String get supportTicketsTitle;

  /// No description provided for @supportTicketsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track and review your inquiries'**
  String get supportTicketsSubtitle;

  /// No description provided for @settingsSupportTickets.
  ///
  /// In en, this message translates to:
  /// **'Support Tickets'**
  String get settingsSupportTickets;

  /// No description provided for @settingsSupportTicketsSub.
  ///
  /// In en, this message translates to:
  /// **'View past inquiries and resolution status'**
  String get settingsSupportTicketsSub;

  /// No description provided for @createTicketFab.
  ///
  /// In en, this message translates to:
  /// **'New Ticket'**
  String get createTicketFab;

  /// No description provided for @emptyTicketsTitle.
  ///
  /// In en, this message translates to:
  /// **'No support tickets yet'**
  String get emptyTicketsTitle;

  /// No description provided for @emptyTicketsDesc.
  ///
  /// In en, this message translates to:
  /// **'Need help? Open a new complaint or inquiry ticket.'**
  String get emptyTicketsDesc;

  /// No description provided for @openNewTicketBtn.
  ///
  /// In en, this message translates to:
  /// **'Open New Ticket'**
  String get openNewTicketBtn;

  /// No description provided for @ticketFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get ticketFilterAll;

  /// No description provided for @ticketFilterOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get ticketFilterOpen;

  /// No description provided for @ticketFilterResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get ticketFilterResolved;

  /// No description provided for @statusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get statusResolved;

  /// No description provided for @statusAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get statusAssigned;

  /// No description provided for @ticketChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Ticket #{id}'**
  String ticketChatTitle(String id);

  /// No description provided for @ticketChatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Customer Support'**
  String get ticketChatSubtitle;

  /// No description provided for @ticketResolvedBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Ticket Resolved'**
  String get ticketResolvedBannerTitle;

  /// No description provided for @ticketResolvedBannerMsg.
  ///
  /// In en, this message translates to:
  /// **'This ticket has been marked as resolved by customer support.'**
  String get ticketResolvedBannerMsg;

  /// No description provided for @ticketResolutionNote.
  ///
  /// In en, this message translates to:
  /// **'Resolution Note'**
  String get ticketResolutionNote;

  /// No description provided for @ticketInputClosed.
  ///
  /// In en, this message translates to:
  /// **'This ticket is resolved and closed for new messages.'**
  String get ticketInputClosed;

  /// No description provided for @ticketAssignedAgent.
  ///
  /// In en, this message translates to:
  /// **'Assigned Agent: {agent}'**
  String ticketAssignedAgent(String agent);

  /// No description provided for @ticketPendingAgent.
  ///
  /// In en, this message translates to:
  /// **'Waiting for agent assignment...'**
  String get ticketPendingAgent;

  /// No description provided for @ticketContextJob.
  ///
  /// In en, this message translates to:
  /// **'Related to Job #{id}'**
  String ticketContextJob(String id);

  /// No description provided for @viewTicketAction.
  ///
  /// In en, this message translates to:
  /// **'View Ticket'**
  String get viewTicketAction;

  /// No description provided for @courierAvailabilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Courier Availability'**
  String get courierAvailabilityTitle;

  /// No description provided for @courierStatusOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get courierStatusOnline;

  /// No description provided for @courierStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get courierStatusOffline;

  /// No description provided for @courierStatusActiveJobLock.
  ///
  /// In en, this message translates to:
  /// **'Availability locked during active job'**
  String get courierStatusActiveJobLock;

  /// No description provided for @courierStatusAcceptingDispatch.
  ///
  /// In en, this message translates to:
  /// **'Accepting new delivery requests'**
  String get courierStatusAcceptingDispatch;

  /// No description provided for @courierStatusNotAcceptingDispatch.
  ///
  /// In en, this message translates to:
  /// **'Not accepting new delivery requests'**
  String get courierStatusNotAcceptingDispatch;

  /// No description provided for @destinationLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Destination Location'**
  String get destinationLocationLabel;

  /// No description provided for @choosePickupLocationBtn.
  ///
  /// In en, this message translates to:
  /// **'Choose Pickup on Map'**
  String get choosePickupLocationBtn;

  /// No description provided for @chooseDestinationLocationBtn.
  ///
  /// In en, this message translates to:
  /// **'Choose Destination on Map'**
  String get chooseDestinationLocationBtn;

  /// No description provided for @changePickupLocationBtn.
  ///
  /// In en, this message translates to:
  /// **'Change Pickup'**
  String get changePickupLocationBtn;

  /// No description provided for @changeDestinationLocationBtn.
  ///
  /// In en, this message translates to:
  /// **'Change Destination'**
  String get changeDestinationLocationBtn;

  /// No description provided for @tripDistanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Trip Distance:'**
  String get tripDistanceLabel;

  /// No description provided for @selectDestinationPrompt.
  ///
  /// In en, this message translates to:
  /// **'Select a destination on the map to calculate trip distance and price estimate.'**
  String get selectDestinationPrompt;

  /// No description provided for @destinationRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Please choose a destination on the map before booking.'**
  String get destinationRequiredError;

  /// No description provided for @estimatedPriceTripNotice.
  ///
  /// In en, this message translates to:
  /// **'Estimated price is based on the actual trip distance from pickup to destination.'**
  String get estimatedPriceTripNotice;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

  /// No description provided for @settingsSecuritySub.
  ///
  /// In en, this message translates to:
  /// **'Two-factor authentication and login protection'**
  String get settingsSecuritySub;

  /// No description provided for @settingsTwoFactorAuth.
  ///
  /// In en, this message translates to:
  /// **'Two-Factor Authentication'**
  String get settingsTwoFactorAuth;

  /// No description provided for @settingsTwoFactorAuthSub.
  ///
  /// In en, this message translates to:
  /// **'Require a 6-digit verification code when logging in'**
  String get settingsTwoFactorAuthSub;

  /// No description provided for @disableTwoFactorConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Disable Two-Factor Authentication?'**
  String get disableTwoFactorConfirmTitle;

  /// No description provided for @disableTwoFactorConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Disabling 2FA reduces your account security. Anyone with your password will be able to log in without an OTP verification step.'**
  String get disableTwoFactorConfirmBody;

  /// No description provided for @disableTwoFactorConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Disable 2FA'**
  String get disableTwoFactorConfirmAction;

  /// No description provided for @disableTwoFactorPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get disableTwoFactorPasswordTitle;

  /// No description provided for @disableTwoFactorPasswordBody.
  ///
  /// In en, this message translates to:
  /// **'Please enter your account password to confirm disabling two-factor authentication.'**
  String get disableTwoFactorPasswordBody;

  /// No description provided for @disableTwoFactorPasswordError.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password. 2FA was not disabled.'**
  String get disableTwoFactorPasswordError;

  /// No description provided for @twoFactorDisabledSuccess.
  ///
  /// In en, this message translates to:
  /// **'Two-factor authentication disabled'**
  String get twoFactorDisabledSuccess;

  /// No description provided for @twoFactorEnabledSuccess.
  ///
  /// In en, this message translates to:
  /// **'Two-factor authentication enabled'**
  String get twoFactorEnabledSuccess;

  /// No description provided for @ratingSubmittedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Rating Submitted'**
  String get ratingSubmittedSuccess;

  /// No description provided for @newDispatchAlertMessage.
  ///
  /// In en, this message translates to:
  /// **'New dispatch offer received. Refreshing available jobs...'**
  String get newDispatchAlertMessage;

  /// No description provided for @freezeWorkerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage worker account status, login access, and dispatch availability'**
  String get freezeWorkerSubtitle;

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
  /// **'Estimated price'**
  String get custEstimatedPrice;

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
  /// **'Soon'**
  String get acctSoon;

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

  /// FE-AUTH-ACCOUNT redesigned customer account (A-Settings).
  ///
  /// In en, this message translates to:
  /// **'Addresses are saved as text, without a map pin.'**
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

  /// FE-OWNER-2 redesigned owner screens.
  ///
  /// In en, this message translates to:
  /// **'Customers see the first letter of your service name for now. Photo upload is coming.'**
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
  /// **'The service was created but some details weren\'t saved. Tap save again.'**
  String get ownSvcErrPartial;

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
  /// **'Location copied: {coords}. Paste it into your maps app.'**
  String courCoordsCopied(String coords);

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
  /// **'Number copied: {phone}. Paste it into your phone app to call.'**
  String courPhoneCopied(String phone);

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
  /// **'Copy the phone number'**
  String get courCopyPhone;

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
  /// **'Enter an Egyptian mobile number like 01012345678, or an international number starting with +.'**
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
