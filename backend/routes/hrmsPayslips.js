const express = require('express');
const { authenticateToken } = require('./auth');
const controller = require('../controllers/hrmsPayslipController');
const router = express.Router();
router.use(authenticateToken);
router.param('payrollId', async (req, res, next, value) => {
  try {
    const db = require('../config/db');
    const [[row]] = await db.query(`SELECT p.id FROM hrms_payroll_items p
      JOIN hrms_employee_profiles e ON e.id = p.profile_id AND e.employee_user_id = p.employee_user_id
      WHERE p.id = ? AND p.employee_user_id = ? AND p.status = 'paid' AND p.monthly_salary > 0`, [value, req.user.id]);
    if (!row) return res.status(404).json({ success: false, message: 'Verified paid payroll not found' });
    next();
  } catch (error) { next(error); }
});
router.get('/my', controller.mine);
router.get('/my/summary', controller.summary);
router.get('/my/deduction-history', controller.myDeductionHistory);
router.post('/:payrollId/request', controller.request);
router.get('/:payrollId/download', controller.download);
router.get('/admin/compensation', controller.requireAdmin, controller.compensationList);
router.post('/admin/compensation', controller.requireAdmin, controller.saveCompensation);
module.exports = router;
