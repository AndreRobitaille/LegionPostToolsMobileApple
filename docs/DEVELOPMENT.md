# Development

## Environment and repository status

Observed during initialization on October 11, 2026:

- Checkout: `/home/andre/Development/LegionPostToolsMobileApple` on Linux.
- Remote: `https://github.com/AndreRobitaille/LegionPostToolsMobileApple.git`.
- Initial revision: `6c9ff96`, on `master`; the worktree was clean before setup.
- `swift`, `xcodebuild`, and `xcrun` were not available on the current PATH.
- No Xcode project, Swift package, app source, dependencies, CI, or tests exist yet.
- MacBook access/configuration, installed iOS version, signing, and device install
  route have not been verified in this session.

Recheck these observations before relying on them; they are not machine requirements
or permanent project state.

## Work primarily on the MacBook

Use the MacBook for the SwiftUI edit/build/run cycle and iPhone verification.
[Xcode](https://developer.apple.com/xcode/) provides previews, simulators, and
Apple-platform development tools. Keep backend development on Linux as useful;
documentation and source editing can happen on either machine.

Once these initialization files are committed and pushed under Andre's
authorization, clone or update this repository on the MacBook and open that
checkout in Codex. Until then, the new files exist only in this Linux worktree;
a fresh clone will not contain uncommitted changes. Keep each machine's unrelated
work intact and exchange scoped changes through Git.

Before creating the app target:

1. Inspect the Mac's macOS and Xcode versions and the iPhone's installed iOS version.
   Check Apple's current compatibility information; do not guess a minimum iOS
   version or require the newest SDK without a reason.
2. Confirm the active developer tools and installed simulators. Read-only starting
   commands on the Mac are `sw_vers`, `xcodebuild -version`, `xcode-select -p`, and
   `xcrun simctl list devices available`.
3. Establish a development signing and install route for Andre's phone. Record
   bundle identifier, deployment target, toolchain, and nonsecret setup steps.
   Keep certificates, private keys, provisioning profiles, and account credentials
   out of Git. Public distribution remains a separate milestone.
4. Create the SwiftUI app and meaningful test targets, then replace the status above
   with verified project/scheme names and exact build/test commands. Prefer the
   smallest setup that another checkout can reproduce.

Useful design and synthetic implementation work can continue before device access
is settled. Record build/device checks as unavailable until actually run.

## Verification

At the documentation-only stage, run `git diff --check`, review new files as well
as tracked changes, and check local Markdown links. No application test command
exists yet. Do not add a green placeholder CI job that implies an iOS build passed.

When app code exists, derive focused tests from the workflow contracts in the
[handoff](BUDDY_CHECK_MOBILE_APP_HANDOFF.md#verification-that-matters). Prioritize
restoration after termination, truthful outcomes/save states, retry behavior, and
reminder lifecycle. Validate rendered screens and real device behavior in addition
to tests. Record the revision, device/OS, scenario, expected and observed result,
and limitations; keep all artifacts synthetic.

## Backend coordination and provenance

The local [handoff](BUDDY_CHECK_MOBILE_APP_HANDOFF.md) is an unchanged copy of
`/home/andre/Development/LegionPostTools/docs/BUDDY_CHECK_MOBILE_APP_HANDOFF.md`,
imported October 11, 2026. Its SHA-256 is
`c2438055ed6484fe85a18b0f62e0d2a97b93c66afea362014bfb3ecfb769d164`.
The source file was untracked at import; the backend HEAD was
`6d4e96da4fe1b086bf333e899caa6ce7e46f8eea`. That commit alone does not contain
the handoff or reproduce its surrounding working tree.

The backend worktree also contained active membership model/service/migration work,
an untracked membership design, and roadmap edits. Only Git status and project
instructions were inspected for initialization; those changes were not reviewed
as an API contract or tested. The handoff's backend inventory is historical.

Before connected work, locate the current LegionPostTools checkout, read its
`AGENTS.md`, `docs/MEMBERSHIP_MANAGEMENT_DESIGN.md`, roles and sign-in guidance,
and inspect current routes and controllers. Treat paths in the copied handoff's
reference map as backend paths, not missing files in this mobile repository.
No production access is needed for a synthetic prototype. Authorized live API
work must use the installation's current permission-filtered `GET /api` handbook.

Preserve the imported handoff as historical context. Record subsequent decisions
in [DECISIONS.md](DECISIONS.md) and progress in [ROADMAP.md](ROADMAP.md), with
explicit provenance if a later source handoff is imported.
