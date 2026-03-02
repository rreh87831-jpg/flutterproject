const express = require('express');
const router = express.Router();
const pool = require('../config/database');

router.get('/:referralNumber/activities', async (req, res) => {
  try {
    const { referralNumber } = req.params;
    const result = await pool.query(
      `SELECT aa.id, am.activity_type, am.level_number, am.telugu_description,
              TO_CHAR(aa.monitoring_date, 'DD/MM/YYYY') AS monitoring_date,
              aa.monitored, aa.escalation_required, aa.ok_status, aa.marked_monitored
         FROM aww_activities aa
         JOIN activity_master am ON aa.activity_id = am.id
        WHERE aa.referral_id = (SELECT id FROM referrals WHERE referral_number = $1)
          AND am.assigned_to = 'AWW'
        ORDER BY am.level_number`,
      [referralNumber],
    );
    res.json(result.rows);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/activity/:activityId/monitor', async (req, res) => {
  try {
    const { activityId } = req.params;
    const { escalation_required, ok_status } = req.body;

    const result = await pool.query(
      `UPDATE aww_activities
          SET monitored = true,
              marked_monitored = true,
              escalation_required = COALESCE($1, escalation_required),
              ok_status = COALESCE($2, ok_status),
              updated_at = CURRENT_TIMESTAMP
        WHERE id = $3
      RETURNING *`,
      [escalation_required, ok_status, activityId],
    );

    if (result.rows.length === 0) return res.status(404).json({ error: 'Activity not found' });
    res.json({ message: 'Activity marked as monitored', activity: result.rows[0] });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
