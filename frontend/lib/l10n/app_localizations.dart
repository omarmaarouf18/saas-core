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

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Quick Delivery'**
  String get appName;

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
  /// **'Email address cannot be changed.'**
  String get myAccountEmailNote;

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
  /// **'Business History'**
  String get ownerHistoryTitle;

  /// No description provided for @ownerHistoryTabAudit.
  ///
  /// In en, this message translates to:
  /// **'Audit Log'**
  String get ownerHistoryTabAudit;

  /// No description provided for @ownerHistoryTabJobs.
  ///
  /// In en, this message translates to:
  /// **'Completed Jobs'**
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
