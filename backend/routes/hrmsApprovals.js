const express = require('express');
const router = express.Router();
const { authenticateToken } = require('./auth');
const hrms = require('../controllers/hrmsApprovalsController');

router.use(authenticateToken);
router.use(hrms.requireAdmin);

router.get('/notifications', hrms.notifications);
router.patch('/notifications/read-all', hrms.markAllNotificationsRead);
router.get('/', hrms.list);
router.patch('/:id', hrms.review);

module.exports = router;
