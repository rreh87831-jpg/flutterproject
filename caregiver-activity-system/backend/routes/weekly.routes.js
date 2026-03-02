const express = require('express');
const router = express.Router();
const pool = require('../config/database');

function getCurrentWeekRange() {
  const today = new Date();
  const day = today.getDay();
  const monday = new Date(today);
  monday.setHours(0, 0, 0, 0);
  monday.setDate(today.getDate() - (day === 0 ? 6 : day - 1));
  const sunday = new Date(monday);
  sunday.setDate(monday.getDate() + 6);
  return { monday: monday.toISOString().split('T')[0], sunday: sunday.toISOString().split('T')[0] };
}

router.get('/child/:childId/current-week', async (req, res) => {
  try {
    const { childId } = req.params;
    const { monday, sunday } = getCurrentWeekRange();

    const query = `
      SELECT wa.*, am.activity_name, am.category,
             json_build_object('id', u1.id, 'full_name', u1.full_name) as caregiver,
             json_build_object('id', u2.id, 'full_name', u2.full_name) as worker
      FROM weekly_activities wa
      JOIN activity_master am ON wa.activity_id = am.id
      LEFT JOIN users u1 ON wa.caregiver_id = u1.id
      LEFT JOIN users u2 ON wa.worker_id = u2.id
      WHERE wa.child_id = $1 AND wa.week_start_date = $2 AND wa.week_end_date = $3`;

    let result = await pool.query(query, [childId, monday, sunday]);

    if (result.rows.length === 0) {
      const activities = await pool.query("SELECT id FROM activity_master WHERE activity_type = 'weekly' ORDER BY category");
      for (const activity of activities.rows) {
        await pool.query(
          `INSERT INTO weekly_activities (child_id, activity_id, week_start_date, week_end_date)
           VALUES ($1, $2, $3, $4)`,
          [childId, activity.id, monday, sunday]
        );
      }
      result = await pool.query(query, [childId, monday, sunday]);
    }

    const weeklyPlan = {
      week_start: monday,
      week_end: sunday,
      planning: result.rows.find(r => r.category === 'Planning'),
      home_visit: result.rows.find(r => r.category === 'Review' && (r.activity_name || '').includes('Home')),
      group_activity: result.rows.find(r => r.category === 'Group'),
      review: result.rows.find(r => r.category === 'Review' && (r.activity_name || '').includes('Weekly')),
      all_activities: result.rows,
    };

    res.json(weeklyPlan);
  } catch (error) {
    console.error('Error fetching weekly activities:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/:weeklyId/:component', async (req, res) => {
  try {
    const { weeklyId, component } = req.params;
    const { notes, progress } = req.body;

    let updateQuery;
    let values;

    switch (component) {
      case 'planning':
        updateQuery = `UPDATE weekly_activities SET planning_completed = true, planning_date = CURRENT_DATE, updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING *`;
        values = [weeklyId];
        break;
      case 'home-visit':
        updateQuery = `UPDATE weekly_activities SET home_visit_completed = true, home_visit_date = CURRENT_DATE, home_visit_notes = COALESCE($2, home_visit_notes), updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING *`;
        values = [weeklyId, notes];
        break;
      case 'group-activity':
        updateQuery = `UPDATE weekly_activities SET group_activity_completed = true, group_activity_date = CURRENT_DATE, updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING *`;
        values = [weeklyId];
        break;
      case 'review':
        updateQuery = `UPDATE weekly_activities SET review_completed = true, review_date = CURRENT_DATE, review_notes = COALESCE($2, review_notes), overall_progress = COALESCE($3, overall_progress), updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING *`;
        values = [weeklyId, notes, progress];
        break;
      default:
        return res.status(400).json({ error: 'Invalid component' });
    }

    const result = await pool.query(updateQuery, values);
    if (result.rows.length === 0) return res.status(404).json({ error: 'Weekly activity not found' });

    res.json({ message: `${component} updated successfully`, activity: result.rows[0] });
  } catch (error) {
    console.error('Error updating weekly activity:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
