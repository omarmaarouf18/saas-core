/// Compile-time feature flags (`--dart-define=NAME=true`).
library;

/// FE-CUST-1: the redesigned customer app (redesign A). Off by default, so a
/// plain build is the existing app; turn it on with
/// `--dart-define=QD_REDESIGN_CUSTOMER=true` until every customer screen is
/// rebuilt (FE-CUST-2, FE-CLEANUP).
const bool kRedesignCustomer =
    bool.fromEnvironment('QD_REDESIGN_CUSTOMER', defaultValue: false);

/// FE-AUTH-ACCOUNT: the redesigned signed-out screens (sign in, sign up,
/// code entry, password reset) and the update-required screen. They are
/// shared by every role, so they have their own flag; turn it on with
/// `--dart-define=QD_REDESIGN_AUTH=true`. The customer account, notification
/// and support pages open from the customer shell and stay behind
/// [kRedesignCustomer].
const bool kRedesignAuth =
    bool.fromEnvironment('QD_REDESIGN_AUTH', defaultValue: false);

/// FE-OWNER-1: the redesigned owner app (redesign A): Today, Orders, Team
/// and the order / courier / payment-review pages. Off by default, so a
/// plain build is the existing owner dashboard; turn it on with
/// `--dart-define=QD_REDESIGN_OWNER=true`. Service setup, fleet map,
/// wallet, subscription, activity log, KYB upload and owner settings are
/// still the existing screens (FE-OWNER-2).
const bool kRedesignOwner =
    bool.fromEnvironment('QD_REDESIGN_OWNER', defaultValue: false);
