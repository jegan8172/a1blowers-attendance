const express = require('express');
const router = express.Router();
const { authenticateToken } = require('./auth');
const hrms = require('../controllers/hrmsPayrollController');

router.use(authenticateToken);
router.use(hrms.requireAdmin);

router.get('/', hrms.list);
router.get('/policy', hrms.getPolicy);
router.put('/policy', hrms.savePolicy);
router.post('/generate', hrms.generate);
router.get('/:profileId/deduction-history', hrms.deductionHistory);
router.put('/:profileId/cycle-override', hrms.saveCycleOverride);
router.patch('/:id', hrms.markPaid);

module.exports = router;
