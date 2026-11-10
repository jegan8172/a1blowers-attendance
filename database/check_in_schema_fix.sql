-- Safe one-time repair for an existing Cloud SQL MySQL database.
-- MySQL does not support ADD COLUMN IF NOT EXISTS, so each statement checks
-- INFORMATION_SCHEMA first and runs either the ALTER or a harmless SELECT.

SET @sql = IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'hrms_employee_profiles'
     AND COLUMN_NAME = 'gender') = 0,
  "ALTER TABLE hrms_employee_profiles ADD COLUMN gender ENUM('Male','Female') NOT NULL DEFAULT 'Male'",
  "SELECT 'gender already exists' AS result"
);
PREPARE statement_from_sql FROM @sql;
EXECUTE statement_from_sql;
DEALLOCATE PREPARE statement_from_sql;

-- Hybrid employees write the same live-location status as Field employees.
-- Older databases did not include 'hybrid' in this ENUM.
ALTER TABLE hrms_employee_location_status
  MODIFY COLUMN status ENUM('office','home','field','hybrid') NOT NULL DEFAULT 'office';

SET @sql = IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'attendance_breaks'
     AND COLUMN_NAME = 'exceeded_comment') = 0,
  'ALTER TABLE attendance_breaks ADD COLUMN exceeded_comment TEXT NULL',
  "SELECT 'exceeded_comment already exists' AS result"
);
PREPARE statement_from_sql FROM @sql;
EXECUTE statement_from_sql;
DEALLOCATE PREPARE statement_from_sql;

SET @sql = IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'attendance_breaks'
     AND COLUMN_NAME = 'exceeded_comment_at') = 0,
  'ALTER TABLE attendance_breaks ADD COLUMN exceeded_comment_at DATETIME NULL',
  "SELECT 'exceeded_comment_at already exists' AS result"
);
PREPARE statement_from_sql FROM @sql;
EXECUTE statement_from_sql;
DEALLOCATE PREPARE statement_from_sql;

SET @sql = IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'attendance_permission_requests'
     AND COLUMN_NAME = 'reclocked_at') = 0,
  'ALTER TABLE attendance_permission_requests ADD COLUMN reclocked_at DATETIME NULL',
  "SELECT 'reclocked_at already exists' AS result"
);
PREPARE statement_from_sql FROM @sql;
EXECUTE statement_from_sql;
DEALLOCATE PREPARE statement_from_sql;

SET @sql = IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'attendance_records'
     AND COLUMN_NAME = 'tracking_stop_reason') = 0,
  'ALTER TABLE attendance_records ADD COLUMN tracking_stop_reason TEXT NULL',
  "SELECT 'tracking_stop_reason already exists' AS result"
);
PREPARE statement_from_sql FROM @sql;
EXECUTE statement_from_sql;
DEALLOCATE PREPARE statement_from_sql;
