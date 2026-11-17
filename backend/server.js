'use strict';

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const db = require('./config/db');
const { ensureAttendanceTables } = require('./lib/ensureAttendanceTables');
const { ensureAuthSchema } = require('./lib/ensureAuthSchema');
const { ensureHrmsEmployeeTables } = require('./lib/ensureHrmsEmployeeTables');
const { ensureHrmsTrackingTables } = require('./lib/ensureHrmsTrackingTables');
const { ensureWeeklyOffTemplateTables } = require('./lib/weeklyOffTemplates');
const attendancePolicy = require('./lib/attendancePolicy');
const payroll = require('./controllers/hrmsPayrollController');
const { createApp: createEmployeeAttendanceApp } = require('./attendance/app');
const clockOutReminder = require('./lib/clockOutReminder');
const { closeForgottenCheckouts } = require('./lib/endOfDayAutoClockout');
const cron = require('node-cron');
const http = require('http');
const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const { ensureMessagingTables } = require('./lib/ensureMessagingTables');
const attendanceMessaging = require('./lib/attendanceMessaging');
const messaging = require('./lib/messaging');
const onlineUsers = new Map();

const app = express();
const port = Number(process.env.PORT || 3000);
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: process.env.CORS_ORIGIN || true, credentials: true } });
app.set('io', io);

io.use((socket, next) => {
  try {
    const token = socket.handshake.auth && socket.handshake.auth.token || socket.handshake.headers.authorization?.replace(/^Bearer\s+/i, '');
    socket.user = jwt.verify(token, process.env.JWT_SECRET || 'change-this-in-production');
    next();
  } catch (_) { next(new Error('Unauthorized socket')); }
});
io.on('connection', socket => {
  const userId = Number(socket.user.id);
  const connections = (onlineUsers.get(userId) || 0) + 1;
  onlineUsers.set(userId, connections);
  if (connections === 1) io.emit('chat:presence', { userId, online: true });
  socket.join(`user:${socket.user.id}`);
  socket.on('chat:join', async ({ conversationId }) => {
    if (await messaging.isParticipant(db, Number(conversationId), socket.user.id)) socket.join(`conversation:${Number(conversationId)}`);
  });
  socket.on('disconnect', async () => {
    const left = (onlineUsers.get(userId) || 1) - 1;
    if (left > 0) return onlineUsers.set(userId, left);
    onlineUsers.delete(userId);
    const lastSeenAt = new Date();
    try { await db.query('INSERT INTO chat_user_presence (user_id,last_seen_at) VALUES (?,?) ON DUPLICATE KEY UPDATE last_seen_at=VALUES(last_seen_at)', [userId, lastSeenAt]); } catch (error) { console.error('Chat presence update failed:', error.message); }
    io.emit('chat:presence', { userId, online: false, lastSeenAt });
  });
});

app.disable('x-powered-by');
app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));
app.use('/uploads', express.static(require('path').join(__dirname, 'uploads')));

// The only retained feature area is Attendance. Authentication and the employee
// directory remain because attendance records are always tied to signed-in staff.
app.use('/api/auth', require('./routes/auth'));
app.use('/api/attendance', require('./routes/attendance'));
app.use('/api/attendance', createEmployeeAttendanceApp({
  pool: db,
  jwtSecret: process.env.JWT_SECRET || 'change-this-in-production',
  timeZone: process.env.ATTENDANCE_TIMEZONE || 'Asia/Kolkata',
  basePath: '',
}));
app.use('/api/hrms/employees', require('./routes/hrmsEmployees'));
app.use('/api/hrms/dashboard', require('./routes/hrmsDashboard'));
app.use('/api/hrms/approvals', require('./routes/hrmsApprovals'));
app.use('/api/hrms/payroll', require('./routes/hrmsPayroll'));
app.use('/api/hrms/payslips', require('./routes/hrmsPayslips'));
app.use('/api/hrms/tracking', require('./routes/hrmsTracking'));
app.use('/api/hrms/weekly-off-templates', require('./routes/hrmsWeeklyOffTemplates'));
app.use('/api/chat', require('./routes/chat'));

app.get('/', (_req, res) => res.json({ status: 'ok', service: 'GoDigital Attendance API' }));
app.use((_req, res) => res.status(404).json({ success: false, message: 'Route not found' }));
app.use((error, _req, res, _next) => {
  console.error(error);
  res.status(500).json({ success: false, message: 'Internal server error' });
});

async function start() {
  await ensureAttendanceTables(db);
  // A half-day leave must remember which half was approved.  Keeping this
  // migration at startup makes the field available to attendance, payroll,
  // and the employee leave page before the first new leave request is made.
  try {
    await db.query(`ALTER TABLE employee_leaves
      ADD COLUMN half_day_session ENUM('morning','evening') NULL AFTER duration_type`);
  } catch (error) {
    if (!error || error.code !== 'ER_DUP_FIELDNAME') throw error;
  }
  await ensureAuthSchema(db);
  await attendancePolicy.getTimeSettings(db);
  await ensureHrmsEmployeeTables(db);
  await ensureHrmsTrackingTables(db);
  await ensureWeeklyOffTemplateTables(db);
  await ensureMessagingTables(db);
  await payroll.ensureDailyPayrollStorage();

  // The API must become available as soon as its schema is ready. Payroll
  // generation can be slow on a large database, so it must not block every
  // attendance endpoint during server startup.
  server.listen(port, () => console.log(`Attendance API running at http://localhost:${port}`));

  // Run once on startup so a restart after midnight can catch up. The
  // scheduled job below is the normal daily trigger.
  try {
    const result = await closeForgottenCheckouts(db);
    if (result.closed) console.log(`End-of-day auto clock-out closed ${result.closed} attendance session(s).`);
  } catch (error) {
    console.error('End-of-day auto clock-out startup failed:', error.message);
  }
  payroll.runAutomaticPayroll().catch((error) =>
    console.error('Automatic payroll startup failed:', error.message));
  // 00:01 every day in the business timezone. runAutomaticPayroll() checks
  // the policy switch and the last-generated date, so retries are idempotent.
  cron.schedule('1 0 * * *', () => {
    payroll.runAutomaticPayroll().catch((error) =>
      console.error('Automatic payroll update failed:', error.message));
  }, { timezone: process.env.ATTENDANCE_TIMEZONE || 'Asia/Kolkata' });
  // Close yesterday's uncompleted sessions first. The stored checkout time is
  // the employee's configured shift end, never the scheduler time (00:00).
  cron.schedule('0 0 * * *', () => {
    closeForgottenCheckouts(db).then((result) => {
      if (result.closed) console.log(`End-of-day auto clock-out closed ${result.closed} attendance session(s).`);
    }).catch((error) => console.error('End-of-day auto clock-out scheduler failed:', error.message));
  }, { timezone: process.env.ATTENDANCE_TIMEZONE || 'Asia/Kolkata' });
  // Event uniqueness makes this safe across transient scheduler overlap; each
  // employee is isolated so one bad row cannot block the rest of the run.
  setInterval(() => {
    clockOutReminder.processAll(db).catch((error) =>
      console.error('Clock-out reminder scheduler failed:', error.message));
  }, 60 * 1000).unref();
  setInterval(() => {
    attendanceMessaging.process(db, io).catch((error) => console.error('Attendance messaging scheduler failed:', error.message));
  }, 60 * 1000).unref();
  attendanceMessaging.process(db, io).catch((error) => console.error('Attendance messaging startup failed:', error.message));
}

start().catch((error) => {
  console.error('Attendance API could not start:', error.message);
  process.exitCode = 1;
});

module.exports = app;
