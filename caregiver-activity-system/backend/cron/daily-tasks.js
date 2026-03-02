module.exports = (pool) => {
  const cron = require('node-cron');

  cron.schedule('0 0 * * *', async () => {
    console.log('Running daily tasks at:', new Date().toISOString());
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      await client.query(`
        INSERT INTO daily_activities (child_id, activity_id, activity_date, scheduled_date)
        SELECT c.id, am.id, CURRENT_DATE, CURRENT_DATE
        FROM children c
        CROSS JOIN activity_master am
        WHERE c.is_active = true
          AND am.activity_type = 'daily'
          AND NOT EXISTS (
            SELECT 1 FROM daily_activities da
            WHERE da.child_id = c.id
              AND da.activity_id = am.id
              AND da.activity_date = CURRENT_DATE
          )`);

      await client.query(`
        UPDATE screenings
        SET status = 'overdue'
        WHERE referral_deadline < CURRENT_DATE
          AND status = 'active'`);

      await client.query(`
        INSERT INTO notifications (user_id, title, message, type, related_to)
        SELECT c.caregiver_id,
               'Daily Activities Reminder',
               'Please complete today''s activities for ' || c.full_name,
               'reminder',
               'daily'
        FROM children c
        WHERE c.caregiver_id IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM daily_activities da
            WHERE da.child_id = c.id
              AND da.activity_date = CURRENT_DATE
              AND da.completed = false
          )`);

      await client.query(`
        INSERT INTO notifications (user_id, title, message, type, related_to)
        SELECT wa.worker_id,
               'Home Visit Reminder',
               'Home visit scheduled for this week',
               'reminder',
               'weekly'
        FROM weekly_activities wa
        WHERE wa.week_start_date <= CURRENT_DATE
          AND wa.week_end_date >= CURRENT_DATE
          AND wa.home_visit_completed = false
          AND wa.worker_id IS NOT NULL`);

      await client.query('COMMIT');
      console.log('Daily tasks completed successfully');
    } catch (error) {
      await client.query('ROLLBACK');
      console.error('Error in daily tasks:', error);
    } finally {
      client.release();
    }
  });

  cron.schedule('0 8 * * 1', async () => {
    console.log('Generating weekly plans at:', new Date().toISOString());
    try {
      const now = new Date();
      const monday = new Date(now);
      const day = now.getDay();
      monday.setDate(now.getDate() - (day === 0 ? 6 : day - 1));
      monday.setHours(0, 0, 0, 0);
      const sunday = new Date(monday);
      sunday.setDate(monday.getDate() + 6);

      await pool.query(
        `INSERT INTO weekly_activities (child_id, activity_id, week_start_date, week_end_date)
         SELECT c.id, am.id, $1::date, $2::date
         FROM children c
         CROSS JOIN activity_master am
         WHERE c.is_active = true
           AND am.activity_type = 'weekly'
           AND NOT EXISTS (
             SELECT 1 FROM weekly_activities wa
             WHERE wa.child_id = c.id
               AND wa.week_start_date = $1::date
               AND wa.activity_id = am.id
           )`,
        [monday.toISOString().split('T')[0], sunday.toISOString().split('T')[0]]
      );

      console.log('Weekly plans generated successfully');
    } catch (error) {
      console.error('Error generating weekly plans:', error);
    }
  });
};
