// const mysql = require('mysql2');
// require('dotenv').config();

// const pool = mysql.createPool({
//   host: process.env.DB_HOST || 'localhost',
//   user: process.env.DB_USER || 'root',
//   password: process.env.DB_PASSWORD || '',
//   database: process.env.DB_NAME || 'godigital_db',
//   waitForConnections: true,
//   connectionLimit: 10
// });

// module.exports = pool.promise();

// const mysql = require('mysql2/promise');

// const pool = mysql.createPool({
//   host:               'localhost',
//   port:               3306,
//   user:               'root',
//   password:           '',       
//   database:           'godigital_db',
//   waitForConnections: true,
//   connectionLimit:    10,
//   queueLimit:         0,
// });

// module.exports = pool;

// const mysql = require('mysql2');
// require('dotenv').config();

// const pool = mysql.createPool({
//   host: process.env.DB_HOST || 'localhost',
//   user: process.env.DB_USER || 'root',
//   password: process.env.DB_PASSWORD || '',
//   database: process.env.DB_NAME || 'godigital_db',
//   waitForConnections: true,
//   connectionLimit: 10
// });

// module.exports = pool.promise();

const mysql = require('mysql2/promise');
require('dotenv').config();

const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  port: 3306,
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'godigital_attendance',

  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

pool.getConnection()
  .then(connection => {
    console.log('✅ Database pool created successfully');
    connection.release();
  })
  .catch(err => {
    console.error('❌ Database pool error:', err.message);
  });

module.exports = pool;
