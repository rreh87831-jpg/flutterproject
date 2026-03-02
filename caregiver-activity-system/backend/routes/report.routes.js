const express = require('express');
const pool = require('../config/database');

const router = express.Router();

router.get('/daily-progress', async (req, res) => {
  const result = await pool.query('SELECT * FROM vw_daily_progress ORDER BY activity_date DESC LIMIT 200');
  res.json(result.rows);
});

router.get('/weekly-summary', async (req, res) => {
  const result = await pool.query('SELECT * FROM vw_weekly_summary ORDER BY week_start_date DESC LIMIT 200');
  res.json(result.rows);
});

module.exports = router;
