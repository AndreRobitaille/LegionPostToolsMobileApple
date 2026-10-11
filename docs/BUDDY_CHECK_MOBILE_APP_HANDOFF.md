# Buddy Check and membership outreach: mobile app handoff

Planning handoff from Andre's October 11, 2026 discussion. Intended to be copied
into a new mobile application repository and read before implementation.

This captures user decisions, research, proposed workflows, and engineering
questions. It is not a claim that these features exist. No mobile app, new
repository, backend outreach feature, or deployment was created in this session.

## Start here

Build a useful iPhone app for Andre on his **iPhone 17 Pro**. Begin with a small,
complete Buddy Check workflow and build up from actual use. The app should help
someone choose a person, make contact, record what happened, and remember or hand
off the next step.

Membership renewal and reconnection are the second related workflow. They may
share the app and supporting infrastructure, but have a different purpose and
different permissions.

Keep two future needs in mind without building them now:

- An Android app will be needed eventually.
- Buddy Checks may be useful to people whose posts do not use LegionPostTools.

The first version can integrate with the existing LegionPostTools installation.
That does not establish a permanent requirement that every future user belongs to
a LegionPostTools installation. Conversely, broader usefulness does not justify
building a new identity service, multi-tenant backend, or standalone subscription
product before Andre has a useful app.

## Decisions and their status

| Subject | Status from this discussion |
| --- | --- |
| First user and device | Confirmed: Andre, iPhone 17 Pro. |
| Initial approach | Confirmed: make the app useful for him first, then expand incrementally. |
| Intended wider audience | Phone owners, including older people with low technical confidence. Andre is the first user, not a substitute for later testing with that audience. |
| Buddy Check callers | Confirmed: any Post member contacting other people; participation is not limited to officers or an assigned calling team. |
| Membership callers | Confirmed: volunteers and officers contacting people. |
| Membership purpose | Confirmed: renewing or reconnecting with existing members. New-member recruitment is outside the initial scope. |
| Recipient participation | The initial concept does not require recipients to install the app or have a login. |
| Repository | Andre will create a new repository and bring this handoff into it. No repository name was selected. |
| Android | Future requirement to accommodate; not a parallel first release. |
| Use outside LegionPostTools | Future possibility to preserve; identity, hosting, and data ownership for that use are undecided. |
| Multi-tenancy | Andre anticipates a future multi-tenant LegionPostTools. That is not the current backend or an implementation task for this app's first version. |
| Native implementation | The direction is an iPhone app. SwiftUI/native screens and Hotwire Native remain implementation candidates; no framework was selected. |
| Member self-check-ins | An optional later idea, not a requested first-version feature. |
| Public distribution | Undecided. Installing a development build for Andre and publishing an App Store product are different milestones. |

Earlier discussion initially favored a phone-friendly web app because it reused
Rails. Andre challenged that reasoning: designing for less technically confident
phone users may reveal native features that materially simplify the workflow.
That correction is central. Evaluate the actual experience before optimizing for
code reuse. Do not reopen the project as a website-only implementation by default.

The latest scope also qualifies the earlier suggestion that every user would use
the existing backend and accounts. That is a sensible first integration, not a
settled architecture for people outside LegionPostTools.

## Product purpose and American Legion context

The initial context is Robert E. Burns Post 165 in Two Rivers, Wisconsin. Use it to
understand the work, while keeping Post identity, resources, contact details, and
membership rules configurable. Broader use outside the Legion itself has not been
decided; do not replace concrete Legion requirements with a generic organization
management product.

Buddy Checks support personal connection and offers of assistance. Renewal work
supports membership continuity and reconnection. One conversation may lead to a
second kind of follow-up, but a welfare contact should not silently become a dues
solicitation. Shared software does not mean shared access to every note.

The intended experience is calm, respectful, and practical. The app should make
ordinary acts of helpfulness easier without turning every friendly conversation
into administrative work.

## Research that informs the concept

Research was reviewed on October 11, 2026. Treat official program guidance,
individual Post examples, and our product recommendations as different things.
Recheck time-sensitive rules and report editions when implementing them.

### Buddy Checks

The [national Buddy Check page](https://www.legion.org/advocacy/be-the-one/buddy-check)
encourages outreach around the Legion birthday and Veterans Day, as well as at
other times appropriate to the community. It supplies scripts and practical
resources; it does not prescribe a particular app.

The [Buddy Check toolkit](https://www.legion.org/getmedia/3ecf21c8-2df1-4c8b-a7ad-b68b3497030d/57mem0923-buddy-check-toolkit.pdf),
especially printed pages 1 and 4–6, describes:

- Contact with current members, former members, and other community veterans.
- Teams and divided contact lists, with existing personal connections helping
  determine who should call whom.
- Local assistance resources available to callers and a record of contacts.
- Welfare and assistance as the purpose, rather than recruitment or fundraising.
- Being ready to explain renewal procedures when the recipient wishes to renew.

The [2026 Officer's Guide](https://www.legion.org/getmedia/9886852f-7570-4d04-85e8-2832116fdb63/27ia0226-post-officers-guide.pdf)
reproduces the Buddy Check resolution and associates membership and retention
planning with the first vice commander. These responsibilities inform workflows;
they do not automatically grant application access based on a displayed title.

A [Post 15 example published in October 2026](https://www.legion.org/information-center/news/buddy-check/2026/october/a-multi-pronged-approach-to-buddy-checks)
describes short email surveys followed by calls or letters, including follow-up
with people who did not respond. This suggests an optional future request-a-call
feature. It is a reported local practice, not evidence that surveys or self-check-ins
must be part of the first app.

### Renewal and reconnection

National's [practical renewal guidance](https://www.legion.org/information-center/news/dispatch/2020/march/time-to-work-renewals)
describes personal follow-up and dividing nonrenewed members among callers. The
article is from 2020; its old goals and totals are not current planning inputs.

Current [MyLegion group help](https://mylegion.org/personifyebusiness/Resources/Help/Help-My-Groups)
explains several important distinctions:

- Last-paid year, future paid years, and PUFL status matter when identifying
  renewal needs. A general Active status is not enough.
- A member absent from a renewal list may already be paid, be in a pending batch,
  have transferred, or require the expired-member process.
- Membership records update when a transmittal posts.
- Undeliverable addresses can prevent notices from reaching someone.

Our design implication is to keep conversation outcomes, local processing, and
source-confirmed membership coverage separate. “I already paid” should create
attributed follow-up for verification, rather than immediately changing the
imported paid-through year.

Wisconsin's [membership forms and tools](https://wilegion.org/membership-forms-%26-tools)
index includes renewal, revitalization, impact-report, and year-in-review
resources. The index was reviewed; not every linked resource was examined. Do not
assume that all linked editions, rates, or dates are current.

### Reporting

The published [2025–2026 Consolidated Post Report](https://www.legion.org/getmedia/2cf68a99-4989-4ad0-bdca-8e7ed764699d/71ia1023-consolidated-post-report-2023-24-fillable.pdf)
uses a June–May activity period and asks about Buddy Check participation and the
number of members contacted. The document's printed edition, not the older year
embedded in its URL, identifies the reviewed form.

Retain enough evidence to distinguish attempts, successful contacts, and distinct
people. A reporting total must identify its period and definition. The form's
short wording does not resolve every counting question, including repeat contacts
and nonmember veterans. Do not claim automatic CPR compliance or submission.

## Proposed first useful slice

This is a recommended sequence, not a commitment to deliver the entire concept
in one release. Start with Buddy Checks to exercise the phone interaction; retain
the membership workflow in the design and add it after the core flow is usable.

1. Launch the app and reach a simple home screen.
2. Choose a person from a small list and open their contact screen.
3. Start a call, with a short optional conversation prompt available beforehand.
4. Return to the same person and record an outcome with minimal typing.
5. Set, change, or cancel a follow-up reminder.
6. Close and reopen the app without losing unfinished work.
7. Open a reminder into the relevant follow-up.

Use clearly synthetic contacts for the initial prototype. A simulated call must
be labelled as simulated and must not dial an arbitrary real number. Before a
real-data pilot, connect through authorized application access and settle what
information is stored on the device and shared with the Post.

A synthetic prototype is a design milestone. The first useful connected version
also needs functioning authentication, permission checks, persistence, recovery,
and an agreed way to receive backend changes. Screens alone do not meet that goal.

Defer team administration, broad distribution, Android implementation, standalone
accounts, tenant onboarding, award dashboards, automated reporting, payments,
VoIP, call recording, transcript generation, and AI analysis. Those are not
dependencies of a useful first Buddy Check app.

## Phone workflows

### Setup and returning to the app

For Andre's first installation, determine a working development/signing route and
help him get the app onto his phone. For later members, aim for one assisted setup
at a Post gathering: install, sign in, find the icon, and complete a practice check.

The returning experience should be predictable. Do not make someone navigate an
email sign-in sequence on every use. Reuse the existing passwordless approach
where appropriate, while designing native session and credential handling
explicitly. Device unlock, app unlock, and server authorization are distinct.

Request optional permissions when their purpose is clear: ask about notifications
when the person creates a reminder. Denial should leave a usable app with an
in-app follow-up list and a clear explanation of what will not happen.

### Home

Candidate member actions:

- **Check on someone**
- **My follow-ups**

An authorized membership participant can also see **Membership contacts**.
Do not crowd ordinary members' screens with officer reports, settings, campaign
statistics, or disabled administration controls.

Outstanding work should be easy to recognize. A saved unfinished check should
offer **Continue your check with Robert**, using an illustrative name rather
than requiring the person to remember where they left off.

### Buddy Check

| Step | Proposed experience | Important boundary |
| --- | --- | --- |
| Choose someone | Search a name, revisit a previous contact, or take an available assignment. | A member does not need an assignment to make a personal check. |
| Prepare | Show the person's name, usable contact method, a short prompt, and **Call Robert**. | Do not expose dues status or another caller's private notes merely because the contact is visible. |
| Contact | Hand off to the phone's calling function; later support recording a text or visit if useful. | Starting a call is not evidence that a conversation occurred. |
| Return | Resume the same person's check and ask **How did it go?** | Preserve context even if the app was closed or the call was cancelled. |
| Record | Offer **We talked**, **No answer**, **Wrong number**, and **I didn't call**, with an appropriate other-outcome path. | Separate attempt from connection. Avoid requiring a narrative. |
| Follow up | Offer **Nothing else needed**, **Remind me to call again**, or **Ask the Post to help**. | A handoff needs an identified recipient and visible status; it is not complete merely because the caller tapped a button. |
| Finish | Show what was saved and the next step. Provide a clear way to correct a mistake. | Never display a server-save confirmation for an unsent local draft. |

Example ordinary path: select a person, call, return, tap **We talked**, choose
**Remind me to call again**, pick Thursday morning, and finish. No typing should
be needed for this common case.

“Ask the Post to help” is a proposed later capability until routing and ownership
exist. Do not ship a button that appears to summon help but has no receiving
workflow. A working direct contact option may be a simpler initial alternative.

For coordinated call sessions, eventually show a minimal recent-contact or
claimed-assignment status to reduce accidental duplicate outreach. Do not turn
that into a prohibition on personal contact or a shared feed of sensitive details.

### Membership renewal and reconnection

An authorized officer prepares a worklist for an explicit membership year.
Volunteers receive the limited records needed for their assignments. A caller
can then use the familiar person → contact → outcome → next-step pattern.

Candidate outcomes include:

- No answer; try again.
- Wants help renewing.
- Says they already paid; officer verification needed.
- Wants to reconnect or attend an activity.
- Asked for a later call.
- Declined further renewal contact.
- Contact information needs correction.
- Another situation needs officer review.

Someone may have paid and still be disconnected from the Post. Renewal coverage
and reconnection are separate facts. Do not define every successful interaction
as a payment, or treat every unpaid record as an invitation to keep calling.

The phone records attributed observations. Authorized officers handle processing
and reconciliation. A volunteer response must not change National membership
facts, create a financial receipt without evidence, or silently alter login access.
Payment processing and local dues administration belong to their own backend
workflow, not to a free-text phone note.

### Optional recipient check-ins

Later, a simple **Please call me** link or a short response form could help people
request contact. Andre had not initially considered this. It is optional discovery
work, and recipients should not need the caller's full app to participate.

## Accessibility and interaction direction

Preserve the intent of LegionPostTools' “The 1919” visual system while making the
phone experience feel at home on iOS. The source design uses navy `#0A2240`, cream
`#F4EEDD`, paper `#FBF7EC`, gold `#C6A15B`, ink `#1B222B`, and restrained attention
red `#8C1622`. Color never carries meaning alone. Test actual contrast instead of
assuming every token combination is accessible.

Use system typography for working screens. The web design floors are 16px for
body/interactive text, 14px for secondary text, and 13px for labels. Native text
should use platform text styles and scale with accessibility settings; do not
translate CSS pixels into fixed native sizes or shrink content to fit. Prefer
larger text and scrolling over dense layouts.

Design expectations:

- Large, separated controls with visible words; no essential icon-only actions.
- One main decision at a time, while avoiding an unnecessarily long wizard.
- Familiar Back and Cancel behavior, clear corrections, and recoverable mistakes.
- Brief prompts available when helpful, not a mandatory script to read aloud.
- Optional short notes; use ordinary keyboard dictation where available rather
  than building speech processing into the first release.
- No essential swipe gesture, hover behavior, transient toast, or timed task.
- Clear empty, loading, unsent, failed, and completed states in ordinary language.
- Controls remain understandable with large text, VoiceOver, reduced motion, and
  landscape or a smaller phone layout.
- A visible way to get help without understanding accounts, tokens, or syncing.

Keep the person and the next action close together. The distinctive element of
the working screen is a clear contact card, not a large decorative header. Use
the Post's recognizable identity with restraint. Names, emblems, and affiliation
must remain appropriate if a broader audience is later supported.

## Where native may improve the experience

These are reasons to evaluate native behavior, not claims that all of it is
implemented or exclusive to native apps.

| Need | Potential benefit | What still requires design and testing |
| --- | --- | --- |
| Find the app again | A recognizable installed app and familiar navigation. | Installation, icon placement, first setup, and recovery on a replacement phone. |
| Return to the right task | Durable local state and deliberate resume behavior. | App termination, cancelled calls, multiple unfinished tasks, and reauthentication. |
| Remember a commitment | OS-scheduled local reminders and notifications linked to the relevant follow-up. | Permission denial, Focus settings, cancellations, time-zone changes, and stale reminders. |
| Follow a link | Associated links can open the installed app at the relevant record. | Browser fallback, expired sessions, permissions, and links that no longer identify accessible work. |
| Read comfortably | Platform text styles and accessibility controls. | Every screen must actually respond correctly at large text sizes. |
| Avoid losing work | A limited, deliberately designed local draft/outbox. | Honest save status, secure storage, retry without duplication, and conflicts. |

Apple documents [local notification scheduling](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app),
[associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains),
and [Dynamic Type](https://developer.apple.com/videos/play/wwdc2024/10074/).
These establish available building blocks, not a measured usability advantage for
this particular audience. Android equivalents need their own later validation.

Passkeys, persistent sign-in, large controls, dictation, and some notification
capabilities are also available on the web. An ordinary cellular call uses the
Phone app from either a web page or a native app; see Apple's
[phone-link documentation](https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/PhoneLinks/PhoneLinks.html).
Do not promise automatic return after a call, automatic conversation detection,
call recording, or calling from a Post-owned number. Calls using the person's
normal dialer also require a decision about callers using their personal numbers.

A native shell displaying the existing site will not automatically deliver the
workflow above. The value must be demonstrated in the interactions and recovery.

## Architecture: start small and keep sensible boundaries

### Repository and initial backend relationship

The recommended division is:

| Mobile repository | LegionPostTools repository |
| --- | --- |
| iOS app, phone navigation, reminders, local state, API client, and device tests | Shared people and membership records, current permissions, durable Post outreach records, APIs, and officer administration |

Both Buddy Checks and renewal work can live in one app. One mobile repository can
eventually hold iOS and Android projects. Do not create an Android project or a
shared runtime solely to reserve that possibility.

Keep integration details out of screens. A small boundary between the contact
workflow and its data source can support synthetic fixtures now and the real API
next. It need not become a general plugin framework.

### Implementation choice still to make

- **Native iOS screens, likely SwiftUI:** a candidate for a compact, deliberately
  designed phone workflow. Evaluate authentication, persistence, reminders, and
  API work as part of the choice, not only how quickly a screen can be drawn.
- **Hotwire Native:** a candidate for reusing suitable Rails screens while adding
  native navigation, controls, or fully native screens. Its official
  [bridge components](https://native.hotwired.dev/overview/bridge-components) and
  [native screens](https://native.hotwired.dev/overview/native-screens)
  documentation describes this mix. There are not yet complete outreach web
  screens in LegionPostTools to reuse.

Choose after a short implementation assessment against the first phone journey.
Android awareness does not by itself require Flutter, React Native, or another
cross-platform UI framework. Shared API contracts, semantics, and test scenarios
can be useful even with separate platform interfaces.

### Preserve broader use without building it now

- Keep a contact's app identity distinct from an optional LegionPostTools person
  reference and optional Legion member number. Do not require a member number
  for the concept of making a Buddy Check.
- If external records are linked, identify their source as well as their ID; a
  person ID alone is not globally unique across installations.
- Keep renewal-specific information out of the basic Buddy Check record.
- Centralize installation URL, organization identity, and integration configuration
  instead of scattering Post 165 details throughout the application.
- Keep notification delivery and other phone-specific services behind small,
  comprehensible interfaces.
- Reuse one authoritative server rule for connected Post records. Android support
  should not require duplicating officer authority or renewal calculations.

Future standalone or hosted use still requires decisions about accounts, backups,
sharing, consent, recovery, and data ownership. Do not silently settle those now
by either requiring LegionPostTools everywhere or creating a second membership
database. Personal local data and shared Post records would need explicit
ownership and sharing boundaries if both modes are later offered.

## Existing backend: verified starting points and gaps

Source repository: `/home/andre/Development/LegionPostTools`.
Source snapshot reviewed for this handoff: commit `6d4e96d`, October 11, 2026,
plus the working-tree documents noted below. These are source observations,
not runtime, production, or mobile-integration verification. Reinspect the current
repository before using them as implementation facts.

| Located in the source | What it offers / does not yet establish |
| --- | --- |
| `app/models/person.rb` | Directory contact fallbacks and imported roster data. `directory_visible` excludes expired/deceased status and removed roster records. |
| `app/controllers/api/people_controller.rb` | `GET /api/people` and `GET /api/people/:id` expose the permitted directory. The list supports name search and pagination. |
| `app/controllers/api/membership_controller.rb` | Private summary, renewals, roster, and individual membership endpoints. They currently require full membership access. |
| `app/services/membership_report.rb` | Explicit membership year, renewal categories, and roster freshness. It is not an outreach log or a historical roster snapshot service. |
| `app/models/user.rb` and `docs/ROLES.md` | Current configured position authority and explicit grants. Full membership access includes current qualifying assignments or `manage_people`; a displayed title alone is not the check. |
| `app/controllers/api/base_controller.rb` | Session authentication with CSRF protection, or bearer authentication through `AgentAccessToken`; existing bearer-write provenance and idempotency are agent-oriented. Private directory/membership responses prohibit caching. |
| `docs/MEMBER_SIGN_IN_GUIDE.md` | Existing email link/code and passkey sign-in, plus returning-session behavior. It is not a native-app authentication specification. |
| `docs/ENDEAVOR_GOVERNANCE.md` | A continuing Buddy Check effort may have an Endeavor identity. Its general updates are not a suitable default store for confidential individual contact notes. |

Important gaps to resolve deliberately:

1. A native app is a human interaction channel. Do not assume the existing personal
   agent token creation flow is the desired member login, or mislabel all native
   activity as delegated-agent execution. Choose and document the mobile
   authentication/session design. Never embed a shared privileged token.
2. Existing full-roster endpoints are not volunteer-assignment endpoints. Build
   the appropriate server-filtered access before giving volunteers a worklist;
   downloading everything and hiding rows on the phone is insufficient.
3. Ordinary directory access does not expose all former members. Supporting any
   member as a Buddy Check caller does not automatically grant that caller access
   to expired or removed roster contacts. Decide the narrow visibility rule when
   that workflow is implemented.
4. Reviewed routes and source do not provide the proposed durable contact attempts,
   follow-ups, campaign assignments, assistance handoffs, or mobile synchronization
   contract. Those need coordinated backend work.
5. The current API resolves `Organization.first!`; it is not a multi-tenant backend.
   Do not rely on a tenant-routing contract that does not exist.
6. Existing private responses use `no-store`. Offline member-data storage would be
   a deliberate new capability with a reviewed scope, not permission to cache the
   roster because a mobile framework makes it convenient.

When actually operating a live installation, authenticate and read its current
permission-filtered `GET /api` handbook. Repository-only design and implementation
can use synthetic data without production sign-in.

### Related membership work already in progress

At handoff creation, `docs/MEMBERSHIP_MANAGEMENT_DESIGN.md` was an untracked design
document and `docs/ROADMAP.md` had unrelated edits. They were read or observed and
left unchanged. The membership design proposes drives, volunteer assignments,
local dues processing, officer reports, and source reconciliation. It explicitly
describes proposed, unimplemented behavior.

Consult the current version in the source repository before building overlapping
features. Coordinate shared backend records and permissions. Do not import its
entire financial/reporting scope into the mobile MVP, treat its endpoints as
implemented, or overwrite that work to make a competing design fit.

## Proposed records and behavioral contracts

These concepts describe what needs to remain distinguishable. They are not a
mandatory database schema or a request to create all models immediately.

| Concept | Minimum meaning |
| --- | --- |
| Contact | A person who can be contacted; optional external identity and usable contact methods. |
| Contact attempt | Who acted, whom they contacted, purpose, method, event time, and outcome. |
| Follow-up | The agreed next action, responsible person, due time, and whether it is still open. |
| Assistance request | A limited request passed to a responsible person, with receiving/handling status and restricted detail. |
| Campaign/assignment | Optional organization of a calling effort, including purpose, dates, and assigned caller. |
| Membership observation | Source, applicable year, observed fact, and when it was obtained; distinct from what a caller reports. |
| Local draft/pending submission | Work stored on the device but not yet accepted by the server. |

Keep intent, action, and evidence distinct. Selecting **Call** starts an attempt;
it does not prove contact. A caller can correct an outcome without silently
rewriting someone else's entry. A reminder being displayed is not proof that the
follow-up happened. Tapping **Ask the Post to help** is not evidence that somebody
accepted responsibility.

Repeated Save taps, a lost response, or a reconnect must not create duplicate
contacts or handoffs. A completed or rescheduled follow-up should cancel or update
its device reminder. If another device or officer changes it, opening an old
notification must refresh authority and status before offering actions.

Use explicit membership years and explicit reporting periods. Reminder times need
an understandable local-time display and a defined policy when the phone changes
time zones. Do not assume the device's date always equals the Post's local date.

## Privacy, authority, and recovery

The Post's ordinary phonebook and a person's sensitive support history have
different audiences. Any-member participation is not permission for every member
to read everyone's notes, renewal information, or assistance requests.

Recommended starting behavior:

- Collect short factual outcomes and the minimum follow-up detail needed.
- Make the audience visible before a note or request is shared.
- Keep detailed health, financial hardship, and family circumstances out of general
  campaign notes and member-visible project updates.
- Track contact preferences and contact corrections without automatically replacing
  authoritative roster fields or applying one purpose's preference to every purpose.
- Keep credentials in platform-appropriate secure storage, and keep personal data
  out of logs, analytics, notification previews, fixtures, and screenshots by default.
- Define how sign-out, disabled accounts, revoked assignments, and lost access
  affect stored drafts, cached information, and reminders.
- On reconnect, recheck authority before accepting queued changes. Do not silently
  publish previously drafted work under an account that no longer has access.

An offline device cannot instantly learn about server-side revocation. Decide
what can be retained, for how long, and which operations require a connection;
do not promise immediate removal of already downloaded information. A limited
draft capability may be sufficient before offline directory browsing is justified.

Assistance routing should use Post-reviewed resources and a clearly owned process.
The app is not an emergency monitoring service. A missed reminder or unanswered
call must not automatically be interpreted as a crisis or trigger an unapproved
external escalation.

Use synthetic data for fixtures and demonstrations. The planning request does not
authorize copying production member data, sending real outreach, making paid AI
calls, changing official records, or deploying either application.

## Implementation sequence for the new repository

### 1. Establish the device development path

Determine access to a suitable Mac/Xcode environment, the phone's installed iOS
version, signing setup, and the simplest way to install a build for Andre. These
were not established in this session. Consult current
[Xcode documentation](https://developer.apple.com/xcode/) rather than assuming a
particular version, account entitlement, distribution route, or price.

The source project is on a Linux filesystem. Do not claim iOS build or device
verification merely because source can be edited there. Keep useful design and
synthetic implementation work moving while identifying any genuine device-build
dependency. Production deployment is not needed for an initial synthetic prototype.

### 2. Design and implement one complete synthetic journey

Use this handoff to choose a small native/hybrid approach and record the rationale.
Build the home, person, outcome, and follow-up screens with durable local prototype
state. Exercise a simulated contact and a real local reminder on the device where
possible. Include permission denial, cancellation, and app restart from the start.

Use the existing frontend/visual design guidance during planning and rendered
review. Critique the actual phone screens at ordinary and large accessibility text
sizes. If a web screen is reused or changed, also review its desktop and narrow
presentation.

### 3. Connect a limited real workflow

Inspect current backend code and the related membership design. Define mobile
authentication, minimum response fields, and the proposed contact/follow-up API.
Coordinate backend changes in LegionPostTools under that repository's guidance.
Use server-enforced authority and explicit persistence states. Real member data
and production operations need authorization covering those actions.

The connected milestone should let Andre complete and later retrieve a real
authorized Buddy Check with a follow-up. Clearly label any capability still
simulated or unavailable.

### 4. Learn from use, then expand

Have Andre use the app through interruptions and actual follow-up intervals.
Refine the friction. Add renewal/reconnection work using the same familiar phone
patterns and the shared backend's membership authority. Later, observe less
technically confident members using it without coaching.

Use those observations to decide when team coordination, additional device sizes,
Android, and users outside LegionPostTools are worth the added work. Do not require
those decisions before making the first app useful.

## Verification that matters

The first success criterion is a complete, understandable workflow on Andre's
iPhone 17 Pro. Later usability work must include the older, less technically
confident audience; Andre completing a task is not proof that they can.

| Scenario | Evidence to obtain |
| --- | --- |
| Open and return later | The member can find the app and continue without unnecessary sign-in or navigation. |
| Complete a check | Correct person, outcome, and follow-up persist and remain visible after relaunch or a later request. |
| Cancel a call / no answer | The app does not claim a conversation or lose its place. |
| Interrupt or terminate the app | Unfinished work resumes understandably; reopening does not manufacture a second attempt. |
| Deny notifications | Follow-ups still work in-app; the app does not promise an alert it cannot deliver. |
| Reschedule or complete | Old reminders are cancelled or handled as stale; the current next action is clear. |
| Lose connection during Save | Local and server status remain truthful; retry does not duplicate work. |
| Change or revoke authority | Requests and queued writes are denied appropriately, and inaccessible detail is not exposed by an old link. |
| Receive assistance request | The intended authorized person can find it and accept or otherwise resolve responsibility. |
| Report already paid | The observation is retained for verification without changing imported membership facts. |
| Large text and VoiceOver | Primary controls remain labelled, reachable, correctly ordered, and free of clipping. |
| Correct a mistake | The member can fix their entry and understand the resulting state. |

Use focused tests for meaningful behavior, plus real-device observation of dialing,
returning, notifications, accessibility, and interruptions. Simulator success,
automated test counts, source review, server persistence, and actual usability are
different evidence. Report each accurately.

## Questions to resolve when they become relevant

Immediate setup questions: available Mac/Xcode access, device iOS version, signing,
and how Andre will install the first build. Early engineering choices: native
versus hybrid composition, native authentication, and the smallest persistence
contract needed for the first connected workflow.

Before involving additional members: who receives assistance requests, what each
participant can see, how former-member contacts become available, and how callers
use personal phone numbers. These should not become an up-front questionnaire
that prevents a synthetic prototype.

Later questions include Android timing, standalone accounts and hosting, cross-device
history, recipient check-ins, public distribution, and the relationship to a future
multi-tenant LegionPostTools. Keep them recorded; do not solve them speculatively.

## Reference map for the next repository

This file is intended to stand on its own. The following paths are references in
the original LegionPostTools repository, not files assumed to exist in the new
repository. Read task-relevant current versions when working on integration:

- `AGENTS.md` — working agreement, data and deployment boundaries.
- `docs/ROLES.md` — directory, membership, and current-assignment authority.
- `docs/MEMBERSHIP_MANAGEMENT_DESIGN.md` — related proposed membership work; verify
  its current status before relying on it.
- `docs/MEMBER_SIGN_IN_GUIDE.md` — current member authentication experience.
- `docs/ARCHITECTURE.md` — backend foundations; verify dated claims against code.
- `docs/ENDEAVOR_GOVERNANCE.md` — continuing Post work and meeting connections.
- `docs/TESTING.md` — workflow validation and precise evidence claims.
- `docs/superpowers/specs/2026-07-11-visual-design-system-design.md` — The 1919
  design intent and readability requirements.
- `config/routes.rb`, `app/controllers/api/base_controller.rb`,
  `app/controllers/api/people_controller.rb`,
  `app/controllers/api/membership_controller.rb`, `app/services/membership_report.rb`,
  `app/models/person.rb`, and `app/models/user.rb` — source integration starting points.

The next agent should read this document, inspect the new repository and available
development environment, preserve the iPhone-first scope, and begin with the
smallest complete phone journey. Maintain a short decision record as open choices
are resolved. The handoff is context for Andre's next implementation request, not
independent authorization for releases, outreach, or unrelated backend expansion.
