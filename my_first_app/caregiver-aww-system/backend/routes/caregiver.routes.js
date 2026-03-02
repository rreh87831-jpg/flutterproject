const express = require('express');
const router = express.Router();
const pool = require('../config/database');

router.get('/:referralNumber/activities', async (req, res) => {
  try {
    const { referralNumber } = req.params;
    const result = await pool.query(
      `SELECT ca.id, am.activity_type, am.level_number, am.telugu_description,
              ca.completed, ca.completion_percentage, ca.status,
              TO_CHAR(ca.deadline_date, 'DD/MM/YYYY') AS deadline_date
         FROM caregiver_activities ca
         JOIN activity_master am ON ca.activity_id = am.id
        WHERE ca.referral_id = (SELECT id FROM referrals WHERE referral_number = $1)
          AND am.assigned_to = 'CAREGIVER'
        ORDER BY am.activity_type, am.level_number`,
      [referralNumber],
    );

    res.json({
      GM: result.rows.filter((r) => r.activity_type === 'GM'),
      LC: result.rows.filter((r) => r.activity_type === 'LC'),
      COG: result.rows.filter((r) => r.activity_type === 'COG'),
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/activity/:activityId/complete', async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { activityId } = req.params;

    const result = await client.query(
      `UPDATE caregiver_activities
          SET completed = true,
              completion_date = CURRENT_DATE,
              completion_percentage = 100,
              status = 'completed',
              updated_at = CURRENT_TIMESTAMP
        WHERE id = $1
      RETURNING *`,
      [activityId],
    );

    if (result.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Activity not found' });
    }

    await client.query('COMMIT');
    res.json({ message: 'Activity marked as completed', activity: result.rows[0] });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error(error);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

module.exports = router;
