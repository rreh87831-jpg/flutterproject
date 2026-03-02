const express = require('express');
const pool = require('../config/database');

const router = express.Router();

router.get('/master', async (req, res) => {
  const result = await pool.query('SELECT * FROM activity_master ORDER BY activity_type, category, activity_name');
  res.json(result.rows);
});

module.exports = router;
