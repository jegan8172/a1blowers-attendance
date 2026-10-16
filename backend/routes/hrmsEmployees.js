const express = require('express');
const router = express.Router();
const { authenticateToken } = require('./auth');
const hrms = require('../controllers/hrmsEmployeesController');

router.use(authenticateToken);
router.use(hrms.requireAdmin);

router.get('/summary', hrms.summary);
router.get('/export', hrms.exportCsv);
router.get('/device-requests', hrms.deviceRequests);
router.post('/device-requests/:id/review', hrms.reviewDeviceRequest);
router.get('/', hrms.list);
router.get('/:id', hrms.detail);
router.post('/', hrms.create);
router.post('/:id/password-reset', hrms.resetPassword);
router.put('/:id', hrms.update);
router.patch('/:id/status', hrms.updateStatus);
router.delete('/:id', hrms.remove);

module.exports = router;
