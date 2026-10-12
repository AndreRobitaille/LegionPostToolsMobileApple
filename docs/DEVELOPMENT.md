# Development

## Environment

Build and run on macOS with full Xcode, an installed iOS Simulator runtime, and
the Swift toolchain that ships with Xcode. The initial development setup uses
Xcode 27, Swift 6.4, and the iOS 27 simulator. The app's provisional minimum is
iOS 18; older supported OS versions require separate verification.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
bash scripts/check-development-environment.sh
```

The check script reads the toolchain/runtime configuration. It does not build the
app, verify signing, install on a phone, or establish physical-device behavior.
Xcode, Swift macros, and CoreSimulator may require host access when an agent's
filesystem sandbox blocks them. Do not change global signing or trust settings
to work around a sandbox error.

## Package tests

`Package.swift` defines `BuddyCheckCore`, `BuddyCheckContacts`, and `BuddyCheckAPI`
with local package dependencies only.

```sh
swift test --scratch-path .build/core
```

These tests use synthetic data and in-memory Contacts objects/fake stores.
They do not access the developer's address book, contact a production installation,
or establish iOS UI, notification delivery, backend persistence, or phone usability.

## Simulator build

Open `BuddyChecks.xcodeproj` and select the shared **BuddyChecks** scheme.
The bundle identifier is `org.wipost165.buddychecks`.

```sh
xcodebuild -project BuddyChecks.xcodeproj -scheme BuddyChecks \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/Xcode CODE_SIGNING_ALLOWED=NO build-for-testing
```

This compiles the app and UI-test runner without installing or running them.
An App Intents metadata-extraction warning is expected because the app has no
App Intents dependency.

Choose an available simulator on your own Mac:

```sh
xcrun simctl list devices available
```

Replace `SIMULATOR_UUID` below with that device's identifier:

```sh
xcrun simctl boot SIMULATOR_UUID
xcrun simctl bootstatus SIMULATOR_UUID -b
xcrun simctl install SIMULATOR_UUID \
  .build/Xcode/Build/Products/Debug-iphonesimulator/BuddyChecks.app
xcrun simctl launch SIMULATOR_UUID org.wipost165.buddychecks
```

Synthetic work persists in the app's sandbox. Terminate/relaunch to inspect draft
restoration. Use a disposable simulator when a test intentionally clears app state
or changes simulator Contacts. Never substitute a real member or arbitrary real
phone number for a synthetic fixture.

## Native UI tests

Use a disposable simulator and supply its identifier explicitly. Select only
the workflow cases relevant to the change. For example:

```sh
xcodebuild -project BuddyChecks.xcodeproj -scheme BuddyChecks \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath .build/Xcode CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:BuddyChecksUITests/StandardWorkflowUITests \
  -only-testing:BuddyChecksUITests/BuddyChecksUITests/testInterruptedManualCheckCorrectionAndSingleRecord \
  -only-testing:BuddyChecksUITests/ConnectedUITests/testConnectedSuggestionRecordAndServerReceipt \
  test
```

`StandardWorkflowUITests` contains only ordinary-size connected workflow checks:
accepted facts and Home activity, method/note restoration after process restart,
uncertain-save recovery, and stale-correction review. Its opt-in workflow-store
fixture uses a UUID-isolated encrypted journal and a file-backed synthetic vault
for unsigned simulator builds. It does not verify Keychain, call Contacts, or
contact a Post server. Focused package coverage is
`swift test --scratch-path .build/core --filter 'HomeActivityTests|JournalTests'`.

The public UI tests exercise synthetic app responses and selected native adapters.
They do not establish live Post permissions or production acceptance. Inspect
standard-size primary-phone screens, interruptions, calling/returning, and
notification permission changes when the behavior is affected.

Andre's October 12 instruction excludes VoiceOver, assistive-technology checks,
and accessibility audits from routine work. Do not enable or run them unless
explicitly requested. Do not run an unfiltered UI suite: existing cases include
VoiceOver and audit checks, sometimes through shared helpers. Inspect the selected
case and its helpers before execution. His later clarification prioritizes major
standard-size design and workflow improvements. Large-font checks and
smaller-phone matrices come later and must not delay that work.

## Local connection and signing

Ordinary builds start with blank connection defaults. The opt-in
`Configuration/Post165.xcconfig` contains only the public installation URL and
public OAuth client identifier. Existing saved settings take precedence.

```sh
xcodebuild -project BuddyChecks.xcodeproj -scheme BuddyChecks \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -xcconfig Configuration/Post165.xcconfig \
  -derivedDataPath .build/Phone \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

Select your team locally and obtain separate authorization for provisioning,
installation, and real-data use. Do not commit personal team settings, signing
profiles, certificates, account credentials, or private connection values.
Building does not install, distribute, or deploy the app or backend.

Private integration diagnostics remain local. They are excluded from the public
source and require `BUDDY_CHECKS_PRIVATE_INTEGRATION` in the local Debug compilation
conditions for both the app and test runner. Ordinary public Debug and Release
builds use the normal transport. Existing private fixture guards, test-service
configuration, and separate authorization still apply; the compilation flag does
not authorize integration activity.

## Design harness and app icon

The [design harness](../design/README.md) is a separate, session-only preview.
It does not implement persistence, real calls, connected records, or reminders.
The production icon source is `BuddyChecks/BuddyChecksIcon.icon`; use the existing
Icon Composer package rather than regenerating flattened icon artwork.

## Verification and publication

Review staged changes, new files, documentation links, and `git diff --check`.
Run package tests and proportionate native checks. Keep package tests, simulator
runs, prior physical observations, and live backend evidence distinct.

Stage explicit source/documentation paths and inspect the resulting tree before
committing. Review evidence, installation-specific integration tools, raw captures,
exported data, credentials, signing material, and trust stores are ignored and
remain local. Scan the exact publishable tree and history for credentials before
pushing to the public repository. Ignored files are not backed up by a Git push.
