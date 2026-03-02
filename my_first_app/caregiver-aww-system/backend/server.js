const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config();

const referralRoutes = require('./routes/referral.routes');
const caregiverRoutes = require('./routes/caregiver.routes');
const awwRoutes = require('./routes/aww.routes');
const followupRoutes = require('./routes/followup.routes');

const app = express();

app.use(cors({
  origin: process.env.FRONTEND_URL || 'http://localhost:3000',
  credentials: true,
}));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use('/api/referrals', referralRoutes);
app.use('/api/caregiver', caregiverRoutes);
app.use('/api/aww', awwRoutes);
app.use('/api/followup', followupRoutes);

app.get('/api/health', (_req, res) => {
  res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: 'Internal Server Error', message: err.message });
});

const PORT = Number(process.env.PORT || 5000);
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

module.exports = app;
