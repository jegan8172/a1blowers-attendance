const db = require('../config/db');
const policy = require('../lib/attendancePolicy');
const locationPolicy = require('../lib/attendanceLocationPolicy');
const crypto = require('crypto');
const clockOutReminder = require('../lib/clockOutReminder');

function ok(res, data, message) {
  return res.json({ success: true, message: message || 'OK', data: data });
}

function fail(res, status, message) {
  return res.status(status).json({ success: false, message: message });
}

function officeDistance(lat1, lon1, lat2, lon2) {
  const r = 6371000, rad = (v) => v * Math.PI / 180;
  const dLat = rad(lat2-lat1), dLon = rad(lon2-lon1);
  const a = Math.sin(dLat/2)**2 + Math.cos(rad(lat1))*Math.cos(rad(lat2))*Math.sin(dLon/2)**2;
  return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}

async function activeOfficeMatch(latitude, longitude) {
  let rows;
  try { [rows] = await db.query('SELECT id,name,latitude,longitude,radius_meters FROM hrms_office_locations WHERE is_active=1'); }
  catch (e) { if (e.code === 'ER_NO_SUCH_TABLE') return null; throw e; }
  const matches = rows.map((o) => ({ ...o, distance: officeDistance(latitude, longitude, Number(o.latitude), Number(o.longitude)) }))
    .filter((o) => o.distance <= Number(o.radius_meters) + 30)
    .sort((a,b) => a.distance-b.distance);
  return matches[0] || null;
}

async function officeLocations(req, res) {
  try { const [items] = await db.query('SELECT * FROM hrms_office_locations ORDER BY is_active DESC, name'); return ok(res, { items }); }
  catch (e) { return fail(res, 500, e.message); }
}

function officeValues(body) {
  const name = String(body.name || '').trim(), address = String(body.address || '').trim();
  const latitude = Number(body.latitude), longitude = Number(body.longitude), radiusMeters = Number(body.radiusMeters ?? body.radius_meters);
  if (!name || name.length > 120 || !address || address.length > 500) throw new Error('Office name and address are required.');
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) throw new Error('Valid latitude and longitude are required.');
  if (!Number.isInteger(radiusMeters) || radiusMeters < 1 || radiusMeters > 10000) throw new Error('Radius must be between 1 and 10000 metres.');
  return { name, address, latitude, longitude, radiusMeters };
}

async function createOfficeLocation(req,res) { try { const v=officeValues(req.body||{}); const [r]=await db.query('INSERT INTO hrms_office_locations (name,address,latitude,longitude,radius_meters,created_by,updated_by) VALUES (?,?,?,?,?,?,?)',[v.name,v.address,v.latitude,v.longitude,v.radiusMeters,req.user.id,req.user.id]); return ok(res,{id:r.insertId},'Office location created'); } catch(e){ return fail(res, e.code==='ER_DUP_ENTRY'?409:400,e.message); } }
async function updateOfficeLocation(req,res) { try { const id=Number(req.params.id), v=officeValues(req.body||{}); const [r]=await db.query('UPDATE hrms_office_locations SET name=?,address=?,latitude=?,longitude=?,radius_meters=?,updated_by=? WHERE id=?',[v.name,v.address,v.latitude,v.longitude,v.radiusMeters,req.user.id,id]); if(!r.affectedRows)return fail(res,404,'Office location not found'); return ok(res,{id},'Office location updated'); } catch(e){ return fail(res,400,e.message); } }
async function archiveOfficeLocation(req,res) { try { const id=Number(req.params.id); const [r]=await db.query('UPDATE hrms_office_locations SET is_active=0,updated_by=? WHERE id=?',[req.user.id,id]); if(!r.affectedRows)return fail(res,404,'Office location not found'); return ok(res,{id},'Office location archived'); } catch(e){ return fail(res,400,e.message); } }
async function restoreOfficeLocation(req,res) { try { const id=Number(req.params.id); const [r]=await db.query('UPDATE hrms_office_locations SET is_active=1,updated_by=? WHERE id=?',[req.user.id,id]); if(!r.affectedRows)return fail(res,404,'Office location not found'); return ok(res,{id},'Office location restored'); } catch(e){ return fail(res,400,e.message); } }
async function deleteOfficeLocation(req,res) {
  try {
    const id = Number(req.params.id);
    const [[active]] = await db.query('SELECT COUNT(*) AS count FROM hrms_tracking_mode_audit WHERE office_location_id=? AND created_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)', [id]);
    if (Number(active.count) > 0) return fail(res, 409, 'This office location is used by recent tracking records. Archive it instead of deleting it.');
    const [result] = await db.query('DELETE FROM hrms_office_locations WHERE id=?', [id]);
    if (!result.affectedRows) return fail(res, 404, 'Office location not found');
    return ok(res, { id }, 'Office location deleted');
  } catch (e) { return fail(res, 400, e.message); }
}

function templateValues(body) {
  const values = {
    name: String(body.name || '').trim(),
    fieldWaitingMinutes: Number(body.fieldWaitingMinutes ?? body.field_waiting_minutes),
    stationaryRadiusMeters: Number(body.stationaryRadiusMeters ?? body.stationary_radius_meters),
    fieldPingIntervalMinutes: Number(body.fieldPingIntervalMinutes ?? body.field_ping_interval_minutes),
    popupAlertRepeatSeconds: Number(body.popupAlertRepeatSeconds ?? body.popup_alert_repeat_seconds),
  };
  if (!values.name || values.name.length > 120) throw new Error('Template name is required (maximum 120 characters).');
  if (![values.fieldWaitingMinutes, values.fieldPingIntervalMinutes].every(Number.isInteger) || values.fieldWaitingMinutes < 1 || values.fieldWaitingMinutes > 1440 || values.fieldPingIntervalMinutes < 1 || values.fieldPingIntervalMinutes > 1440) throw new Error('Waiting and GPS intervals must be between 1 and 1440 minutes.');
  if (!Number.isInteger(values.stationaryRadiusMeters) || values.stationaryRadiusMeters < 1 || values.stationaryRadiusMeters > 10000) throw new Error('Stationary radius must be between 1 and 10000 metres.');
  if (!Number.isInteger(values.popupAlertRepeatSeconds) || values.popupAlertRepeatSeconds < 2 || values.popupAlertRepeatSeconds > 3600) throw new Error('Popup repeat must be between 2 and 3600 seconds.');
  return values;
}

async function trackingTemplates(req, res) {
  try {
    const [rows] = await db.query(`SELECT t.*, COUNT(p.id) AS assigned_employee_count FROM hrms_tracking_templates t LEFT JOIN hrms_employee_profiles p ON p.tracking_template_id=t.id AND p.work_mode IN ('Field','Hybrid') GROUP BY t.id ORDER BY t.is_active DESC, t.name`);
    return ok(res, { items: rows });
  } catch (error) { return fail(res, 500, error.message); }
}

async function createTrackingTemplate(req, res) {
  try {
    const v = templateValues(req.body || {});
    const [result] = await db.query(`INSERT INTO hrms_tracking_templates (name,field_waiting_minutes,stationary_radius_meters,field_ping_interval_minutes,popup_alert_repeat_seconds,created_by,updated_by) VALUES (?,?,?,?,?,?,?)`, [v.name,v.fieldWaitingMinutes,v.stationaryRadiusMeters,v.fieldPingIntervalMinutes,v.popupAlertRepeatSeconds,req.user.id,req.user.id]);
    await db.query('INSERT INTO hrms_tracking_template_audit (action_type,admin_id,template_id,new_values) VALUES (?,?,?,?)', ['create',req.user.id,result.insertId,JSON.stringify(v)]);
    return ok(res, { id: result.insertId }, 'Tracking template created');
  } catch (error) { return fail(res, error.code === 'ER_DUP_ENTRY' ? 409 : 400, error.message); }
}

async function updateTrackingTemplate(req, res) {
  try {
    const id = Number(req.params.id); const v = templateValues(req.body || {});
    const [before] = await db.query('SELECT * FROM hrms_tracking_templates WHERE id=?', [id]);
    if (!before.length) return fail(res, 404, 'Tracking template not found');
    await db.query(`UPDATE hrms_tracking_templates SET name=?,field_waiting_minutes=?,stationary_radius_meters=?,field_ping_interval_minutes=?,popup_alert_repeat_seconds=?,updated_by=? WHERE id=?`, [v.name,v.fieldWaitingMinutes,v.stationaryRadiusMeters,v.fieldPingIntervalMinutes,v.popupAlertRepeatSeconds,req.user.id,id]);
    await db.query('INSERT INTO hrms_tracking_template_audit (action_type,admin_id,template_id,old_values,new_values) VALUES (?,?,?,?,?)', ['update',req.user.id,id,JSON.stringify(before[0]),JSON.stringify(v)]);
    return ok(res, { id }, 'Tracking template updated');
  } catch (error) { return fail(res, error.code === 'ER_DUP_ENTRY' ? 409 : 400, error.message); }
}

async function archiveTrackingTemplate(req, res) {
  try {
    const id = Number(req.params.id); const [rows] = await db.query('SELECT * FROM hrms_tracking_templates WHERE id=?', [id]);
    if (!rows.length) return fail(res, 404, 'Tracking template not found');
    await db.query('UPDATE hrms_tracking_templates SET is_active=0,updated_by=? WHERE id=?', [req.user.id,id]);
    await db.query('INSERT INTO hrms_tracking_template_audit (action_type,admin_id,template_id,old_values,new_values) VALUES (?,?,?,?,?)', ['archive',req.user.id,id,JSON.stringify(rows[0]),JSON.stringify({is_active:0})]);
    return ok(res, { id }, 'Tracking template archived');
  } catch (error) { return fail(res, 400, error.message); }
}

async function restoreTrackingTemplate(req, res) {
  try {
    const id = Number(req.params.id);
    const [rows] = await db.query('SELECT * FROM hrms_tracking_templates WHERE id=?', [id]);
    if (!rows.length) return fail(res, 404, 'Tracking template not found');
    await db.query('UPDATE hrms_tracking_templates SET is_active=1, updated_by=? WHERE id=?', [req.user.id, id]);
    await db.query('INSERT INTO hrms_tracking_template_audit (action_type,admin_id,template_id,old_values,new_values) VALUES (?,?,?,?,?)', ['restore', req.user.id, id, JSON.stringify({is_active: rows[0].is_active}), JSON.stringify({is_active: 1})]);
    return ok(res, { id }, 'Tracking template restored');
  } catch (error) { return fail(res, 400, error.message); }
}

async function deleteTrackingTemplate(req, res) {
  try {
    const id = Number(req.params.id);
    const [assigned] = await db.query('SELECT COUNT(*) AS count FROM hrms_employee_profiles WHERE tracking_template_id=?', [id]);
    if (Number(assigned[0].count) > 0) return fail(res, 409, 'This template is used by other employees. Reassign them before deleting it.');
    const [result] = await db.query('DELETE FROM hrms_tracking_templates WHERE id=? AND name<>\'Default\'', [id]);
    if (!result.affectedRows) return fail(res, 400, 'Default or missing template cannot be deleted.');
    await db.query('INSERT INTO hrms_tracking_template_audit (action_type,admin_id,template_id,new_values) VALUES (?,?,?,?)', ['delete', req.user.id, id, JSON.stringify({deleted: true})]);
    return ok(res, { id }, 'Tracking template deleted');
  } catch (error) { return fail(res, 400, error.message); }
}

async function assignTrackingTemplate(req, res) {
  try {
    const employeeId = Number(req.params.employeeId); const templateId = req.body && req.body.templateId == null ? null : Number(req.body.templateId);
    const [employee] = await db.query('SELECT id,employee_user_id,work_mode,tracking_template_id FROM hrms_employee_profiles WHERE id=?', [employeeId]);
    if (!employee.length) return fail(res, 404, 'Employee not found');
    if (['Field','Hybrid'].includes(employee[0].work_mode)) {
      if (!templateId) return fail(res, 400, 'A tracking template is required for Field and Hybrid employees');
      const [t] = await db.query('SELECT id FROM hrms_tracking_templates WHERE id=? AND is_active=1', [templateId]);
      if (!t.length) return fail(res, 400, 'Select an active tracking template');
    }
    await db.query('UPDATE hrms_employee_profiles SET tracking_template_id=? WHERE id=?', [templateId || null, employeeId]);
    await db.query('INSERT INTO hrms_tracking_template_audit (action_type,admin_id,employee_id,old_values,new_values) VALUES (?,?,?,?,?)', ['assign',req.user.id,employeeId,JSON.stringify({trackingTemplateId:employee[0].tracking_template_id}),JSON.stringify({trackingTemplateId:templateId || null})]);
    return ok(res, { employeeId, trackingTemplateId: templateId || null }, 'Tracking template assigned');
  } catch (error) { return fail(res, 400, error.message); }
}

function requireAdmin(req, res, next) {
  const userType = String((req.user && req.user.userType) || '').toLowerCase();
  if (userType !== 'admin') {
    return fail(res, 403, 'Admin access required');
  }
  return next();
}

const LEAVE_TYPES = ['leave', 'risk_leave', 'annual_leave', 'sick_leave', 'personal_leave'];

function isoDate(value) {
  if (!value) return '';
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString().slice(0, 10);
  }
  const match = String(value).match(/(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : '';
}

function formatHours(minutes) {
  const total = Math.max(0, Number(minutes) || 0);
  const hours = Math.floor(total / 60);
  const mins = total % 60;
  if (!total) return '—';
  return hours + 'h ' + String(mins).padStart(2, '0') + 'm';
}

function minutesFromCheckIn(checkInAt) {
  if (!checkInAt) return 0;
  const start = new Date(String(checkInAt).replace(' ', 'T'));
  if (Number.isNaN(start.getTime())) return 0;
  return Math.max(0, Math.round((Date.now() - start.getTime()) / 60000));
}

function weekdayIndex(date) {
  const [year, month, day] = date.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay();
}

async function list(req, res) {
  try {
    const today = policy.todayIstDate();
    const date = String(req.query.date || today).slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return fail(res, 400, 'date must be YYYY-MM-DD');
    }
    const employee = String(req.query.employee || '').trim();
    const statusFilter = String(req.query.status || '').trim();
    const isSunday = weekdayIndex(date) === 0;
    const isFuture = date > today;

    const [profiles] = await db.query(`
      SELECT * FROM hrms_employee_profiles
      WHERE employment_status <> 'Inactive'
      ORDER BY full_name ASC
    `);

    const userIds = profiles.map(function (row) { return row.employee_user_id; }).filter(Boolean);

    const [records] = userIds.length
      ? await db.query(
          `SELECT employee_id, DATE_FORMAT(attendance_date, '%Y-%m-%d') AS attendance_date,
                  check_in_at, check_out_at, is_late, working_minutes, check_in_method,
                  attendance_status, session_status
           FROM attendance_records
           WHERE attendance_date = ?
             AND employee_id IN (?)`,
          [date, userIds]
        )
      : [[]];

    const leavePlaceholders = LEAVE_TYPES.map(function () { return '?'; }).join(', ');
    const [leaves] = userIds.length
      ? await db.query(
          `SELECT employee_id, request_type
           FROM attendance_permission_requests
           WHERE status = 'approved'
             AND request_type IN (` + leavePlaceholders + `)
             AND request_date = ?
             AND employee_id IN (?)`,
          LEAVE_TYPES.concat([date, userIds])
        )
      : [[]];

    const recordMap = new Map();
    records.forEach(function (row) {
      recordMap.set(Number(row.employee_id), row);
    });
    const leaveMap = new Map();
    leaves.forEach(function (row) {
      leaveMap.set(Number(row.employee_id), row.request_type);
    });

    let present = 0;
    let late = 0;
    let stillIn = 0;
    let absent = 0;
    let onLeave = 0;

    let items = profiles.map(function (profile) {
      const record = profile.employee_user_id
        ? recordMap.get(Number(profile.employee_user_id))
        : null;
      const leaveType = profile.employee_user_id
        ? leaveMap.get(Number(profile.employee_user_id))
        : null;
      const checkIn = record && record.check_in_at;
      const checkOut = record && record.check_out_at;
      const isLate = Boolean(record && Number(record.is_late));
      const markedAbsent = Boolean(record && record.attendance_status === 'absent');
      let status = 'Absent';
      let minutes = Number((record && record.working_minutes) || 0);

      if (isFuture) {
        status = 'Upcoming';
      } else if (isSunday) {
        status = 'Weekly off';
      } else if (markedAbsent) {
        status = 'Absent';
        absent += 1;
      } else if (checkIn) {
        if (checkOut) {
          status = isLate ? 'Late · out' : 'Checked out';
          present += 1;
          if (isLate) late += 1;
        } else {
          status = isLate ? 'Late · in' : 'In';
          minutes = minutesFromCheckIn(checkIn);
          present += 1;
          stillIn += 1;
          if (isLate) late += 1;
        }
      } else if (leaveType) {
        status = 'On leave';
        onLeave += 1;
      } else {
        absent += 1;
      }

      return {
        profileId: profile.id,
        employeeUserId: profile.employee_user_id,
        name: String(profile.full_name || '').trim(),
        employeeCode: profile.employee_code,
        department: profile.department,
        checkIn: policy.formatDisplayTime(checkIn),
        checkOut: policy.formatDisplayTime(checkOut),
        method: (record && record.check_in_method) || '—',
        hours: formatHours(minutes),
        workingMinutes: minutes,
        isLate: isLate,
        status: status,
      };
    });

    const names = [...new Set(items.map(function (item) { return item.name; }))];
    if (employee && employee !== 'All Employees') {
      items = items.filter(function (item) { return item.name === employee; });
    }
    if (statusFilter && statusFilter !== 'All Status') {
      items = items.filter(function (item) { return item.status === statusFilter; });
    }

    return ok(res, {
      date: date,
      today: today,
      timezone: policy.TIME_ZONE,
      lateAfter: policy.LATE_AFTER,
      absentAfter: policy.ABSENT_AFTER,
      shiftStart: policy.SHIFT_START,
      requiredHours: policy.REQUIRED_MINUTES / 60,
      employees: names,
      items: items,
      kpis: {
        present: present,
        late: late,
        stillIn: stillIn,
        absent: absent,
        onLeave: onLeave,
        total: profiles.length,
      },
    });
  } catch (error) {
    console.error('GET /hrms/tracking', error);
    return fail(res, 500, error.message);
  }
}

const ACTIVE_WINDOW_MINUTES = 15;
// Browser and some lower-cost Android GPS providers can report 100–1000 m
// accuracy indoors. Keep a generous ceiling so legitimate tracking can start;
// mock locations and impossible travel jumps are still rejected separately.
const MAX_LOCATION_ACCURACY_METERS = 2000;
// Chrome DevTools can teleport a simulated GPS fix between locations. Keep
// the production anti-jump guard strict, while allowing local development
// sensor testing to exercise office/field transitions without being rejected.
const MAX_TRAVEL_SPEED_KMPH = process.env.NODE_ENV === 'production' ? 160 : 1000;

function distanceMeters(aLat, aLng, bLat, bLng) {
  const radians = Math.PI / 180;
  const dLat = (bLat - aLat) * radians;
  const dLng = (bLng - aLng) * radians;
  const value = Math.sin(dLat / 2) ** 2 + Math.cos(aLat * radians) * Math.cos(bLat * radians) * Math.sin(dLng / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
}

async function validateTrackingLocation(employeeUserId, latitude, longitude, accuracy, isMocked) {
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    throw new Error('A valid GPS location is required.');
  }
  if (isMocked === true) throw new Error('Mock locations are not allowed for live tracking.');
  if (Number.isFinite(accuracy) && (accuracy < 0 || accuracy > MAX_LOCATION_ACCURACY_METERS)) {
    throw new Error('Location accuracy is too low. Move outdoors and try again.');
  }

  const [rows] = await db.query(
    `SELECT latitude, longitude, recorded_at FROM hrms_location_pings
     WHERE employee_user_id = ? ORDER BY recorded_at DESC LIMIT 1`,
    [employeeUserId]
  );
  if (!rows.length) return;
  const previous = rows[0];
  const elapsedHours = (Date.now() - new Date(previous.recorded_at).getTime()) / 3600000;
  if (!Number.isFinite(elapsedHours) || elapsedHours <= 0) return;
  const speed = (distanceMeters(Number(previous.latitude), Number(previous.longitude), latitude, longitude) / 1000) / elapsedHours;
  if (speed > MAX_TRAVEL_SPEED_KMPH) {
    throw new Error('Location jump rejected because it would require an impossible travel speed.');
  }
}

async function ensureInvalidTrackingDatesTable() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_invalid_tracking_dates (
    employee_user_id INT NOT NULL,
    route_date DATE NOT NULL,
    invalidated_by INT NOT NULL,
    reason VARCHAR(500) NOT NULL,
    invalidated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (employee_user_id, route_date)
  )`);
}

async function ensureRoadRouteCacheTable() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_road_route_cache (
    employee_user_id INT NOT NULL,
    route_date DATE NOT NULL,
    source_signature CHAR(64) NOT NULL,
    route_points_json LONGTEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (employee_user_id, route_date)
  )`);
}

function rawRoutePoints(pings) {
  return pings.map(function (row) {
    return {
      latitude: Number(row.latitude),
      longitude: Number(row.longitude),
      address: row.address,
      recordedAt: row.recorded_at,
    };
  });
}

function routeSignature(points, engine) {
  return crypto.createHash('sha256').update(points.map(function (point) {
    return [point.latitude, point.longitude, String(point.recordedAt || '')].join(',');
  }).join('|') + '|' + String(engine || 'raw')).digest('hex');
}

function withoutDuplicatePoints(points) {
  return points.filter(function (point, index) {
    if (!index) return true;
    const previous = points[index - 1];
    return previous.latitude !== point.latitude || previous.longitude !== point.longitude;
  });
}

// Google Routes returns a compact encoded polyline. Decode it on the server so
// Flutter only receives ordinary latitude/longitude points.
function decodePolyline(encoded) {
  const points = [];
  let index = 0, latitude = 0, longitude = 0;
  while (index < encoded.length) {
    let result = 0, shift = 0, byte;
    do { byte = encoded.charCodeAt(index++) - 63; result |= (byte & 0x1f) << shift; shift += 5; } while (byte >= 0x20 && index < encoded.length);
    latitude += (result & 1) ? ~(result >> 1) : (result >> 1);
    result = 0; shift = 0;
    do { byte = encoded.charCodeAt(index++) - 63; result |= (byte & 0x1f) << shift; shift += 5; } while (byte >= 0x20 && index < encoded.length);
    longitude += (result & 1) ? ~(result >> 1) : (result >> 1);
    points.push({ latitude: latitude / 1e5, longitude: longitude / 1e5 });
  }
  return points;
}

function routesWaypoint(point) {
  return { location: { latLng: { latitude: Number(point.latitude), longitude: Number(point.longitude) } } };
}

async function routeWithGoogleRoutes(rawPoints, apiKey) {
  // Routes API accepts a limited number of intermediate waypoints. Each group
  // overlaps one point, preserving a continuous whole-day journey.
  const MAX_POINTS_PER_REQUEST = 27; // origin + 25 intermediates + destination
  const chunks = [];
  for (let start = 0; start < rawPoints.length - 1; start += MAX_POINTS_PER_REQUEST - 1) {
    const chunk = rawPoints.slice(start, start + MAX_POINTS_PER_REQUEST);
    if (chunk.length >= 2) chunks.push(chunk);
  }
  // These chunks are independent because adjacent chunks share a boundary
  // point. Running them concurrently removes the N * network-latency delay
  // when an employee has hundreds of GPS points, while Promise.all preserves
  // the original chunk order for the final geometry.
  const geometries = await Promise.all(chunks.map(async (chunk) => {
    const response = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'routes.polyline.encodedPolyline'
      },
      body: JSON.stringify({
        origin: routesWaypoint(chunk[0]),
        destination: routesWaypoint(chunk[chunk.length - 1]),
        intermediates: chunk.slice(1, -1).map(routesWaypoint),
        travelMode: 'DRIVE',
        routingPreference: 'TRAFFIC_UNAWARE',
        polylineQuality: 'HIGH_QUALITY',
        polylineEncoding: 'ENCODED_POLYLINE'
      })
    });
    if (!response.ok) throw new Error('Routes API returned ' + response.status + ': ' + (await response.text()).slice(0, 180));
    const body = await response.json();
    const encoded = body && body.routes && body.routes[0] && body.routes[0].polyline && body.routes[0].polyline.encodedPolyline;
    const points = encoded ? decodePolyline(encoded) : [];
    if (points.length < 2) throw new Error('Routes API returned no usable route polyline');
    return points;
  }));
  const geometry = geometries.flat();
  return withoutDuplicatePoints(geometry);
}

async function snapRouteToRoads(employeeUserId, date, rawPoints) {
  const apiKey = String(process.env.GOOGLE_ROADS_API_KEY || '').trim();
  const routesApiKey = String(process.env.GOOGLE_ROUTES_API_KEY || process.env.GOOGLE_ROADS_API_KEY || '').trim();
  if (rawPoints.length < 2 || (!apiKey && !routesApiKey)) {
    return { points: rawPoints, roadSnapped: false };
  }

  // Prefer Routes API: unlike point snapping, it calculates the road path
  // between GPS readings. Cache it under a new signature so an old snapped
  // route is never returned after this upgrade.
  if (routesApiKey) {
    const routesSignature = routeSignature(rawPoints, 'routes-v1');
    try {
      await ensureRoadRouteCacheTable();
      const [cachedRows] = await db.query(
        `SELECT route_points_json FROM hrms_road_route_cache
         WHERE employee_user_id = ? AND route_date = ? AND source_signature = ?`,
        [employeeUserId, date, routesSignature]
      );
      if (cachedRows.length) {
        const cached = JSON.parse(cachedRows[0].route_points_json);
        if (Array.isArray(cached) && cached.length >= 2) return { points: cached, roadSnapped: true, routeMatched: true };
      }
      const route = await routeWithGoogleRoutes(rawPoints, routesApiKey);
      if (route.length < 2) throw new Error('Routes API did not produce a usable route');
      await db.query(
        `INSERT INTO hrms_road_route_cache (employee_user_id, route_date, source_signature, route_points_json)
         VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE source_signature = VALUES(source_signature), route_points_json = VALUES(route_points_json)`,
        [employeeUserId, date, routesSignature, JSON.stringify(route)]
      );
      return { points: route, roadSnapped: true, routeMatched: true };
    } catch (error) {
      console.error('Routes API failed; trying Roads API fallback:', error.message);
    }
  }

  const signature = routeSignature(rawPoints, 'roads-v1');
  try {
    await ensureRoadRouteCacheTable();
    const [cachedRows] = await db.query(
      `SELECT route_points_json FROM hrms_road_route_cache
       WHERE employee_user_id = ? AND route_date = ? AND source_signature = ?`,
      [employeeUserId, date, signature]
    );
    if (cachedRows.length) {
      const cached = JSON.parse(cachedRows[0].route_points_json);
      if (Array.isArray(cached) && cached.length >= 2) {
        return { points: cached, roadSnapped: true };
      }
    }

    // Roads API accepts at most 100 GPS points per request. Adjacent chunks
    // share their boundary point so a long journey remains continuous.
    const snapped = [];
    for (let start = 0; start < rawPoints.length; start += 99) {
      const chunk = rawPoints.slice(start, start + 100);
      if (chunk.length < 2) break;
      const path = chunk.map(function (point) {
        return point.latitude + ',' + point.longitude;
      }).join('|');
      const url = 'https://roads.googleapis.com/v1/snapToRoads?interpolate=true&path=' +
        encodeURIComponent(path) + '&key=' + encodeURIComponent(apiKey);
      const response = await fetch(url);
      if (!response.ok) throw new Error('Roads API returned ' + response.status);
      const body = await response.json();
      const points = Array.isArray(body.snappedPoints) ? body.snappedPoints : [];
      if (!points.length) throw new Error('Roads API returned no snapped points');
      points.forEach(function (point) {
        if (point.location) {
          snapped.push({
            latitude: Number(point.location.latitude),
            longitude: Number(point.location.longitude),
          });
        }
      });
    }

    const route = withoutDuplicatePoints(snapped);
    if (route.length < 2) throw new Error('Roads API did not produce a usable route');
    await db.query(
      `INSERT INTO hrms_road_route_cache
       (employee_user_id, route_date, source_signature, route_points_json)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE source_signature = VALUES(source_signature),
         route_points_json = VALUES(route_points_json)`,
      [employeeUserId, date, signature, JSON.stringify(route)]
    );
    return { points: route, roadSnapped: true };
  } catch (error) {
    console.error('Road snapping failed; using raw GPS route:', error.message);
    return { points: rawPoints, roadSnapped: false };
  }
}
const GEOCODE_CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24h; rounded coords repeat a lot
const geocodeCache = new Map();

function roundCoord(value) {
  return Math.round(Number(value) * 10000) / 10000; // ~11m precision
}

async function reverseGeocode(latitude, longitude) {
  const key = roundCoord(latitude) + ',' + roundCoord(longitude);
  const cached = geocodeCache.get(key);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.address;
  }

  try {
    const apiKey = process.env.GOOGLE_GEOCODING_API_KEY;
    const url = apiKey
      ? 'https://maps.googleapis.com/maps/api/geocode/json?latlng=' + encodeURIComponent(latitude + ',' + longitude) + '&key=' + apiKey
      : 'https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18&lat=' + encodeURIComponent(latitude) + '&lon=' + encodeURIComponent(longitude);
    const headers = apiKey ? {} : { 'User-Agent': 'GoDigital-Attendance/1.0' };
    const response = await fetch(url, { headers: headers });
    const data = await response.json();

    if (!apiKey) {
      const address = data && data.display_name;
      if (!address) return null;
      geocodeCache.set(key, { address: address, expiresAt: Date.now() + GEOCODE_CACHE_TTL_MS });
      return address;
    }

    if (data.status !== 'OK' || !data.results || !data.results.length) {
      return null;
    }

    const localityResult = data.results.find(function (r) {
      return r.types.includes('sublocality') || r.types.includes('locality');
    });
    const address = (localityResult || data.results[0]).formatted_address;

    geocodeCache.set(key, { address: address, expiresAt: Date.now() + GEOCODE_CACHE_TTL_MS });
    return address;
  } catch (error) {
    console.error('Reverse geocode failed', error.message);
    return null;
  }
}

async function setStatus(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;
    const status = String(req.body.status || '').toLowerCase();
    if (!employeeUserId) return fail(res, 401, 'Unauthorized');
    if (!['office', 'home', 'field'].includes(status)) {
      return fail(res, 400, "status must be 'office', 'home', or 'field'");
    }
    await db.query(
      `INSERT INTO hrms_employee_location_status (employee_user_id, status)
       VALUES (?, ?)
       ON DUPLICATE KEY UPDATE status = VALUES(status), updated_at = CURRENT_TIMESTAMP`,
      [employeeUserId, status]
    );
    return ok(res, { status: status }, 'Status updated');
  } catch (error) {
    console.error('POST /hrms/tracking/status', error);
    return fail(res, 500, error.message);
  }
}

function distanceMeters(lat1, lng1, lat2, lng2) {
  const earthRadius = 6371000;

  const toRadians = (value) => (value * Math.PI) / 180;

  const dLat = toRadians(lat2 - lat1);
  const dLng = toRadians(lng2 - lng1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);

  return earthRadius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function detectFieldWaitingTime(employeeUserId, latitude, longitude) {
  const [sessions] = await db.query(
    `SELECT id, started_at, field_started_at, session_mode, field_waiting_minutes AS session_waiting_minutes, stationary_radius_meters AS session_radius_meters
     FROM hrms_field_tracking_sessions
     WHERE employee_user_id = ? AND is_active = 1
     ORDER BY started_at DESC
     LIMIT 1`,
    [employeeUserId]
  );

  if (!sessions.length) return;

  const session = sessions[0];
  if (session.session_mode && session.session_mode !== 'field_tracking') return;

  const [settingsRows] = await db.query(
    `SELECT field_waiting_minutes, stationary_radius_meters
     FROM hrms_tracking_settings
     WHERE id = 1`
  );

  if (!settingsRows.length) return;

  const waitingMinutes = Number(session.session_waiting_minutes || settingsRows[0].field_waiting_minutes || 60);

  const stationaryRadius = Number(
    session.session_radius_meters || settingsRows[0].stationary_radius_meters || 50
  );

  const [existingAlerts] = await db.query(
    `SELECT id
     FROM hrms_field_waiting_reasons
     WHERE field_session_id = ?
       AND reason IS NULL
       AND review_status = 'pending'
     LIMIT 1`,
    [session.id]
  );

  if (existingAlerts.length) return;

  const [pings] = await db.query(
    `SELECT latitude, longitude, recorded_at
     FROM hrms_location_pings
     WHERE employee_user_id = ?
       AND recorded_at >= ?
     ORDER BY recorded_at ASC`,
    [employeeUserId, session.field_started_at || session.started_at]
  );

  if (pings.length < 2) return;

  let firstStillPing = pings[pings.length - 1];

  for (let index = pings.length - 1; index >= 0; index--) {
    const ping = pings[index];

    const distance = distanceMeters(
      latitude,
      longitude,
      Number(ping.latitude),
      Number(ping.longitude)
    );

    if (distance > stationaryRadius) break;

    firstStillPing = ping;
  }

  // A submitted reason closes only the current waiting-alert cycle, not the
  // employee's stationary period.  If the employee stays inside this same
  // radius, start a fresh cycle from that submission and use the admin's
  // field_waiting_minutes setting again.
  const [lastSubmittedReasons] = await db.query(
    `SELECT reason_submitted_at
     FROM hrms_field_waiting_reasons
     WHERE field_session_id = ?
       AND reason IS NOT NULL
       AND reason_submitted_at IS NOT NULL
       AND reason_submitted_at >= ?
     ORDER BY reason_submitted_at DESC
     LIMIT 1`,
    [session.id, firstStillPing.recorded_at]
  );

  const cycleStartedAt = lastSubmittedReasons.length
    ? lastSubmittedReasons[0].reason_submitted_at
    : firstStillPing.recorded_at;
  const startedAt = new Date(cycleStartedAt);

  const elapsedMinutes = Math.floor(
    (Date.now() - startedAt.getTime()) / 60000
  );

  if (elapsedMinutes < waitingMinutes) return;

  // The cycle start is part of the key. This keeps one unresolved alert at a
  // time, while allowing a new alert after a submitted reason and another
  // full admin-configured waiting interval at the same location.
  const eventKey = `${session.id}:${new Date(cycleStartedAt).toISOString()}`;

await db.query(
  `INSERT IGNORE INTO hrms_field_waiting_reasons (
     field_session_id,
     employee_user_id,
     latitude,
     longitude,
     waiting_started_at,
     waiting_detected_at,
     waiting_minutes,
     event_key
   )
   VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, ?, ?)`,
  [
    session.id,
    employeeUserId,
    latitude,
    longitude,
    cycleStartedAt,
    elapsedMinutes,
    eventKey,
  ]
);
}

async function ping(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;
    const latitude = Number(req.body.latitude);
    const longitude = Number(req.body.longitude);
    const accuracy = req.body.accuracy != null ? Number(req.body.accuracy) : null;
    const isMocked = req.body.isMocked === true;
    if (!employeeUserId) return fail(res, 401, 'Unauthorized');
    await validateTrackingLocation(employeeUserId, latitude, longitude, accuracy, isMocked);
    const [sessions] = await db.query('SELECT id,session_mode,outside_fix_count FROM hrms_field_tracking_sessions WHERE employee_user_id=? AND is_active=1 ORDER BY id DESC LIMIT 1',[employeeUserId]);
    const activeSession = sessions[0];
    const office = await activeOfficeMatch(latitude, longitude);
    if (activeSession) {
      const previousMode = activeSession.session_mode || 'field_tracking';
      if (office) {
        await db.query(`UPDATE hrms_field_tracking_sessions SET session_mode='office_tracking', outside_fix_count=0, office_started_at=IF(session_mode='office_tracking',office_started_at,CURRENT_TIMESTAMP), last_mode_changed_at=IF(session_mode='office_tracking',last_mode_changed_at,CURRENT_TIMESTAMP) WHERE id=?`,[activeSession.id]);
        if (previousMode !== 'office_tracking') await db.query('INSERT INTO hrms_tracking_mode_audit (employee_user_id,field_session_id,previous_mode,new_mode,latitude,longitude,office_location_id,reason) VALUES (?,?,?,?,?,?,?,?)',[employeeUserId,activeSession.id,previousMode,'office_tracking',latitude,longitude,office.id,'Returned inside active office']);
      } else {
        const count = Number(activeSession.outside_fix_count || 0) + 1;
        if (previousMode === 'office_tracking' && count >= 3) {
          await db.query(`UPDATE hrms_field_tracking_sessions SET session_mode='field_tracking', outside_fix_count=?, field_started_at=CURRENT_TIMESTAMP, last_mode_changed_at=CURRENT_TIMESTAMP WHERE id=?`,[count,activeSession.id]);
          await db.query('INSERT INTO hrms_tracking_mode_audit (employee_user_id,field_session_id,previous_mode,new_mode,latitude,longitude,reason) VALUES (?,?,?,?,?,?,?)',[employeeUserId,activeSession.id,previousMode,'field_tracking',latitude,longitude,'Three consecutive outside-office fixes']);
        } else await db.query('UPDATE hrms_field_tracking_sessions SET outside_fix_count=? WHERE id=?',[count,activeSession.id]);
      }
    }
    const [result] = await db.query(
      `INSERT INTO hrms_location_pings (employee_user_id, latitude, longitude, accuracy_meters)
       VALUES (?, ?, ?, ?)`,
      [employeeUserId, latitude, longitude, accuracy]
    );
    const pingId = result.insertId;

    // Finish stationary-time detection before acknowledging the ping. This
    // ensures the employee app can retrieve a newly-created waiting alert on
    // its next one-minute check instead of racing a background task.
    await detectFieldWaitingTime(employeeUserId, latitude, longitude);

    ok(res, null, 'Location recorded'); // respond right away, don't block on geocoding

    reverseGeocode(latitude, longitude).then(function (address) {
      if (!address) return;
      db.query(`UPDATE hrms_location_pings SET address = ? WHERE id = ?`, [address, pingId])
        .catch(function (e) { console.error('Address backfill failed', e.message); });
    });
  } catch (error) {
    console.error('POST /hrms/tracking/ping', error);
    return fail(res, 500, error.message);
  }
}

async function liveOverview(req, res) {
  try {
    const [profiles] = await db.query(`
      SELECT id, employee_user_id, full_name, employee_code
      FROM hrms_employee_profiles
      WHERE employment_status <> 'Inactive'
    `);
    const userIds = profiles.map(function (row) { return row.employee_user_id; }).filter(Boolean);

    const [statuses] = userIds.length
      ? await db.query(
          `SELECT employee_user_id, status FROM hrms_employee_location_status
           WHERE employee_user_id IN (?)`,
          [userIds]
        )
      : [[]];
    const statusMap = new Map();
    statuses.forEach(function (row) { statusMap.set(Number(row.employee_user_id), row.status); });

    const [latestPings] = userIds.length
      ? await db.query(
          `SELECT p.employee_user_id, p.latitude, p.longitude, p.address, p.recorded_at
           FROM hrms_location_pings p
           INNER JOIN (
             SELECT employee_user_id, MAX(recorded_at) AS max_time
             FROM hrms_location_pings
             WHERE employee_user_id IN (?)
             GROUP BY employee_user_id
           ) latest
           ON latest.employee_user_id = p.employee_user_id AND latest.max_time = p.recorded_at`,
          [userIds]
        )
      : [[]];
    const pingMap = new Map();
    latestPings.forEach(function (row) { pingMap.set(Number(row.employee_user_id), row); });

    const now = Date.now();
    let activeNow = 0;
    const counts = { office: 0, home: 0, field: 0 };

    const items = profiles.map(function (profile) {
      const uid = profile.employee_user_id ? Number(profile.employee_user_id) : null;
      const status = (uid && statusMap.get(uid)) || 'office';
      const ping = uid ? pingMap.get(uid) : null;
      counts[status] = (counts[status] || 0) + 1;

      let isActive = false;
      if (ping && ping.recorded_at) {
        const ageMinutes = (now - new Date(ping.recorded_at).getTime()) / 60000;
        isActive = ageMinutes <= ACTIVE_WINDOW_MINUTES;
      }
      if (isActive) activeNow += 1;

      return {
        employeeUserId: uid,
        name: String(profile.full_name || '').trim(),
        employeeCode: profile.employee_code,
        status: status,
        latitude: ping ? Number(ping.latitude) : null,
        longitude: ping ? Number(ping.longitude) : null,
        address: ping ? ping.address : null,
        lastUpdated: ping ? ping.recorded_at : null,
        active: isActive,
      };
    });

    return ok(res, {
      counts: {
        office: counts.office || 0,
        home: counts.home || 0,
        field: counts.field || 0,
        activeNow: activeNow,
      },
      items: items,
    });
  } catch (error) {
    console.error('GET /hrms/tracking/live', error);
    return fail(res, 500, error.message);
  }
}

async function routeHistory(req, res) {
  try {
    const employeeUserId = Number(req.params.employeeUserId);
    const date = String(req.query.date || policy.todayIstDate()).slice(0, 10);
    if (!employeeUserId) return fail(res, 400, 'Valid employeeUserId is required');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return fail(res, 400, 'date must be YYYY-MM-DD');

    await ensureInvalidTrackingDatesTable();
    const [invalidRows] = await db.query(
      `SELECT reason, invalidated_at AS invalidatedAt
       FROM hrms_invalid_tracking_dates
       WHERE employee_user_id = ? AND route_date = ?`,
      [employeeUserId, date]
    );
    if (invalidRows.length) {
      return ok(res, {
        employeeUserId: employeeUserId,
        date: date,
        points: [],
        activityPoints: [],
        roadSnapped: false,
        waitingReasons: [],
        comments: [],
        invalidated: true,
        invalidationReason: invalidRows[0].reason,
        invalidatedAt: invalidRows[0].invalidatedAt,
      });
    }

    const [pings] = await db.query(
      `SELECT latitude, longitude, address, recorded_at
       FROM hrms_location_pings
       WHERE employee_user_id = ? AND DATE(recorded_at) = ?
       ORDER BY recorded_at ASC`,
      [employeeUserId, date]
    );

    // Keep the admin detail view self-contained: route points, resolved
    // waiting-popup reasons, and permanent comments all come from the same
    // date-scoped request. Previously `/route/:employeeUserId` returned only
    // GPS points, so the Waiting Popup Comments tab was always empty.
    const [waitingRows, commentRows] = await Promise.all([
      db.query(
        `SELECT id,
                reason,
                latitude,
                longitude,
                waiting_minutes AS waitingMinutes,
                waiting_started_at AS waitingStartedAt,
                waiting_detected_at AS waitingDetectedAt,
                reason_submitted_at AS reasonSubmittedAt
         FROM hrms_field_waiting_reasons
         WHERE employee_user_id = ?
           AND reason IS NOT NULL
           AND DATE(COALESCE(reason_submitted_at, waiting_detected_at)) = ?
         ORDER BY COALESCE(reason_submitted_at, waiting_detected_at) DESC`,
        [employeeUserId, date]
      ),
      db.query(
        `SELECT id,
                comment_text AS comment,
                latitude,
                longitude,
                address,
                created_at AS createdAt
         FROM hrms_employee_tracking_comments
         WHERE employee_user_id = ?
           AND DATE(created_at) = ?
         ORDER BY created_at DESC`,
        [employeeUserId, date]
      ),
    ]);
    const route = await snapRouteToRoads(employeeUserId, date, rawRoutePoints(pings));
    return ok(res, {
      employeeUserId: employeeUserId,
      date: date,
      points: route.points,
      roadSnapped: route.roadSnapped,
      waitingReasons: waitingRows[0],
      comments: commentRows[0],
      activityPoints: rawRoutePoints(pings),
    });
  } catch (error) {
    console.error('GET /hrms/tracking/route/:employeeUserId', error);
    return fail(res, 500, error.message);
  }
}

async function invalidateRoute(req, res) {
  try {
    const employeeUserId = Number(req.params.employeeUserId);
    const date = String((req.body && req.body.date) || '').slice(0, 10);
    const reason = String((req.body && req.body.reason) || '').trim();
    if (!employeeUserId) return fail(res, 400, 'Valid employeeUserId is required');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return fail(res, 400, 'date must be YYYY-MM-DD');
    if (reason.length < 3 || reason.length > 500) return fail(res, 400, 'Enter an invalidation reason between 3 and 500 characters.');
    await ensureInvalidTrackingDatesTable();
    await db.query(
      `INSERT INTO hrms_invalid_tracking_dates (employee_user_id, route_date, invalidated_by, reason)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE invalidated_by = VALUES(invalidated_by), reason = VALUES(reason), invalidated_at = CURRENT_TIMESTAMP`,
      [employeeUserId, date, req.user.id, reason]
    );
    return ok(res, null, 'The route was invalidated. Original GPS data is retained for audit.');
  } catch (error) {
    console.error('POST /hrms/tracking/route/:employeeUserId/invalidate', error);
    return fail(res, 500, error.message);
  }
}

async function myRouteHistoryList(req, res) {
  try {
    const limit = Math.min(30, Math.max(1, Number(req.query.limit || 10)));
    const [pings] = await db.query(
      `SELECT latitude, longitude, address, recorded_at
       FROM hrms_location_pings WHERE employee_user_id = ?
       ORDER BY recorded_at DESC LIMIT 5000`,
      [req.user.id]
    );
    const byDate = new Map();
    pings.reverse().forEach(function (ping) {
      const date = isoDate(ping.recorded_at);
      if (!date) return;
      if (!byDate.has(date)) byDate.set(date, []);
      byDate.get(date).push(ping);
    });
    const items = Array.from(byDate.entries()).sort(function (a, b) { return b[0].localeCompare(a[0]); }).slice(0, limit).map(function (entry) {
      const date = entry[0];
      const points = entry[1];
      let meters = 0;
      for (let i = 1; i < points.length; i += 1) {
        meters += locationPolicy.distanceMeters(Number(points[i - 1].latitude), Number(points[i - 1].longitude), Number(points[i].latitude), Number(points[i].longitude));
      }
      const first = points[0];
      const last = points[points.length - 1];
      const started = new Date(first.recorded_at);
      const ended = new Date(last.recorded_at);
      return {
        date: date,
        startAddress: first.address || 'Starting location',
        endAddress: last.address || 'Latest location',
        distanceKm: Math.round((meters / 1000) * 100) / 100,
        durationMinutes: Number.isNaN(started.getTime()) || Number.isNaN(ended.getTime()) ? 0 : Math.max(0, Math.round((ended.getTime() - started.getTime()) / 60000)),
        pointCount: points.length
      };
    });
    return ok(res, { items: items });
  } catch (error) {
    console.error('GET /hrms/tracking/route/my/history', error);
    return fail(res, 500, error.message);
  }
}

async function myRouteHistory(req, res) {
  try {
    const date = String(req.query.date || policy.todayIstDate()).slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return fail(res, 400, 'date must be YYYY-MM-DD');
    const [pings] = await db.query(
      `SELECT latitude, longitude, address, recorded_at
       FROM hrms_location_pings
       WHERE employee_user_id = ? AND DATE(recorded_at) = ?
       ORDER BY recorded_at ASC`,
      [req.user.id, date]
    );
    const route = await snapRouteToRoads(req.user.id, date, rawRoutePoints(pings));
    return ok(res, {
      employeeUserId: req.user.id,
      date: date,
      points: route.points,
      roadSnapped: route.roadSnapped,
    });
  } catch (error) {
    console.error('GET /hrms/tracking/route/my', error);
    return fail(res, 500, error.message);
  }
}
async function getTrackingSettings(req, res) {
  try {
    const [rows] = await db.query(
      'SELECT * FROM hrms_tracking_settings WHERE id = 1'
    );

    if (!rows.length) {
      return fail(res, 404, 'Tracking settings not found');
    }

    return ok(res, rows[0]);
  } catch (error) {
    console.error('GET /hrms/tracking/settings', error);
    return fail(res, 500, error.message);
  }
}

async function updateTrackingSettings(req, res) {
  try {
    const [rows] = await db.query(
      'SELECT * FROM hrms_tracking_settings WHERE id = 1'
    );

    if (!rows.length) {
      return fail(res, 404, 'Tracking settings not found');
    }

    const current = rows[0];

    const officeName =
        String(req.body.officeName ?? current.office_name).trim();

    const officeAddress =
        String(req.body.officeAddress ?? current.office_address).trim();

    const officeLatitude =
        Number(req.body.officeLatitude ?? current.office_latitude);

    const officeLongitude =
        Number(req.body.officeLongitude ?? current.office_longitude);

    const officeRadiusMeters =
        Number(req.body.officeRadiusMeters ?? current.office_radius_meters);

    const outsideRadiusGraceMinutes =
        Number(req.body.outsideRadiusGraceMinutes ?? current.outside_radius_grace_minutes ?? 2);

    const fieldPingIntervalMinutes =
        Number(req.body.fieldPingIntervalMinutes ??
            current.field_ping_interval_minutes);

    const fieldWaitingMinutes =
        Number(req.body.fieldWaitingMinutes ??
            current.field_waiting_minutes);

    const popupAlertRepeatSeconds =
        Number(req.body.popupAlertRepeatSeconds ??
            current.popup_alert_repeat_seconds ?? 5);

    const lunchBreakLimitMinutes =
        Number(req.body.lunchBreakLimitMinutes ?? current.lunch_break_limit_minutes ?? 70);

    const stationaryRadiusMeters =
        Number(req.body.stationaryRadiusMeters ??
            current.stationary_radius_meters);

    const homeTrackingEnabled = req.body.homeTrackingEnabled == null
      ? Number(current.home_tracking_enabled || 0) === 1
      : req.body.homeTrackingEnabled === true || req.body.homeTrackingEnabled === 1 || req.body.homeTrackingEnabled === '1';

    const autoClockOutEnabled = req.body.autoClockOutEnabled == null
      ? Number(current.auto_clock_out_enabled || 0) === 1
      : req.body.autoClockOutEnabled === true || req.body.autoClockOutEnabled === 1 || req.body.autoClockOutEnabled === '1';
    const autoClockOutConfirmationMinutes = Number(req.body.autoClockOutConfirmationMinutes ?? current.auto_clock_out_confirmation_minutes ?? 3);
    const autoClockOutWarningSeconds = Number(req.body.autoClockOutWarningSeconds ?? current.auto_clock_out_warning_seconds ?? 60);
    const autoClockOutBoundaryBufferMeters = Number(req.body.autoClockOutBoundaryBufferMeters ?? current.auto_clock_out_boundary_buffer_meters ?? 50);
    const autoClockOutSnoozeMinutes = Number(req.body.autoClockOutSnoozeMinutes ?? current.auto_clock_out_snooze_minutes ?? 15);
    const clockOutReminderEnabled = req.body.clockOutReminderEnabled == null
      ? Number(current.clock_out_reminder_enabled || 0) === 1
      : clockOutReminder.asBool(req.body.clockOutReminderEnabled);
    const clockOutReminderThresholdMinutes = Number(req.body.clockOutReminderThresholdMinutes ?? current.clock_out_reminder_threshold_minutes ?? 15);
    const clockOutReminderRepeatMinutes = Number(req.body.clockOutReminderRepeatMinutes ?? current.clock_out_reminder_repeat_minutes ?? 15);
    const clockOutReminderSound = String(req.body.clockOutReminderSound ?? current.clock_out_reminder_sound ?? 'notification.mp3').trim();

    try {
      clockOutReminder.validateSettings({
        clockOutReminderThresholdMinutes,
        clockOutReminderRepeatMinutes,
        autoClockOutSnoozeMinutes,
        autoClockOutConfirmationMinutes,
        autoClockOutWarningSeconds,
        clockOutReminderSound,
      });
    } catch (error) {
      return fail(res, error.status || 400, error.message);
    }

    if (
      !officeName ||
      !officeAddress ||
      !Number.isFinite(officeLatitude) ||
      !Number.isFinite(officeLongitude) ||
      officeLatitude < -90 ||
      officeLatitude > 90 ||
      officeLongitude < -180 ||
      officeLongitude > 180 ||
      officeRadiusMeters < 1 ||
      outsideRadiusGraceMinutes < 1 ||
      fieldPingIntervalMinutes < 1 ||
      fieldWaitingMinutes < 1 ||
      !Number.isInteger(popupAlertRepeatSeconds) ||
      popupAlertRepeatSeconds < 1 ||
      popupAlertRepeatSeconds > 30 ||
      lunchBreakLimitMinutes < 1 ||
      stationaryRadiusMeters < 1
      || autoClockOutConfirmationMinutes < 1
      || autoClockOutWarningSeconds < 10
      || autoClockOutBoundaryBufferMeters < 0
      || autoClockOutSnoozeMinutes < 1
    ) {
      return fail(res, 400, 'Invalid tracking settings');
    }

    await db.query(
      `UPDATE hrms_tracking_settings
       SET office_name = ?,
           office_address = ?,
           office_latitude = ?,
           office_longitude = ?,
           office_radius_meters = ?,
           outside_radius_grace_minutes = ?,
           field_ping_interval_minutes = ?,
           field_waiting_minutes = ?,
           popup_alert_repeat_seconds = ?,
           lunch_break_limit_minutes = ?,
           stationary_radius_meters = ?,
           home_tracking_enabled = ?,
           auto_clock_out_enabled = ?,
           auto_clock_out_confirmation_minutes = ?,
           auto_clock_out_warning_seconds = ?,
           auto_clock_out_boundary_buffer_meters = ?,
           auto_clock_out_snooze_minutes = ?,
           clock_out_reminder_enabled = ?,
           clock_out_reminder_threshold_minutes = ?,
           clock_out_reminder_repeat_minutes = ?,
           clock_out_reminder_sound = ?,
           clock_out_reminder_updated_at = CURRENT_TIMESTAMP,
           updated_by = ?
       WHERE id = 1`,
      [
        officeName,
        officeAddress,
        officeLatitude,
        officeLongitude,
        officeRadiusMeters,
        outsideRadiusGraceMinutes,
        fieldPingIntervalMinutes,
        fieldWaitingMinutes,
        popupAlertRepeatSeconds,
        lunchBreakLimitMinutes,
        stationaryRadiusMeters,
        homeTrackingEnabled ? 1 : 0,
        autoClockOutEnabled ? 1 : 0,
        autoClockOutConfirmationMinutes,
        autoClockOutWarningSeconds,
        autoClockOutBoundaryBufferMeters,
        autoClockOutSnoozeMinutes,
        clockOutReminderEnabled ? 1 : 0,
        clockOutReminderThresholdMinutes,
        clockOutReminderRepeatMinutes,
        clockOutReminderSound,
        req.user.id,
      ]
    );

    return getTrackingSettings(req, res);
  } catch (error) {
    console.error('PUT /hrms/tracking/settings', error);
    return fail(res, 500, error.message);
  }
}

async function homeFeatureEnabled() {
  const [rows] = await db.query('SELECT home_tracking_enabled FROM hrms_tracking_settings WHERE id = 1');
  return Number(rows[0] && rows[0].home_tracking_enabled) === 1;
}

async function requireHomeFeature(res) {
  if (await homeFeatureEnabled()) return true;
  fail(res, 403, 'Home work functionality is disabled by the administrator');
  return false;
}

async function getMyHomeLocation(req, res) {
  try {
    if (!await requireHomeFeature(res)) return;
    const employeeUserId = req.user && req.user.id;

    if (!employeeUserId) {
      return fail(res, 401, 'Unauthorized');
    }

    const [rows] = await db.query(
      `SELECT employee_user_id, latitude, longitude, address,
              approval_status, submitted_at, reviewed_at, rejection_reason
       FROM hrms_employee_home_locations
       WHERE employee_user_id = ?`,
      [employeeUserId]
    );

    return ok(res, rows[0] || null);
  } catch (error) {
    console.error('GET /hrms/tracking/home-location', error);
    return fail(res, 500, error.message);
  }
}

async function submitHomeLocation(req, res) {
  let connection;
  try {
    if (!await requireHomeFeature(res)) return;
    const employeeUserId = req.user && req.user.id;
    const body = req.body || {};
    const address = typeof body.address === 'string' ? body.address.trim() : '';

    if (!employeeUserId) {
      return fail(res, 401, 'Unauthorized');
    }

    if (address.length > 500) return fail(res, 400, 'Home address must be 500 characters or fewer.');
    connection = await db.getConnection();
    await connection.beginTransaction();
    await locationPolicy.profileFor(connection, employeeUserId, true);
    const settings = await locationPolicy.settingsFor(connection, true);
    const fix = locationPolicy.validateFix(body, settings.radiusMeters);

    await connection.query(
      `INSERT INTO hrms_employee_home_locations
        (employee_user_id, latitude, longitude, address, approval_status)
       VALUES (?, ?, ?, ?, 'pending')
       ON DUPLICATE KEY UPDATE
         latitude = VALUES(latitude),
         longitude = VALUES(longitude),
         address = VALUES(address),
         approval_status = 'pending',
         reviewed_by = NULL,
         reviewed_at = NULL,
         rejection_reason = NULL,
         submitted_at = CURRENT_TIMESTAMP,
         updated_at = CURRENT_TIMESTAMP`,
      [employeeUserId, fix.latitude, fix.longitude, address || null]
    );
    await connection.commit();
    return ok(res, null, 'Home location submitted for admin approval');
  } catch (error) {
    if (connection) await connection.rollback();
    if (error instanceof locationPolicy.LocationPolicyError) return fail(res, error.status, error.message);
    console.error('POST /hrms/tracking/home-location', error);
    return fail(res, 500, 'Unable to submit Home location. Please try again.');
  } finally {
    if (connection) connection.release();
  }
}

async function listHomeLocations(req, res) {
  try {
    if (!await requireHomeFeature(res)) return;
    if (String(req.user && req.user.userType || '').toLowerCase() !== 'admin') {
      return fail(res, 403, 'Admin access required');
    }
    const [rows] = await db.query(`
      SELECT h.employee_user_id, h.latitude, h.longitude, h.address,
             h.approval_status, h.submitted_at, h.reviewed_at,
             h.rejection_reason, p.full_name, p.employee_code
      FROM hrms_employee_home_locations h
      LEFT JOIN hrms_employee_profiles p
        ON p.employee_user_id = h.employee_user_id
      ORDER BY
        CASE h.approval_status
          WHEN 'pending' THEN 1
          WHEN 'approved' THEN 2
          ELSE 3
        END,
        h.submitted_at DESC
    `);

    return ok(res, { items: rows });
  } catch (error) {
    console.error('GET /hrms/tracking/home-locations', error);
    return fail(res, 500, error.message);
  }
}

async function reviewHomeLocation(req, res) {
  let connection;
  try {
    if (!await requireHomeFeature(res)) return;
    if (String(req.user && req.user.userType || '').toLowerCase() !== 'admin') {
      return fail(res, 403, 'Admin access required');
    }
    const employeeUserId = Number(req.params.employeeUserId);
    const body = req.body || {};
    const approvalStatus = String(body.approvalStatus || '').toLowerCase();
    const rejectionReason = typeof body.rejectionReason === 'string' ? body.rejectionReason.trim() : '';

    if (!Number.isSafeInteger(employeeUserId) || employeeUserId < 1) {
      return fail(res, 400, 'Valid employee ID is required');
    }

    if (!['approved', 'rejected'].includes(approvalStatus)) {
      return fail(res, 400, 'approvalStatus must be approved or rejected');
    }
    if (rejectionReason.length > 500) return fail(res, 400, 'Rejection reason must be 500 characters or fewer.');
    if (approvalStatus === 'rejected' && !rejectionReason) {
      return fail(res, 400, 'Enter a reason for rejecting the Home location.');
    }
    const reviewedCoordinates = locationPolicy.coordinates(body.latitude, body.longitude);
    connection = await db.getConnection();
    await connection.beginTransaction();
    const profile = await locationPolicy.profileFor(connection, employeeUserId, true);
    const [homes] = await connection.query(
      `SELECT latitude, longitude, approval_status FROM hrms_employee_home_locations
       WHERE employee_user_id = ? FOR UPDATE`, [employeeUserId]);
    if (homes.length !== 1) {
      throw new locationPolicy.LocationPolicyError(404, 'Home location request not found.');
    }
    if (homes[0].approval_status !== 'pending') {
      throw new locationPolicy.LocationPolicyError(409, 'This Home location request was already reviewed. Refresh the list.');
    }
    if (Number(homes[0].latitude) !== reviewedCoordinates.latitude ||
        Number(homes[0].longitude) !== reviewedCoordinates.longitude) {
      throw new locationPolicy.LocationPolicyError(409, 'The employee submitted a different Home location. Refresh and review the new request.');
    }
    await connection.query(
      `UPDATE hrms_employee_home_locations
       SET approval_status = ?,
           reviewed_by = ?,
           reviewed_at = CURRENT_TIMESTAMP,
           rejection_reason = ?
       WHERE employee_user_id = ? AND approval_status = 'pending'`,
      [
        approvalStatus,
        req.user.id,
        approvalStatus === 'rejected' ? rejectionReason || null : null,
        employeeUserId,
      ]
    );
    if (approvalStatus === 'approved') {
      await connection.query(
        "UPDATE hrms_employee_profiles SET work_mode = 'Home' WHERE id = ?", [profile.id]);
    }
    await connection.commit();
    return ok(res, null, approvalStatus === 'approved'
      ? 'Home location approved. Employee work mode is now Home.'
      : 'Home location rejected');
  } catch (error) {
    if (connection) await connection.rollback();
    if (error instanceof locationPolicy.LocationPolicyError) return fail(res, error.status, error.message);
    console.error('PATCH /hrms/tracking/home-locations/:employeeUserId', error);
    return fail(res, 500, 'Unable to review Home location. Please try again.');
  } finally {
    if (connection) connection.release();
  }
}

async function getMyFieldSession(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;

    if (!employeeUserId) {
      return fail(res, 401, 'Unauthorized');
    }

    const [rows] = await db.query(
      `SELECT *
       FROM hrms_field_tracking_sessions
       WHERE employee_user_id = ? AND is_active = 1
       ORDER BY started_at DESC
       LIMIT 1`,
      [employeeUserId]
    );

    return ok(res, rows[0] || { isActive: false });
  } catch (error) {
    console.error('GET /hrms/tracking/field-session', error);
    return fail(res, 500, error.message);
  }
}

async function getTrackingPermissions(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;
    if (!employeeUserId) return fail(res, 401, 'Unauthorized');

    const [[profiles], [settingsRows]] = await Promise.all([
      db.query(
        `SELECT work_mode FROM hrms_employee_profiles
         WHERE employee_user_id = ? LIMIT 1`,
        [employeeUserId]
      ),
      db.query(
        `SELECT home_tracking_enabled FROM hrms_tracking_settings
         WHERE id = 1 LIMIT 1`
      ),
    ]);

    const profile = profiles[0];
    const settings = settingsRows[0];
    const workMode = String((profile && profile.work_mode) || 'Office');
    return ok(res, {
      fieldTrackingEnabled: ['Field', 'Hybrid'].includes(workMode),
      workMode,
      homeLocationEnabled: Number(settings && settings.home_tracking_enabled) === 1,
    });
  } catch (error) {
    console.error('GET /hrms/tracking/permissions', error);
    return fail(res, 500, 'Unable to load tracking permissions');
  }
}

async function getFieldSessionSummary(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;
    if (!employeeUserId) return fail(res, 401, 'Unauthorized');

    const [sessions] = await db.query(
      `SELECT id, started_at, session_mode
       FROM hrms_field_tracking_sessions
       WHERE employee_user_id = ? AND is_active = 1
       ORDER BY started_at DESC LIMIT 1`,
      [employeeUserId]
    );

    if (!sessions.length) {
      return ok(res, {
        hasSession: false,
        durationSeconds: 0,
        distanceKm: 0,
        averageSpeedKmph: 0,
      });
    }

    const session = sessions[0];
    const [pings] = await db.query(
      `SELECT latitude, longitude
       FROM hrms_location_pings
       WHERE employee_user_id = ? AND recorded_at >= ?
       ORDER BY recorded_at ASC`,
      [employeeUserId, session.started_at]
    );

    let meters = 0;
    for (let index = 1; index < pings.length; index += 1) {
      meters += distanceMeters(
        Number(pings[index - 1].latitude),
        Number(pings[index - 1].longitude),
        Number(pings[index].latitude),
        Number(pings[index].longitude)
      );
    }

    const durationSeconds = Math.max(
      0,
      Math.floor((Date.now() - new Date(session.started_at).getTime()) / 1000) || 0
    );
    const distanceKm = Math.round((meters / 1000) * 100) / 100;
    const averageSpeedKmph = durationSeconds > 0
      ? Math.round(((meters / 1000) / (durationSeconds / 3600)) * 10) / 10
      : 0;

    return ok(res, {
      hasSession: true,
      sessionMode: session.session_mode || 'field_tracking',
      durationSeconds,
      distanceKm,
      averageSpeedKmph,
    });
  } catch (error) {
    console.error('GET /hrms/tracking/field-session/summary', error);
    return fail(res, 500, 'Unable to load field session summary');
  }
}

// The employee app uses this endpoint to restore the same route and timeline
// after navigation.  A completed session remains available for the rest of
// the day, instead of disappearing as soon as it is stopped.
async function getFieldSessionTimeline(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;
    if (!employeeUserId) return fail(res, 401, 'Unauthorized');

    const [sessions] = await db.query(
      `SELECT * FROM hrms_field_tracking_sessions
       WHERE employee_user_id = ?
         AND (is_active = 1 OR DATE(started_at) = ?)
       ORDER BY is_active DESC, started_at DESC
       LIMIT 1`,
      [employeeUserId, policy.todayIstDate()]
    );
    if (!sessions.length) {
      return ok(res, { hasSession: false, isActive: false, events: [], points: [], durationSeconds: 0, distanceKm: 0, averageSpeedKmph: 0 });
    }

    const session = sessions[0];
    const end = session.is_active ? new Date() : session.stopped_at;
    const [pings] = await db.query(
      `SELECT id, latitude, longitude, accuracy_meters, address, recorded_at
       FROM hrms_location_pings
       WHERE employee_user_id = ? AND recorded_at >= ? AND recorded_at <= ?
       ORDER BY recorded_at ASC`,
      [employeeUserId, session.started_at, end]
    );

    let meters = 0;
    for (let index = 1; index < pings.length; index += 1) {
      meters += distanceMeters(Number(pings[index - 1].latitude), Number(pings[index - 1].longitude), Number(pings[index].latitude), Number(pings[index].longitude));
    }
    const durationSeconds = Math.max(0, Math.floor((new Date(end).getTime() - new Date(session.started_at).getTime()) / 1000));
    const distanceKm = Math.round((meters / 1000) * 100) / 100;
    const averageSpeedKmph = durationSeconds > 0 ? Math.round(((meters / 1000) / (durationSeconds / 3600)) * 10) / 10 : 0;
    const events = [{
      type: 'start', recordedAt: session.started_at, latitude: session.start_latitude, longitude: session.start_longitude, address: null, text: 'Started live Field tracking'
    }];
    for (const ping of pings) events.push({
      type: 'location', recordedAt: ping.recorded_at, latitude: ping.latitude, longitude: ping.longitude, address: ping.address, accuracy: ping.accuracy_meters, text: 'Live location updated'
    });
    if (!session.is_active && session.stopped_at) events.push({
      type: 'stop', recordedAt: session.stopped_at, latitude: session.stop_latitude, longitude: session.stop_longitude, address: null, reason: session.stop_reason, text: 'Stopped live Field tracking'
    });
    return ok(res, {
      hasSession: true, sessionId: session.id, isActive: Number(session.is_active) === 1,
      startedAt: session.started_at, stoppedAt: session.stopped_at, stopReason: session.stop_reason,
      events, points: pings, durationSeconds, distanceKm, averageSpeedKmph,
    });
  } catch (error) {
    console.error('GET /hrms/tracking/field-session/timeline', error);
    return fail(res, 500, 'Unable to load field session timeline');
  }
}

async function startFieldTracking(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;
    const latitude = Number(req.body.latitude);
    const longitude = Number(req.body.longitude);
    const accuracy =
        req.body.accuracy != null ? Number(req.body.accuracy) : null;
    const isMocked = req.body.isMocked === true;
    if (!employeeUserId) {
      return fail(res, 401, 'Unauthorized');
    }

    await validateTrackingLocation(employeeUserId, latitude, longitude, accuracy, isMocked);

    const [profiles] = await db.query(
      `SELECT work_mode, tracking_template_id
       FROM hrms_employee_profiles
       WHERE employee_user_id = ?`,
      [employeeUserId]
    );

    if (!profiles.length || !['Field', 'Hybrid'].includes(profiles[0].work_mode)) {
      return fail(res, 403, 'Live tracking is available only for Field or Hybrid employees');
    }
    if (!profiles[0].tracking_template_id) return fail(res, 400, 'Ask Admin to assign a live tracking template before starting tracking.');
    const [templates] = await db.query('SELECT * FROM hrms_tracking_templates WHERE id=? AND is_active=1', [profiles[0].tracking_template_id]);
    if (!templates.length) return fail(res, 400, 'Ask Admin to assign an active live tracking template before starting tracking.');
    const template = templates[0];

    const [activeSessions] = await db.query(
      `SELECT id
       FROM hrms_field_tracking_sessions
       WHERE employee_user_id = ? AND is_active = 1
       LIMIT 1`,
      [employeeUserId]
    );

    if (activeSessions.length) {
      return ok(
        res,
        { sessionId: activeSessions[0].id, isActive: true },
        'Live tracking is already active'
      );
    }

    const office = await activeOfficeMatch(latitude, longitude);
    const sessionMode = office ? 'office_tracking' : 'field_tracking';
    const [session] = await db.query(
      `INSERT INTO hrms_field_tracking_sessions
        (employee_user_id, start_latitude, start_longitude, tracking_template_id, template_name, field_waiting_minutes, stationary_radius_meters, field_ping_interval_minutes, popup_alert_repeat_seconds, session_mode, outside_fix_count, office_started_at, field_started_at, last_mode_changed_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, IF(?='office_tracking',CURRENT_TIMESTAMP,NULL), IF(?='field_tracking',CURRENT_TIMESTAMP,NULL), CURRENT_TIMESTAMP)`,
      [employeeUserId, latitude, longitude, template.id, template.name, template.field_waiting_minutes, template.stationary_radius_meters, template.field_ping_interval_minutes, template.popup_alert_repeat_seconds, sessionMode, office ? 0 : 1, sessionMode, sessionMode]
    );

    await db.query(
      `INSERT INTO hrms_location_pings
        (employee_user_id, latitude, longitude, accuracy_meters)
       VALUES (?, ?, ?, ?)`,
      [employeeUserId, latitude, longitude, accuracy]
    );

    await db.query(
      `INSERT INTO hrms_employee_location_status (employee_user_id, status)
       VALUES (?, 'field')
       ON DUPLICATE KEY UPDATE
         status = 'field',
         updated_at = CURRENT_TIMESTAMP`,
      [employeeUserId]
    );

    return ok(
      res,
      { sessionId: session.insertId, isActive: true, sessionMode, template: { id: template.id, name: template.name, fieldWaitingMinutes: template.field_waiting_minutes, stationaryRadiusMeters: template.stationary_radius_meters, fieldPingIntervalMinutes: template.field_ping_interval_minutes, popupAlertRepeatSeconds: template.popup_alert_repeat_seconds } },
      'Field live tracking started'
    );
  } catch (error) {
    console.error('POST /hrms/tracking/field-session/start', error);
    return fail(res, 500, error.message);
  }
}

async function stopFieldTracking(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;
    const latitude =
        req.body.latitude != null ? Number(req.body.latitude) : null;
    const longitude =
        req.body.longitude != null ? Number(req.body.longitude) : null;
    const accuracy =
        req.body.accuracy != null ? Number(req.body.accuracy) : null;
    const isMocked = req.body.isMocked === true;
    const reason = String((req.body && req.body.reason) || '').trim();

    if (!employeeUserId) {
      return fail(res, 401, 'Unauthorized');
    }
    if (reason.length < 3 || reason.length > 1000) {
      return fail(res, 400, 'Enter a tracking stop reason between 3 and 1000 characters.');
    }

    const [activeSessions] = await db.query(
      `SELECT id
       FROM hrms_field_tracking_sessions
       WHERE employee_user_id = ? AND is_active = 1
       ORDER BY started_at DESC
       LIMIT 1`,
      [employeeUserId]
    );

    if (!activeSessions.length) {
      return ok(res, { isActive: false }, 'No active field tracking session');
    }

    const sessionId = activeSessions[0].id;

    // Validate the final point before closing the session.  This prevents a
    // rejected stale/mock/inaccurate reading from closing tracking while the
    // map is left with an old or incorrect final location.
    if (Number.isFinite(latitude) && Number.isFinite(longitude)) {
      await validateTrackingLocation(employeeUserId, latitude, longitude, accuracy, isMocked);
    }

    await db.query(
      `UPDATE hrms_field_tracking_sessions
       SET is_active = 0,
           stopped_at = CURRENT_TIMESTAMP,
           stop_latitude = ?,
           stop_longitude = ?,
           stop_reason = ?
       WHERE id = ?`,
      [
        Number.isFinite(latitude) ? latitude : null,
        Number.isFinite(longitude) ? longitude : null,
        reason,
        sessionId,
      ]
    );

    // Tracking can stop independently of attendance. Clock out owns the
    // attendance close and uses its single reason for both actions.
    await db.query(
      `UPDATE attendance_records
       SET tracking_stop_reason = ?
       WHERE employee_id = ?
         AND attendance_date = ?
         AND check_in_at IS NOT NULL
         AND check_out_at IS NULL`,
      [reason, employeeUserId, policy.todayIstDate()]
    );

    if (Number.isFinite(latitude) && Number.isFinite(longitude)) {
      const [finalPing] = await db.query(
        `INSERT INTO hrms_location_pings
          (employee_user_id, latitude, longitude, accuracy_meters)
         VALUES (?, ?, ?, ?)`,
        [employeeUserId, latitude, longitude, accuracy]
      );

      // The map route uses location pings. Save and reverse-geocode the exact
      // final Stop point so the route ends where the employee actually stopped.
      reverseGeocode(latitude, longitude).then(function (address) {
        if (!address) return;
        db.query(
          'UPDATE hrms_location_pings SET address = ? WHERE id = ?',
          [address, finalPing.insertId]
        ).catch(function (geocodeError) {
          console.error('Stop location address backfill failed', geocodeError.message);
        });
      });
    }

    return ok(
      res,
      { sessionId: sessionId, isActive: false },
      'Field live tracking stopped'
    );
  } catch (error) {
    console.error('POST /hrms/tracking/field-session/stop', error);
    return fail(res, 500, error.message);
  }
}
async function getMyWaitingAlert(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;

    // The employee page polls this endpoint once per minute. Re-run the
    // stationary check here as a reliable fallback in case a browser or
    // network timing issue completed a ping before its detector finished.
    const [latestPings] = await db.query(
      `SELECT latitude, longitude
       FROM hrms_location_pings
       WHERE employee_user_id = ?
       ORDER BY recorded_at DESC
       LIMIT 1`,
      [employeeUserId]
    );
    if (latestPings.length) {
      await detectFieldWaitingTime(
        employeeUserId,
        Number(latestPings[0].latitude),
        Number(latestPings[0].longitude)
      );
    }

    const [rows] = await db.query(
      `SELECT id, waiting_minutes, waiting_started_at, waiting_detected_at
       FROM hrms_field_waiting_reasons
       WHERE employee_user_id = ?
         AND reason IS NULL
         AND review_status = 'pending'
       ORDER BY waiting_detected_at DESC
       LIMIT 1`,
      [employeeUserId]
    );

    return ok(res, rows[0] || null);
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

async function submitWaitingReason(req, res) {
  try {
    const employeeUserId = req.user && req.user.id;
    const reasonId = Number(req.params.id);
    const reason = String(req.body.reason || '').trim();

    if (!reasonId || !reason) {
      return fail(res, 400, 'Waiting reason is required');
    }
    if (reason.length > 500) {
      return fail(res, 400, 'Waiting reason must be 500 characters or less');
    }

    const [result] = await db.query(
      `UPDATE hrms_field_waiting_reasons
       SET reason = ?,
           reason_submitted_at = CURRENT_TIMESTAMP
       WHERE id = ?
         AND employee_user_id = ?
         AND reason IS NULL`,
      [reason, reasonId, employeeUserId]
    );

    if (!result.affectedRows) {
      return fail(res, 404, 'Waiting alert not found');
    }

    return ok(res, null, 'Waiting reason submitted');
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

async function listFieldWaitingReasons(req, res) {
  try {
    const [rows] = await db.query(`
      SELECT w.*,
             p.full_name,
             p.employee_code
      FROM hrms_field_waiting_reasons w
      LEFT JOIN hrms_employee_profiles p
        ON p.employee_user_id = w.employee_user_id
      ORDER BY w.waiting_detected_at DESC
      LIMIT 100
    `);

    return ok(res, { items: rows });
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

async function myFieldWaitingReasons(req, res) {
  try {
    const employeeUserId = Number(req.user && req.user.id);
    if (!employeeUserId) {
      return fail(res, 401, 'Authentication is required');
    }

    const [rows] = await db.query(
      `SELECT id,
              reason,
              latitude,
              longitude,
              waiting_minutes AS waitingMinutes,
              waiting_started_at AS waitingStartedAt,
              waiting_detected_at AS waitingDetectedAt,
              reason_submitted_at AS reasonSubmittedAt
       FROM hrms_field_waiting_reasons
       WHERE employee_user_id = ?
         AND reason IS NOT NULL
       ORDER BY reason_submitted_at DESC
       LIMIT 100`,
      [employeeUserId]
    );

    return ok(res, { items: rows });
  } catch (error) {
    return fail(res, 500, error.message);
  }
}

async function reviewFieldWaitingReason(req, res) {
  try {
    const reasonId = Number(req.params.id);

    if (!reasonId) {
      return fail(res, 400, 'Valid waiting reason ID is required');
    }

    const [result] = await db.query(
      `UPDATE hrms_field_waiting_reasons
       SET review_status = 'reviewed',
           reviewed_by = ?,
           reviewed_at = CURRENT_TIMESTAMP
       WHERE id = ?`,
      [req.user.id, reasonId]
    );

    if (!result.affectedRows) {
      return fail(res, 404, 'Waiting reason not found');
    }

    return ok(res, null, 'Waiting reason reviewed');
  } catch (error) {
    return fail(res, 500, error.message);
  }
}



async function addTrackingComment(req, res) {
  try {
    const employeeUserId = Number(req.user && req.user.id);
    const text = String((req.body && req.body.comment) || '').trim();
    if (!text) return fail(res, 400, 'Comment is required');
    if (text.length > 2000) return fail(res, 400, 'Comment is too long');
    const [profiles] = await db.query('SELECT work_mode FROM hrms_employee_profiles WHERE employee_user_id = ?', [employeeUserId]);
    if (!profiles.length || !['Field', 'Hybrid'].includes(profiles[0].work_mode)) return fail(res, 403, 'Comments are available only to Field and Hybrid employees');
    const latitude = Number(req.body.latitude), longitude = Number(req.body.longitude);
    await db.query('INSERT INTO hrms_employee_tracking_comments (employee_user_id, comment_text, latitude, longitude, address) VALUES (?, ?, ?, ?, ?)', [employeeUserId, text, Number.isFinite(latitude) ? latitude : null, Number.isFinite(longitude) ? longitude : null, String(req.body.address || '').trim() || null]);
    return ok(res, null, 'Comment saved');
  } catch (error) { return fail(res, 500, error.message); }
}

async function myTrackingComments(req, res) {
  try {
    const [rows] = await db.query(`SELECT id, comment_text AS comment, latitude, longitude, address, created_at AS createdAt FROM hrms_employee_tracking_comments WHERE employee_user_id = ? ORDER BY created_at DESC LIMIT 100`, [req.user.id]);
    return ok(res, { items: rows });
  } catch (error) { return fail(res, 500, error.message); }
}

async function adminTrackingComments(req, res) {
  try {
    const [rows] = await db.query(`SELECT c.id, c.employee_user_id AS employeeUserId, p.full_name AS employeeName, p.employee_code AS employeeCode, c.comment_text AS comment, c.latitude, c.longitude, c.address, c.created_at AS createdAt FROM hrms_employee_tracking_comments c INNER JOIN employee_users u ON u.id = c.employee_user_id INNER JOIN hrms_employee_profiles p ON p.employee_user_id = c.employee_user_id WHERE c.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY) ORDER BY c.created_at DESC`);
    return ok(res, { items: rows });
  } catch (error) { return fail(res, 500, error.message); }
}

module.exports = {
  requireAdmin,
  list,
  setStatus,
  ping,
  liveOverview,
  routeHistory,
  invalidateRoute,
  myRouteHistoryList,
  myRouteHistory,
  getTrackingSettings,
  updateTrackingSettings,
  getMyHomeLocation,
  submitHomeLocation,
  listHomeLocations,
  reviewHomeLocation,
  getMyFieldSession,
  getTrackingPermissions,
  getFieldSessionSummary,
  getFieldSessionTimeline,
startFieldTracking,
stopFieldTracking,
getMyWaitingAlert,
submitWaitingReason,
listFieldWaitingReasons,
myFieldWaitingReasons,
reviewFieldWaitingReason,
  addTrackingComment,
  myTrackingComments,
  adminTrackingComments,
  trackingTemplates,
  createTrackingTemplate,
  updateTrackingTemplate,
  archiveTrackingTemplate,
  restoreTrackingTemplate,
  deleteTrackingTemplate,
  assignTrackingTemplate,
  officeLocations,
  createOfficeLocation,
  updateOfficeLocation,
  archiveOfficeLocation,
  restoreOfficeLocation,
  deleteOfficeLocation,
};
