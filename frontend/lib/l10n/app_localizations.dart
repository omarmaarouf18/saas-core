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

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

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

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming Soon'**
  String get comingSoon;

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

  /// No description provided for @navEmployees.
  ///
  /// In en, this message translates to:
  /// **'Employees'**
  String get navEmployees;

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

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsAppearanceSub.
  ///
  /// In en, this message translates to:
  /// **'Customize application look and feel'**
  String get settingsAppearanceSub;

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

  /// No description provided for @enterOtpPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit verification code sent to your new email.'**
  String get enterOtpPrompt;

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
  /// **'e.g. Quick Cargo Express'**
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

  /// No description provided for @ownerConfigPhotoUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Photo URL'**
  String get ownerConfigPhotoUrlLabel;

  /// No description provided for @ownerConfigPhotoUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://example.com/logo.png'**
  String get ownerConfigPhotoUrlHint;

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

  /// No description provided for @customerHomeQuickBookBanner.
  ///
  /// In en, this message translates to:
  /// **'Need a quick delivery?'**
  String get customerHomeQuickBookBanner;

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

  /// No description provided for @customerMarketplaceSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search services...'**
  String get customerMarketplaceSearchHint;

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

  /// No description provided for @customerMarketplaceBookBtn.
  ///
  /// In en, this message translates to:
  /// **'BOOK SERVICE'**
  String get customerMarketplaceBookBtn;

  /// No description provided for @customerMarketplaceCodNote.
  ///
  /// In en, this message translates to:
  /// **'Note: COD (Cash on Delivery) is enforced during beta.'**
  String get customerMarketplaceCodNote;

  /// No description provided for @customerJobsTitle.
  ///
  /// In en, this message translates to:
  /// **'My Orders'**
  String get customerJobsTitle;

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

  /// No description provided for @customerJobsViewDetails.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get customerJobsViewDetails;

  /// No description provided for @jobStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Order Status'**
  String get jobStatusTitle;

  /// No description provided for @jobStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get jobStatusPending;

  /// No description provided for @jobStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get jobStatusActive;

  /// No description provided for @jobStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get jobStatusCompleted;

  /// No description provided for @jobStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get jobStatusCancelled;

  /// No description provided for @jobStatusCancelBtn.
  ///
  /// In en, this message translates to:
  /// **'Cancel Order'**
  String get jobStatusCancelBtn;

  /// No description provided for @jobStatusOpenTicketBtn.
  ///
  /// In en, this message translates to:
  /// **'Open Complaint Ticket'**
  String get jobStatusOpenTicketBtn;

  /// No description provided for @jobStatusCounterOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Price Counter-Offer'**
  String get jobStatusCounterOfferTitle;

  /// No description provided for @jobStatusCounterOfferSubmit.
  ///
  /// In en, this message translates to:
  /// **'Propose Counter Price'**
  String get jobStatusCounterOfferSubmit;

  /// No description provided for @ownerHomeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get ownerHomeGreeting;

  /// No description provided for @ownerHomeKycAlert.
  ///
  /// In en, this message translates to:
  /// **'Your KYC verification is pending admin approval.'**
  String get ownerHomeKycAlert;

  /// No description provided for @ownerHomeMetricsWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet Balance'**
  String get ownerHomeMetricsWallet;

  /// No description provided for @ownerHomeMetricsSubscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription Tier'**
  String get ownerHomeMetricsSubscription;

  /// No description provided for @ownerHomeEntryWallet.
  ///
  /// In en, this message translates to:
  /// **'Manage Wallet'**
  String get ownerHomeEntryWallet;

  /// No description provided for @ownerHomeEntryService.
  ///
  /// In en, this message translates to:
  /// **'Service Configuration'**
  String get ownerHomeEntryService;

  /// No description provided for @ownerHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'History & Audit Logs'**
  String get ownerHistoryTitle;

  /// No description provided for @ownerHistoryTabAudit.
  ///
  /// In en, this message translates to:
  /// **'Audit Log'**
  String get ownerHistoryTabAudit;

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

  /// No description provided for @ownerFleetMapTitle.
  ///
  /// In en, this message translates to:
  /// **'Fleet Map'**
  String get ownerFleetMapTitle;

  /// No description provided for @customerJobMapTitle.
  ///
  /// In en, this message translates to:
  /// **'Live Tracking'**
  String get customerJobMapTitle;

  /// No description provided for @employeeJobsTitle.
  ///
  /// In en, this message translates to:
  /// **'Assigned Jobs'**
  String get employeeJobsTitle;

  /// No description provided for @employeeJobsCompleteBtn.
  ///
  /// In en, this message translates to:
  /// **'Complete Job'**
  String get employeeJobsCompleteBtn;

  /// No description provided for @employeeJobsVerifyDocsBtn.
  ///
  /// In en, this message translates to:
  /// **'KYC Documents'**
  String get employeeJobsVerifyDocsBtn;

  /// No description provided for @employeeJobsChatBtn.
  ///
  /// In en, this message translates to:
  /// **'Chat with Customer'**
  String get employeeJobsChatBtn;

  /// No description provided for @employeeJobsCashConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Cash Collection'**
  String get employeeJobsCashConfirmTitle;

  /// No description provided for @employeeJobsCashConfirmMsg.
  ///
  /// In en, this message translates to:
  /// **'Did you collect cash from the customer for this COD job?'**
  String get employeeJobsCashConfirmMsg;

  /// No description provided for @employeeScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Workers'**
  String get employeeScreenTitle;

  /// No description provided for @employeeRegisterHeader.
  ///
  /// In en, this message translates to:
  /// **'Register New Worker'**
  String get employeeRegisterHeader;

  /// No description provided for @employeeFreezeBtn.
  ///
  /// In en, this message translates to:
  /// **'Freeze'**
  String get employeeFreezeBtn;

  /// No description provided for @employeeUnfreezeBtn.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get employeeUnfreezeBtn;

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

  /// No description provided for @chatSendBtn.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSendBtn;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

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

  /// No description provided for @notificationsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get notificationsClear;

  /// No description provided for @kycTitle.
  ///
  /// In en, this message translates to:
  /// **'Document Verification'**
  String get kycTitle;

  /// No description provided for @kycRejectionBanner.
  ///
  /// In en, this message translates to:
  /// **'Your documents were rejected. Reason:'**
  String get kycRejectionBanner;

  /// No description provided for @kycApprovedBadge.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get kycApprovedBadge;

  /// No description provided for @kybKyeReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'KYC Review Queue'**
  String get kybKyeReviewTitle;

  /// No description provided for @kybKyeApproveBtn.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get kybKyeApproveBtn;

  /// No description provided for @kybKyeRejectBtn.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get kybKyeRejectBtn;

  /// No description provided for @walletTitle.
  ///
  /// In en, this message translates to:
  /// **'Owner Wallet'**
  String get walletTitle;

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

  /// No description provided for @walletEscrow.
  ///
  /// In en, this message translates to:
  /// **'In Escrow'**
  String get walletEscrow;

  /// No description provided for @walletDepositBtn.
  ///
  /// In en, this message translates to:
  /// **'Deposit Funds'**
  String get walletDepositBtn;

  /// No description provided for @reconciliationTitle.
  ///
  /// In en, this message translates to:
  /// **'Escrow Reconciliation'**
  String get reconciliationTitle;

  /// No description provided for @reconciliationReleaseBtn.
  ///
  /// In en, this message translates to:
  /// **'Release Funds'**
  String get reconciliationReleaseBtn;

  /// No description provided for @reconciliationRefundBtn.
  ///
  /// In en, this message translates to:
  /// **'Refund Customer'**
  String get reconciliationRefundBtn;

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

  /// No description provided for @subscriptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription Plans'**
  String get subscriptionTitle;

  /// No description provided for @subscriptionFree.
  ///
  /// In en, this message translates to:
  /// **'Free Tier'**
  String get subscriptionFree;

  /// No description provided for @subscriptionPro.
  ///
  /// In en, this message translates to:
  /// **'Professional Tier'**
  String get subscriptionPro;

  /// No description provided for @locationPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose Location on Map'**
  String get locationPickerTitle;

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

  /// No description provided for @pendingKybKyeSubmissions.
  ///
  /// In en, this message translates to:
  /// **'Pending KYB/KYE Submissions'**
  String get pendingKybKyeSubmissions;

  /// No description provided for @reviewCompletedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Review completed successfully for {username}.'**
  String reviewCompletedSuccess(String username);

  /// No description provided for @reconciliationReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Escrow Reconciliation Review'**
  String get reconciliationReviewTitle;

  /// No description provided for @tooltipRefreshQueue.
  ///
  /// In en, this message translates to:
  /// **'Refresh Queue'**
  String get tooltipRefreshQueue;

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

  /// No description provided for @docViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'Document Viewer'**
  String get docViewerTitle;

  /// No description provided for @docTabIdFront.
  ///
  /// In en, this message translates to:
  /// **'Front ID'**
  String get docTabIdFront;

  /// No description provided for @docTabIdBack.
  ///
  /// In en, this message translates to:
  /// **'Back ID'**
  String get docTabIdBack;

  /// No description provided for @docTabSelfie.
  ///
  /// In en, this message translates to:
  /// **'Selfie'**
  String get docTabSelfie;

  /// No description provided for @docTabBusinessProof.
  ///
  /// In en, this message translates to:
  /// **'Business Proof'**
  String get docTabBusinessProof;

  /// No description provided for @docLoadingPreview.
  ///
  /// In en, this message translates to:
  /// **'Loading document preview...'**
  String get docLoadingPreview;

  /// No description provided for @docNotProvided.
  ///
  /// In en, this message translates to:
  /// **'Document not provided for this submission.'**
  String get docNotProvided;

  /// No description provided for @docFailedLoad.
  ///
  /// In en, this message translates to:
  /// **'Failed to load document preview'**
  String get docFailedLoad;

  /// No description provided for @docPdfPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'PDF Document Preview'**
  String get docPdfPreviewTitle;

  /// No description provided for @docFileSize.
  ///
  /// In en, this message translates to:
  /// **'File Size: {size} bytes'**
  String docFileSize(int size);

  /// No description provided for @docDecodeError.
  ///
  /// In en, this message translates to:
  /// **'Failed to decode image bytes.'**
  String get docDecodeError;

  /// No description provided for @docNoDocument.
  ///
  /// In en, this message translates to:
  /// **'No document loaded.'**
  String get docNoDocument;

  /// No description provided for @docRejectionReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Rejection Reason / Notes'**
  String get docRejectionReasonLabel;

  /// No description provided for @docRejectionReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Explain why this submission is being rejected...'**
  String get docRejectionReasonHint;

  /// No description provided for @docRejectionReasonReq.
  ///
  /// In en, this message translates to:
  /// **'Rejection reason is required.'**
  String get docRejectionReasonReq;

  /// No description provided for @docConfirmReject.
  ///
  /// In en, this message translates to:
  /// **'Confirm Reject'**
  String get docConfirmReject;

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

  /// No description provided for @ownerHomeTabTitleHistory.
  ///
  /// In en, this message translates to:
  /// **'History & Audit Logs'**
  String get ownerHomeTabTitleHistory;

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

  /// No description provided for @ownerHomeTooltipReviewQueue.
  ///
  /// In en, this message translates to:
  /// **'KYB/KYE Review Queue'**
  String get ownerHomeTooltipReviewQueue;

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

  /// No description provided for @ownerHomeJobCancelledEscrowRefunded.
  ///
  /// In en, this message translates to:
  /// **'Job cancelled successfully. Escrow refunded to wallet.'**
  String get ownerHomeJobCancelledEscrowRefunded;

  /// No description provided for @ownerHomeJobCancelled.
  ///
  /// In en, this message translates to:
  /// **'Job cancelled successfully.'**
  String get ownerHomeJobCancelled;

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
  /// **'Employee Action Simulator'**
  String get employeeJobsSimulatorTitle;

  /// No description provided for @employeeJobsSimulatorDesc.
  ///
  /// In en, this message translates to:
  /// **'Log service events directly into the tenant audit trail.'**
  String get employeeJobsSimulatorDesc;

  /// No description provided for @employeeJobsSimulatorLabel.
  ///
  /// In en, this message translates to:
  /// **'Simulation Action Text'**
  String get employeeJobsSimulatorLabel;

  /// No description provided for @employeeJobsSimulatorHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Arrived at Pickup, Job in Route'**
  String get employeeJobsSimulatorHint;

  /// No description provided for @employeeJobsSimulatorValidation.
  ///
  /// In en, this message translates to:
  /// **'Please enter or select an action to simulate'**
  String get employeeJobsSimulatorValidation;

  /// No description provided for @employeeJobsSimulateButton.
  ///
  /// In en, this message translates to:
  /// **'Simulate Action'**
  String get employeeJobsSimulateButton;

  /// No description provided for @employeeJobsSectionAssigned.
  ///
  /// In en, this message translates to:
  /// **'Your Assigned Jobs'**
  String get employeeJobsSectionAssigned;

  /// No description provided for @employeeJobsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading assigned jobs...'**
  String get employeeJobsLoading;

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

  /// No description provided for @walletLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading wallet...'**
  String get walletLoading;

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

  /// No description provided for @sortByLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort By'**
  String get sortByLabel;

  /// No description provided for @searchingServices.
  ///
  /// In en, this message translates to:
  /// **'Searching services...'**
  String get searchingServices;

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

  /// No description provided for @employeeRegisteredTitle.
  ///
  /// In en, this message translates to:
  /// **'Employee Registered'**
  String get employeeRegisteredTitle;

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

  /// No description provided for @workerStatusUpdated.
  ///
  /// In en, this message translates to:
  /// **'Worker Status Updated'**
  String get workerStatusUpdated;

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

  /// No description provided for @liveTrackingTitle.
  ///
  /// In en, this message translates to:
  /// **'Live Tracking'**
  String get liveTrackingTitle;

  /// No description provided for @stepRequestPlaced.
  ///
  /// In en, this message translates to:
  /// **'Request Placed'**
  String get stepRequestPlaced;

  /// No description provided for @stepWaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for operator approval'**
  String get stepWaitingApproval;

  /// No description provided for @stepWorkerDispatched.
  ///
  /// In en, this message translates to:
  /// **'Worker Dispatched'**
  String get stepWorkerDispatched;

  /// No description provided for @stepJobCompleted.
  ///
  /// In en, this message translates to:
  /// **'Job Completed'**
  String get stepJobCompleted;

  /// No description provided for @stepCompletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Delivery completed successfully'**
  String get stepCompletedSuccessfully;

  /// No description provided for @jobDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Job Details'**
  String get jobDetailsTitle;

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

  /// No description provided for @accessDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'Access Denied'**
  String get accessDeniedTitle;

  /// No description provided for @loadingPendingSubmissions.
  ///
  /// In en, this message translates to:
  /// **'Loading pending submissions...'**
  String get loadingPendingSubmissions;

  /// No description provided for @noPendingSubmissions.
  ///
  /// In en, this message translates to:
  /// **'No Pending Submissions'**
  String get noPendingSubmissions;

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

  /// No description provided for @privateFeedbackHint.
  ///
  /// In en, this message translates to:
  /// **'What went well? What could be improved?'**
  String get privateFeedbackHint;

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
