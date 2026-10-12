# Decisions

Public product and implementation summary as of October 12, 2026. The original
[handoff](BUDDY_CHECK_MOBILE_APP_HANDOFF.md) is a dated planning snapshot; later
user instructions and these decisions supersede its open choices. Detailed local
handoffs and operational verification records are retained privately.

## Product and implementation direction

- Begin with American Legion Buddy Checks on the first user's iPhone 17 Pro.
  Membership renewal/reconnection follows as a distinct workflow.
- Use SwiftUI and native device integrations. Android, broader distribution,
  standalone installations, and multi-tenancy remain later decisions.
- Keep installation URL and Post identity configurable. Rails remains authoritative
  for connected records and permissions; do not introduce a second roster database.
- A contact has its own identity, optional source-qualified external reference,
  and optional member number. Keep renewal facts separate from Buddy Check history.
- Contact workflow, data access, persistence, and device services use small interfaces.
  Runtime dependencies are Apple frameworks and the local Swift packages.

## Native navigation and visual direction

- Use the approved October 12 workflow design: navy identity and capsule actions,
  mist canvas, broad white working sections, gold conversation help and green
  accepted confirmation. Use native text styles and labelled controls; navigation
  rows and outcome choices do not inherit button-shaped containers.
- Home and Follow-ups are the main tabs. The person icon opens Account and Post settings.
- Home places the approved buddy artwork left of the title and Post identity,
  with Account at right. First-use/status symbols sit beside their headings.
  Member details use a navy profile; forms use compact person context with initials.
- Choose a member combines search and suggestions in one destination. Browsing
  suggestions never creates a draft or authorizes a contact attempt.
- On newer supported iOS versions, use the native hard bottom scroll-edge treatment
  to keep lower actions legible near floating tabs. Prioritize standard-size screens.
- Use the approved visible-hand Icon Composer asset already included in the app.
- The connected recording screen groups outcomes, keeps method/time editable
  behind a compact summary, discloses optional notes and follow-up time editing,
  and holds Save above the native tabs. It never selects an outcome automatically.
- Connected confirmation uses the accepted receipt's outcome, method, event time
  and follow-up. Phone-alert status is separate. Home, follow-up and correction
  are explicit next actions; correction first refreshes the current Post record.
- Home prioritizes pending/rejected submissions and named unfinished work, then
  the earliest open caller-owned follow-up and three recently recorded checks.
  Complete pagination and merge logical-record revisions before ranking. These
  summaries remain in memory; only displayed people are resolved, and failed
  reads never claim there is no work. Hidden suggestions lives in Suggest someone.
- Member and follow-up screens lead with contact/recording actions. Conversation
  help uses a short gold section; Contacts, refresh and phone-alert controls are secondary.

## Design review scope

- Andre's latest October 12 instruction makes standard-size iPhone 17 Pro design
  and substantial main-workflow improvements the priority. Large-font checks,
  smaller-phone matrices and broader accessibility work come later; they must
  not dominate or delay the main design work.
- Do not enable VoiceOver or run assistive-technology checks or accessibility
  audits unless Andre explicitly requests them. Use focused UI test selections
  rather than broad suites that include these checks.
- This supersedes earlier review requirements in the handoff and design plans.
  Retained source notes and historical findings are reference material, not a
  requirement to resume that work.

## Durable synthetic workflow

- Synthetic contacts and simulated calls remain clearly identified. Simulating or
  starting a call never selects an outcome or establishes a conversation.
- Persist one active draft before leaving the app. Retain person, workflow step,
  contact method, event instant/zone, proposed outcome, and follow-up.
- Atomic versioned persistence preserves existing data on decode/version errors and
  publishes state only after successful writes. Repeated saves reuse the record identity.
- Keep event time and entry time distinct. Dates are fixed instants displayed in
  the current device time zone. Corrections preserve identity and prior facts.
- Manual phone, text, and visit recording remain available. Local save status,
  pending submission, and server acceptance must be truthful and distinct.

## Connected workflow

- Use human authorization with PKCE and securely stored device-only credentials.
  A human session is not an agent-token session; never embed a shared privileged token.
- Fetch only server-permitted records and fields. Never download a full roster and
  hide unauthorized rows on the phone.
- Restore protected drafts after interruption or ordinary expiry for the same
  account. Confirmed revocation or account-access removal purges protected work.
- Record submission identity before transmission and recover accepted work through
  its receipt. Explicit retry must not duplicate an accepted operation.
- Preserve rejected corrections for deliberate comparison with current saved facts
  and an explicit new Save. Refresh connected member/follow-up facts before actions.
- Align short contact-eligibility leases with the server response clock. Fetch fresh
  authority before a phone handoff; do not shift recorded event timestamps.
- Remembered sign-in is approved for 180 days after human consent. Renewal cannot
  extend that original deadline, and website-access removal ends app access.
  Existing legacy credentials require one fresh sign-in. The elapsed physical
  renewal experience remains unverified.

## Contacts

- Creation, linking, and updates are explicit caller actions. A personal Contacts
  copy is distinct from an authoritative Post record.
- Review permitted fields and preserve native fields the app does not own. Track
  copied-field identifiers, source identity, and the saved association.
- Invalidate review after permission or native-card changes. Clear unavailable
  Post fields, preserve the association, and retry with current permitted details.
- Retain an interrupted creation guard. Recover a previously saved card through
  the picker rather than silently creating another. Cancelling a later attempt
  does not discard an earlier unresolved creation.
- Present visible save failures and preserve the review for retry. Explain read-only
  account failures and provide existing contact/new-card options.
- Use native Home labels for personal email/address details. Account sync and
  read-only behavior require device/account evidence separate from package tests.

## Suggestions and follow-ups

- Suggestions browse people. Suggest someone and Someone else create no draft,
  assignment, reminder, or Post record. Previously hidden synthetic choices can
  be restored with Show again.
- Explain the dated history reason. With insufficient history, show optional
  server-selected random eligible people without manufacturing a history reason.
- Phone reminders are optional. Denial leaves usable in-app follow-ups.
- Notification copy may include first name and action, such as “Call Robert for a
  Buddy Check.” Exclude surname, contact details, notes, and outcomes.
- Snooze changes only the phone alert. The follow-up keeps its original due time
  and remains open. Dismiss reminder also leaves the follow-up open.
- Cancel/reschedule alerts durably and refresh current server authority when a
  connected reminder opens. Stale links need clear recovery.
- Assistance handoffs remain unavailable until a named recipient, access, handling
  status, and receiving workflow are established. No automatic emergency escalation.

## Public repository checkpoint

On October 12, Andre authorized committing and pushing the mobile implementation
and required secrets and private security/operational material to stay out of the
public repository. Publish app/package source, synthetic tests, reusable build
commands, product documentation, and the production icon. Retain raw diagnostics,
captures, private handoffs, integration infrastructure, and signing material locally.
Private diagnostic adapters require an explicit local compilation flag and are
excluded from the public tree. This does not change the normal Release transport.

## Decisions still needed

- Connected physical reminder delivery, elapsed remembered-session behavior,
  wider phone/OS compatibility, and volunteer usability acceptance.
- Narrow former-member visibility, sharing audiences, contact preferences, and
  use of callers' personal numbers before wider participation.
- Recipient and handling workflow before enabling assistance routing.
- Android timing, standalone ownership/backup/hosting, public distribution,
  and the future multi-tenant backend relationship.

Resolve the decision needed for the current milestone. Implementation or a
planning document does not authorize outreach, official-record changes, releases,
or production data operations.
