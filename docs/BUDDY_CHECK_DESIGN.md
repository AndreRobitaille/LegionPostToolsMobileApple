# First Buddy Check design

Design proposal, October 11, 2026. This defines the first synthetic journey for
review. It does not establish backend behavior or complete M1. Read it alongside
the [handoff](BUDDY_CHECK_MOBILE_APP_HANDOFF.md) and [decisions](DECISIONS.md).

## Current review scope

Andre's October 12 instruction supersedes the earlier review requirements below.
Prioritize substantial workflow and visual improvements at standard text size
on iPhone 17 Pro. Large-font checks, smaller-phone matrices and broader
accessibility work come later and must not delay the main design work.
Do not enable VoiceOver or run assistive-technology checks or
accessibility audits unless Andre explicitly requests them. Historical diagnostic
notes remain a record of earlier work, not instructions to repeat it.

## Standard-size workflow implementation

October 12: implement the approved four-screen study in the connected SwiftUI
journey, beginning with recording and confirmation, then Home and member details.
Keep the shared person header and native Home/Follow-ups tabs. Group outcome
choices in one white surface, summarize editable method/time, disclose optional
notes and follow-up time editing, and pin Save in the native bottom safe area.
No outcome is selected automatically. Draft, correction and uncertain-submission
recovery retain their existing identities and persistence rules.

Confirmation displays accepted receipt facts and offers Home, the saved follow-up
and correction. Home prioritizes pending submissions and named drafts, then shows
the next open caller-owned follow-up and recent caller-owned checks. Read all
pages before ranking these summaries; resolve names only for displayed records
and retain no directory/history cache. Loading and failed reads must not claim an
empty list. Hide suggestions management belongs in the suggestion flow.

Member detail places contact and recording actions ahead of the expandable
conversation prompt. Follow-up detail places the member action before phone-alert
settings. Keep eligibility explanations and phone-alert status truthful. Verify
the changed normal-size iPhone 17 Pro journey, accepted corrections, retained
drafts and uncertain saves with synthetic data. No VoiceOver, accessibility or
large-font work is part of this implementation.

The connected implementation now follows this plan. Standard-size simulator
checks cover accepted facts, returning Home from either main tab, correction,
method/note restoration after process restart, pending-save recovery and stale
correction review. Package checks cover complete pagination, latest revisions,
protected drafts and receipt recovery. These use synthetic Post responses; they
are not physical-phone or live-backend acceptance. While entering a note, Done
shares the bottom action bar with Save so a floating keyboard control cannot
cover it. Connected entry and receipt summaries retain the recorded entry zone,
with a zone label when it differs from the device's current zone.

## Scroll-edge contrast follow-up

Andre needs to review a member's details and reach the labelled Contacts actions
on a small phone. The current iOS 27 screenshot shows an action label distorted
under the floating native tabs. Test the native hard bottom scroll-edge treatment
on iOS 26 and later, keeping the existing native behavior on iOS 18–25. This is a
shared page treatment: the final action and copy must still scroll clear of the
tabs, with no fixed empty spacer or extra menu. The navy identity/navigation,
white working surfaces, grey canvas and blue actions keep their existing tokens;
native type and the shared person-card dimensions stay unchanged.

Flow stays person → Contacts details → create/select, with native Back and tabs.
The experiment succeeds when rendered standard-size primary-phone screens retain
clear, reachable actions at the initial position and with lower actions fully
visible. Inspect the visible navigation title and content near the tabs.
The API is documented in [Apple's scroll-edge guidance](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)).

## Historical audit diagnosis

The earlier diagnostic compared the unchanged Contacts screen at initial,
actions-visible and footer-fully-visible scroll positions, retaining SDK findings
alongside screenshots and descriptions. It separated occluded scroll content from
reports on fully visible title/address text. The diagnostic preserved the
navy/white/blue palette, shared person card, caller flow, permissions and Contacts
records. It is outside the current routine review scope.

The full audit changed the visible content position after the pre-audit screenshot.
A separate contrast-only diagnostic therefore used the same full-footer geometry
checks without replacing any all-types case. Its observer also recorded every
finding. Results (local record) distinguish
palette measurements, actual viewport changes and the still-failing SDK checks.

## The job

Help a caller choose someone, make contact, record what happened, and remember
the next step. The ordinary path needs no written note. A returning caller should
see unfinished work and due follow-ups before starting over.

The native design preview uses fictional people and session-only state. It cannot
call, message, schedule a notification, or share a record. Closing the process
resets the preview. Persistent drafts and device reminders remain implementation
work, even where the preview illustrates their intended appearance.

## Visual plan

Revision after Andre's review: the first pass had too much uninterrupted tan and
too much explanatory text. Use a cool neutral canvas, white working surfaces,
navy navigation and contact panels, and visibly separated action areas. Remove
the fixed preview notice. The bottom holds native **Home** and **Follow-ups**
navigation. Andre requested no preview notices or Preview menu; keep the design
harness explanation in repository documentation. The simulated call action is
labelled **Simulate call** and still cannot dial.
This revision changes presentation and navigation, not the simulated workflow's
storage or device-service boundaries.

Second review: use one person-heading component on contact, outcome, reminder,
confirmation and follow-up detail screens. It always uses the native title2 bold
style, 20-point padding, a 12-point internal gap and a 16-point corner radius.
At the same phone width and text setting, the same name has the same card height;
long names and Dynamic Type still expand naturally. Remove the compact variant.

Reserve action blue for interactive surfaces. Primary buttons and selected
outcomes use `#1466CC` with white text. Secondary buttons, selectable people and
follow-up rows use pale blue `#E3EEFF`, a blue border and dark blue labels.
Navy identity panels and white information sections never use these action fills.
Native navigation/date controls retain their recognizable system form with an
appropriate action tint. Keep checkmarks and chevrons so color is not the only cue.

| Token | Use |
| --- | --- |
| Navy `#0A2240` | Navigation, contact panels and static headings |
| Action blue `#1466CC` | Primary buttons and selected choices |
| Pale blue `#E3EEFF` | Secondary actions and selectable rows |
| Canvas `#F0F2F5` | Neutral screen background |
| White `#FFFFFF` | Lists, inputs and working sections |
| Paper `#FBF7EC` | Brief conversation prompt only |
| Gold `#C6A15B` | A short identity rule; never small text on cream |
| Ink `#1B222B` | Body text and secondary information |
| Red `#8C1622` | Destructive actions and errors, always with words |

Use the system font and semantic text styles. Large titles identify destinations;
title and headline styles identify people and actions. Body text explains only
what the caller needs to decide. Secondary text remains readable rather than
faint. Everything aligns to the leading edge except centred button labels.

Use a native navigation stack and scrolling content. Keep touch controls at least
48 points high, with flexible height for wrapped text. Avoid horizontal action
groups and fixed-height cards. No essential action depends on a swipe or icon.
Use native date/time pickers and Back behavior. Respect reduced motion by adding
no custom animations.

At large text sizes, remove redundant introductory copy and put date/time
labels above their controls.
Let content scroll instead of shrinking text or clipping controls.

The memorable element is the person's name in a navy contact panel with a short
gold rule. Post identity anchors Home. No large
emblem, dashboard statistics, badge system, decorative illustration, or repeated
card grid is needed.

Plan review: navy and gold retain The 1919 identity while broad tan surfaces are
removed. The contact panel, white information groups and blue action surfaces have
different visual roles. System typography remains native and scalable. Shorten
instructions where the labelled controls already explain what to do.

## Navigation

```text
Home
  Continue check ----------------------> Outcome
  Check on someone -> People -> Person -> Simulate call -> Outcome
  My follow-ups -> Follow-up -> Change time / Complete / Cancel

Outcome -> Nothing else needed ----------------> Confirmation
        -> Remind me to call again -> Reminder -> Confirmation
Confirmation -> Correct outcome / View follow-up / Done
```

Home and Follow-ups are persistent native tabs with separate navigation stacks.
Switching tabs preserves the current screen and selections.

One check is in progress at a time in the first journey. Starting another check
while one is unfinished must offer to continue it or explicitly discard it.
Back preserves current selections. Leaving the flow does not silently discard
work. A future production draft is saved before handing off to Phone; returning
asks what happened regardless of call length or whether a call was placed.

## Screens and wording

| Screen | Content and primary action |
| --- | --- |
| Home | Buddy Checks, Post identity, a prominent unfinished check when present, **Check on someone**, and **My follow-ups** with readable due information. No officer tools. |
| People | Search by name in a short permitted list. The design fixture contains only fictional people. Empty results explain how to try again. |
| Person | Name and a short conversation prompt. **Simulate call** opens the outcome screen without dialing. A later real build will show a usable method and **Call [name]**. |
| Outcome | **How did it go?**, person's name, **We talked**, **No answer**, **Wrong number**, **I didn't call**. After choosing, show **Nothing else needed** and **Remind me to call again**. Selection has a checkmark and accessible selected state. |
| Reminder | Person, selected outcome, editable date/time, time-zone explanation, and **Save check**. Show a specific validation message for a past time. |
| Confirmation | **Check recorded**, outcome, next action, **Correct outcome**, and **Done**. This displays in-memory state; it does not establish durable storage or server acceptance. |
| My follow-ups | Open follow-ups by due time. Each row names the person, due time and current status. Empty state says there are no follow-ups. |
| Follow-up | Person, due time, context limited to this caller's check, **Change time**, **Mark complete**, and **Cancel follow-up**. Completion and cancellation do not manufacture a new conversation. |

Wrong number explains that the authoritative contact information is unchanged.
I didn't call is not counted as an attempted call. Other outcomes and optional
notes need later design; neither is required for the ordinary first journey.
Do not offer **Ask the Post to help** until a receiving workflow exists.

## State and recovery contract for implementation

| Situation | Required behavior |
| --- | --- |
| Unfinished check | Restore person, workflow position, selected outcome and proposed reminder. Home offers Continue. Discard requires an explicit choice. |
| Save on synthetic device | Say saved on this device only after durable storage succeeds. On failure retain the draft and offer retry. The preview's session-only save does not prove this. |
| Connected save | Distinguish local draft, waiting to send, failed, and server-accepted. Repeated taps/retries reuse the operation identity. |
| Correction | Edit this caller's existing entry; preserve its identity and follow-up unless the caller explicitly changes it. Never create another contact attempt just to correct an outcome. |
| Notification denied | Save the follow-up, keep it visible in-app, and say **No phone alert. Find this in My follow-ups.** Do not repeatedly prompt. |
| Reminder changed | Replace the old scheduled notification after saving the new due time. Handle a schedule failure separately from saving the follow-up. |
| Follow-up completed/cancelled | Keep a truthful status and remove its scheduled reminder. Completing it means the task is done, not necessarily that a conversation happened. |
| Old notification | Look up current follow-up state and authority before displaying detail. Show already completed/cancelled or unavailable when appropriate. |
| Missing person/contact method | Explain what is unavailable and provide a route back. Never fabricate a phone number or silently switch people. |

Proposed time policy: choosing a date and time creates a fixed instant with the
creation time zone retained. Travelling does not move the appointment. Display
the due time in the phone's current zone and make the zone explicit when relevant.
For example, a 9 AM Chicago reminder appears as 10 AM in New York. Resolve calendar
and daylight-saving transitions using platform calendar behavior; test both DST
boundaries before implementing a real reminder. The preview uses a fixed Chicago
fixture for reproducible review and labels that zone.

Notifications must use generic copy such as **You have a Buddy Check follow-up**,
with no person's name or sensitive detail on the lock screen. Ask for permission
only when the first real reminder is requested. The preview never requests it.

The synthetic preview has no shared audience. Before connected work, show who can
see each record and settle retention/revocation. A Buddy Check screen must not
include dues status or another caller's private notes.

## Ideas under exploration: contacts, recording, and suggestions

October 11, 2026. Andre proposed these additions during design review. The flows
below are candidates, not implemented features or settled backend contracts.
The job is to help a caller reach a member, record contact with little effort,
and choose someone who may otherwise be missed.

Tracked work: [Contacts #1](https://github.com/AndreRobitaille/LegionPostToolsMobileApple/issues/1),
[recording and call return #2](https://github.com/AndreRobitaille/LegionPostToolsMobileApple/issues/2),
and [suggestions #3](https://github.com/AndreRobitaille/LegionPostToolsMobileApple/issues/3).

### Add a member to phone Contacts

On a person's screen, offer **Add to Contacts**. Open the native contact editor
with a person contact containing the permitted source fields:

| Phone contact field | Value |
| --- | --- |
| Company | American Legion Post 165, derived from configurable Post identity |
| First and last name | Separate member name fields |
| Phone and email | Available contact numbers and email address |
| Postal address | Street, city, state, ZIP, and country when available |

Apple's [Contacts model](https://developer.apple.com/documentation/contacts/cncontact)
supports these fields, and [Contacts UI](https://developer.apple.com/documentation/contactsui/cncontactviewcontroller)
provides native create/edit screens. Keep this action on the person's screen.
The flow is person → Add to Contacts → review/edit → save or cancel.

Start with an explicit add/update action. Continuous synchronization needs a
separate conflict policy. Remember the association between the source-qualified
member identity and the local contact identifier; repeated use should offer
**Update contact**, not create duplicates. Let the caller choose an existing
contact when needed. A matching name or shared household number is insufficient
to silently merge records. Review changes before replacing an existing company,
phone, or address; preserve unrelated personal fields.

Handle denied or [limited Contacts access](https://developer.apple.com/documentation/contacts/accessing-the-contact-store)
and missing/deleted linked contacts. Export only authorized contact fields, never
Buddy Check notes, support history, or renewal information. This creates a copy
outside the app, potentially in a synced Contacts account; app sign-out or server
revocation cannot be assumed to remove it. Decide export authority before using
real member data. Phone edits do not update authoritative Post records.

### Record contact without reading the phone log

Apple Developer Technical Support confirms there is
[no supported API for reading the user's call log](https://developer.apple.com/forums/thread/808429).
[CXCallObserver](https://developer.apple.com/documentation/callkit/cxcallobserver)
observes active calls; it is not a history query. The installed iOS 27 SDK's
`CXCall` interface exposes call identity and state, not the remote phone number.
Do not design automatic matching against Phone Recents for this app.

For calls started here, save the intended person and draft before opening Phone.
On return, offer **How did it go?** without assuming a call connected. Restore
that draft after a delayed return or process restart. For contact made elsewhere,
offer **Record a check** → person → event date/time and method → outcome → save.
Distinguish when contact happened from when it was entered.

Keep unfinished work in one resumable Home item, with a way to discard it. Do not
present a sequence of historical-call prompts after a long absence. The proposed
single-draft workflow already bounds that backlog.

### Suggest someone to check on

Offer **Suggest someone** from Home or the person-selection menu. Show one person,
a short reason, and **Check on [name]** / **Someone else**. Example reasons:
**No Buddy Check recorded**, **Last recorded check: July 12**, or
**No attendance recorded at the last two meetings**. These describe records;
they do not establish that nobody called or that a person is in difficulty.

LegionPostTools should select from the caller's permitted contacts. It needs
individual Buddy Check events (recipient, caller, event time, method and outcome)
and reliable per-person meeting attendance. Preserve attempts separately from
successful conversations, including corrections and retry deduplication. Track
whether meeting attendance was actually completed; a missing register must not
count as absence. A recent attempt can temporarily defer another suggestion even
when no conversation was recorded.

The suggested initial policy is to prioritize no recorded check or the longest
time since a completed conversation, with sustained meeting absence as another
signal. Respect contact preferences and current eligibility; account for recent
outreach or existing assignments to avoid repeatedly suggesting the same person.
Only share the permitted recent-contact summary needed for coordination, not
another caller's private notes. Ranking thresholds, shared summary visibility,
and attendance completeness remain design decisions.

Distinguish **No suggestions right now** from missing attendance/history and a
failed refresh. Selecting a suggestion does not create a Buddy Check record.
Current backend attendance, outreach schema and APIs were not inspected in this
exploration; recheck them and the membership design before integration.

Before implementation, review the add/update contact flow with duplicate,
conflicting and missing fields; test call-return/restart drafts; and use synthetic
attendance/history examples to check suggestion reasons, exclusions and stale
data. The current UI and simulator harness are unchanged by these notes.

## Review and next implementation boundary

Review the ordinary path, Home with an unfinished check, a correction, a changed
or cancelled follow-up, empty search/list states, and notification denial. Check
standard-size screens on the primary phone. Defer dedicated large-font and
smaller-phone passes. Rendered screenshots show
layout only; they do not prove phone usability or workflow behavior.

The preview source and repeatable build instructions live in
[design/README.md](../design/README.md). Record rendered observations and any
remaining limitations in DESIGN_REVIEW.md (local record).

After design review, create the app project and implement durable local state,
reminder lifecycle, and meaningful workflow tests. Device signing and the real
phone's iOS version are still open. No backend integration is required to review
this design.
