# Decisions

## 2026-10-11: initial scope

Confirmed in the [imported handoff](BUDDY_CHECK_MOBILE_APP_HANDOFF.md): first user
Andre, iPhone 17 Pro, Buddy Checks first, renewal/reconnection second. Any Post
member may be a Buddy Check caller; access to contacts and private records still
requires appropriate authority. Recipients need neither installation nor login.

The first implementation uses synthetic contacts. Android and broader use outside
LegionPostTools remain future considerations, without new account/hosting systems
or a second membership database now. This is repository initialization; no app or
backend feature is claimed complete.

## 2026-10-11: SwiftUI direction

Andre expressed a preference for SwiftUI while remaining open to a substantive
Hotwire argument. Proceed with **SwiftUI for the first iPhone journey**. This
resolves the framework choice left open in the handoff for initial implementation.

The engineering assessment is that the small home/person/outcome/follow-up flow,
restoration after interruptions, local persistence, and reminders benefit from a
direct native implementation. SwiftUI can compose with UIKit where a platform
integration requires it; Apple documents that interoperability in its
[SwiftUI overview](https://developer.apple.com/swiftui/).

[Hotwire Native](https://native.hotwired.dev/) offers shared web screens across
iOS and Android, existing Rails-screen reuse, and web-delivered screen updates.
It also supports [fully native screens](https://native.hotwired.dev/overview/native-screens),
so native functionality is not exclusive to SwiftUI. Its strongest argument here
would be substantial reuse of suitable outreach screens. The handoff reports no
complete outreach screens to reuse; Android is not the first release. On that
basis, adding a web/native composition is not currently justified.

Tradeoff: SwiftUI means an Apple-specific UI and later separate Android UI work;
native changes require a new app build. Shared API contracts, authorization rules,
and workflow scenarios can still serve both platforms. SwiftUI does not solve
authentication, durable state, accessibility, or synchronization automatically.
Those remain implementation and verification work. Revisit this choice only if
new requirements or observed maintenance costs provide a concrete reason.

## Open decisions, at the point they matter

| When | Decision still needed |
| --- | --- |
| First build | Verified Mac/Xcode environment, device iOS, deployment target, bundle ID, signing and installation route. |
| Synthetic journey | Smallest durable local store, draft restoration rules, reminder time-zone behavior. |
| Connected pilot | Human mobile authentication, API contract, retries/conflicts, minimum data fields, local retention and revocation rules. |
| Wider participation | Narrow former-member visibility, sharing audiences, contact preferences, use of callers' personal numbers. |
| Assistance feature | Named recipient, access, acceptance/resolution workflow, and Post-reviewed resources. |
| Later expansion | Android timing, standalone ownership/backup/hosting, public distribution, and multi-tenant backend relationship. |

Resolve only decisions needed for the active milestone. Record the reason and
evidence when a choice changes; a planning document does not authorize releases
or production data operations.
