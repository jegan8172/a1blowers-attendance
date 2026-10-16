const policy = require('./attendancePolicy');
const locationPolicy = require('./attendanceLocationPolicy');

function freshFix(body) {
  const latitude = Number(body && body.latitude);
  const longitude = Number(body && body.longitude);
  const accuracy = Number(body && body.accuracy);
  const capturedAt = Date.parse(body && body.capturedAt);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
      !Number.isFinite(accuracy) || accuracy < 0 || accuracy > 50 ||
      !Number.isFinite(capturedAt) || Date.now() - capturedAt > 120000 || capturedAt - Date.now() > 30000) return null;
  return { latitude, longitude, accuracy };
}

async function audit(db, values) {
  await db.query(
    `INSERT INTO hrms_auto_clockout_audit
      (employee_user_id, attendance_id, event_type, latitude, longitude, accuracy_meters, distance_meters, details)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`, values);
}

async function evaluate(db, employeeId, body) {
  const [settingsRows] = await db.query('SELECT * FROM hrms_tracking_settings WHERE id = 1');
  const settings = settingsRows[0];
  if (!settings || Number(settings.auto_clock_out_enabled) !== 1) return { enabled: false };
  const fix = freshFix(body);
  if (!fix) return { enabled: true, unavailable: true, message: 'Fresh precise location is required. Auto clock-out is paused.' };
  const [profiles] = await db.query('SELECT work_mode FROM hrms_employee_profiles WHERE employee_user_id = ?', [employeeId]);
  const mode = String(profiles[0] && profiles[0].work_mode || '');
  if (!['Office', 'Home'].includes(mode)) return { enabled: true, eligible: false };
  const [records] = await db.query(
    `SELECT id, check_in_at, outside_radius_since, auto_clockout_outside_count,
            auto_clockout_last_fix_at, auto_clockout_warning_at, auto_clockout_snoozed_until
     FROM attendance_records WHERE employee_id = ? AND attendance_date = ?
       AND check_in_at IS NOT NULL AND check_out_at IS NULL ORDER BY id DESC LIMIT 1`,
    [employeeId, policy.todayIstDate()]);
  if (!records.length) return { enabled: true, eligible: true, checkedIn: false };
  const record = records[0];
  const [breaks] = await db.query(
    `SELECT id FROM attendance_breaks WHERE attendance_id = ? AND status = 'active' LIMIT 1`, [record.id]);
  if (breaks.length) {
    await db.query(`UPDATE attendance_records SET outside_radius_since = NULL, auto_clockout_outside_count = 0, auto_clockout_warning_at = NULL WHERE id = ?`, [record.id]);
    return { enabled: true, eligible: true, protectedByBreak: true };
  }
  let center;
  let radius = Number(settings.office_radius_meters);
  if (mode === 'Office') center = { latitude: Number(settings.office_latitude), longitude: Number(settings.office_longitude) };
  else {
    const [home] = await db.query(`SELECT latitude, longitude, approval_status FROM hrms_employee_home_locations WHERE employee_user_id = ? LIMIT 1`, [employeeId]);
    if (!home.length || home[0].approval_status !== 'approved') return { enabled: true, eligible: true, unavailable: true, message: 'Approved Home location is unavailable. Auto clock-out is paused.' };
    center = { latitude: Number(home[0].latitude), longitude: Number(home[0].longitude) };
  }
  const distance = locationPolicy.distanceMeters(center, fix);
  const boundary = radius + Number(settings.auto_clock_out_boundary_buffer_meters || 50);
  if (distance <= boundary) {
    await db.query(`UPDATE attendance_records SET outside_radius_since = NULL, auto_clockout_outside_count = 0, auto_clockout_warning_at = NULL, auto_clockout_snoozed_until = NULL WHERE id = ?`, [record.id]);
    return { enabled: true, eligible: true, outside: false };
  }
  const now = Date.now();
  const last = record.auto_clockout_last_fix_at ? new Date(record.auto_clockout_last_fix_at).getTime() : 0;
  const consecutive = last && now - last <= 10 * 60 * 1000 ? Number(record.auto_clockout_outside_count || 0) + 1 : 1;
  const outsideSince = record.outside_radius_since || new Date().toISOString().slice(0, 19).replace('T', ' ');
  await db.query(
    `UPDATE attendance_records SET outside_radius_since = ?, auto_clockout_outside_count = ?, auto_clockout_last_latitude = ?, auto_clockout_last_longitude = ?, auto_clockout_last_accuracy = ?, auto_clockout_last_fix_at = CURRENT_TIMESTAMP WHERE id = ? AND check_out_at IS NULL`,
    [outsideSince, consecutive, fix.latitude, fix.longitude, fix.accuracy, record.id]);
  await audit(db, [employeeId, record.id, 'outside_fix', fix.latitude, fix.longitude, fix.accuracy, distance, JSON.stringify({ mode, consecutive, boundary })]);
  const minutes = (now - new Date(outsideSince).getTime()) / 60000;
  if (consecutive < 2 || minutes < Number(settings.auto_clock_out_confirmation_minutes || 3)) return { enabled: true, eligible: true, outside: true, verifying: true, consecutive, distance };
  if (record.auto_clockout_snoozed_until && new Date(record.auto_clockout_snoozed_until).getTime() > now) return { enabled: true, eligible: true, outside: true, snoozedUntil: record.auto_clockout_snoozed_until, distance };
  if (!record.auto_clockout_warning_at) {
    await db.query(`UPDATE attendance_records SET auto_clockout_warning_at = CURRENT_TIMESTAMP WHERE id = ? AND check_out_at IS NULL`, [record.id]);
    await audit(db, [employeeId, record.id, 'warning_shown', fix.latitude, fix.longitude, fix.accuracy, distance, JSON.stringify({ mode })]);
    return { enabled: true, eligible: true, warning: true, warningSeconds: Number(settings.auto_clock_out_warning_seconds || 60), distance };
  }
  const warningAge = (now - new Date(record.auto_clockout_warning_at).getTime()) / 1000;
  if (warningAge < Number(settings.auto_clock_out_warning_seconds || 60)) return { enabled: true, eligible: true, warning: true, warningSeconds: Math.ceil(Number(settings.auto_clock_out_warning_seconds || 60) - warningAge), distance };
  const reason = mode === 'Home' ? 'Auto clock-out: left approved home radius' : 'Auto clock-out: left office radius';
  const [result] = await db.query(
    `UPDATE attendance_records SET check_out_at = CURRENT_TIMESTAMP, working_minutes = GREATEST(0, TIMESTAMPDIFF(MINUTE, check_in_at, CURRENT_TIMESTAMP)), attendance_status = 'Present', session_status = 'completed', clock_out_reason = ?, tracking_stop_reason = ?, outside_radius_since = NULL, auto_clockout_warning_at = NULL WHERE id = ? AND check_out_at IS NULL`,
    [reason, reason, record.id]);
  if (result.affectedRows) {
    await audit(db, [employeeId, record.id, 'auto_clockout', fix.latitude, fix.longitude, fix.accuracy, distance, JSON.stringify({ mode, reason })]);
    return { enabled: true, eligible: true, autoClockedOut: true, reason };
  }
  return { enabled: true, eligible: true };
}

async function respond(db, employeeId, action) {
  const [rows] = await db.query(`SELECT a.*, p.work_mode FROM attendance_records a JOIN hrms_employee_profiles p ON p.employee_user_id = a.employee_id WHERE a.employee_id = ? AND a.attendance_date = ? AND a.check_in_at IS NOT NULL AND a.check_out_at IS NULL ORDER BY a.id DESC LIMIT 1`, [employeeId, policy.todayIstDate()]);
  if (!rows.length) return { ok: false, message: 'There is no active work session.' };
  const record = rows[0];
  if (action === 'still_working') {
    const minutes = Number((await db.query('SELECT auto_clock_out_snooze_minutes FROM hrms_tracking_settings WHERE id = 1'))[0][0].auto_clock_out_snooze_minutes || 15);
    await db.query(`UPDATE attendance_records SET auto_clockout_warning_at = NULL, auto_clockout_snoozed_until = DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? MINUTE) WHERE id = ? AND check_out_at IS NULL`, [minutes, record.id]);
    await audit(db, [employeeId, record.id, 'warning_cancelled', null, null, null, null, JSON.stringify({ snoozeMinutes: minutes })]);
    return { ok: true, snoozedMinutes: minutes };
  }
  return { ok: false, message: 'Unknown auto clock-out response.' };
}

module.exports = { evaluate, respond };
