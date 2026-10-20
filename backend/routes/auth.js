// routes/auth.js — CORRECTED VERSION with proper bcrypt

const express = require('express');
const router = express.Router();
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const db = require('../config/db'); 

const JWT_SECRET = process.env.JWT_SECRET || 'change-this-in-production-to-random-key';
const JWT_EXPIRY = '7d';

async function ensureDeviceTables() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_registered_devices (
    employee_user_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    device_hash CHAR(64) NOT NULL,
    device_label VARCHAR(180) NOT NULL DEFAULT 'Registered browser',
    registered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY device_hash (device_hash)
  )`);
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_device_change_requests (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    employee_user_id BIGINT UNSIGNED NOT NULL,
    proposed_device_hash CHAR(64) NOT NULL,
    proposed_device_label VARCHAR(180) NOT NULL DEFAULT 'New browser',
    reason VARCHAR(500) NULL,
    status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
    requested_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMP NULL,
    reviewed_by BIGINT UNSIGNED NULL,
    review_note VARCHAR(500) NULL,
    KEY device_request_status (status, requested_at),
    KEY device_request_employee (employee_user_id)
  )`);
}

async function ensureActiveSessionsTable() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_active_sessions (
    employee_user_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    session_id CHAR(64) NOT NULL,
    device_hash CHAR(64) NULL,
    device_label VARCHAR(180) NOT NULL DEFAULT 'Unknown device',
    signed_in_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY session_id (session_id)
  )`);
}

async function ensurePasswordAuditTable() {
  await db.query(`CREATE TABLE IF NOT EXISTS hrms_password_change_log (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    employee_user_id BIGINT UNSIGNED NOT NULL,
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(30) NOT NULL DEFAULT 'employee',
    KEY password_changed_employee (employee_user_id, changed_at)
  )`);
}

function deviceHash(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex');
}

// ⭐ POST /api/auth/login — FIXED: Uses bcrypt for password verification ⭐
router.post('/login', async (req, res) => {
  const { email, password, userType, deviceId, deviceLabel, deviceChangeReason } = req.body;

  if (!email || !password) {
    return res.status(400).json({
      success: false,
      message: 'Email and password are required',
    });
  }

  try {
    // Query employee_users table
    // const [rows] = await db.query(
    //   `SELECT id, first_name, last_name, full_name, email, username, 
    //           password, role, user_type, is_active, staff_id, initials
    //    FROM employee_users 
    //    WHERE (email = ? OR username = ?) AND user_type = ?
    //    LIMIT 1`,
    //   [email, email, userType || 'employee']
    // );
    const [rows] = await db.query(
`
SELECT id, first_name, last_name, full_name,
email, username, password,
role, user_type, is_active, is_main_admin,
staff_id, initials
FROM employee_users
WHERE (
LOWER(email) = LOWER(?)
OR LOWER(username) = LOWER(?)
)
AND LOWER(user_type) = LOWER(?)
LIMIT 1
`,
[email, email, userType || 'employee']
);

    // if (rows.length === 0) {
    //   console.log(`❌ Login failed: No user found with email "${email}"`);
    //   return res.status(401).json({
    //     success: false,
    //     message: 'Invalid email or password',
    //   });
    // }

    if (rows.length === 0) {
  console.log(`❌ Login failed: No user found with "${email}"`);
  return res.status(401).json({
    success: false,
    message: 'Username or email not found.',
  });
}

    const user = rows[0];
    console.log(`📌 User found: ${user.full_name} (${user.role})`);

    // Check if user is active
    if (!user.is_active) {
      console.log(`❌ Login failed: User "${user.full_name}" is inactive`);
      return res.status(403).json({
        success: false,
        message: 'Your account has been deactivated. Contact admin.',
      });
    }

    // Employee creation stores bcrypt hashes; compare the submitted password
    // against that hash instead of comparing plaintext strings.
    const storedPassword = String(user.password || '');
    const passwordMatch = storedPassword.startsWith('$2')
      ? await bcrypt.compare(String(password), storedPassword)
      : String(password) === storedPassword;

    // if (!passwordMatch) {
    //   console.log(`❌ Login failed: Invalid password for "${email}"`);
    //   return res.status(401).json({
    //     success: false,
    //     message: 'Invalid email or password',
    //   });
    // }

    if (!passwordMatch) {
  console.log(`❌ Login failed: Incorrect password for "${email}"`);
  return res.status(401).json({
    success: false,
    message: 'Incorrect password.',
  });
}

    // Browser/device IDs are random installation IDs generated by the app.
    // A new login replaces the active session below, which signs out the old
    // device. Browsers deliberately cannot expose a MAC address.
    if (String(user.user_type).toLowerCase() === 'employee') {
      if (!deviceId || String(deviceId).length < 16) {
        return res.status(400).json({ success: false, message: 'This browser could not be registered. Please refresh and try again.' });
      }
      await ensureDeviceTables();
      const hash = deviceHash(deviceId);
      const label = String(deviceLabel || 'Registered browser').slice(0, 180);
      const [registered] = await db.query('SELECT device_hash FROM hrms_registered_devices WHERE employee_user_id = ? LIMIT 1', [user.id]);
      if (!registered.length) {
        await db.query('INSERT INTO hrms_registered_devices (employee_user_id, device_hash, device_label) VALUES (?, ?, ?)', [user.id, hash, label]);
      } else {
        await db.query('UPDATE hrms_registered_devices SET device_hash = ?, device_label = ?, last_seen_at = CURRENT_TIMESTAMP WHERE employee_user_id = ?', [hash, label, user.id]);
      }
    }

    await ensureActiveSessionsTable();
    const sessionId = crypto.randomBytes(32).toString('hex');
    const activeDeviceHash = deviceId ? deviceHash(deviceId) : null;
    const activeDeviceLabel = String(deviceLabel || 'Unknown device').slice(0, 180);
    await db.query(
      `INSERT INTO hrms_active_sessions (employee_user_id, session_id, device_hash, device_label)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE session_id = VALUES(session_id), device_hash = VALUES(device_hash),
         device_label = VALUES(device_label), signed_in_at = CURRENT_TIMESTAMP, last_seen_at = CURRENT_TIMESTAMP`,
      [user.id, sessionId, activeDeviceHash, activeDeviceLabel]
    );

// Password check pannuthuku apram intha query-a podunga:
const [accessRows] = await db.query(
  `SELECT allowed_pages FROM role_page_access WHERE employee_id = ?`,
  [user.id]
);

const allowedPages = accessRows.length > 0 
  ? JSON.parse(accessRows[0].allowed_pages || '[]') 
  : [];

    // Generate JWT token
    const token = jwt.sign(
      {
        id: user.id,
        fullName: user.full_name,
        email: user.email,
        role: user.role,
        userType: user.user_type,
        sessionId: sessionId,
      },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );

    console.log(`✅ Login successful: ${user.full_name} (${user.role})`);

    // Return success response
    return res.json({
      success: true,
      message: 'Login successful',
      token: token,
      user: {
        id: user.id,
        firstName: user.first_name,
        lastName: user.last_name,
        fullName: user.full_name,
        email: user.email,
        username: user.username,
        role: user.role,
        userType: user.user_type,
        staffId: user.staff_id,
        initials: user.initials,
        isMainAdmin: user.is_main_admin == 1 || user.is_main_admin === true, // 🟢 itha add pannunga
  allowed_pages: allowedPages, // 🟢 itha add pannunga

      },
    });
  } catch (err) {
    console.error('❌ POST /auth/login ERROR:', err.message);
    return res.status(500).json({
      success: false,
      message: 'Server error during login',
    });
  }
});

// POST /api/auth/logout
router.post('/logout', authenticateToken, async (req, res) => {
  try {
    await ensureActiveSessionsTable();
    await db.query('DELETE FROM hrms_active_sessions WHERE employee_user_id = ? AND session_id = ?', [req.user.id, req.user.sessionId]);
    return res.json({ success: true, message: 'Logout successful' });
  } catch (error) {
    return res.status(500).json({ success: false, message: 'Unable to log out' });
  }
});

// The signed-in employee can replace their password only after confirming the
// existing one. Password values are never returned or stored as readable text.
router.post('/change-password', authenticateToken, async (req, res) => {
  const username = String((req.body && req.body.username) || '').trim();
  const newUsername = String((req.body && req.body.newUsername) || '').trim();
  const currentPassword = String((req.body && req.body.currentPassword) || '');
  const newPassword = String((req.body && req.body.newPassword) || '');
    if (!username || !currentPassword || (!newUsername && !newPassword)) {
    return res.status(400).json({ success: false, message: 'Current username and password, plus a new username or password, are required.' });
  }
  try {
    const [rows] = await db.query('SELECT id, username, password FROM employee_users WHERE id = ? LIMIT 1', [req.user.id]);
    const account = rows[0];
    if (!account || String(account.username || '').toLowerCase() !== username.toLowerCase()) {
      return res.status(400).json({ success: false, message: 'Username does not match your account.' });
    }
    const stored = String(account.password || '');
    const valid = stored.startsWith('$2') ? await bcrypt.compare(currentPassword, stored) : currentPassword === stored;
    if (!valid) return res.status(400).json({ success: false, message: 'Current password is incorrect.' });
    if (newPassword && newPassword.length < 8) return res.status(400).json({ success: false, message: 'New password must have at least 8 characters.' });
    if (newPassword && currentPassword === newPassword) return res.status(400).json({ success: false, message: 'New password must be different from the current password.' });
    const updates = [];
    const values = [];
    if (newUsername && newUsername.toLowerCase() !== username.toLowerCase()) { updates.push('username = ?'); values.push(newUsername); }
    if (newPassword) { updates.push('password = ?'); values.push(await bcrypt.hash(newPassword, 10)); }
    if (!updates.length) return res.status(400).json({ success: false, message: 'Enter a different username or a new password.' });
    values.push(account.id);
    await db.query('UPDATE employee_users SET ' + updates.join(', ') + ' WHERE id = ?', values);
    await ensurePasswordAuditTable();
    await db.query("INSERT INTO hrms_password_change_log (employee_user_id, changed_by) VALUES (?, 'employee')", [account.id]);
    return res.json({ success: true, message: 'Account credentials updated successfully.' });
  } catch (err) {
    return res.status(500).json({ success: false, message: 'Unable to update password.' });
  }
});

// GET /api/auth/verify — Verify JWT token
router.get('/verify', authenticateToken, (req, res) => {
  return res.json({
    success: true,
    message: 'Token is valid',
    user: req.user,
  });
});

// Read the signed-in employee's current profile from employee_users.
router.get('/me', authenticateToken, (req, res) => {
  return res.json({
    success: true,
    data: {
      id: req.user.id,
      fullName: req.user.fullName,
      staffId: req.user.staffId,
      email: req.user.email,
      role: req.user.role,
      userType: req.user.userType,
    },
  });
});

// POST /api/auth/refresh — Refresh JWT token
router.post('/refresh', authenticateToken, (req, res) => {
  const newToken = jwt.sign(
    {
      id: req.user.id,
      email: req.user.email,
      role: req.user.role,
      userType: req.user.userType,
      sessionId: req.user.sessionId,
    },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRY }
  );

  return res.json({
    success: true,
    message: 'Token refreshed',
    token: newToken,
  });
});

// ⭐ Middleware to authenticate JWT token ⭐
function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({
      success: false,
      message: 'Access token required',
    });
  }

  jwt.verify(token, JWT_SECRET, async (err, user) => {
    if (err) {
      if (err.name === 'TokenExpiredError') {
        return res.status(401).json({
          success: false,
          message: 'Token has expired',
        });
      }
      return res.status(403).json({
        success: false,
        message: 'Invalid token',
      });
    }

    try {
      const [[account]] = await db.query('SELECT id, full_name, staff_id, email, role, user_type, is_active FROM employee_users WHERE id = ?', [user.id]);
      if (!account || !Number(account.is_active)) {
        return res.status(401).json({ success: false, message: 'Employee account is unavailable. Please sign in again.' });
      }
      await ensureActiveSessionsTable();
      const [[session]] = await db.query('SELECT session_id FROM hrms_active_sessions WHERE employee_user_id = ?', [account.id]);
      if (!session || !user.sessionId || session.session_id !== user.sessionId) {
        return res.status(401).json({ success: false, code: 'SESSION_REPLACED', message: 'You were signed out because this account signed in on another device.' });
      }
      req.user = { ...user, id: account.id, fullName: account.full_name, staffId: account.staff_id,
        email: account.email, role: account.role, userType: account.user_type };
      next();
    } catch (error) {
      return res.status(503).json({ success: false, message: 'Unable to verify employee account' });
    }
  });
}

module.exports = router;
module.exports.authenticateToken = authenticateToken;
// Shared so every auth layer verifies against the exact key login signs with.
module.exports.JWT_SECRET = JWT_SECRET;
