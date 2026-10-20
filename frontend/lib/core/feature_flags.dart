/// Compile-time feature flags (`--dart-define=NAME=true`).
library;

/// FE-CUST-1: the redesigned customer app (redesign A). Off by default, so a
/// plain build is the existing app; turn it on with
/// `--dart-define=QD_REDESIGN_CUSTOMER=true` until every customer screen is
/// rebuilt (FE-CUST-2, FE-CLEANUP).
const bool kRedesignCustomer =
    bool.fromEnvironment('QD_REDESIGN_CUSTOMER', defaultValue: false);
