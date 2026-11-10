# Attendance: employee home screen

The employee dashboard now uses the existing login token to load its name, staff
ID, attendance status, worked hours and monthly present count. Clock buttons wait
for server confirmation and refresh afterward. Loading, expired-login and retry
states replace the earlier sample attendance data.

## Integration

The existing backend mounts this module at `/api/attendance` through one added
line in `backend/server.js`. `integration.js` uses a separate UTC-configured MySQL
pool with the existing backend's database settings and `JWT_SECRET`.

The frontend uses its existing `ApiConfig.baseUrl` and `AuthService` token.
No login changes or separate attendance login are required. The optional
`server.js` in this folder can still run the service separately on loopback port
3101, but it is not needed when running the main backend.

Start/restart the normal backend and rebuild/run the frontend to use the changes.
The live deployment was not restarted, rebuilt or published during this step.

## Database

`schema.sql` creates only `hrms_attendance_sessions`. It was applied successfully
to the configured **local** database on 2026-09-05. Production environments still
need this migration applied to their own database before enabling the module.

The actual local `employee_users.id` column has no unique index. To avoid altering
that existing table, attendance validates the employee in application code rather
than adding a foreign key. Missing, inactive and ambiguous employee IDs are denied.
Attendance enforces one record per employee/local date with its own unique index.
Employee deletion/reuse must therefore be managed separately; attendance does not
cascade-delete records or change employee records.

## API

All endpoints require `Authorization: Bearer <existing login token>`.

- `GET /api/attendance/dashboard?month=2026-09` returns identity, server time,
  attendance status, session worked seconds, available actions and monthly counts.
  Month defaults to the current month.
- `POST /api/attendance/clock-in` starts today's session. No body required.
- `POST /api/attendance/clock-out` closes the open session. No body required.

Responses use `{ success: true, data: ... }`. Identity, time and duration are
server-controlled. Duplicate punches return 409. Transactions serialize punches
using an employee row lock. The frontend refreshes after failed/timeout requests
too, because the server may already have recorded a punch.

## Current rules and scope

One session per local calendar day; default timezone Asia/Kolkata; stored times
are UTC. An overnight session can be closed the next day and is labelled Current
Work Session. Worked time is elapsed time without break deductions. The screen
updates worked time locally and refreshes from the server every minute and when
the app resumes. Clock actions are disabled while saving or when data is stale.

Absent and late counts remain null and display as unavailable until the working
calendar, holidays, shift start and grace period are supplied. There is no assumed
8-hour target. Present counts include all recorded clock-in days.

Only the attendance portion of the employee dashboard is integrated in this step.
Calendar, clock log, admin screens and other modules remain for later steps.

## Verification

From `backend`: `node --test attendance/service.test.js attendance/app.test.js`.
From `Frontend`: `flutter test --no-pub test/attendance_dashboard_test.dart`.

The backend tests use isolated database doubles. Additional real MySQL checks
verified dashboard reads, clock-in, duplicate prevention, worked duration and
clock-out inside one transaction, then rolled back all test records. The local
attendance table was empty afterward. Widget tests verified authenticated data,
clock-in refresh, and loading failure/retry behavior.

This copied project's generated Flutter configuration pointed to a missing T:
drive. Local verification refreshed dependency paths. The installed Flutter SDK
required temporary resolver changes; the original four dependency versions were
restored after testing. For tests on this machine, invoke Flutter using the Windows
short path `C:\Users\JOHNJ~1\flutter_windows_3.24.0-stable\flutter\bin\flutter.bat`
to avoid a native-assets tool failure with spaces in the SDK path.
