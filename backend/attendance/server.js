'use strict';

const path = require('node:path');
require('dotenv').config({ path: path.join(__dirname, '..', '..', '.env') });
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const mysql = require('mysql2/promise');
const { createApp } = require('./app');

const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'godigital_db',
  timezone: 'Z',
  dateStrings: true,
  connectionLimit: 5,
});

const app = createApp({
  pool,
  jwtSecret: process.env.JWT_SECRET || 'your_fallback_secret_key_here',
  timeZone: process.env.ATTENDANCE_TIMEZONE || 'Asia/Kolkata',
});

const port = Number(process.env.ATTENDANCE_PORT || 3101);
const server = app.listen(port, '0.0.0.0', () => {
  console.log(`✅ Attendance service successfully listening on port ${port}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(async () => { await pool.end(); }));
}