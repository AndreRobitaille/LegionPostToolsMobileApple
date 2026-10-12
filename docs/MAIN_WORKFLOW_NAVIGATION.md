# Buddy Checks in the main navigation

October 12, 2026. Andre's physical call test exposed that connected Buddy Checks
were hidden behind the person icon. That icon is reserved for account and Post
settings. This supersedes the earlier Post connection entry route.

The caller opens the app to choose someone, resume unfinished work or act on a
follow-up. These are repeated actions and belong on Home and Follow-ups. With a
configured account, restore and revalidate its session at app launch, then show
the connected Home directly. Continue unfinished check stays on that Home after
restart. No member details are shown while authority is unavailable.

Flow: open app → restoring → Home / Follow-ups. An expired session or failed
connection shows recovery on the main screen, with Sign in or Retry connection.
Successful sign-in closes settings and returns to Home. The person icon opens
only profile, Post connection details and sign-out; Done returns to the workflow.
Sign-out still confirms removal of unfinished connected work. It does not delete
server records or silently switch a configured Post to synthetic records.

Unconfigured installations retain the existing synthetic Home and Follow-ups.
Existing synthetic reminder links still open their original record; when a Post
account is active, that temporary local context offers Back to Post. Connected
reminders select the main connected Home and resolve their current record there.
No source selector, preview notice or new preference is added.

Reuse the existing navy identity, white information surfaces, gray canvas, blue
actions, native text styles and shared person card. This is a navigation change,
not a color or typography revision. Main actions remain visible; account settings
contain no member search, draft, history or follow-up navigation.

Verify direct connected launch, settings/Done, Home and Follow-ups, restart into
the retained draft, sign-out and sign-in recovery, and reminder routing using
synthetic fixtures. Inspect ordinary rendered screens and run focused native
workflow checks. Do not reopen the broad cosmetic/accessibility matrix under
Andre's latest direction. Preserve the physical normal snapshot and clean up the
approved Phone test account separately.

## Verification

The signed simulator build, signed physical Debug build and unsigned physical
Release build passed. Strict signature verification passed for the installed
Debug app. The Release executable excludes all five physical Phone fixture
activation/storage/type markers.

Three focused native navigation tests passed in `MainNavigation-02.xcresult`:
direct connected Home and Follow-ups; account-only settings, Done and sign-out
recovery; encrypted draft restoration after process termination directly on Home
with no outcome selected; and unconfigured local Home/settings separation. The
protected fixture uses a UUID-specific real Keychain/journal, without Contacts
permission or writes. Rendered Home (local record),
settings (local record)
and restored draft entry (local record)
show the expected main actions, tabs and separation without observed clipping at
ordinary text size. This pass did not repeat the broader accessibility matrix.

The existing connected suggestion/record/receipt/correction case passed in the
first run. That run also had one new-test selector failure: it expected a different
empty-follow-up sentence. The selector was corrected to the existing copy; the
app was not changed to satisfy it. All three navigation tests then passed. The
first runner remained in reporting after its terminal four-test summary, and was
interrupted separately; it is retained as a failed run, not a successful suite.

One existing real-notification regression passed on a new disposable iPhone 17 Pro
simulator. An OS notification arrived while the app was terminated; tapping it
cold-launched the app into the current connected follow-up. Rescheduling survived
restart and settings-based sign-out removed its alert. These are real simulator
notifications, Keychain and encrypted storage with synthetic Post responses,
not a new live-backend pass. Rendered current follow-up (local record)
and attachment manifests are retained. The owned notification simulator was removed;
the ordinary development simulator and its Contacts were preserved.

The new build is installed on Andre's iPhone. Its existing 933-byte synthetic
snapshot, including Robert's linked contact identifiers, remained byte-identical
through installation. Automatic launch was rejected because the phone was locked.
Andre subsequently opened the app and confirmed Home/Follow-ups directly and
account-only settings through the person icon. The isolated encrypted Phone run
directory is absent. Only the public-UUID reset marker remains in its parent;
device Keychain contents were not inspected externally. No repeated unlock timing
was needed.

Live integration UI tests were adapted to the new account-settings entry and
compiled, but live OAuth/sign-in and backend scenarios were not rerun for this
navigation change. Previous live evidence remains dated separately. No backend
changes, production access, commit or push occurred. See
[commands](DEVELOPMENT.md) and
sanitized results (local record).
