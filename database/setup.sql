-- GoDigital Attendance standalone database (MySQL 8+).
-- This schema name is intentionally separate from any existing godigital_attendance database.
CREATE DATABASE IF NOT EXISTS godigital_attendance_standalone
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE godigital_attendance_standalone;

CREATE TABLE IF NOT EXISTS employee_users (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  first_name VARCHAR(100) NOT NULL DEFAULT '',
  last_name VARCHAR(100) NOT NULL DEFAULT '',
  full_name VARCHAR(200) NOT NULL,
  email VARCHAR(190) NOT NULL,
  username VARCHAR(100) NOT NULL,
  password VARCHAR(255) NOT NULL,
  role VARCHAR(100) NOT NULL DEFAULT 'Employee',
  user_type ENUM('admin','employee') NOT NULL DEFAULT 'employee',
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  is_main_admin TINYINT(1) NOT NULL DEFAULT 0,
  staff_id VARCHAR(64) NULL,
  initials VARCHAR(12) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_employee_email (email),
  UNIQUE KEY uq_employee_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS role_page_access (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  employee_id INT NOT NULL,
  allowed_pages TEXT NOT NULL,
  KEY idx_role_page_employee (employee_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS user_roles (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  role_name VARCHAR(100) NOT NULL UNIQUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_employee_profiles (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  employee_user_id INT NULL UNIQUE,
  employee_code VARCHAR(64) NOT NULL UNIQUE,
  full_name VARCHAR(160) NOT NULL,
  email VARCHAR(160) NULL,
  department VARCHAR(100) NOT NULL DEFAULT 'Engineering',
  work_mode VARCHAR(32) NOT NULL DEFAULT 'Office',
  employment_status VARCHAR(32) NOT NULL DEFAULT 'Active',
  field_tracking_enabled TINYINT(1) NOT NULL DEFAULT 0,
  monthly_salary DECIMAL(12,2) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS attendance_records (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  employee_id INT NOT NULL, attendance_date DATE NOT NULL,
  check_in_at DATETIME NULL, check_out_at DATETIME NULL,
  attendance_status VARCHAR(32) NOT NULL DEFAULT 'absent',
  session_status VARCHAR(32) NOT NULL DEFAULT 'open',
  check_in_method VARCHAR(32) NULL, is_late TINYINT(1) NOT NULL DEFAULT 0,
  working_minutes INT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_attendance_employee_day (employee_id, attendance_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS attendance_breaks (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, attendance_id BIGINT UNSIGNED NOT NULL,
  started_at DATETIME NOT NULL, ended_at DATETIME NULL, duration_minutes INT UNSIGNED NOT NULL DEFAULT 0,
  status ENUM('active','completed','auto_closed') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_break_attendance (attendance_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS attendance_permission_requests (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, employee_id INT NOT NULL,
  request_type VARCHAR(32) NOT NULL, request_date DATE NOT NULL,
  permission_start_time TIME NULL, permission_end_time TIME NULL, reason VARCHAR(500) NULL,
  status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  reviewed_by INT NULL, reviewed_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_permission_employee (employee_id, request_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_attendance_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, employee_id INT NOT NULL,
  work_date DATE NOT NULL, clock_in_at DATETIME(3) NOT NULL, clock_out_at DATETIME(3) NULL,
  UNIQUE KEY uq_hrms_attendance_employee_day (employee_id, work_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS employee_leaves (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, employee_id INT NOT NULL,
  leave_type VARCHAR(64) NOT NULL, duration_type VARCHAR(32) NOT NULL DEFAULT 'Full Day',
  from_date DATE NOT NULL, to_date DATE NOT NULL, days_count DECIMAL(5,2) NOT NULL DEFAULT 1,
  reason TEXT NULL, status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_leave_employee (employee_id, from_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS employee_extra_hours (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, employee_id INT NOT NULL, work_date DATE NOT NULL,
  regular_out_time TIME NULL, actual_out_time TIME NULL, extra_minutes INT NOT NULL DEFAULT 0,
  reason TEXT NULL, status VARCHAR(16) NOT NULL DEFAULT 'PENDING', created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS employee_permissions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, employee_id INT NOT NULL, permission_date DATE NOT NULL,
  time_required VARCHAR(64) NOT NULL, reason TEXT NOT NULL, status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_admin_notifications (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, approval_request_id BIGINT UNSIGNED NOT NULL,
  title VARCHAR(160) NOT NULL, message VARCHAR(500) NOT NULL, is_read TINYINT(1) NOT NULL DEFAULT 0,
  read_at DATETIME NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_approval_notification (approval_request_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_leave_approval_links (
  leave_id BIGINT UNSIGNED NOT NULL PRIMARY KEY, approval_request_id BIGINT UNSIGNED NOT NULL,
  UNIQUE KEY uniq_leave_approval_request (approval_request_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_attendance_time_settings (
  id TINYINT PRIMARY KEY, shift_start TIME NOT NULL, shift_end TIME NOT NULL,
  late_after TIME NOT NULL, absent_after TIME NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_tracking_settings (
  id TINYINT PRIMARY KEY, office_name VARCHAR(120) NOT NULL, office_address VARCHAR(500) NOT NULL,
  office_latitude DECIMAL(10,7) NOT NULL, office_longitude DECIMAL(10,7) NOT NULL,
  office_radius_meters INT NOT NULL DEFAULT 100, field_ping_interval_minutes INT NOT NULL DEFAULT 15,
  field_waiting_minutes INT NOT NULL DEFAULT 60, stationary_radius_meters INT NOT NULL DEFAULT 50,
  updated_by INT NULL, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_employee_location_status (
  employee_user_id INT PRIMARY KEY, status ENUM('office','home','field') NOT NULL DEFAULT 'office',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_location_pings (
  id INT AUTO_INCREMENT PRIMARY KEY, employee_user_id INT NOT NULL,
  latitude DECIMAL(10,7) NOT NULL, longitude DECIMAL(10,7) NOT NULL, accuracy_meters DECIMAL(6,1) NULL,
  address VARCHAR(255) NULL, recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_employee_recorded (employee_user_id, recorded_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_field_tracking_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  employee_user_id INT NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  stopped_at DATETIME NULL,
  start_latitude DECIMAL(10,7) NULL,
  start_longitude DECIMAL(10,7) NULL,
  stop_latitude DECIMAL(10,7) NULL,
  stop_longitude DECIMAL(10,7) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_field_employee (employee_user_id, is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_field_waiting_reasons (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  field_session_id BIGINT UNSIGNED NOT NULL,
  employee_user_id INT NOT NULL,
  latitude DECIMAL(10,7) NULL,
  longitude DECIMAL(10,7) NULL,
  waiting_started_at DATETIME NOT NULL,
  waiting_detected_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  waiting_minutes INT NOT NULL DEFAULT 0,
  event_key VARCHAR(180) NOT NULL,
  reason TEXT NULL,
  reason_submitted_at DATETIME NULL,
  review_status ENUM('pending','reviewed') NOT NULL DEFAULT 'pending',
  reviewed_by INT NULL,
  reviewed_at DATETIME NULL,
  UNIQUE KEY uq_field_waiting_event (event_key),
  KEY idx_waiting_employee (employee_user_id, review_status),
  KEY idx_waiting_session (field_session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_employee_home_locations (
  employee_user_id INT NOT NULL PRIMARY KEY,
  latitude DECIMAL(10,7) NOT NULL,
  longitude DECIMAL(10,7) NOT NULL,
  address VARCHAR(500) NULL,
  approval_status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  submitted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_by INT NULL,
  reviewed_at DATETIME NULL,
  rejection_reason VARCHAR(500) NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_payroll_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  profile_id INT NOT NULL,
  employee_user_id INT NULL,
  pay_year INT NOT NULL,
  pay_month TINYINT NOT NULL,
  monthly_salary DECIMAL(12,2) NULL,
  working_days INT NOT NULL DEFAULT 0,
  paid_days INT NOT NULL DEFAULT 0,
  lop_days INT NOT NULL DEFAULT 0,
  deductions DECIMAL(12,2) NOT NULL DEFAULT 0,
  net_pay DECIMAL(12,2) NOT NULL DEFAULT 0,
  status ENUM('draft','pending','paid') NOT NULL DEFAULT 'draft',
  paid_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_payroll_profile_period (profile_id, pay_year, pay_month),
  KEY idx_payroll_period (pay_year, pay_month)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_payslip_download_requests (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  payroll_item_id BIGINT UNSIGNED NOT NULL,
  employee_user_id INT NOT NULL,
  approval_request_id BIGINT UNSIGNED NOT NULL,
  status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_payslip_employee_period (payroll_item_id, employee_user_id),
  UNIQUE KEY uq_payslip_approval_request (approval_request_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_paid_leave_policy (
  id TINYINT NOT NULL PRIMARY KEY,
  weekly_limit DECIMAL(5,2) NOT NULL DEFAULT 1,
  monthly_limit DECIMAL(5,2) NOT NULL DEFAULT 2,
  yearly_limit DECIMAL(5,2) NOT NULL DEFAULT 12,
  probation_days INT NOT NULL DEFAULT 0,
  minimum_notice_days INT NOT NULL DEFAULT 0,
  max_consecutive_days DECIMAL(5,2) NOT NULL DEFAULT 0,
  allow_half_day TINYINT(1) NOT NULL DEFAULT 1,
  weekly_required_worked_days INT NOT NULL DEFAULT 0,
  monthly_required_worked_days INT NOT NULL DEFAULT 0,
  yearly_required_worked_days INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS hrms_leave_type_policies (
  leave_type VARCHAR(64) NOT NULL PRIMARY KEY,
  yearly_limit DECIMAL(5,2) NOT NULL DEFAULT 0,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS employee_punches (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, employee_id INT NOT NULL,
  punch_type VARCHAR(16) NOT NULL, punched_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS employee_tracking_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, employee_id INT NOT NULL,
  date DATE NOT NULL, start_time DATETIME NULL, end_time DATETIME NULL, status VARCHAR(32) NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS employee_tracking_activities (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, employee_id INT NOT NULL,
  activity_time DATETIME NOT NULL, activity_text TEXT NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO hrms_attendance_time_settings (id, shift_start, shift_end, late_after, absent_after)
VALUES (1, '09:30:00', '18:30:00', '10:00:00', '12:00:00');
INSERT IGNORE INTO hrms_tracking_settings (id, office_name, office_address, office_latitude, office_longitude)
VALUES (1, 'Main Office', 'Configure this address in Admin > Tracking', 12.8542438, 80.0699862);
-- Fresh standalone login accounts, unrelated to the supplied godigital_db.sql.
INSERT IGNORE INTO employee_users
  (id, first_name, last_name, full_name, email, username, password, role, user_type, is_active, is_main_admin, staff_id, initials)
VALUES
  (1, 'Standalone', 'Admin', 'Standalone Admin', 'admin@standalone.local', 'standalone_admin', 'Admin@2026!', 'Administrator', 'admin', 1, 1, 'ADM001', 'SA'),
  (2, 'Standalone', 'Employee', 'Standalone Employee', 'employee@standalone.local', 'standalone_employee', 'Employee@2026!', 'Employee', 'employee', 1, 0, 'EMP001', 'SE');

INSERT IGNORE INTO hrms_employee_profiles
  (id, employee_user_id, employee_code, full_name, email, department, work_mode, employment_status, field_tracking_enabled, monthly_salary)
VALUES
  (1, 1, 'ADM001', 'Standalone Admin', 'admin@standalone.local', 'Administration', 'Office', 'Active', 0, NULL),
  (2, 2, 'EMP001', 'Standalone Employee', 'employee@standalone.local', 'Operations', 'Office', 'Active', 0, NULL);

INSERT IGNORE INTO role_page_access (employee_id, allowed_pages)
SELECT id, '["attendance"]' FROM employee_users;
