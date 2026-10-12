# Member suggestions

October 11, 2026. Synthetic mobile slice for [issue #3](https://github.com/AndreRobitaille/LegionPostToolsMobileApple/issues/3).

## Job and flow

A caller wants to check on someone who might otherwise be missed. Success is one
understandable recommendation leading into the existing contact workflow. A false
claim about missing contact or attendance could cause duplicate, unwanted outreach.

Home / person selection → Suggest someone → shared person card, dated reason →
Check on [first name] → existing person preparation. Selection creates no check
or draft. The existing unfinished-work guard still applies when starting contact.

October 12 correction from Andre: suggestions are browsing, not assignments or
reminders. Someone else skips that person for the current browsing round. After
all choices are seen, offer Start again without cycling automatically. Remove the
seven-day snooze action in both local and connected suggestions. Merely browsing,
skipping or opening a person must not create an assignment, check, draft, reminder
or persistent exclusion. Check on [first name] opens the existing preparation
screen; starting contact or recording remains a separate choice.

Keep recovery for previously saved exclusions under Hidden suggestions / Show
again, without silently undoing prior choices or changing backend records. The
stored snooze format and API remain compatible. Actual follow-up reminders retain
their Snooze reminder action. Assignments are outside this iteration; any future
assignment flow requires the caller's explicit acceptance.

## Initial policy

This is a deterministic design policy to validate, not a settled Post policy.

- Accept only synthetic people in the local ranking implementation. A future
  connected source must filter and rank on Rails and recheck authority before
  outreach; do not adapt this into a full-roster download.
- Exclude unavailable people, contact pauses, assignments to another caller,
  open local follow-ups, the current unfinished check, and active snoozes.
- Defer a recorded attempt for 7 elapsed days; a recorded conversation for 60.
  Not attempted and administrative events are not attempts. Current corrected
  local records, not their prior revisions, contribute to the summary.
- Rank known-empty Buddy Check history first, known attempts without a conversation
  next, then conversations at least 60 days old. Within those groups, sustained
  recorded absence comes first, then longest wait, then stable person UUID.
- Absence can also qualify someone whose contact history is unknown. It requires
  explicit absence in the latest two general-member meeting registers, both
  complete, on distinct dates. Missing, excused, officer-only and incomplete
  records cannot count. Explain incomplete contact history next to that reason.
- Show the record coverage start for empty/no-conversation history, the latest
  successful-contact date, or both meeting dates. Never claim nobody made contact
  or imply urgency or a welfare concern from these records alone.

Unknown history is distinct from a known empty period. A stale batch, failed load,
insufficient evidence, no eligible people, and choices already seen have different
messages. A failed refresh clears the old recommendation. Re-read the source and
re-evaluate eligibility on selection, app return and refresh; refresh does not
clear session skips. No source notes, renewal or support details are needed.

## Storage and presentation

Version 3 adds person/expiry snoozes to the synthetic snapshot. Migrate versions
1 and 2 without losing drafts, checks, follow-ups or Contacts associations. Writes
remain atomic. Do not persist candidate summaries or a connected roster.

Use the existing navy PersonCard, white evidence surface and blue labelled
actions. No preview notice or extra tab. Keep one primary Check on action and
secondary Someone else control. Dynamic Type must wrap without shrinking
names. Review normal and accessibility text on iPhone 17 Pro and smaller layouts.

## Verification boundary

Exercise ordering/ties, eligibility changes, failed/stale sources, unknown versus
empty history, complete/incomplete attendance, recent attempts, corrections,
session exhaustion, selection without writes, and recovery of older exclusions.
Inspect the actual simulator flow and accessibility labels. Physical-device use,
spoken VoiceOver and backend integration remain separate evidence. See the
backend inspection (local record) before connected work.

For the retained live synthetic fixture, verify coordination by signing in as
the second caller and reading existing accepted work. Recent corrected checks
and another caller's open follow-up must defer outreach without exposing their
private histories. Keep the explicit absence reason for the remaining candidate,
the insufficient-history state after skipping it, and server-filtered search for
an assignment-only member. This verification adds no product flow or records;
compare whole-row fingerprints before and after, then sign out. It does not
establish changes to assignments, attendance or permissions during a session.

The remaining response-privacy check reads the same live service through direct
HTTPS using normal synthetic email/code sign-in, consent and PKCE. Validate JSON
before Swift decoding can discard extra fields: exact nested field sets, identity
and ownership against a read-only fixture snapshot, and absence of private note
text/member numbers. Include populated renewal fields and address tiers in the
fixture coverage. Do not store raw responses or credentials. Probe API operations
are GET-only; revoke the two probe tokens and compare Post-record fingerprints.
This supplements the native UI evidence; it does not retest native authentication
or authorize backend edits or new records.
