const express = require('express');
const router = express.Router();
const pool = require('../config/database');
const { body, validationResult } = require('express-validator');

router.get('/child/:childId/today', async (req, res) => {
  try {
    const { childId } = req.params;
    const today = new Date().toISOString().split('T')[0];

    const query = `
      SELECT da.id, da.child_id, da.activity_date, da.completed, da.completion_time, da.notes, da.difficulty_level,
             am.activity_code, am.activity_name, am.category, am.description, am.telugu_description, am.duration_minutes
      FROM daily_activities da
      JOIN activity_master am ON da.activity_id = am.id
      WHERE da.child_id = $1 AND da.activity_date = $2 AND am.activity_type = 'daily'
      ORDER BY am.category`;

    const result = await pool.query(query, [childId, today]);

    if (result.rows.length === 0) {
      await pool.query('CALL generate_daily_activities($1, $2, $3)', [childId, today, 1]);
      const newResult = await pool.query(query, [childId, today]);
      return res.json(newResult.rows);
    }

    res.json(result.rows);
  } catch (error) {
    console.error('Error fetching daily activities:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/child/:childId/week', async (req, res) => {
  try {
    const { childId } = req.params;
    const query = `
      SELECT da.activity_date,
             COUNT(CASE WHEN da.completed THEN 1 END) as completed_count,
             COUNT(*) as total_count,
             ROUND(COUNT(CASE WHEN da.completed THEN 1 END) * 100.0 / NULLIF(COUNT(*),0), 2) as completion_percentage,
             json_agg(json_build_object(
               'id', da.id,
               'activity_name', am.activity_name,
               'category', am.category,
               'completed', da.completed,
               'completion_time', da.completion_time
             ) ORDER BY am.category) as activities
      FROM daily_activities da
      JOIN activity_master am ON da.activity_id = am.id
      WHERE da.child_id = $1 AND da.activity_date BETWEEN CURRENT_DATE - INTERVAL '7 days' AND CURRENT_DATE
      GROUP BY da.activity_date
      ORDER BY da.activity_date DESC`;

    const result = await pool.query(query, [childId]);
    res.json(result.rows);
  } catch (error) {
    console.error('Error fetching weekly daily activities:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/:activityId/complete', [
  body('notes').optional().isString(),
  body('difficulty_level').optional().isInt({ min: 1, max: 5 })
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  try {
    const { activityId } = req.params;
    const { notes, difficulty_level } = req.body;
    const completionTime = new Date().toTimeString().split(' ')[0];

    const result = await pool.query(
      `UPDATE daily_activities
       SET completed = true,
           completion_time = $1,
           notes = COALESCE($2, notes),
           difficulty_level = COALESCE($3, difficulty_level),
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $4
       RETURNING *`,
      [completionTime, notes, difficulty_level, activityId]
    );

    if (result.rows.length === 0) return res.status(404).json({ error: 'Activity not found' });

    const childId = result.rows[0].child_id;
    const todayCheck = await pool.query(
      `SELECT COUNT(*)::int as total,
              COUNT(CASE WHEN completed THEN 1 END)::int as completed
       FROM daily_activities
       WHERE child_id = $1 AND activity_date = CURRENT_DATE`,
      [childId]
    );

    const { total, completed } = todayCheck.rows[0];
    if (total > 0 && total === completed) {
      await pool.query(
        `INSERT INTO notifications (user_id, title, message, type, related_to, related_id)
         SELECT c.caregiver_id, 'Daily Activities Complete',
                'All daily activities for today have been completed!',
                'success', 'daily', $1
         FROM children c WHERE c.id = $2 AND c.caregiver_id IS NOT NULL`,
        [childId, childId]
      );
    }

    res.json({
      message: 'Activity marked as complete',
      activity: result.rows[0],
      daily_progress: {
        total,
        completed,
        percentage: total > 0 ? Number(((completed / total) * 100).toFixed(2)) : 0
      }
    });
  } catch (error) {
    console.error('Error completing activity:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/bulk-complete', [
  body('activities').isArray(),
  body('activities.*.id').isUUID()
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { activities } = req.body;
    const completionTime = new Date().toTimeString().split(' ')[0];
    const results = [];

    for (const activity of activities) {
      const result = await client.query(
        `UPDATE daily_activities
         SET completed = true,
             completion_time = $1,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $2
         RETURNING *`,
        [completionTime, activity.id]
      );
      if (result.rows[0]) results.push(result.rows[0]);
    }

    await client.query('COMMIT');
    res.json({ message: `${results.length} activities marked as complete`, activities: results });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error bulk completing activities:', error);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

router.get('/child/:childId/stats', async (req, res) => {
  try {
    const { childId } = req.params;
    const days = Math.max(1, parseInt(req.query.days || '30', 10));

    const query = `
      WITH date_series AS (
        SELECT generate_series(CURRENT_DATE - ($2::int || ' days')::interval, CURRENT_DATE, '1 day'::interval)::date AS date
      )
      SELECT ds.date,
             COALESCE(da.completed_count, 0) as completed,
             COALESCE(da.total_count, 3) as total,
             COALESCE(da.completion_percentage, 0) as percentage
      FROM date_series ds
      LEFT JOIN (
        SELECT activity_date,
               COUNT(CASE WHEN completed THEN 1 END) as completed_count,
               COUNT(*) as total_count,
               ROUND(COUNT(CASE WHEN completed THEN 1 END) * 100.0 / NULLIF(COUNT(*),0), 2) as completion_percentage
        FROM daily_activities
        WHERE child_id = $1 AND activity_date >= CURRENT_DATE - ($2::int || ' days')::interval
        GROUP BY activity_date
      ) da ON ds.date = da.activity_date
      ORDER BY ds.date DESC`;

    const result = await pool.query(query, [childId, days]);
    const nonZero = result.rows.filter(r => Number(r.percentage) > 0);
    const average = nonZero.length
      ? (nonZero.reduce((acc, r) => acc + Number(r.percentage), 0) / nonZero.length).toFixed(2)
      : '0.00';

    const bestDay = result.rows.reduce((best, current) =>
      Number(current.percentage) > Number(best.percentage || 0) ? current : best, { percentage: 0 });

    res.json({
      daily: result.rows,
      summary: {
        total_days: result.rows.length,
        days_with_data: result.rows.filter(r => Number(r.completed) > 0).length,
        average_completion: average,
        best_day: bestDay,
      }
    });
  } catch (error) {
    console.error('Error fetching activity stats:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
