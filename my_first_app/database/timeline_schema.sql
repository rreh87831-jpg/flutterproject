-- ============================================================================
-- PROBLEM B - TIMELINE-BASED SYSTEM (ADDITIVE, PostgreSQL)
-- Compatible with this project's existing TEXT child_id pattern.
-- ============================================================================

CREATE SEQUENCE IF NOT EXISTS referrals_seq START 1;
CREATE SEQUENCE IF NOT EXISTS reviews_seq START 1;
CREATE SEQUENCE IF NOT EXISTS activities_seq START 1;

-- referrals timeline fields (create table only if absent, then ensure fields).
CREATE TABLE IF NOT EXISTS referrals (
    id BIGSERIAL PRIMARY KEY,
    referral_id VARCHAR(50) UNIQUE NOT NULL
        DEFAULT ('REF-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(nextval('referrals_seq')::TEXT, 4, '0')),
    child_id TEXT NOT NULL,
    overall_risk_score INTEGER NOT NULL,
    overall_risk_level VARCHAR(20) NOT NULL CHECK (overall_risk_level IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    num_delays INTEGER NOT NULL DEFAULT 0,
    autism_score INTEGER DEFAULT 0,
    adhd_score INTEGER DEFAULT 0,
    domain_breakdown JSONB NOT NULL DEFAULT '{}'::jsonb,
    facility_type VARCHAR(50) NOT NULL DEFAULT 'PHC',
    urgency VARCHAR(20) NOT NULL DEFAULT 'ROUTINE',
    status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'COMPLETED', 'ESCALATED')),
    escalation_level INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE referrals ADD COLUMN IF NOT EXISTS referral_deadline DATE;
ALTER TABLE referrals ADD COLUMN IF NOT EXISTS screening_date DATE;
ALTER TABLE referrals ADD COLUMN IF NOT EXISTS follow_up_start_date DATE DEFAULT CURRENT_DATE;
ALTER TABLE referrals ADD COLUMN IF NOT EXISTS follow_up_end_date DATE;
ALTER TABLE referrals ADD COLUMN IF NOT EXISTS review_frequency VARCHAR(20);
ALTER TABLE referrals ADD COLUMN IF NOT EXISTS last_escalation_date DATE;
ALTER TABLE referrals ADD COLUMN IF NOT EXISTS specialist_visit_date DATE;
ALTER TABLE referrals ADD COLUMN IF NOT EXISTS specialist_visit_completed BOOLEAN DEFAULT FALSE;

-- Reviews
CREATE TABLE IF NOT EXISTS follow_up_reviews (
    id BIGSERIAL PRIMARY KEY,
    review_id VARCHAR(50) UNIQUE NOT NULL
        DEFAULT ('REV-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(nextval('reviews_seq')::TEXT, 4, '0')),
    referral_id BIGINT NOT NULL REFERENCES referrals(id) ON DELETE CASCADE,
    scheduled_date DATE NOT NULL,
    review_type VARCHAR(20) NOT NULL CHECK (review_type IN ('AWW', 'SPECIALIST')),
    week_number INTEGER,
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'COMPLETED', 'MISSED')),
    completed_at TIMESTAMP,
    notes TEXT,
    was_missed BOOLEAN DEFAULT FALSE,
    missed_escalated BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(referral_id, scheduled_date, review_type)
);

-- Activities (ensure timeline columns exist in existing table)
CREATE TABLE IF NOT EXISTS follow_up_activities (
    id BIGSERIAL PRIMARY KEY,
    activity_id VARCHAR(50) UNIQUE NOT NULL
        DEFAULT ('ACT-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(nextval('activities_seq')::TEXT, 6, '0')),
    referral_id TEXT NOT NULL,
    scheduled_date DATE NOT NULL DEFAULT CURRENT_DATE,
    day_number INTEGER NOT NULL DEFAULT 1,
    activity_title VARCHAR(200),
    activity_description TEXT,
    domain VARCHAR(20) NOT NULL DEFAULT 'GENERAL',
    target_role VARCHAR(20) DEFAULT 'CAREGIVER',
    instructions_english TEXT,
    instructions_telugu TEXT,
    visual_aid_url TEXT,
    time_required_minutes INTEGER DEFAULT 5,
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'COMPLETED', 'MISSED')),
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS scheduled_date DATE;
ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS day_number INTEGER;
ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS activity_title VARCHAR(200);
ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS activity_description TEXT;
ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS child_id TEXT;
ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS title VARCHAR(200);
ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS due_date DATE;
ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS frequency VARCHAR(20);
ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS target_role VARCHAR(20);
ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS instructions_english TEXT;
ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS instructions_telugu TEXT;
ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS time_required_minutes INTEGER;
ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS visual_aid_url TEXT;
ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP;

UPDATE follow_up_activities
SET activity_title = COALESCE(activity_title, title, 'Activity'),
    activity_description = COALESCE(activity_description, description),
    scheduled_date = COALESCE(scheduled_date, CURRENT_DATE),
    day_number = COALESCE(day_number, 1),
    target_role = COALESCE(target_role, target_user, 'CAREGIVER'),
    updated_at = COALESCE(updated_at, CURRENT_TIMESTAMP)
WHERE activity_title IS NULL
   OR activity_description IS NULL
   OR scheduled_date IS NULL
   OR day_number IS NULL
   OR target_role IS NULL
   OR updated_at IS NULL;

-- Compliance
CREATE TABLE IF NOT EXISTS compliance_summary (
    id BIGSERIAL PRIMARY KEY,
    referral_id BIGINT NOT NULL REFERENCES referrals(id) ON DELETE CASCADE UNIQUE,
    total_activities INTEGER DEFAULT 0,
    completed_activities INTEGER DEFAULT 0,
    compliance_percentage DECIMAL(5,2) DEFAULT 0,
    total_reviews INTEGER DEFAULT 0,
    completed_reviews INTEGER DEFAULT 0,
    review_compliance DECIMAL(5,2) DEFAULT 0,
    specialist_visit_completed BOOLEAN DEFAULT FALSE,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Improvement tracking
CREATE TABLE IF NOT EXISTS improvement_tracking (
    id BIGSERIAL PRIMARY KEY,
    referral_id BIGINT NOT NULL REFERENCES referrals(id) ON DELETE CASCADE UNIQUE,
    baseline_score INTEGER NOT NULL,
    current_score INTEGER,
    score_improvement INTEGER,
    improvement_percentage DECIMAL(5,2) DEFAULT 0,
    improvement_status VARCHAR(20) CHECK (improvement_status IN ('IMPROVED', 'WORSENED', 'NO_CHANGE', 'PENDING')),
    calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Timeline-specific escalation logs (separate from legacy escalation_logs)
CREATE TABLE IF NOT EXISTS timeline_escalation_logs (
    id BIGSERIAL PRIMARY KEY,
    referral_id BIGINT NOT NULL REFERENCES referrals(id) ON DELETE CASCADE,
    escalation_level INTEGER NOT NULL,
    escalation_reason VARCHAR(100) NOT NULL,
    escalated_to VARCHAR(50),
    previous_compliance DECIMAL(5,2),
    previous_review_status VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_referrals_deadline ON referrals(referral_deadline);
CREATE INDEX IF NOT EXISTS idx_referrals_status ON referrals(status);
CREATE INDEX IF NOT EXISTS idx_referrals_risk ON referrals(overall_risk_level);

CREATE INDEX IF NOT EXISTS idx_activities_scheduled ON follow_up_activities(scheduled_date);
CREATE INDEX IF NOT EXISTS idx_activities_status ON follow_up_activities(status);
CREATE INDEX IF NOT EXISTS idx_activities_referral ON follow_up_activities(referral_id);

CREATE INDEX IF NOT EXISTS idx_reviews_scheduled ON follow_up_reviews(scheduled_date);
CREATE INDEX IF NOT EXISTS idx_reviews_status ON follow_up_reviews(status);
CREATE INDEX IF NOT EXISTS idx_timeline_escalation_ref ON timeline_escalation_logs(referral_id);
