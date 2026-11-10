const db = require('../config/db');

exports.createEmployee = async (req, res) => {
    const { fullName, staffId, role, email, username, password } = req.body;
    try {
        const query = `INSERT INTO employees (full_name, staff_id, role, email, username, password) VALUES (?, ?, ?, ?, ?, ?)`;
        const [result] = await db.execute(query, [fullName, staffId, role, email, username, password]);
        
        res.status(201).json({ message: "Employee saved!", id: result.insertId });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
};

exports.getEmployees = async (req, res) => {
    try {
        const [rows] = await db.query('SELECT * FROM employees');
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
};