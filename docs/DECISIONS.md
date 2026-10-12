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

- Preserve the restrained 1919 direction: navy identity/navigation, white working
  surfaces, grey canvas, blue actions, native text styles, and labelled large controls.
- Home and Follow-ups are the main tabs. The person icon opens Account and Post settings.
- Use one shared title2-bold person header with 20-point padding and Dynamic Type.
- On newer supported iOS versions, use the native hard bottom scroll-edge treatment
  to keep lower actions legible near floating tabs. Review smaller layouts and VoiceOver.
- Use the approved visible-hand Icon Composer asset already included in the app.

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
