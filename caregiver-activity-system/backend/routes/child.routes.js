const express = require('express');
const pool = require('../config/database');

const router = express.Router();

router.get('/', async (req, res) => {
  const result = await pool.query('SELECT * FROM children ORDER BY created_at DESC');
  res.json(result.rows);
});

router.post('/', async (req, res) => {
  const { child_code, full_name, date_of_birth, caregiver_id, aanganwadi_center_id } = req.body;
  const result = await pool.query(
    `INSERT INTO children (child_code, full_name, date_of_birth, caregiver_id, aanganwadi_center_id)
     VALUES ($1,$2,$3,$4,$5) RETURNING *`,
    [child_code, full_name, date_of_birth, caregiver_id, aanganwadi_center_id]
  );
  res.status(201).json(result.rows[0]);
});

module.exports = router;
