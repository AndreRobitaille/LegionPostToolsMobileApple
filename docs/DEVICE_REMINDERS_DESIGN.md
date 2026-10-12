# Device reminders

## October 12 revision: useful reminders, snooze and dismiss

Andre confirmed that a reminder arrived on his locked iPhone and opened Robert's
still-open follow-up. His feedback supersedes the generic notification copy below.
The job is to recognize the next action immediately, defer the alert when busy,
or dismiss it without claiming the contact happened.

Use first name and action: “Call Robert for a Buddy Check” for a phone follow-up;
text/visit use the corresponding method. Connected follow-ups currently have no
planned-method field, so use “Check in with Alex for a Buddy Check” from a fresh
permitted person read. Do not infer a call from an absent method or download
history to construct an alert. No surname, number, address, notes or outcome is
included. This is an explicit exception to the earlier no-name notification rule.

Keep the existing navy/white/grey/blue palette and native text styles. On the open
follow-up, **Record a check** remains the work action. In the Phone reminder
surface, **Snooze reminder** opens a scrollable sheet with 15 minutes, 1 hour,
Tomorrow at 9 AM, and Cancel. After Andre’s follow-up instruction, the sheet
also places **Dismiss reminder** below those blue time choices, with an extra
20 points of separation and a red label/border on a pale red fill. The same
dismiss control remains available on the follow-up’s Phone reminder surface. It removes pending/delivered alerts and opt-in, while the follow-up stays
open. A later snooze can create another alert; no confirmation dialog is needed.

Snooze changes only this phone's alert time, with the same notification identity.
It does not change the follow-up due time, complete it or create a check. Persist
the override before scheduling; preserve it through restart. Changing the actual
follow-up date clears the override. Tomorrow means 9 AM tomorrow in the phone's
current calendar/time zone, then a fixed instant even after travel. Dismiss,
completion, cancellation and account sign-out retain existing cleanup guarantees.
Connected snooze requires fresh record/person authority and saves only its date
in the encrypted journal; no backend mutation or roster cache is added.

Verify migration, repeated snooze/dismiss, failed persistence, stale notification
links, race cleanup and connected authority. Inspect ordinary/maximum text and
VoiceOver; observe actual OS content and queue replacement on a disposable
simulator before updating the approved physical development installation.

October 11, 2026. This implements the remaining synthetic follow-up reminder
lifecycle before live backend/device acceptance. A later
connected reminder design (local record) supplies the account
adapter and fresh server authority. Neither slice may schedule notifications from
cached connected records alone.

Andre has saved a follow-up and wants the phone to remind him at its due time.
Success is an explicitly requested OS notification that returns to the current
follow-up. Delivery or opening must never complete it or record contact.

Flow: saved follow-up → Remind me on this iPhone → system permission when needed →
verified pending request, denied permission, or scheduling failure. Denial retains
the in-app follow-up and offers notification settings. Turning the reminder off,
closing the follow-up or changing its time reconciles pending and delivered alerts.
Persist intent before scheduling; restart repairs an interrupted schedule. Permission
is never requested merely by opening the app. Scheduling is not a delivery guarantee;
Focus and system settings still apply.

Use the existing navy identity card (#0A2240), white information (#FFFFFF), grey
canvas (#F0F2F5), blue actions (#1466CC/#E3EEFF) and gold rule (#C6A15B). Native text
styles and left-aligned, single-column controls match existing follow-up detail.
Place reminder status and actions below the due time. Do not add a preview notice,
global preference screen or a second follow-up form. Keep the saved follow-up and
its optional device alert visibly distinct.

Notifications contain only “Buddy Check follow-up” and “Open Buddy Checks to review
your follow-up.” No member name, phone, outcome, notes or Post details. The payload
contains only a synthetic store namespace, follow-up UUID and due instant. Use the
same request identifier for rescheduling; explicitly encode UTC calendar components
so travel does not move the instant. Save opt-in IDs in snapshot version 4, migrating
versions 1–3 without enabling any existing follow-up.

On tap, validate the payload and namespace, load current local status and navigate
to the saved follow-up. Old dates show the current date, closed items remain closed,
and missing items show unavailable. Never create a draft/check from a notification.
An unreadable store remains protected and unchanged. Refresh on app activation and
every saved follow-up change; serialize reconciliation so a late schedule cannot
resurrect a cancelled alert. Only this store's notification IDs may be removed.

Verification: focused tests for migration, write failure, interruption/restart,
denial, unchanged retry, reschedule, completion/cancellation, stale links, timezone
components, scheduling failure and in-flight cancellation. Native simulator tests
must distinguish injected scheduler evidence from actual OS scheduling/delivery.
Inspect ordinary and maximum text. Physical delivery, Focus, locked-device behavior
and connected authority remain separate acceptance gates.

Platform reference: [Apple local notification scheduling](https://developer.apple.com/documentation/UserNotifications/scheduling-a-notification-locally-from-your-app).

## Cold-launch verification plan

Use a fresh disposable simulator named `Buddy Checks Cold Reminder`. Prepare one
synthetic follow-up through the existing UUID-scoped Debug fixture, then copy that
fixture into this new simulator's normal app storage while the app is stopped.
The native test must launch without a test-store environment, request an actual
notification, terminate the process and tap the delivered OS notification without
launching the app itself. Confirm the current follow-up opens and stays open until
explicit completion, with the original check unchanged. Fixture preparation is
separate from evidence of normal storage, OS delivery and cold notification routing.
Never copy into an existing development simulator's normal store.
