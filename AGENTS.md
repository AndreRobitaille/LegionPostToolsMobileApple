# Agent instructions

## Start here

This repository is the Apple mobile application for American Legion Buddy Checks
and, later, membership renewal/reconnection. Read [README.md](README.md), the
[handoff](docs/BUDDY_CHECK_MOBILE_APP_HANDOFF.md), and
[current decisions](docs/DECISIONS.md) before the first implementation task.
Use [the roadmap](docs/ROADMAP.md) and [development guide](docs/DEVELOPMENT.md) for
the affected milestone. Read deeper references only when relevant.

The handoff is a dated source snapshot. Later user instructions and recorded
decisions supersede its open choices; neither planning documents nor source
observations establish current backend or production behavior.

## Working agreement

- Carry authorized work through proportionate verification. Make routine,
  reversible choices without repeatedly asking permission. Ask only for a
  material unresolved decision, missing information, or required authority.
- Inspect the worktree before editing; preserve unrelated edits and untracked
  files. Do not reset, stash, overwrite, or stage somebody else's work.
- Commit, push, merge, distribution, deployment, external messages, and destructive
  operations need authorization covering that action. Do not infer authorization
  for real outreach, copying production member data, paid AI calls, or changing
  official records from an implementation request.
- Keep work in the requested repository. Backend changes belong in LegionPostTools
  under its own instructions and an authorized scope. Do not overwrite its active
  membership work to fit a mobile design.
- Use `codex/` for new branches. Use subagents only when requested or required by
  applicable instructions. No mandatory delegation or approval ceremony.
- Update relevant decisions, setup commands, and milestone status when they change.
  Report what changed, what was checked, and what remains unverified.

## Product and architecture

- SwiftUI is the implementation direction. Start with Andre's iPhone 17 Pro and
  one complete synthetic Buddy Check journey; prioritize actual phone usability.
  Do not turn this into a website-only app or adopt Hotwire for Rails familiarity.
- Keep the American Legion context. Make installation URL and Post identity
  configurable. Android and use outside LegionPostTools are future concerns;
  do not introduce a shared UI runtime, tenant backend, or second membership database.
- Keep contact workflow, data access, persistence, and device services separated
  by small interfaces where needed. Avoid speculative frameworks and dependencies.
- A contact has its own identity, an optional source-qualified external reference,
  and an optional member number. Keep renewal facts distinct from Buddy Checks.
- Rails remains authoritative for connected Post records and permissions. Never
  download a full roster and hide unauthorized rows on the phone. Reinspect current
  APIs and the membership design before integrating; a mobile human session is not
  automatically an agent-token session. Never embed a shared privileged token.

## Behavior and privacy

- Use synthetic data in fixtures, previews, tests, and demonstrations. Clearly label
  simulated contact; it must not dial an arbitrary number or send real messages.
- Starting a call does not mean people talked. An alert does not mean a follow-up
  happened. Local drafts, pending submissions, and server-accepted records must
  have truthful, distinct states. Retry must not duplicate accepted work.
- Restore interrupted work; support outcome corrections, notification denial,
  reminder cancellation/rescheduling, and stale links. Define time-zone behavior.
- Assistance handoffs need an identified recipient and handling status before
  presenting them as available. No automatic emergency escalation.
- Any-member participation does not grant access to another caller's private notes,
  renewal details, or sensitive support history. Make the sharing audience clear.
- Store credentials securely. Keep personal information out of logs, notification
  previews, analytics, screenshots, and general Post updates. Decide retention and
  sign-out/revocation behavior before storing real data offline; existing backend
  `no-store` responses do not authorize a roster cache.
- Recheck server authority on reconnect. A caller's "already paid" observation
  must not change authoritative membership coverage or create financial evidence.

## Design and verification

Use the available frontend/visual design skill for user-facing UI work. Record a
brief design before meaningful behavior changes and critique rendered phone
screens. Preserve the handoff's restrained "The 1919" direction using native
text styles, Dynamic Type, labelled large controls, and clear recovery. Inspect
ordinary and accessibility text sizes, VoiceOver, and smaller layouts.

There is currently no app or runnable test suite. Do not invent build commands or
claim source review proves iOS behavior. Add exact project/scheme, setup, build,
and test commands to the development guide when the app is created.

For documentation changes, check links, consistency, and `git diff --check`,
including new files in the review. For behavior changes, use focused meaningful
tests plus the handoff's relevant workflow scenarios. Device checks must cover
interruptions, calling/returning, notifications, and accessibility when affected.
Keep source inspection, unit tests, simulator runs, device observation, backend
persistence, and usability evidence distinct. Linux work is not an iOS build.
