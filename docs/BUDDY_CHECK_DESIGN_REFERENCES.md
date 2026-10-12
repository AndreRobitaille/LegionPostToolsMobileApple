# Buddy Checks design application

This document applies the [reusable iOS design notes](IOS_DESIGN_REFERENCES.md)
to the Buddy Checks app. It pairs source guidance with the app's audience,
approved decisions, and concrete review scenarios. It is not an app audit or a
new product specification. Prepared October 12, 2026.

Read [current decisions](DECISIONS.md) before using these applications. The
[original design](BUDDY_CHECK_DESIGN.md) provides visual detail and dated proposals;
current decisions and later user instructions take precedence. Keep general
guidance in the reusable library and app-specific interpretation here.

## Review scope

Per Andre's latest October 12 instruction, prioritize standard-size iPhone 17 Pro
screens, visible hierarchy and substantial workflow improvements. Large-font
checks, smaller-phone matrices and broader accessibility work come later.
They must not dominate or delay the main design work. Do not enable VoiceOver or run
assistive-technology checks or accessibility audits unless explicitly requested.
This overrides earlier review plans. Use focused UI tests that stay within this
scope; the presence of a test or source recommendation does not authorize it.

## Approved workflow and visual direction

Andre’s later October 12 physical-phone feedback identifies ambiguous actions on
Home and excessive rounded panels throughout the app. The current palette and
shared person-card treatment are open for reconsideration. The proposed direction
uses a single member chooser for search and suggestions, person-focused detail,
a short recording flow, and an accepted receipt with a clear exit. This is a
direction approved for SwiftUI implementation on October 12.

Use `ios-explicit-actions`, `ios-compact-activity`, and
`ios-person-action-proximity`. Give primary actions, secondary actions, navigation,
choices and plain facts distinct treatments. Prefer compact activity rows and
unboxed information where a card adds no meaning. A person monogram can identify
someone without inventing portrait data; a calendar marker can carry the due date.
Keep the app’s Legion identity without repeating a large navy person panel on
every screen. Shared components must preserve those distinctions across connected and local
practice journeys.

His next review accepts the proposed typography and placement but finds the
continuous white page too minimal. Keep that hierarchy while adding visual
substance: the existing two-buddy artwork, broad section colors, a stronger member
profile, and composed recording and confirmation surfaces. Prefer meaningful
whole-section treatments to a rounded panel around each fact. Preserve the
approved icon artwork itself and avoid invented portraits or filler copy.
Andre approved this design for native implementation, including the compact
Home masthead: artwork left, title/Post beside it, Account at right, and the first-use
page symbol beside its heading.

The job remains choosing a person, making contact, recording the result and
following through. Home prioritizes pending submissions, unfinished checks and
open follow-ups. A redesigned presentation must preserve the existing authority,
draft, correction and receipt contracts. Prototype appearance does not establish
SwiftUI behavior or physical-phone acceptance.

## Audience and task

Help a caller choose someone, make contact, record what happened, and remember
the next step. Begin with Andre's iPhone 17 Pro and synthetic examples. The wider
audience includes older people with limited technical confidence; their usability
acceptance requires separate observation.

Retain the American Legion context and restrained 1919 direction. Membership
renewal remains a distinct future workflow. A source example does not expand
permissions, introduce another roster database, or authorize outreach.

## Readable controls

Guidance IDs: `ios-adaptive-type`, `ios-touch-targets`, `ios-state-cues`.

Preserve native text styles, a distinct member profile and compact form context,
and flexible primary control height of at least 48 points. Check hit width separately. These dimensions
are project choices; the source library records Apple's guidance in its own terms.
Use words and selection indicators as well as color.

Review long synthetic names, wrapped actions, and selected outcomes at standard
text on the primary phone. Keep every action readable and reachable. Preserve
native scalable text styles; defer dedicated large-font checks to a later pass.

Basis: [visual decisions](DECISIONS.md#native-navigation-and-visual-direction)
and the [visual plan](BUDDY_CHECK_DESIGN.md#visual-plan).

## Navigation and working surfaces

Guidance IDs: `ios-tab-destinations`, `ios-adaptive-layout`,
`ios-material-hierarchy`, `ios-state-cues`.

Home and Follow-ups remain the primary destinations, with separate navigation
stacks and unfinished-work context. Account and Post settings use the person
icon. Call and save are explicit actions rather than tabs.

Use navy identity/actions, mist canvas, white working sections, gold conversation
help and green accepted confirmation. Inspect the native scroll-edge treatment near floating tabs. Keep lower
actions readable and able to scroll fully clear; article screenshots do not
establish fixed native insets or authorize a visual redesign.

Review empty Follow-ups, tab switching during unfinished work, the onscreen
keyboard, and lower content at standard text size. Inspect the visible
appearance on supported OS versions when affected by a change.

Basis: [visual decisions](DECISIONS.md#native-navigation-and-visual-direction)
and the [navigation design](BUDDY_CHECK_DESIGN.md#navigation).

## Entry and recovery

Guidance IDs: `ios-sheet-exit`, `ios-explicit-actions`, `ios-efficient-entry`.

The ordinary journey should not require a narrative note. Keep simulated contact,
caller-confirmed outcomes, local drafts, pending submissions, and server acceptance
distinct. Restore interrupted work; retries and corrections preserve identity.
These are domain contracts from project decisions, not HIG requirements.

Review cancellation and return from Phone, interruption during an edited form,
an invalid reminder time, a failed save, and correction of an accepted outcome.
Where sheets are used, try back, cancel, and swipe dismissal with unsaved changes.
Labels and confirmations must describe what actually happened.

Basis: [durable workflow](DECISIONS.md#durable-synthetic-workflow) and
[connected workflow](DECISIONS.md#connected-workflow).

## Reminder content and permissions

Guidance IDs: `ios-discreet-notifications`, `ios-contextual-permissions`.

Andre permits first name plus action in reminder notifications. Exclude surnames,
contact details, notes, and outcomes. Apple broadly discourages personal
information in notifications; this allowance is an explicit project choice,
not an Apple recommendation. The older generic-only preview wording in the
original design is superseded by current decisions.

Ask for optional notification access when the caller requests a phone reminder.
Denial leaves the in-app follow-up usable. Snooze changes only the phone alert;
dismissal does not complete the follow-up. Opening an old notification must
respect the current record and authority.

Review delivered notification content and preview settings on a device, along
with denial, rescheduling, cancellation, snooze, and stale links. A screenshot or
package test does not prove delivery or reminder lifecycle behavior.

Basis: [follow-up decisions](DECISIONS.md#suggestions-and-follow-ups) and
[privacy instructions](../AGENTS.md#behavior-and-privacy).

## Contacts and authorized data

Guidance IDs: `ios-contextual-permissions`, `ios-efficient-entry`.

Data-entry convenience never expands server permission or permits a full roster
cache. Contacts export remains an explicit review of permitted fields. A personal
Contacts copy stays separate from an authoritative Post record.

Review denied or changed Contacts access, an unavailable linked contact, read-only
account failures, and interrupted creation. Preserve unrelated native fields and
the recovery path; never infer a safe merge from a matching name alone.

Basis: [connected workflow](DECISIONS.md#connected-workflow) and
[Contacts decisions](DECISIONS.md#contacts).

## Pattern research priorities

Individual Pttrns patterns still await signed-in review. Start with person search
and empty results, readable contact detail, short outcome choices and corrections,
reminder editing, permission denial, and recovery after interruption. Use the
capture fields in the reusable library's `pttrns-selected-patterns` queue item.

Keep Buddy Checks assessments here with the example URL, relevant guidance IDs,
observed behavior, limits, and the reason to adopt, adapt, or reject the pattern.
Promote a lesson to the reusable notes only when it is useful beyond this app
and its source supports that broader scope.

Use synthetic information in reviews. Any permitted raw captures and operational
findings stay in the ignored `.private/` area under this repository's publication
rules. Keep source guidance, proposed checks, and observed results distinct.

## Using the pair

For a reminder change, read the reminder section above, then retrieve the relevant
records from the repository root:

```sh
jq '.guidance[] | select(.tags | index("reminders"))' docs/IOS_DESIGN_REFERENCES.json
```

Every guidance ID in this document resolves to that JSON file. Update this
application document when a project decision changes; update the reusable library
when source guidance changes. Preserve that distinction when adding future notes.
