const express = require('express');
const router = express.Router();
const pool = require('../config/database');

router.get('/center/:centerId/week/:startDate', async (req, res) => {
  try {
    const { centerId, startDate } = req.params;

    const query = `
      SELECT aa.*, am.activity_name, am.category, am.description, am.telugu_description, am.duration_minutes,
             json_build_object('id', u.id, 'full_name', u.full_name) as conducted_by_user
      FROM anganwadi_activities aa
      JOIN activity_master am ON aa.activity_id = am.id
      LEFT JOIN users u ON aa.conducted_by = u.id
      WHERE aa.center_id = $1
        AND aa.activity_date BETWEEN $2::date AND ($2::date + interval '6 days')
      ORDER BY aa.activity_date, am.category`;

    let result = await pool.query(query, [centerId, startDate]);

    if (result.rows.length === 0) {
      const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
      const dayActivities = {
        Monday: 'ANG-MON-01', Tuesday: 'ANG-TUE-01', Wednesday: 'ANG-WED-01',
        Thursday: 'ANG-THU-01', Friday: 'ANG-FRI-01', Saturday: 'ANG-SAT-01'
      };

      for (let i = 0; i < days.length; i++) {
        const currentDate = new Date(startDate);
        currentDate.setDate(currentDate.getDate() + i);
        const dateStr = currentDate.toISOString().split('T')[0];
        const activityCode = dayActivities[days[i]];

        await pool.query(
          `INSERT INTO anganwadi_activities (center_id, activity_id, activity_date, day_of_week)
           SELECT $1, id, $2, $3
           FROM activity_master
           WHERE activity_code = $4
             AND NOT EXISTS (
               SELECT 1 FROM anganwadi_activities
               WHERE center_id = $1 AND activity_date = $2 AND activity_id = activity_master.id
             )`,
          [centerId, dateStr, days[i], activityCode]
        );
      }

      result = await pool.query(query, [centerId, startDate]);
    }

    const schedule = {};
    result.rows.forEach((activity) => {
      const date = activity.activity_date;
      if (!schedule[date]) {
        schedule[date] = { date, day: activity.day_of_week, activities: [] };
      }
      schedule[date].activities.push(activity);
    });

    res.json(Object.values(schedule));
  } catch (error) {
    console.error('Error fetching anganwadi schedule:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/activity/:activityId/conduct', async (req, res) => {
  try {
    const { activityId } = req.params;
    const { children_present, start_time, end_time, notes, materials_used } = req.body;
    const workerId = req.user.id;

    const result = await pool.query(
      `UPDATE anganwadi_activities
       SET conducted = true,
           conducted_by = $1,
           children_present = COALESCE($2, children_present),
           start_time = COALESCE($3, start_time),
           end_time = COALESCE($4, end_time),
           notes = COALESCE($5, notes),
           materials_used = COALESCE($6, materials_used),
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $7
       RETURNING *`,
      [workerId, children_present, start_time, end_time, notes, materials_used, activityId]
    );

    if (result.rows.length === 0) return res.status(404).json({ error: 'Activity not found' });

    res.json({ message: 'Activity marked as conducted', activity: result.rows[0] });
  } catch (error) {
    console.error('Error conducting activity:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/center/:centerId/holiday', async (req, res) => {
  try {
    const { centerId } = req.params;
    const { date, reason } = req.body;

    const result = await pool.query(
      `UPDATE anganwadi_activities
       SET is_holiday = true,
           notes = CONCAT(COALESCE(notes, ''), ' HOLIDAY: ', $3),
           updated_at = CURRENT_TIMESTAMP
       WHERE center_id = $1 AND activity_date = $2
       RETURNING *`,
      [centerId, date, reason || 'No reason']
    );

    res.json({ message: 'Day marked as holiday', updated_activities: result.rows.length });
  } catch (error) {
    console.error('Error marking holiday:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
