# LegionPostToolsMobileApple

An iPhone app for American Legion Buddy Checks, followed by membership renewal
and reconnection. The first user is Andre on his iPhone 17 Pro. The initial Post
context is Robert E. Burns Post 165 in Two Rivers, Wisconsin.

The implementation direction is **SwiftUI**, with LegionPostTools providing the
shared records and server-enforced permissions for the eventual connected app.
Start with a complete synthetic journey: choose someone, simulate contact, record
an outcome, set a follow-up, and return later without losing work.

## Current status

Repository initialized for Codex work on October 11, 2026. It contains project
guidance and planning documents; no app target, dependency manifest, build scripts,
CI, or automated tests exist yet. A working iPhone build is the next milestone.

Use a **MacBook with Xcode for primary iOS development**. The Linux checkout can
support documentation, source editing, and backend coordination. See the
[development guide](docs/DEVELOPMENT.md) for the environment facts and setup work
still needed.

## Start here

- [AGENTS.md](AGENTS.md): Codex working agreement and product boundaries.
- [Original handoff](docs/BUDDY_CHECK_MOBILE_APP_HANDOFF.md): preserved product
  context, workflows, privacy requirements, and verification scenarios.
- [Decisions](docs/DECISIONS.md): current direction and unresolved choices;
  supersedes the handoff's open framework choice.
- [Roadmap](docs/ROADMAP.md): small milestones with observable completion criteria.
- [Development](docs/DEVELOPMENT.md): Mac/Linux workflow, validation, and source
  provenance.

Codex uses the root `AGENTS.md` for repository instructions, following the
[official guidance](https://learn.chatgpt.com/docs/agent-configuration/agents-md).
Read task-relevant documents before implementation; the roadmap is a plan, not a
claim of shipped features.

## Scope

Buddy Checks and renewal work have different purposes and audiences. Any-member
Buddy Check participation does not imply access to private support history or
full membership records. Recipients do not need the app or an account.

Use synthetic contacts for development. Android, standalone accounts, multi-tenant
hosting, payments, AI features, and public distribution are later decisions.

The repository retains its existing [GPL-3.0 license](LICENSE).
