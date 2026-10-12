# LegionPostToolsMobileApple

A SwiftUI iPhone app for American Legion Buddy Checks, with membership renewal
and reconnection planned as a later workflow. The initial Post context is
Robert E. Burns Post 165 in Two Rivers, Wisconsin; Post identity and installation
URL are configurable.

## Current status

The repository contains the `BuddyChecks` app, three local Swift package
libraries, synthetic fixtures, package tests, native UI tests, and a separate
design harness. There are no third-party runtime dependencies.

Implemented workflows include:

- Durable synthetic drafts, simulated contact, manual check recording, corrections,
  and in-app follow-ups.
- Human sign-in, server-filtered member search and suggestions, protected connected
  drafts, accepted-record recovery, corrections, and connected follow-ups.
- Explicit Contacts creation/linking and reviewed updates, with recovery from
  unavailable contacts, changed permissions, interrupted creation, and failed saves.
- Optional phone reminders, first-name/action notification text, phone-only snooze,
  dismissal, and current-record checks when opening a reminder.
- Home and Follow-ups as the main tabs, with Account and Post settings behind the
  person icon. Suggestions browse people without creating work.

Dated local verification records document simulator workflows and installation
on the first user's iPhone 17 Pro. Physical acceptance covers the synthetic core
journey, selected Contacts workflows, and suggestions. Connected physical reminder
behavior, elapsed remembered-session behavior, broader devices/OS versions, and
wider volunteer usability still need their own evidence. Source and package tests
alone do not establish those outcomes.

This public checkpoint includes implementation and reusable documentation.
Private integration handoffs, infrastructure details, recordings, screenshots,
raw diagnostics, and signing material remain local and are ignored by Git.
Public documentation summarizes progress; it does not publish operational evidence
or establish current backend behavior. There is no CI or distributed build yet.

## Start here

- [Agent instructions](AGENTS.md): working agreement and product boundaries.
- [Original handoff](docs/BUDDY_CHECK_MOBILE_APP_HANDOFF.md): dated initial product
  context; later decisions supersede its open implementation choices.
- [Decisions](docs/DECISIONS.md): current product and implementation direction.
- [Roadmap](docs/ROADMAP.md): milestone status and remaining acceptance.
- [Development](docs/DEVELOPMENT.md): reproducible package, build, and UI-test commands.
- [Implementation](docs/IMPLEMENTATION.md): durable synthetic workflow design.
- [Buddy Check design](docs/BUDDY_CHECK_DESIGN.md): native interaction design.
- [Reusable iOS design notes](docs/IOS_DESIGN_REFERENCES.md): source-linked
  guidance and searchable review criteria for iOS projects.
- [Buddy Checks design application](docs/BUDDY_CHECK_DESIGN_REFERENCES.md): how
  those notes apply to this app's audience, decisions, and review scenarios.
- [Design harness](design/README.md): a separate session-only SwiftUI study.

## Build

Use macOS with full Xcode selected. The initial development environment uses
Xcode 27 and the iOS 27 simulator. The app's provisional minimum is iOS 18;
that setting does not establish compatibility testing on iOS 18.

```sh
bash scripts/check-development-environment.sh
swift test --scratch-path .build/core
xcodebuild -project BuddyChecks.xcodeproj -scheme BuddyChecks \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/Xcode CODE_SIGNING_ALLOWED=NO build-for-testing
```

See the development guide for simulator execution and local signing. Only public
connection defaults belong in configuration files; never embed account credentials,
shared privileged tokens, personal signing settings, or real contact fixtures.
