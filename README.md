# GoDigital Attendance (standalone)

This package contains the extracted Admin Attendance and Employee Attendance workspaces. The original attendance screens, API shapes, clock-in/clock-out rules, leave, permissions, extra-hours, approvals, employee directory, and attendance-related tracking are retained. Legacy Task Manager, Client Repository, quotation, invoice, planner, and other business routes are not mounted by the standalone API or exposed by the Flutter router.

The supplied legacy SQL was used only to understand table names and relationships. `database/setup.sql` creates a new database named `godigital_attendance` and contains no copied attendance records.

## Run the database and API

1. Install MySQL 8+ and Node.js 18+.
2. From the project directory run `mysql -u root -p < database/setup.sql`.
3. Copy `backend/.env.example` to `backend/.env` and set the MySQL password and a long JWT secret.
4. Run `cd backend`, `npm install`, then `npm start`.

The API listens on `http://localhost:3000`; its health check is `GET /`.

The seeded development logins are `admin@attendance.local` / `admin123` and `employee@attendance.local` / `employee123`. Change them before production use.

## Run the Flutter frontend

Install Flutter 3.24+ and run `cd frontend`, `flutter pub get`, then `flutter run` (or `flutter run -d chrome`). Android emulators use `10.0.2.2:3000`; web on localhost uses `localhost:3000`. For a physical phone, update `frontend/lib/services/api_config.dart` to the computer's LAN address.

## Verification

`flutter analyze` completed successfully on the extracted frontend. The dependency-free attendance service tests ran with 7 passing cases; the remaining integration/widget test requires the declared Node test dependencies and a live MySQL instance. Run `npm install` and `npm test` after installing the prerequisites above. The included API uses the same authenticated frontend-to-API flow as the original project.

## Folders

- `frontend/` — Flutter UI and attendance design.
- `backend/` — standalone Express API and attendance services.
- `database/setup.sql` — fresh schema and development seed users.
