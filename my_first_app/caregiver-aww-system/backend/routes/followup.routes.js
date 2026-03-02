const express = require('express');
const router = express.Router();
const pool = require('../config/database');

router.get('/:referralNumber/plan', async (req, res) => {
  try {
    const { referralNumber } = req.params;
    const result = await pool.query(
      `SELECT fp.id,
              TO_CHAR(fp.followup_date, 'DD/MM/YYYY') AS followup_date,
              fp.level_number,
              fp.completed,
              fp.marked_as_completed,
              CASE
                WHEN fp.followup_date = CURRENT_DATE THEN 'Today'
                WHEN fp.followup_date > CURRENT_DATE THEN 'Upcoming'
                ELSE 'Overdue'
              END AS status
         FROM followup_plan fp
        WHERE fp.referral_id = (SELECT id FROM referrals WHERE referral_number = $1)
        ORDER BY fp.followup_date`,
      [referralNumber],
    );

    res.json({
      today: result.rows.filter((r) => r.status === 'Today'),
      upcoming: result.rows.filter((r) => r.status === 'Upcoming'),
      overdue: result.rows.filter((r) => r.status === 'Overdue'),
      completed: result.rows.filter((r) => r.completed),
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/:followupId/complete', async (req, res) => {
  try {
    const { followupId } = req.params;
    const result = await pool.query(
      `UPDATE followup_plan
          SET completed = true,
              marked_as_completed = true,
              completion_time = CURRENT_TIMESTAMP
        WHERE id = $1
      RETURNING *`,
      [followupId],
    );

    if (result.rows.length === 0) return res.status(404).json({ error: 'Follow-up not found' });
    res.json({ message: 'Follow-up marked as completed', followup: result.rows[0] });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/:referralNumber/timeline', async (req, res) => {
  try {
    const { referralNumber } = req.params;
    const result = await pool.query(
      `WITH referral_info AS (
         SELECT referral_deadline, follow_up_end_date
           FROM referrals
          WHERE referral_number = $1
       )
       SELECT * FROM (
         SELECT 'Referral Deadline' AS event,
                TO_CHAR(referral_deadline, 'DD/MM/YYYY') AS date,
                CASE
                  WHEN referral_deadline < CURRENT_DATE THEN 'Overdue'
                  WHEN referral_deadline = CURRENT_DATE THEN 'Today'
                  ELSE 'Upcoming'
                END AS status,
                (referral_deadline - CURRENT_DATE) || ' days remaining' AS details,
                referral_deadline AS sort_date
           FROM referral_info
         UNION ALL
         SELECT 'Follow-Up End' AS event,
                TO_CHAR(follow_up_end_date, 'DD/MM/YYYY') AS date,
                CASE
                  WHEN follow_up_end_date < CURRENT_DATE THEN 'Completed'
                  WHEN follow_up_end_date = CURRENT_DATE THEN 'Today'
                  ELSE 'Upcoming'
                END AS status,
                (follow_up_end_date - CURRENT_DATE) || ' days left' AS details,
                follow_up_end_date AS sort_date
           FROM referral_info
       ) t
       ORDER BY sort_date`,
      [referralNumber],
    );

    res.json(result.rows.map(({ sort_date, ...rest }) => rest));
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
