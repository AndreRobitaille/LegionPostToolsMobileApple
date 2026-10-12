# Native design preview

A tappable SwiftUI design study for the first Buddy Check journey. This is a
simulator-only preview with fictional people and in-memory state. It does not
dial, send messages, access a backend, persist work, or schedule notifications.
Restarting its process resets all practice work.

The [design specification](../docs/BUDDY_CHECK_DESIGN.md) describes the intended
product behavior. The review record (local record) distinguishes
observed preview behavior from work that still needs implementation and testing.

## Build and open

From the repository root, with the full Xcode toolchain selected:

```sh
bash design/build-preview.sh
xcrun simctl list devices available
```

The script compiles `BuddyCheckPreview.swift` directly with Apple's Swift compiler
and iOS Simulator SDK. It creates `.build/design/BuddyCheckDesign.app`. There is
no Xcode project, scheme, package dependency, signing identity, or test target.
The preview's compile minimum is iOS 18; only the installed iOS 27 runtime has
been tested. This is not a deployment-target decision for the future app.

Choose an available iPhone simulator with `xcrun simctl list devices available`.
Replace `SIMULATOR_UUID` below with its identifier. If it is shut down, boot it
and wait for startup before installation:

```sh
xcrun simctl boot SIMULATOR_UUID
xcrun simctl bootstatus SIMULATOR_UUID -b
```

Then install and launch:

```sh
xcrun simctl install SIMULATOR_UUID .build/design/BuddyCheckDesign.app
xcrun simctl launch SIMULATOR_UUID org.wipost165.buddychecks.designpreview
```

Open **Xcode > Open Developer Tool > Device Hub** and select **Legion Buddy
Checks - iPhone 17 Pro**. The app is named **Buddy Check Design**. The bundle ID
belongs only to this preview and is not the production app's identifier.

Xcode's macro compiler and CoreSimulator require host access when Codex's sandbox
blocks them. A sandbox failure does not mean the project failed to compile under
the working host toolchain. Do not change signing or global toolchain settings to
work around a sandbox error.

## Try the design

1. Choose **Check on someone**, then Robert Miller.
2. Choose **Simulate call with Robert**. No number is dialed.
3. Choose an outcome, then **Remind me to call again**.
4. Choose a future date/time and **Save check**.
5. Correct the outcome, open the follow-up, change its time, complete or cancel it.

The native **Home** and **Follow-ups** tabs retain separate navigation stacks.
There are no preview notices or Preview menu. Example unfinished and
notification-denied states use the launch arguments below.
The preview shows only the most recent check confirmation; it is not a history
store. The person list and Post identity are synthetic fixture configuration in
this design file, not an integration contract.

## Reproduce screen captures

With the preview installed on a booted simulator:

```sh
bash design/capture-preview.sh SIMULATOR_UUID
```

This restarts the preview for each screenshot and writes under `design/review`.
It captures ordinary text and maximum accessibility text (`accessibility5`).
Set `PREVIEW_RENDER_WAIT_SECONDS=8` on a slow simulator. Always inspect the images;
the capture command alone does not prove a screen finished rendering.

Individual scenarios use a launch argument after terminating the existing process:

```sh
xcrun simctl terminate SIMULATOR_UUID org.wipost165.buddychecks.designpreview
xcrun simctl launch SIMULATOR_UUID org.wipost165.buddychecks.designpreview --screen reminder --accessibility-max
```

Screens: `home`, `people`, `person`, `outcome`, `reminder`, `saved`, `followups`,
`followup`, `resume`, and `denied`. `--accessibility` uses accessibility3;
`--accessibility-max` uses accessibility5. Without either override, the preview
uses the simulator's Dynamic Type setting. The first pass is light appearance
only; dark appearance remains design work.

The smaller-layout review used an iPhone SE (3rd generation) simulator on iOS 27.
Choose a comparable simulator on your Mac and inspect the generated captures
locally. Review images are excluded from the public repository.

The design harness has no automated test suite. Run `bash -n design/*.sh` and
`git diff --check` for script syntax and whitespace; neither verifies UI behavior.
