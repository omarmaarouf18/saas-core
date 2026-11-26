# STORE-PIPELINE: Fastlane for Play internal/closed testing and TestFlight
# (frontend/docs/STORE_TESTING.md). Run lanes with `bundle exec fastlane ...`
# from this directory. Gemfile.lock is not committed yet: the first CI run
# resolves it and uploads it as an artifact; commit that file to pin the
# versions (see the worklog).
source "https://rubygems.org"

gem "fastlane", "~> 2.228"
# flutter_secure_storage has no Swift Package Manager support, so Flutter
# runs `pod install` during the iOS build. Under `bundle exec` the runner's
# system CocoaPods (another Ruby) is "installed but broken"; this one works.
gem "cocoapods", "~> 1.16"
