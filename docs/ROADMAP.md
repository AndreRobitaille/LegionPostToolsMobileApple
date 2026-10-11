# Roadmap

Status as of October 11, 2026. These milestones describe intended outcomes;
unchecked items are not implemented. The original behavioral requirements remain
in the [handoff](BUDDY_CHECK_MOBILE_APP_HANDOFF.md).

## M0: repository ready for Codex

- [x] Preserve the source handoff locally with provenance.
- [x] Establish repository instructions, development notes, and decision record.
- [x] Record SwiftUI as the initial implementation direction.
- [x] Identify Linux tooling limits and recommend the MacBook development path.

This milestone establishes project context, not a buildable app.

## M1: one complete synthetic Buddy Check on iPhone

Next work: establish the Mac/Xcode/device path and design the small SwiftUI journey.

- [ ] Record a working development signing/install route and supported toolchain.
- [ ] Create a reproducible SwiftUI project with exact build/test commands.
- [ ] Design home, contact, outcome, and follow-up screens using the handoff's visual
  direction; review ordinary and accessibility text sizes.
- [ ] Choose a clearly synthetic contact and simulate a call without dialing.
- [ ] Record talked/no answer/wrong number/did not call outcomes and corrections.
- [ ] Save a follow-up; change, complete, or cancel it.
- [ ] Restore drafts and completed work after app termination without duplication.
- [ ] Schedule a real local device reminder, return to its follow-up, and handle
  denied permissions, stale reminders, and time-zone behavior truthfully.
- [ ] Verify the journey on Andre's iPhone 17 Pro, including interruption, relaunch,
  large text, and VoiceOver. Record checks and limitations.

Completion means the synthetic workflow persists and is understandable on the
phone. A simulated call remains visibly simulated; previews or screenshots alone
do not complete this milestone. Assistance routing is unavailable until a real
receiving workflow exists.

## M2: limited connected Buddy Check

- [ ] Reinspect current LegionPostTools code and membership work before designing
  shared records or endpoints; coordinate changes in the backend repository.
- [ ] Specify human mobile authentication, server-filtered access, minimum fields,
  and authorized device storage/retention.
- [ ] Define contact/follow-up persistence, retry deduplication, and conflict rules.
- [ ] Implement truthful local/pending/server-accepted states and recovery from
  failed saves, expired sessions, changed permissions, and stale notification links.
- [ ] Under authorization for real data, complete and later retrieve Andre's Buddy
  Check and follow-up through the backend; verify server persistence.

No volunteer worklist may depend on downloading an unrestricted roster. A local
prototype is not evidence of a working mobile API or authentication contract.

## M3: use, refine, then add renewal/reconnection

- [ ] Observe Andre using the app through real follow-up intervals and interruptions.
- [ ] Refine friction from those observations.
- [ ] Add permitted membership assignments for an explicit year, coordinating with
  existing backend membership work.
- [ ] Preserve caller observations separately from source-confirmed membership facts.
- [ ] Observe older, less technically confident members using the workflow without
  coaching before claiming it serves that audience well.

Team administration, assistance routing, Android, standalone use, public
distribution, payments, AI analysis, VoIP, call recording, and automated reporting
remain deferred. Add them when actual needs justify a scoped milestone.
