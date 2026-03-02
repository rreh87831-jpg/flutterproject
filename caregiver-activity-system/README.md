# Caregiver Activity Tracking System

Production-style module for tracking:
- Daily caregiver activities (GM/LC/COG)
- Weekly workflow (planning/home visit/group/review)
- Anganwadi day-wise schedule

## Structure

- `backend/` Node.js + Express + PostgreSQL
- `frontend/` Static HTML/CSS/JS dashboard

## Setup

1. Create DB and run schema:
```bash
createdb caregiver_activity_db
psql -U postgres -d caregiver_activity_db -f backend/database/schema.sql
```

2. Backend:
```bash
cd backend
npm install
cp .env.example .env
# update DB_PASSWORD
npm run dev
```

3. Frontend:
```bash
cd ../frontend
npx http-server -p 3000
```

4. Health check:
```bash
curl http://localhost:5000/api/health
```

## Important notes

- Backend routes under `/api/*`.
- JWT auth middleware is active for non-auth routes.
- Demo users are seeded in schema (`caregiver1`, `worker1`, `admin1`) with placeholder password hashes.
- Replace placeholder hashes with bcrypt hashes before production use.
