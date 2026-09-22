// The human-facing app version, mirrored from pubspec.yaml's `version:`
// entry. The two MUST be bumped together in a release change: the
// about/onboarding page shows this constant, and the sync is enforced by
// test/version_test.dart, which reads pubspec.yaml and pins the constant to
// it exactly — a drift fails the suite.
const String appVersion = '0.1.0+1';
