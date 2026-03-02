CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS anganwadi_centers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    center_code VARCHAR(20) UNIQUE NOT NULL,
    center_name VARCHAR(100) NOT NULL,
    address TEXT,
    city VARCHAR(50),
    district VARCHAR(50),
    state VARCHAR(50),
    pincode VARCHAR(10),
    phone VARCHAR(20),
    supervisor_name VARCHAR(100),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE,
    phone VARCHAR(20),
    role VARCHAR(20) CHECK (role IN ('caregiver', 'anganwadi_worker', 'admin', 'supervisor')),
    aanganwadi_center_id UUID REFERENCES anganwadi_centers(id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS children (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    child_code VARCHAR(20) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    date_of_birth DATE NOT NULL,
    gender VARCHAR(10) CHECK (gender IN ('Male', 'Female', 'Other')),
    father_name VARCHAR(100),
    mother_name VARCHAR(100),
    caregiver_id UUID REFERENCES users(id),
    aanganwadi_center_id UUID REFERENCES anganwadi_centers(id),
    address TEXT,
    registration_date DATE DEFAULT CURRENT_DATE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS activity_master (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    activity_code VARCHAR(20) UNIQUE NOT NULL,
    activity_name VARCHAR(100) NOT NULL,
    activity_type VARCHAR(20) CHECK (activity_type IN ('daily', 'weekly', 'anganwadi', 'one_time')),
    category VARCHAR(30) CHECK (category IN ('GM', 'LC', 'COG', 'Planning', 'Review', 'Group', 'Health', 'Learning')),
    description TEXT,
    telugu_description TEXT,
    duration_minutes INTEGER,
    frequency_per_week INTEGER DEFAULT 1,
    is_mandatory BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS screenings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    screening_code VARCHAR(30) UNIQUE NOT NULL,
    child_id UUID REFERENCES children(id),
    screened_by UUID REFERENCES users(id),
    screening_date DATE NOT NULL,
    priority_level VARCHAR(20) CHECK (priority_level IN ('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')),
    referral_deadline DATE,
    follow_up_end_date DATE,
    notes TEXT,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'completed', 'overdue')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS referrals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referral_number VARCHAR(30) UNIQUE NOT NULL,
    screening_id UUID REFERENCES screenings(id),
    child_id UUID REFERENCES children(id),
    referred_to UUID REFERENCES users(id),
    referred_by UUID REFERENCES users(id),
    referral_date DATE NOT NULL,
    facility VARCHAR(100),
    urgency VARCHAR(20) CHECK (urgency IN ('IMMEDIATE', 'URGENT', 'NORMAL')),
    deadline_date DATE,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'overdue')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS daily_activities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    child_id UUID REFERENCES children(id),
    activity_id UUID REFERENCES activity_master(id),
    caregiver_id UUID REFERENCES users(id),
    activity_date DATE NOT NULL,
    scheduled_date DATE,
    completed BOOLEAN DEFAULT false,
    completion_time TIME,
    notes TEXT,
    caregiver_remark TEXT,
    difficulty_level INTEGER CHECK (difficulty_level BETWEEN 1 AND 5),
    photo_evidence_url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(child_id, activity_id, activity_date)
);

CREATE TABLE IF NOT EXISTS weekly_activities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    child_id UUID REFERENCES children(id),
    activity_id UUID REFERENCES activity_master(id),
    week_start_date DATE NOT NULL,
    week_end_date DATE NOT NULL,
    planning_completed BOOLEAN DEFAULT false,
    planning_date DATE,
    home_visit_completed BOOLEAN DEFAULT false,
    home_visit_date DATE,
    home_visit_notes TEXT,
    group_activity_completed BOOLEAN DEFAULT false,
    group_activity_date DATE,
    review_completed BOOLEAN DEFAULT false,
    review_date DATE,
    review_notes TEXT,
    caregiver_id UUID REFERENCES users(id),
    worker_id UUID REFERENCES users(id),
    overall_progress INTEGER CHECK (overall_progress BETWEEN 0 AND 100),
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS anganwadi_activities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    center_id UUID REFERENCES anganwadi_centers(id),
    activity_id UUID REFERENCES activity_master(id),
    activity_date DATE NOT NULL,
    day_of_week VARCHAR(10) CHECK (day_of_week IN ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')),
    conducted BOOLEAN DEFAULT false,
    conducted_by UUID REFERENCES users(id),
    children_present INTEGER DEFAULT 0,
    start_time TIME,
    end_time TIME,
    materials_used TEXT,
    notes TEXT,
    is_holiday BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(center_id, activity_date, activity_id)
);

CREATE TABLE IF NOT EXISTS follow_up_schedule (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referral_id UUID REFERENCES referrals(id),
    follow_up_date DATE NOT NULL,
    follow_up_level INTEGER,
    follow_up_type VARCHAR(20) CHECK (follow_up_type IN ('call', 'visit', 'review')),
    assigned_to UUID REFERENCES users(id),
    completed BOOLEAN DEFAULT false,
    completion_date DATE,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS progress_tracking (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    child_id UUID REFERENCES children(id),
    tracking_date DATE NOT NULL,
    daily_completed INTEGER DEFAULT 0,
    daily_total INTEGER DEFAULT 0,
    weekly_completed INTEGER DEFAULT 0,
    weekly_total INTEGER DEFAULT 0,
    anganwadi_completed INTEGER DEFAULT 0,
    anganwadi_total INTEGER DEFAULT 0,
    overall_percentage DECIMAL(5,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(child_id, tracking_date)
);

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    title VARCHAR(200),
    message TEXT,
    type VARCHAR(20) CHECK (type IN ('reminder', 'alert', 'info', 'success')),
    related_to VARCHAR(50),
    related_id UUID,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS activity_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    action VARCHAR(50),
    table_name VARCHAR(50),
    record_id UUID,
    old_data JSONB,
    new_data JSONB,
    ip_address VARCHAR(45),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO activity_master (activity_code, activity_name, activity_type, category, description, telugu_description, duration_minutes, frequency_per_week) VALUES
('GM-DAILY-01', 'Walking/Running Exercise', 'daily', 'GM', 'Walking, running, jumping exercises for physical development', 'నడక, పరుగు, దూకడం ప్రాణిస్తే చేయండి', 30, 7),
('LC-DAILY-01', 'Reading Practice', 'daily', 'LC', 'Read stories, name objects, identify things', 'పునస్థితులు చదువండి, వస్తువులకు పేర్లు చెప్పండి', 20, 7),
('COG-DAILY-01', 'Puzzle Games', 'daily', 'COG', 'Play matching games, solve puzzles', 'జతవరచే ఆటలు, పజల్నీ ఆడండి', 30, 7),
('WK-PLAN-01', 'Weekly Planning Meeting', 'weekly', 'Planning', 'Plan weekly activities with caregiver', 'వారపు కార్యక్రమాల ప్రణాళిక', 60, 1),
('WK-VISIT-01', 'Home Visit', 'weekly', 'Review', 'Worker visits home to check progress', 'హోమ్ విజిట్', 45, 1),
('WK-GROUP-01', 'Group Activity Session', 'weekly', 'Group', 'Group activities at Anganwadi', 'గ్రూప్ కార్యకలాపాలు', 90, 1),
('WK-REVIEW-01', 'Weekly Review', 'weekly', 'Review', 'Review weekly progress', 'వారపు సమీక్ష', 30, 1),
('ANG-MON-01', 'Alphabet Learning', 'anganwadi', 'Learning', 'Learn alphabets, numbers, colors', 'అక్షరాలు, సంఖ్యలు, రంగులు నేర్చుకోవడం', 60, 1),
('ANG-TUE-01', 'Creative Arts', 'anganwadi', 'Learning', 'Drawing, coloring, clay modeling', 'డ్రాయింగ్, కలరింగ్, క్లే మోడలింగ్', 60, 1),
('ANG-WED-01', 'Physical Activities', 'anganwadi', 'GM', 'Outdoor games, exercises', 'అవుట్డోర్ గేమ్స్, వ్యాయామాలు', 60, 1),
('ANG-THU-01', 'Music & Rhymes', 'anganwadi', 'Learning', 'Songs, rhymes, dance', 'పాటలు, రైమ్స్, డాన్స్', 45, 1),
('ANG-FRI-01', 'Story Time', 'anganwadi', 'Learning', 'Story telling, role play', 'కథలు, రోల్ ప్లే', 45, 1),
('ANG-SAT-01', 'Health Check', 'anganwadi', 'Health', 'Growth monitoring, health check', 'ఆరోగ్య తనిఖీ', 120, 1),
('OT-GM-01', 'GM Level 0 Assessment', 'one_time', 'GM', 'Initial GM assessment', 'ప్రారంభ GM మూల్యాంకనం', 30, 1),
('OT-LC-01', 'LC Level 0 Assessment', 'one_time', 'LC', 'Initial LC assessment', 'ప్రారంభ LC మూల్యాంకనం', 30, 1),
('OT-COG-01', 'COG Level 0 Assessment', 'one_time', 'COG', 'Initial COG assessment', 'ప్రారంభ COG మూల్యాంకనం', 30, 1)
ON CONFLICT (activity_code) DO NOTHING;

INSERT INTO anganwadi_centers (center_code, center_name, district, supervisor_name)
VALUES ('ANG001', 'District Specialist Center', 'Central', 'Supriya Devi')
ON CONFLICT (center_code) DO NOTHING;

INSERT INTO users (username, password_hash, full_name, role, aanganwadi_center_id)
SELECT 'caregiver1', 'hash123', 'Lakshmi Devi', 'caregiver', id
FROM anganwadi_centers WHERE center_code = 'ANG001'
ON CONFLICT (username) DO NOTHING;

INSERT INTO users (username, password_hash, full_name, role, aanganwadi_center_id)
SELECT 'worker1', 'hash456', 'Anita Kumari', 'anganwadi_worker', id
FROM anganwadi_centers WHERE center_code = 'ANG001'
ON CONFLICT (username) DO NOTHING;

INSERT INTO users (username, password_hash, full_name, role)
VALUES ('admin1', 'hash789', 'Priya Sharma', 'admin')
ON CONFLICT (username) DO NOTHING;

INSERT INTO children (child_code, full_name, date_of_birth, caregiver_id, aanganwadi_center_id)
SELECT 'CHILD001', 'Ravi Kumar', '2020-05-15', u.id, c.id
FROM users u
JOIN anganwadi_centers c ON c.center_code = 'ANG001'
WHERE u.username = 'caregiver1'
ON CONFLICT (child_code) DO NOTHING;

INSERT INTO screenings (screening_code, child_id, screened_by, screening_date, priority_level, referral_deadline, follow_up_end_date)
SELECT 'SCR20260302001', ch.id, u.id, '2026-03-02', 'CRITICAL', '2026-03-05', '2026-03-12'
FROM children ch, users u
WHERE ch.child_code = 'CHILD001' AND u.username = 'worker1'
ON CONFLICT (screening_code) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_daily_activities_date ON daily_activities(activity_date);
CREATE INDEX IF NOT EXISTS idx_daily_activities_child ON daily_activities(child_id);
CREATE INDEX IF NOT EXISTS idx_weekly_activities_week ON weekly_activities(week_start_date);
CREATE INDEX IF NOT EXISTS idx_anganwadi_activities_date ON anganwadi_activities(activity_date);
CREATE INDEX IF NOT EXISTS idx_follow_up_date ON follow_up_schedule(follow_up_date);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_screenings_priority ON screenings(priority_level, status);

CREATE OR REPLACE VIEW vw_daily_progress AS
SELECT c.child_code,
       c.full_name AS child_name,
       da.activity_date,
       COUNT(CASE WHEN da.completed THEN 1 END) AS completed_count,
       COUNT(*) AS total_count,
       ROUND(COUNT(CASE WHEN da.completed THEN 1 END) * 100.0 / NULLIF(COUNT(*),0), 2) AS completion_percentage
FROM daily_activities da
JOIN children c ON da.child_id = c.id
GROUP BY c.child_code, c.full_name, da.activity_date;

CREATE OR REPLACE VIEW vw_weekly_summary AS
SELECT c.child_code,
       c.full_name,
       wa.week_start_date,
       wa.week_end_date,
       wa.planning_completed,
       wa.home_visit_completed,
       wa.group_activity_completed,
       wa.review_completed,
       wa.overall_progress
FROM weekly_activities wa
JOIN children c ON wa.child_id = c.id;

CREATE OR REPLACE FUNCTION update_progress_tracking()
RETURNS TRIGGER AS $$
DECLARE
    v_child_id UUID;
    v_tracking_date DATE;
    v_daily_completed INTEGER;
    v_daily_total INTEGER;
BEGIN
    IF TG_TABLE_NAME = 'daily_activities' THEN
        v_child_id := NEW.child_id;
        v_tracking_date := NEW.activity_date;
    ELSIF TG_TABLE_NAME = 'weekly_activities' THEN
        v_child_id := NEW.child_id;
        v_tracking_date := NEW.week_end_date;
    ELSE
        RETURN NEW;
    END IF;

    SELECT COUNT(CASE WHEN completed THEN 1 END), COUNT(*)
      INTO v_daily_completed, v_daily_total
      FROM daily_activities
      WHERE child_id = v_child_id AND activity_date = v_tracking_date;

    INSERT INTO progress_tracking (child_id, tracking_date, daily_completed, daily_total, overall_percentage)
    VALUES (v_child_id, v_tracking_date, v_daily_completed, v_daily_total,
            CASE WHEN v_daily_total > 0 THEN (v_daily_completed * 100.0 / v_daily_total) ELSE 0 END)
    ON CONFLICT (child_id, tracking_date) DO UPDATE
    SET daily_completed = EXCLUDED.daily_completed,
        daily_total = EXCLUDED.daily_total,
        overall_percentage = EXCLUDED.overall_percentage;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_daily_activities_progress ON daily_activities;
CREATE TRIGGER trg_daily_activities_progress
AFTER INSERT OR UPDATE ON daily_activities
FOR EACH ROW
EXECUTE FUNCTION update_progress_tracking();

DROP TRIGGER IF EXISTS trg_weekly_activities_progress ON weekly_activities;
CREATE TRIGGER trg_weekly_activities_progress
AFTER INSERT OR UPDATE ON weekly_activities
FOR EACH ROW
EXECUTE FUNCTION update_progress_tracking();

CREATE OR REPLACE PROCEDURE generate_daily_activities(p_child_id UUID, p_start_date DATE, p_num_days INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_date DATE;
BEGIN
    FOR i IN 0..p_num_days-1 LOOP
        v_date := p_start_date + i;

        INSERT INTO daily_activities (child_id, activity_id, activity_date, scheduled_date)
        SELECT p_child_id, id, v_date, v_date
        FROM activity_master
        WHERE activity_code = 'GM-DAILY-01'
          AND NOT EXISTS (
              SELECT 1 FROM daily_activities
              WHERE child_id = p_child_id
                AND activity_id = activity_master.id
                AND activity_date = v_date
          );

        INSERT INTO daily_activities (child_id, activity_id, activity_date, scheduled_date)
        SELECT p_child_id, id, v_date, v_date
        FROM activity_master
        WHERE activity_code = 'LC-DAILY-01'
          AND NOT EXISTS (
              SELECT 1 FROM daily_activities
              WHERE child_id = p_child_id
                AND activity_id = activity_master.id
                AND activity_date = v_date
          );

        INSERT INTO daily_activities (child_id, activity_id, activity_date, scheduled_date)
        SELECT p_child_id, id, v_date, v_date
        FROM activity_master
        WHERE activity_code = 'COG-DAILY-01'
          AND NOT EXISTS (
              SELECT 1 FROM daily_activities
              WHERE child_id = p_child_id
                AND activity_id = activity_master.id
                AND activity_date = v_date
          );
    END LOOP;
END;
$$;
