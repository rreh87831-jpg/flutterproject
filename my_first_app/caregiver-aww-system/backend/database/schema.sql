CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS centers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  center_code VARCHAR(20) UNIQUE NOT NULL,
  center_name VARCHAR(100) NOT NULL,
  district VARCHAR(50),
  address TEXT,
  phone VARCHAR(20),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  username VARCHAR(50) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  full_name VARCHAR(100) NOT NULL,
  email VARCHAR(100),
  phone VARCHAR(20),
  role VARCHAR(20) CHECK (role IN ('caregiver', 'aww', 'supervisor', 'admin')),
  center_id UUID REFERENCES centers(id),
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS children (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_code VARCHAR(20) UNIQUE NOT NULL,
  full_name VARCHAR(100) NOT NULL,
  date_of_birth DATE NOT NULL,
  gender VARCHAR(10),
  father_name VARCHAR(100),
  mother_name VARCHAR(100),
  caregiver_id UUID REFERENCES users(id),
  center_id UUID REFERENCES centers(id),
  address TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS referrals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  referral_number VARCHAR(30) UNIQUE NOT NULL,
  child_id UUID REFERENCES children(id),
  facility VARCHAR(100) NOT NULL DEFAULT 'DISTRICT SPECIALIST',
  urgency VARCHAR(20) CHECK (urgency IN ('IMMEDIATE', 'URGENT', 'NORMAL')) DEFAULT 'IMMEDIATE',
  screening_date DATE NOT NULL,
  referral_deadline DATE NOT NULL,
  follow_up_end_date DATE NOT NULL,
  review_frequency VARCHAR(20) DEFAULT 'DAILY',
  total_activities INTEGER DEFAULT 32,
  completed_activities INTEGER DEFAULT 1,
  progress_percentage DECIMAL(5,2) DEFAULT 3.00,
  status VARCHAR(20) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS activity_master (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  activity_code VARCHAR(20) UNIQUE NOT NULL,
  activity_name VARCHAR(100) NOT NULL,
  activity_type VARCHAR(20) CHECK (activity_type IN ('GM', 'LC', 'COG', 'GENERAL')),
  level_number INTEGER CHECK (level_number BETWEEN 0 AND 7),
  description TEXT,
  telugu_description TEXT,
  assigned_to VARCHAR(20) CHECK (assigned_to IN ('CAREGIVER', 'AWW')),
  frequency VARCHAR(20) DEFAULT 'One-time',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS caregiver_activities (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  referral_id UUID REFERENCES referrals(id),
  child_id UUID REFERENCES children(id),
  activity_id UUID REFERENCES activity_master(id),
  activity_code VARCHAR(20),
  level_number INTEGER,
  assigned_date DATE NOT NULL,
  deadline_date DATE,
  completed BOOLEAN DEFAULT false,
  completion_date DATE,
  completion_percentage INTEGER DEFAULT 0,
  status VARCHAR(20) DEFAULT 'pending',
  remarks TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(referral_id, activity_id, level_number)
);

CREATE TABLE IF NOT EXISTS aww_activities (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  referral_id UUID REFERENCES referrals(id),
  child_id UUID REFERENCES children(id),
  activity_id UUID REFERENCES activity_master(id),
  activity_code VARCHAR(20),
  level_number INTEGER,
  monitoring_date DATE NOT NULL,
  monitored BOOLEAN DEFAULT false,
  escalation_required BOOLEAN DEFAULT false,
  ok_status BOOLEAN DEFAULT false,
  marked_monitored BOOLEAN DEFAULT false,
  remarks TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS followup_plan (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  referral_id UUID REFERENCES referrals(id),
  followup_date DATE NOT NULL,
  level_number INTEGER NOT NULL,
  activity_type VARCHAR(20),
  completed BOOLEAN DEFAULT false,
  completion_time TIMESTAMP,
  marked_as_completed BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS progress_tracking (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  referral_id UUID REFERENCES referrals(id),
  total_activities INTEGER DEFAULT 32,
  completed_activities INTEGER DEFAULT 1,
  progress_percentage DECIMAL(5,2) DEFAULT 3.00,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS activity_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id),
  action VARCHAR(50),
  activity_type VARCHAR(20),
  level_number INTEGER,
  status VARCHAR(20),
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION update_progress_on_completion()
RETURNS TRIGGER AS $$
DECLARE
  v_referral_id UUID;
  v_total INTEGER := 32;
  v_completed INTEGER;
  v_percentage DECIMAL;
BEGIN
  v_referral_id := NEW.referral_id;

  SELECT COUNT(*) INTO v_completed
  FROM caregiver_activities
  WHERE referral_id = v_referral_id AND completed = true;

  v_percentage := (v_completed::DECIMAL / v_total::DECIMAL) * 100;

  UPDATE referrals
  SET completed_activities = v_completed,
      progress_percentage = ROUND(v_percentage, 2),
      updated_at = CURRENT_TIMESTAMP
  WHERE id = v_referral_id;

  UPDATE progress_tracking
  SET completed_activities = v_completed,
      progress_percentage = ROUND(v_percentage, 2),
      last_updated = CURRENT_TIMESTAMP
  WHERE referral_id = v_referral_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_caregiver_activities_progress ON caregiver_activities;
CREATE TRIGGER trg_caregiver_activities_progress
AFTER UPDATE OF completed ON caregiver_activities
FOR EACH ROW
WHEN (OLD.completed IS DISTINCT FROM NEW.completed)
EXECUTE FUNCTION update_progress_on_completion();

INSERT INTO centers (center_code, center_name, district)
VALUES ('C001', 'District Specialist Center', 'Central')
ON CONFLICT (center_code) DO NOTHING;

INSERT INTO users (username, password_hash, full_name, role, center_id)
VALUES
('caregiver1', 'hash123', 'Lakshmi Devi', 'caregiver', (SELECT id FROM centers WHERE center_code='C001')),
('aww1', 'hash456', 'Anita Kumari', 'aww', (SELECT id FROM centers WHERE center_code='C001')),
('supervisor1', 'hash789', 'Supriya Devi', 'supervisor', (SELECT id FROM centers WHERE center_code='C001'))
ON CONFLICT (username) DO NOTHING;

INSERT INTO children (child_code, full_name, date_of_birth, caregiver_id, center_id)
VALUES (
'CHILD001',
'Ravi Kumar',
'2020-05-15',
(SELECT id FROM users WHERE username='caregiver1'),
(SELECT id FROM centers WHERE center_code='C001')
)
ON CONFLICT (child_code) DO NOTHING;

INSERT INTO referrals (
  referral_number, child_id, facility, urgency,
  screening_date, referral_deadline, follow_up_end_date,
  review_frequency, total_activities, completed_activities, progress_percentage
)
VALUES (
  'REF-20260302-0020',
  (SELECT id FROM children WHERE child_code='CHILD001'),
  'DISTRICT SPECIALIST', 'IMMEDIATE',
  '2026-03-02', '2026-03-04', '2026-03-11',
  'DAILY', 32, 1, 3.00
)
ON CONFLICT (referral_number) DO NOTHING;

DO $$
DECLARE
  v_level INTEGER;
  v_type TEXT;
BEGIN
  FOR v_type IN SELECT unnest(ARRAY['GM','LC','COG']) LOOP
    FOR v_level IN 0..7 LOOP
      INSERT INTO activity_master (
        activity_code, activity_name, activity_type, level_number,
        description, telugu_description, assigned_to
      ) VALUES (
        v_type || '-L' || v_level,
        v_type || ' Caregiver Activity - Level ' || v_level,
        v_type,
        v_level,
        CASE v_type
          WHEN 'GM' THEN 'Walking, running, jumping exercises'
          WHEN 'LC' THEN 'Reading books, naming objects'
          WHEN 'COG' THEN 'Matching games, puzzles'
        END,
        CASE v_type
          WHEN 'GM' THEN 'నడక, పరుగు, దూకడం ప్రాక్షిక్ చేయండి.'
          WHEN 'LC' THEN 'పుస్తకాలు చదవండి, వస్తువులకు పేర్లు చెప్పండి.'
          WHEN 'COG' THEN 'జతపర్చే ఆటలు, పజిల్లీ ఆడండి.'
        END,
        'CAREGIVER'
      ) ON CONFLICT (activity_code) DO NOTHING;
    END LOOP;
  END LOOP;

  FOR v_level IN 0..7 LOOP
    INSERT INTO activity_master (
      activity_code, activity_name, activity_type, level_number,
      description, telugu_description, assigned_to
    ) VALUES (
      'GEN-L' || v_level,
      'Level ' || v_level || ' - Follow-up Review',
      'GENERAL',
      v_level,
      'Review progress and caregiver compliance',
      'ఈ పాట్లో అప్ లెవేట్ ప్రోగతి మరియు సంరక్షకుడి అనుసరణను సమీక్షించండి.',
      'AWW'
    ) ON CONFLICT (activity_code) DO NOTHING;
  END LOOP;
END $$;

INSERT INTO caregiver_activities (
  referral_id, child_id, activity_id, activity_code, level_number,
  assigned_date, deadline_date, completed, completion_percentage, status
)
SELECT
  r.id, r.child_id, am.id, am.activity_code, am.level_number,
  '2026-03-02', '2026-03-04',
  CASE WHEN am.level_number = 0 THEN true ELSE false END,
  CASE WHEN am.level_number = 0 THEN 100 ELSE 0 END,
  CASE WHEN am.level_number = 0 THEN 'completed' ELSE 'pending' END
FROM referrals r
JOIN activity_master am ON am.assigned_to = 'CAREGIVER' AND am.activity_type IN ('GM','LC','COG')
WHERE r.referral_number = 'REF-20260302-0020'
ON CONFLICT (referral_id, activity_id, level_number) DO NOTHING;

INSERT INTO aww_activities (
  referral_id, child_id, activity_id, activity_code, level_number, monitoring_date
)
SELECT
  r.id, r.child_id, am.id, am.activity_code, am.level_number,
  DATE '2026-03-02' + am.level_number
FROM referrals r
JOIN activity_master am ON am.assigned_to = 'AWW'
WHERE r.referral_number = 'REF-20260302-0020'
AND NOT EXISTS (
  SELECT 1 FROM aww_activities aa WHERE aa.referral_id = r.id AND aa.activity_id = am.id
);

INSERT INTO followup_plan (referral_id, followup_date, level_number, activity_type, completed)
SELECT r.id, DATE '2026-03-02' + g, g, 'DAILY_FOLLOWUP', false
FROM referrals r
CROSS JOIN generate_series(0, 7) g
WHERE r.referral_number = 'REF-20260302-0020'
AND NOT EXISTS (
  SELECT 1 FROM followup_plan fp WHERE fp.referral_id = r.id AND fp.level_number = g
);

INSERT INTO progress_tracking (referral_id, total_activities, completed_activities, progress_percentage)
SELECT r.id, r.total_activities, r.completed_activities, r.progress_percentage
FROM referrals r
WHERE r.referral_number = 'REF-20260302-0020'
AND NOT EXISTS (
  SELECT 1 FROM progress_tracking pt WHERE pt.referral_id = r.id
);
