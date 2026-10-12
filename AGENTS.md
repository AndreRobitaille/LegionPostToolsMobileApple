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
- This is a public repository. Andre's October 12 publishing instruction excludes
  secrets, personal/member data, private security or operational evidence, raw
  captures, infrastructure details, and signing/trust material. Honor the explicit
  documentation/tool allowlist in `.gitignore`; do not force-add ignored files.
  Full pre-publication working documents are preserved locally under the ignored
  `.private/publication-2026-10-12/` directory. Private integration hooks need the local
  `BUDDY_CHECKS_PRIVATE_INTEGRATION` compilation flag and their ignored source.

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
- Store credentials securely. Keep personal information out of logs, analytics,
  screenshots, and general Post updates. Andre's October 12 instruction permits
  a first name and action in reminder notifications, such as “Call Robert for a
  Buddy Check.” Exclude surnames, contact details, notes and outcomes. Decide retention and
  sign-out/revocation behavior before storing real data offline; existing backend
  `no-store` responses do not authorize a roster cache.
- Recheck server authority on reconnect. A caller's "already paid" observation
  must not change authoritative membership coverage or create financial evidence.

## Design and verification

For UI research, pair the [reusable iOS design notes](docs/IOS_DESIGN_REFERENCES.md)
with the [Buddy Checks application](docs/BUDDY_CHECK_DESIGN_REFERENCES.md).
Keep general source guidance in the reusable library and app-specific decisions
and review scenarios in the paired document. External guidance informs design;
it does not supersede current user instructions or recorded product decisions.

Use the available frontend/visual design skill for user-facing UI work. Record a
brief design before meaningful behavior changes and critique rendered phone
screens. Preserve the handoff's restrained "The 1919" direction using native
text styles, Dynamic Type, labelled large controls, and clear recovery. Review
workflow, visible hierarchy, and the standard-size iPhone 17 Pro experience first.
Andre's latest October 12 direction prioritizes substantial improvements to the
main screens and workflows. Defer large-font checks and smaller-phone matrices
until that experience is settled; they must not dominate or delay this work.
Andre's October 12 instruction excludes VoiceOver, assistive-technology checks,
and accessibility audits from routine work. Do not enable or run them unless
Andre explicitly requests them. Existing tests, historical plans, and external
guidance do not authorize these checks. Select focused UI tests so a broad suite
cannot enable VoiceOver incidentally.
If an excluded test is already running when the user changes the scope, stop it
immediately before continuing other work.

The `BuddyChecks.xcodeproj` app and `BuddyCheckCore` package implement the durable
synthetic workflow. Exact build and test commands are in `docs/DEVELOPMENT.md`.
The separate `design/` harness remains session-only. Do not claim source review
or core tests prove iOS behavior; record simulator and physical-device evidence
separately.

For documentation changes, check links, consistency, and `git diff --check`,
including new files in the review. For behavior changes, use focused meaningful
tests plus the handoff's relevant workflow scenarios. Device checks must cover
interruptions, calling/returning, and notifications when affected. Prioritize
standard-size rendered screens and the main workflow; large-font work comes later.
Keep source inspection, unit tests, simulator runs, device observation, backend
persistence, and usability evidence distinct. Linux work is not an iOS build.
