const express = require('express');
const router = express.Router();
const { authenticateToken } = require('./auth');
const hrms = require('../controllers/hrmsDashboardController');

router.use(authenticateToken);
router.use(hrms.requireAdmin);

router.get('/time-settings', hrms.timeSettings);
router.put('/time-settings', hrms.updateTimeSettings);
router.get('/calendar-overrides', hrms.calendarOverrides);
router.put('/calendar-overrides', hrms.saveCalendarOverride);
router.get('/', hrms.monthView);

module.exports = router;
