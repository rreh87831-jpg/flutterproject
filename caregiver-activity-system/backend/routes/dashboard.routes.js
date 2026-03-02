const express = require('express');
const router = express.Router();
const pool = require('../config/database');

router.get('/caregiver/:caregiverId', async (req, res) => {
  try {
    const { caregiverId } = req.params;

    const children = await pool.query(
      `SELECT id, child_code, full_name, date_of_birth
       FROM children
       WHERE caregiver_id = $1 AND is_active = true`,
      [caregiverId]
    );

    const dashboard = {
      caregiver_id: caregiverId,
      children: [],
      today_summary: { total_activities: 0, completed: 0, pending: 0 },
      weekly_progress: [],
      notifications: [],
    };

    for (const child of children.rows) {
      const today = await pool.query(
        `SELECT COUNT(*)::int as total,
                COUNT(CASE WHEN completed THEN 1 END)::int as completed
         FROM daily_activities
         WHERE child_id = $1 AND activity_date = CURRENT_DATE`,
        [child.id]
      );

      const week = await pool.query(
        `SELECT activity_date,
                COUNT(CASE WHEN completed THEN 1 END)::int as completed_count,
                COUNT(*)::int as total_count
         FROM daily_activities
         WHERE child_id = $1 AND activity_date >= CURRENT_DATE - INTERVAL '7 days'
         GROUP BY activity_date
         ORDER BY activity_date DESC`,
        [child.id]
      );

      dashboard.children.push({ ...child, today: today.rows[0], week: week.rows });
      dashboard.today_summary.total_activities += today.rows[0]?.total || 0;
      dashboard.today_summary.completed += today.rows[0]?.completed || 0;
    }

    dashboard.today_summary.pending =
      dashboard.today_summary.total_activities - dashboard.today_summary.completed;

    const notifications = await pool.query(
      `SELECT * FROM notifications
       WHERE user_id = $1 AND is_read = false
       ORDER BY created_at DESC
       LIMIT 10`,
      [caregiverId]
    );
    dashboard.notifications = notifications.rows;

    res.json(dashboard);
  } catch (error) {
    console.error('Error fetching caregiver dashboard:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/worker/:workerId', async (req, res) => {
  try {
    const { workerId } = req.params;

    const worker = await pool.query(
      `SELECT aanganwadi_center_id, full_name FROM users WHERE id = $1`,
      [workerId]
    );

    const centerId = worker.rows[0]?.aanganwadi_center_id;
    const dashboard = {
      worker_id: workerId,
      worker_name: worker.rows[0]?.full_name,
      center_id: centerId,
      today_activities: [],
      pending_home_visits: [],
      children_summary: { total: 0, active: 0, critical: 0 },
      weekly_anganwadi_schedule: [],
    };

    if (centerId) {
      const todayAnganwadi = await pool.query(
        `SELECT aa.*, am.activity_name, am.category
         FROM anganwadi_activities aa
         JOIN activity_master am ON aa.activity_id = am.id
         WHERE aa.center_id = $1 AND aa.activity_date = CURRENT_DATE`,
        [centerId]
      );
      dashboard.today_activities = todayAnganwadi.rows;

      const pendingVisits = await pool.query(
        `SELECT wa.*, c.full_name as child_name, c.child_code
         FROM weekly_activities wa
         JOIN children c ON wa.child_id = c.id
         WHERE wa.week_start_date <= CURRENT_DATE
           AND wa.week_end_date >= CURRENT_DATE
           AND wa.home_visit_completed = false`
      );
      dashboard.pending_home_visits = pendingVisits.rows;

      const childrenSummary = await pool.query(
        `SELECT COUNT(*)::int as total,
                COUNT(CASE WHEN c.is_active THEN 1 END)::int as active,
                COUNT(DISTINCT s.id)::int as critical
         FROM children c
         LEFT JOIN screenings s ON c.id = s.child_id
              AND s.priority_level = 'CRITICAL'
              AND s.status = 'active'
         WHERE c.aanganwadi_center_id = $1`,
        [centerId]
      );
      dashboard.children_summary = childrenSummary.rows[0];

      const weeklySchedule = await pool.query(
        `SELECT activity_date, day_of_week,
                COUNT(*)::int as total_activities,
                COUNT(CASE WHEN conducted THEN 1 END)::int as conducted
         FROM anganwadi_activities
         WHERE center_id = $1
           AND activity_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '6 days'
         GROUP BY activity_date, day_of_week
         ORDER BY activity_date`,
        [centerId]
      );
      dashboard.weekly_anganwadi_schedule = weeklySchedule.rows;
    }

    res.json(dashboard);
  } catch (error) {
    console.error('Error fetching worker dashboard:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
