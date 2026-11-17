# Shift access

In Administration, choose the working-hours clock beside a staff member. These controls cover Reception, Tailors, Managers and Supervisors. Admin remains exempt so schedules can always be corrected. Only Admin can view or change schedules and view off-shift security alerts.

Restrictions are disabled by default, including for existing accounts. Configure and review a schedule before enabling it. An enabled schedule with no periods blocks all access. To restore unrestricted access, disable that employee's restrictions and save. Role and branch permissions still apply.

## Schedule

- All times use Kuwait time (Asia/Kuwait), evaluated by the server clock. Phone and computer clock changes cannot bypass enforcement.
- Add weekly periods with a day, start time, end time and optional branch. Split shifts and overnight shifts are supported. Start is inclusive; end is exclusive. Use `24:00` for the end of a calendar day. Overlapping periods are rejected.
- A period without a specific branch permits the employee's currently assigned branches. A branch-specific period permits only that branch during the period. A schedule never grants access to an unassigned branch.
- Unlisted days are off. A dated exception replaces the entire calendar date. Choose a full day off, or one or more replacement working periods. A dated exception also stops an incoming overnight period at midnight. For example, Monday 22:00–06:00 stops at Tuesday 00:00 if Tuesday is explicitly a day off.
- Use a dated working exception for approved overtime or a temporary transfer. First assign the destination branch to the employee, then configure the exception. Afterward the weekly schedule resumes.
- Each period has its own boundary. At the end of a period the employee must sign in again, even if another authorized period starts immediately.

Saving a schedule takes effect on the next server request, including existing sessions. Conflicting simultaneous edits are rejected; reopen the editor to load the latest version. Shift changes appear in the audit history.

## Session lock and alerts

The server checks verified sign-ins and every authenticated API/document request. Outside a permitted period, access is rejected and that account's sessions are revoked. Scheduled branch restrictions are checked on the server as well as in branch selection. The app warns before a period ends and locks the open session at its deadline. Passive session checks and normal automatic shift-end locks do not generate misuse alerts. A request racing the deadline may still be blocked and recorded.

An actual off-shift sign-in with a correct password, or a blocked request from a valid session, creates an Admin-only alert. Incorrect passwords do not create a shift alert against the named employee. Attempts with an expired/revoked session still receive the normal sign-in rejection; they cannot be attributed as a verified off-shift account attempt.

Admin receives the alert in the notification inbox and can open Administration → Off-shift alerts for date filters, attempt totals, affected accounts and request details. Managers and Supervisors do not receive these security alerts. Repeated attempts for the same account, reason, source and branch are grouped in 15-minute windows; the attempt count and last occurrence still update. Read state is per Admin.

Optional browser push uses the existing device-notification permission. Its lock-screen message contains no staff identity or invoice/customer details. Push depends on HTTPS, browser permission, device support and connectivity; the server log and Admin inbox are the durable record. Only devices currently bound to an active Admin are eligible for these alerts.

An unsaved invoice draft is retained only in the current browser tab's memory and restored after the same account signs in and selects the same branch. A page reload or explicit logout can discard it. Save or hold invoices before the shift ends. Other accounts and branches cannot restore that draft.

## What the analysis means

The report measures blocked account activity, not attendance or proof of the person physically using credentials. A shared password used during the correct shift can still pass these rules. Individual staff accounts, branch assignments and the audit log remain necessary. Device approval, MFA and clock-in/booking-roster integration are future additions; this version uses schedules entered by Admin.

Back up the database before deployment and keep all migrations. Migration `0007_shift_access.sql` adds schedule and security-alert tables without enabling restrictions or changing existing invoices, payments or staff passwords.
