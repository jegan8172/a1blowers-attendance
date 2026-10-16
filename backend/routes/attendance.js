const express = require('express');
const router = express.Router();
const { authenticateToken } = require('./auth');
const attendance = require('../controllers/attendanceController');

router.use(authenticateToken);
const leavePolicies = require('../controllers/leavePolicies');
router.use('/leave/policies', attendance.requireAdmin);
router.get('/leave/policies', attendance.requireAdmin, leavePolicies.list);
router.put('/leave/policies/:id', attendance.requireAdmin, leavePolicies.save);

// Both portals keep their existing URL.  The signed-in user determines the
// response shape, while both response paths read the same attendance_records.
router.get('/dashboard', function (req, res, next) {
  const userType = String((req.user && req.user.userType) || '').toLowerCase();
  if (userType === 'admin') return attendance.dashboard(req, res, next);
  return attendance.employeeDashboard(req, res, next);
});
router.get('/clock-logs', attendance.requireAdmin, attendance.clockLogs);
router.get('/overtime/my', attendance.myOvertime);
router.get('/overtime/:employeeId/history', attendance.requireAdmin, attendance.overtimeHistory);
router.get('/export', attendance.requireAdmin, attendance.exportCsv);
router.get('/permissions', attendance.requireAdmin, attendance.adminPermissions);
router.patch('/permissions/:id', attendance.requireAdmin, attendance.reviewPermission);

router.get('/me', attendance.myHistory);
router.get('/me/export', attendance.myExport);
router.get('/check-in-policy', attendance.checkInPolicy);
router.post('/check-in', attendance.checkIn);
router.post('/check-out', attendance.checkOut);
router.post('/break-in', attendance.startBreak);
router.post('/break-out', attendance.endBreak);
router.post('/break-exceeded-comment', attendance.submitExceededBreakComment);
router.post('/heartbeat', attendance.heartbeat);
router.post('/auto-clockout-response', attendance.autoClockoutResponse);
router.get('/clock-out-reminder', attendance.clockOutReminderStatus);
router.post('/clock-out-reminder/response', attendance.clockOutReminderResponse);
// Compatibility with the employee module's original API contract.
router.post('/clock-in', attendance.checkIn);
router.post('/clock-out', attendance.checkOut);
router.post('/reclock-in-request', attendance.createReclockInRequest);
router.get('/permissions/mine', attendance.myPermissions);
router.post('/permissions', attendance.createPermission);

module.exports = router;
