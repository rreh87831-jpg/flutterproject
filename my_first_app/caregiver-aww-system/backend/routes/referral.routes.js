const express = require('express');
const router = express.Router();
const pool = require('../config/database');

router.get('/:referralNumber', async (req, res) => {
  try {
    const { referralNumber } = req.params;
    const result = await pool.query(
      `SELECT r.referral_number, r.facility, r.urgency,
              TO_CHAR(r.referral_deadline, 'DD/MM/YYYY') AS referral_deadline,
              TO_CHAR(r.follow_up_end_date, 'DD/MM/YYYY') AS follow_up_end_date,
              r.review_frequency, r.total_activities, r.completed_activities,
              r.progress_percentage, (r.referral_deadline - CURRENT_DATE) AS days_remaining,
              c.full_name AS child_name, u.full_name AS caregiver_name
         FROM referrals r
         JOIN children c ON r.child_id = c.id
         JOIN users u ON c.caregiver_id = u.id
        WHERE r.referral_number = $1`,
      [referralNumber],
    );

    if (result.rows.length === 0) return res.status(404).json({ error: 'Referral not found' });
    res.json(result.rows[0]);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/:referralNumber/progress', async (req, res) => {
  try {
    const { referralNumber } = req.params;
    const result = await pool.query(
      `SELECT pt.progress_percentage, pt.completed_activities, pt.total_activities, pt.last_updated
         FROM progress_tracking pt
         JOIN referrals r ON pt.referral_id = r.id
        WHERE r.referral_number = $1`,
      [referralNumber],
    );
    res.json(result.rows[0] || { progress_percentage: 3.0, completed_activities: 1, total_activities: 32 });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
