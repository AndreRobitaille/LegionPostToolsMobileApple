# App implementation

October 11, 2026. Work toward issues #2, #1 and #3. This is the plan for the
durable synthetic app, separate from the disposable `design/` harness.

## First slice: durable recording

Keep the approved native navigation, shared name card and action colors. Add
**Record a check** to Home and **Recent checks** for reviewing/correcting saved
work. The call action stays **Simulate call** for synthetic contacts. No preview
notice or development menu is added.

Flows:

- Choose person → Simulate call → outcome → optional follow-up → saved check.
- Record a check → choose person → method and event time → outcome → saved check.
- Home → Continue unfinished check → its saved workflow position and selections.
- Recent checks → check → correct → update the same record, preserve follow-up.

Use a small Foundation/Observation core package for models, atomic JSON storage
and workflow transactions, with SwiftUI and device adapters in the iOS app. Use
only Apple frameworks. The Xcode project must build from a clean checkout with a
shared scheme, and the core must have focused executable tests.

The local snapshot contains synthetic drafts, checks and follow-ups, not a member
roster. One active draft is allowed. Save the candidate snapshot atomically before
publishing the new UI state. On read failure, keep the existing file and offer
Retry; never silently replace damaged/unknown-version data with an empty store.
On write failure, stay at the current step with the previous saved state.

A draft's UUID becomes the check identity. Repeated save of the same draft returns
the same check. Corrections retain that identity and entry time and preserve a
prior-value revision. Event time, entry time and correction time are distinct.
Follow-up completion/cancellation never manufactures a new contact event.

Dates represent fixed instants. Retain the zone in which each event/reminder was
entered; display dates and editable controls in the device's current zone with a
visible zone label. Reject future event times and past follow-up times. Storage
and device-notification success are separate facts; do not promise an alert until
the device scheduler accepts it.

Only locally saved state is implemented initially. Pending/server-accepted states
and retry transport require a reviewed backend contract, not fake success flags.
Real Phone handoff requires a permitted real contact and physical-device checks;
synthetic contacts cannot invoke it. Contacts and suggestions follow the same
core record identities.

## Verification

Test round-trip storage and restart restoration, single-draft protection,
incomplete saves, event/reminder validation, duplicate saves after restart,
correction identity/history/follow-up preservation, failed writes, corrupted or
unsupported storage, and completed/cancelled follow-ups. Then verify actual
simulator termination/relaunch, ordinary and maximum text, and labelled controls.
Record physical phone and backend verification separately; neither follows from
passing core tests or simulator screenshots.

## Contacts slice (#1)

Job: Andre wants a member's basic details in his personal address book and wants
later updates without duplicate cards or overwritten personal information. This
is an occasional per-person task. Success is an explicitly saved contact, a durable
link, and truthful feedback if either operation fails.

Keep the shared navy name card, native text styles, white information surfaces
and blue actions. Person → Contacts → Create new contact (native editor), or
Choose existing contact (native picker) → review individual Post-field changes →
Save changes. A linked contact offers Review updates and Open contact, where the
native editor remains available. New Contacts entries use configurable company,
separate names, phone, email and full postal address. No check/support/renewal data
is exported.

The link key is a source-qualified external identity when present, otherwise the
app person's UUID. Never infer identity from name, number or household. Store only
the device contact identifier and identifiers of linked multi-value fields, not a
copy of the address book. Each change is shown alongside the current value. Missing
Post fields never clear phone data. Replacing nonempty values requires selection;
adding missing values is selected initially. Unrelated phone/email/address values,
labels and all other fields are retained. Re-fetch before applying; changes to
reviewed fields require a new review. Native Contacts remains authoritative for
its personal copy; nothing writes back to Post records.

Native creation and app link persistence cannot be one transaction. Persist a
creation-pending marker before showing the editor. Cancellation clears it; a saved
contact is linked only after the editor returns a saved identifier. If interrupted
or link storage fails, offer Choose existing contact before another explicit create.
Keep links when access is revoked or a contact is missing; report that it may be
unshared or deleted, and offer access management or choosing a replacement.
Limited access is sufficient. Use Apple's access picker to expand it, and refresh
permission/link availability on return from Settings. Never repeatedly prompt after
denial. Do not enumerate the whole address book.

Synthetic export is available now. Real export remains disabled until the connected
permission contract explicitly permits those fields. A saved personal copy may sync
through the user's Contacts account and remains after app removal, sign-out or
future Post access revocation. The app will not promise to retract that copy.
Automatic continuous synchronization and reverse updates are outside this feature.

Verify pure field planning/preservation, source identity, interrupted creation,
failed linking, schema migration, missing values and contact changes during review.
Use in-memory native contact objects for adapter tests without touching the Mac's
address book. Then exercise create/cancel/update/conflict and permission recovery
on the synthetic simulator, plus ordinary and maximum-text rendering. Physical
account synchronization remains separate evidence.

Platform references: [Contacts authorization](https://developer.apple.com/documentation/contacts/accessing-the-contact-store),
[native contact view](https://developer.apple.com/documentation/contactsui/cncontactviewcontroller),
and [save requests](https://developer.apple.com/documentation/contacts/cnsaverequest).

## Native UI verification

Add a reproducible XCUITest target to investigate the simulator accessibility-tree
navigation gap and exercise the real SwiftUI workflow. Each test uses a new UUID
store in the app's Debug-only UITests directory, so restarting the app restores
that test's draft without replacing the development simulator's saved work. No
real contacts, calls, permission overrides or connected data are needed.

Check native Back/Refresh controls, suggestion selection without new work, skip
exhaustion, Contacts navigation, outcome restoration after termination, correction
and one saved record. Run Apple's accessibility audit on the actual screens;
inspect and fix findings rather than suppressing them. These audits and native
accessibility assertions complement the rendered reviews. The installed iOS 27 VoiceOver test service can also verify focus traversal and
returned speech utterances on the simulator. Human listening and physical-phone
usability remain separate checks. Retain unresolved unfiltered audit findings in
a separate diagnostic suite; do not suppress them to obtain a green result. See
the native review (local record).
