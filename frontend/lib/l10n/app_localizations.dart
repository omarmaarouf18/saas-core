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
  /// **'Auto (System)'**
  String get langAuto;

  /// No description provided for @langEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @langArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية (مصر)'**
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
  /// **'Email Address (Read-Only)'**
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
  /// **'Save quick locations for faster booking (max 10).'**
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

  /// No description provided for @ownerConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Owner Configuration'**
  String get ownerConfigTitle;

  /// No description provided for @myServicesTitle.
  ///
  /// In en, this message translates to:
  /// **'My Services'**
  String get myServicesTitle;

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
  /// **'Coverage Radius (KM)'**
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

  /// No description provided for @ownerConfigBasePriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Base Price (\$)'**
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
  /// **'Price per KM (\$)'**
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
  /// **'At least 6 characters'**
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
  /// **'Max Distance (KM)'**
  String get customerMarketplaceFilterRadius;

  /// No description provided for @customerMarketplaceChooseMap.
  ///
  /// In en, this message translates to:
  /// **'Choose Location on Map'**
  String get customerMarketplaceChooseMap;

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
  /// **'Total Balance'**
  String get walletTotalBalance;

  /// No description provided for @walletWithdrawable.
  ///
  /// In en, this message translates to:
  /// **'Withdrawable'**
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

  /// No description provided for @unauthenticatedMsg.
  ///
  /// In en, this message translates to:
  /// **'Unauthenticated'**
  String get unauthenticatedMsg;

  /// No description provided for @serviceCreatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Service created successfully!'**
  String get serviceCreatedSuccess;

  /// No description provided for @serviceCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create service: {error}'**
  String serviceCreateFailed(String error);

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
  /// **'Identity Verification (KYC)'**
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

  /// No description provided for @ownerHomeServices.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get ownerHomeServices;

  /// No description provided for @ownerHomeServicesSub.
  ///
  /// In en, this message translates to:
  /// **'Rates & config'**
  String get ownerHomeServicesSub;

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
  /// **'Confirm you have physically collected the cash payment of \${amount} (COD) from the customer.\n\nThis will deduct the platform fee from the owner\'s wallet and mark Job #{jobId} as completed.'**
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
  /// **'Locked (Escrow)'**
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
  /// **'Amount (Credits)'**
  String get walletAmountCredits;

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
  /// **'At least 6 characters'**
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
  /// **'Private Feedback (Optional)'**
  String get privateFeedbackLabel;

  /// No description provided for @loadingStatus.
  ///
  /// In en, this message translates to:
  /// **'Loading status...'**
  String get loadingStatus;

  /// No description provided for @loadingServices.
  ///
  /// In en, this message translates to:
  /// **'Loading services...'**
  String get loadingServices;

  /// No description provided for @noServicesConfigured.
  ///
  /// In en, this message translates to:
  /// **'No Services Configured'**
  String get noServicesConfigured;

  /// No description provided for @noServicesDescription.
  ///
  /// In en, this message translates to:
  /// **'No services configured yet.\nTap the + button to create a service.'**
  String get noServicesDescription;

  /// No description provided for @addService.
  ///
  /// In en, this message translates to:
  /// **'Add Service'**
  String get addService;

  /// No description provided for @kycPending.
  ///
  /// In en, this message translates to:
  /// **'KYC Pending'**
  String get kycPending;

  /// No description provided for @kycRejectedDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification Rejected'**
  String get kycRejectedDialogTitle;

  /// No description provided for @serviceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Service Name'**
  String get serviceNameLabel;

  /// No description provided for @categoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get categoryLabel;

  /// No description provided for @basePriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Base Price (\$)'**
  String get basePriceLabel;

  /// No description provided for @ratePerKmLabel.
  ///
  /// In en, this message translates to:
  /// **'Rate per KM (\$)'**
  String get ratePerKmLabel;

  /// No description provided for @latitudeLabel.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get latitudeLabel;

  /// No description provided for @longitudeLabel.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get longitudeLabel;

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
  /// **'IBAN (e.g. EG123456789012345678901234567)'**
  String get payoutAccountDetailsBankHint;

  /// No description provided for @payoutAccountDetailsInstapayHint.
  ///
  /// In en, this message translates to:
  /// **'InstaPay Mobile / Address (e.g. 01012345678)'**
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
  /// **'Enter destination or pickup area...'**
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
  /// **'Cash on Delivery (COD)'**
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

  /// No description provided for @clientIpLine.
  ///
  /// In en, this message translates to:
  /// **'IP: {ip}'**
  String clientIpLine(String ip);

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
  /// **'Password must be at least 6 characters'**
  String get passwordTooShort;

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

  /// No description provided for @jobsTrendChipMock.
  ///
  /// In en, this message translates to:
  /// **'+12% vs last week'**
  String get jobsTrendChipMock;

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
  /// **'Negotiation Window Expired (5-min limit lapsed)'**
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
  /// **'Allowed bound: {min} – {max} (±50%)'**
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
  /// **'Owners must upload all 4 documents (ID Front, ID Back, Selfie, Business Proof).'**
  String get kycOwnerDocsSub;

  /// No description provided for @kycEmployeeDocsSub.
  ///
  /// In en, this message translates to:
  /// **'Employees must upload all 3 documents (ID Front, ID Back, Selfie).'**
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

  /// No description provided for @serviceMgmtHeader.
  ///
  /// In en, this message translates to:
  /// **'Service Management'**
  String get serviceMgmtHeader;

  /// No description provided for @serviceMgmtSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure and monitor active logistics services.'**
  String get serviceMgmtSubtitle;

  /// No description provided for @verificationRequiredHeader.
  ///
  /// In en, this message translates to:
  /// **'Verification Required'**
  String get verificationRequiredHeader;

  /// No description provided for @kycRequiredDesc.
  ///
  /// In en, this message translates to:
  /// **'Please complete KYC verification to create new services or modify existing ones.'**
  String get kycRequiredDesc;

  /// No description provided for @baseRateBadge.
  ///
  /// In en, this message translates to:
  /// **'BASE RATE'**
  String get baseRateBadge;

  /// No description provided for @perKmBadge.
  ///
  /// In en, this message translates to:
  /// **'PER KM'**
  String get perKmBadge;

  /// No description provided for @serviceLocationLine.
  ///
  /// In en, this message translates to:
  /// **'Location: ({lat}, {lon})'**
  String serviceLocationLine(String lat, String lon);

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

  /// No description provided for @platformFeeLine.
  ///
  /// In en, this message translates to:
  /// **'Platform fee: {fee}%'**
  String platformFeeLine(String fee);

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
  /// **'AVAILABLE BALANCE'**
  String get availableBalanceBadge;

  /// No description provided for @balanceTrendChipMock.
  ///
  /// In en, this message translates to:
  /// **'+8.4% vs last mo'**
  String get balanceTrendChipMock;

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

  /// No description provided for @createNewServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Create New Service'**
  String get createNewServiceTitle;

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

  /// No description provided for @basePriceRequired.
  ///
  /// In en, this message translates to:
  /// **'Base price is required'**
  String get basePriceRequired;

  /// No description provided for @invalidPriceValue.
  ///
  /// In en, this message translates to:
  /// **'Invalid price'**
  String get invalidPriceValue;

  /// No description provided for @rateRequired.
  ///
  /// In en, this message translates to:
  /// **'Rate is required'**
  String get rateRequired;

  /// No description provided for @invalidRateValue.
  ///
  /// In en, this message translates to:
  /// **'Invalid rate'**
  String get invalidRateValue;

  /// No description provided for @fieldRequiredGeneric.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get fieldRequiredGeneric;

  /// No description provided for @latRangeMessage.
  ///
  /// In en, this message translates to:
  /// **'Must be between -90 and 90'**
  String get latRangeMessage;

  /// No description provided for @lonRangeMessage.
  ///
  /// In en, this message translates to:
  /// **'Must be between -180 and 180'**
  String get lonRangeMessage;

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
  /// **'Set account to Active (Unfreeze)'**
  String get employeeSetActiveStatus;

  /// No description provided for @employeeSetFrozenStatus.
  ///
  /// In en, this message translates to:
  /// **'Set account to Frozen (Suspended)'**
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

  /// No description provided for @createActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createActionLabel;

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
  /// **'Cash on Delivery (COD) bookings'**
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

  /// No description provided for @createServiceAction.
  ///
  /// In en, this message translates to:
  /// **'Create Service'**
  String get createServiceAction;

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
  /// **'Your document submission was rejected. Please review the reason below and re-upload the corrected document(s).'**
  String get kycRejectedBanner;

  /// No description provided for @kycUploadAllBanner.
  ///
  /// In en, this message translates to:
  /// **'Please upload all required verification documents below to complete identity verification.'**
  String get kycUploadAllBanner;

  /// No description provided for @ownerKybTitle.
  ///
  /// In en, this message translates to:
  /// **'Owner Verification (KYB)'**
  String get ownerKybTitle;

  /// No description provided for @employeeKyeTitle.
  ///
  /// In en, this message translates to:
  /// **'Employee Verification (KYE)'**
  String get employeeKyeTitle;

  /// No description provided for @idFrontTitle.
  ///
  /// In en, this message translates to:
  /// **'ID Card (Front)'**
  String get idFrontTitle;

  /// No description provided for @idFrontDesc.
  ///
  /// In en, this message translates to:
  /// **'Clear photo of the front side of your National ID or Passport.'**
  String get idFrontDesc;

  /// No description provided for @idBackTitle.
  ///
  /// In en, this message translates to:
  /// **'ID Card (Back)'**
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
  /// **'Official commercial register or tax registration document (PDF, JPEG, or PNG).'**
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

  /// No description provided for @nameRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequiredError;

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

  /// No description provided for @serviceFallbackLabel.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get serviceFallbackLabel;

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
  /// **'File size exceeds maximum allowed size of 10MB ({size}MB).'**
  String fileSizeExceededError(String size);

  /// Indicator that a document is already uploaded and on file
  ///
  /// In en, this message translates to:
  /// **'Document on file ({filename})'**
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
  /// **'Ticket submitted successfully! (Ticket ID: {id})'**
  String ticketSubmittedSuccess(String id);
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
