'use strict';

const mysql = require('mysql2/promise');
const { createApp } = require('./app');

// Attendance needs UTC DATETIME handling independently of other modules.
const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'godigital_db',
  timezone: 'Z', dateStrings: true, connectionLimit: 5,
});

module.exports = createApp({
  pool, jwtSecret: process.env.JWT_SECRET,
  timeZone: process.env.ATTENDANCE_TIMEZONE || 'Asia/Kolkata', basePath: '',
});
