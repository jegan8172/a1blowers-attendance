const express = require('express');
const router = express.Router();
const { authenticateToken } = require('./auth');
const hrms = require('../controllers/hrmsTrackingController');

router.use(authenticateToken);
router.get('/settings', hrms.getTrackingSettings);
router.put('/settings', hrms.requireAdmin, hrms.updateTrackingSettings);

// Employee self-service — called from the mobile app
router.post('/status', hrms.setStatus);
router.post('/ping', hrms.ping);
router.post('/comments', hrms.addTrackingComment);
router.get('/comments', hrms.myTrackingComments);
router.get('/admin-comments', hrms.requireAdmin, hrms.adminTrackingComments);

// Admin dashboard views
router.get('/', hrms.requireAdmin, hrms.list);
router.get('/live', hrms.requireAdmin, hrms.liveOverview);
router.get('/route/my/history', hrms.myRouteHistoryList);
router.get('/route/my', hrms.myRouteHistory);
router.post('/route/:employeeUserId/invalidate', hrms.requireAdmin, hrms.invalidateRoute);
router.get('/route/:employeeUserId', hrms.requireAdmin, hrms.routeHistory);

router.get('/home-location', hrms.getMyHomeLocation);
router.post('/home-location', hrms.submitHomeLocation);

router.get('/home-locations', hrms.requireAdmin, hrms.listHomeLocations);
router.patch(
  '/home-locations/:employeeUserId',
  hrms.requireAdmin,
  hrms.reviewHomeLocation
);
router.get('/field-waiting-alert', hrms.getMyWaitingAlert);
router.post(
  '/field-waiting-reasons/:id',
  hrms.submitWaitingReason
);
router.get('/my-field-waiting-reasons', hrms.myFieldWaitingReasons);

router.get(
  '/field-waiting-reasons',
  hrms.requireAdmin,
  hrms.listFieldWaitingReasons
);

router.patch(
  '/field-waiting-reasons/:id/review',
  hrms.requireAdmin,
  hrms.reviewFieldWaitingReason
);

router.get('/permissions', hrms.getTrackingPermissions);
router.get('/field-session/summary', hrms.getFieldSessionSummary);
router.get('/field-session/timeline', hrms.getFieldSessionTimeline);
router.get('/field-session', hrms.getMyFieldSession);
router.post('/field-session/start', hrms.startFieldTracking);
router.post('/field-session/stop', hrms.stopFieldTracking);

module.exports = router;
