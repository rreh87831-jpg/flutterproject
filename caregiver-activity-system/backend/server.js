const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const path = require('path');

dotenv.config();

const pool = require('./config/database');

const authRoutes = require('./routes/auth.routes');
const childRoutes = require('./routes/child.routes');
const activityRoutes = require('./routes/activity.routes');
const dailyRoutes = require('./routes/daily.routes');
const weeklyRoutes = require('./routes/weekly.routes');
const anganwadiRoutes = require('./routes/anganwadi.routes');
const reportRoutes = require('./routes/report.routes');
const dashboardRoutes = require('./routes/dashboard.routes');

const { errorHandler } = require('./middleware/errorHandler');
const { authenticateToken } = require('./middleware/auth');

const app = express();

app.use(cors({ origin: process.env.FRONTEND_URL || 'http://localhost:3000', credentials: true }));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

app.use('/api/auth', authRoutes);
app.use('/api/children', authenticateToken, childRoutes);
app.use('/api/activities', authenticateToken, activityRoutes);
app.use('/api/daily', authenticateToken, dailyRoutes);
app.use('/api/weekly', authenticateToken, weeklyRoutes);
app.use('/api/anganwadi', authenticateToken, anganwadiRoutes);
app.use('/api/reports', authenticateToken, reportRoutes);
app.use('/api/dashboard', authenticateToken, dashboardRoutes);

app.get('/api/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'OK', timestamp: new Date().toISOString() });
  } catch (error) {
    res.status(500).json({ status: 'ERROR', error: error.message });
  }
});

app.use(errorHandler);

require('./cron/daily-tasks')(pool);

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

module.exports = app;
