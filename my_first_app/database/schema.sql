-- ============================================================================
-- PROBLEM B - REFERRAL + FOLLOW-UP SCHEMA (PostgreSQL)
-- Compatible with existing project tables without altering Problem A tables.
-- ============================================================================

-- Sequences for readable IDs.
CREATE SEQUENCE IF NOT EXISTS referrals_seq START 1;
CREATE SEQUENCE IF NOT EXISTS activities_seq START 1;

-- ============================================================================
-- 1) referrals
-- ============================================================================
CREATE TABLE IF NOT EXISTS referrals (
    id BIGSERIAL PRIMARY KEY,
    referral_id VARCHAR(50) UNIQUE NOT NULL
        DEFAULT ('REF-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(nextval('referrals_seq')::TEXT, 4, '0')),

    -- Child linkage (kept as TEXT to match existing child_profile.child_id usage).
    child_id TEXT NOT NULL,

    -- Snapshot from Risk Dashboard.
    overall_risk_score INTEGER NOT NULL,
    overall_risk_level VARCHAR(20) NOT NULL CHECK (overall_risk_level IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    num_delays INTEGER NOT NULL DEFAULT 0,

    -- Domain percentage scores.
    gm_score INTEGER DEFAULT 0,
    fm_score INTEGER DEFAULT 0,
    lc_score INTEGER DEFAULT 0,
    cog_score INTEGER DEFAULT 0,
    se_score INTEGER DEFAULT 0,
    autism_score INTEGER DEFAULT 0,
    adhd_score INTEGER DEFAULT 0,

    domain_breakdown JSONB NOT NULL DEFAULT '{}'::JSONB,

    -- Routing details.
    facility_type VARCHAR(50) NOT NULL,
    urgency VARCHAR(20) NOT NULL,
    deadline DATE NOT NULL,

    status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'IN_PROGRESS', 'COMPLETED', 'ESCALATED')),
    escalation_level INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 2) activity_library (master templates)
-- ============================================================================
CREATE TABLE IF NOT EXISTS activity_library (
    id BIGSERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    instructions_english TEXT,
    instructions_telugu TEXT,
    domain VARCHAR(20) NOT NULL CHECK (domain IN ('GM', 'FM', 'LC', 'COG', 'SE', 'NEURO', 'GENERAL')),
    target_role VARCHAR(20) NOT NULL CHECK (target_role IN ('CAREGIVER', 'AWW', 'BOTH')),
    frequency VARCHAR(20) NOT NULL DEFAULT 'DAILY' CHECK (frequency IN ('DAILY', 'WEEKLY', 'ONCE')),
    materials_needed TEXT,
    time_required_minutes INTEGER,
    visual_aid_url TEXT,
    risk_bucket VARCHAR(20) NOT NULL DEFAULT 'ALL' CHECK (risk_bucket IN ('ALL', 'HIGH', 'CRITICAL', 'MEDIUM')),
    target_completions INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 3) follow_up_activities (assigned per referral)
-- ============================================================================
CREATE TABLE IF NOT EXISTS follow_up_activities (
    id BIGSERIAL PRIMARY KEY,
    activity_id VARCHAR(50) UNIQUE NOT NULL
        DEFAULT ('ACT-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(nextval('activities_seq')::TEXT, 4, '0')),

    referral_id BIGINT NOT NULL REFERENCES referrals(id) ON DELETE CASCADE,
    child_id TEXT NOT NULL,

    title VARCHAR(200) NOT NULL,
    description TEXT,
    instructions_english TEXT,
    instructions_telugu TEXT,

    domain VARCHAR(20) CHECK (domain IN ('GM', 'FM', 'LC', 'COG', 'SE', 'NEURO', 'GENERAL')),
    target_role VARCHAR(20) NOT NULL CHECK (target_role IN ('CAREGIVER', 'AWW', 'BOTH')),
    frequency VARCHAR(20) NOT NULL DEFAULT 'DAILY' CHECK (frequency IN ('DAILY', 'WEEKLY', 'ONCE')),
    due_date DATE NOT NULL,

    materials_needed TEXT,
    time_required_minutes INTEGER,
    visual_aid_url TEXT,

    status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'COMPLETED', 'MISSED', 'SKIPPED')),
    completed_at TIMESTAMP,

    target_completions INTEGER NOT NULL DEFAULT 1,
    current_completions INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 4) activity_log (daily completion log)
-- ============================================================================
CREATE TABLE IF NOT EXISTS activity_log (
    id BIGSERIAL PRIMARY KEY,
    activity_id BIGINT NOT NULL REFERENCES follow_up_activities(id) ON DELETE CASCADE,
    child_id TEXT NOT NULL,
    log_date DATE NOT NULL DEFAULT CURRENT_DATE,
    completed BOOLEAN NOT NULL DEFAULT FALSE,
    completed_at TIMESTAMP,
    caregiver_notes TEXT,
    difficulty_rating INTEGER CHECK (difficulty_rating BETWEEN 1 AND 5),
    reported_by VARCHAR(50),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(activity_id, log_date)
);

-- ============================================================================
-- 5) escalation_logs
-- ============================================================================
CREATE TABLE IF NOT EXISTS escalation_logs (
    id BIGSERIAL PRIMARY KEY,
    referral_id BIGINT NOT NULL REFERENCES referrals(id) ON DELETE CASCADE,
    previous_level INTEGER NOT NULL,
    new_level INTEGER NOT NULL,
    reason TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 6) caregiver_preferences
-- ============================================================================
CREATE TABLE IF NOT EXISTS caregiver_preferences (
    id BIGSERIAL PRIMARY KEY,
    child_id TEXT NOT NULL UNIQUE,
    caregiver_name VARCHAR(100),
    phone VARCHAR(20),
    preferred_language VARCHAR(10) NOT NULL DEFAULT 'telugu',
    notification_time TIME NOT NULL DEFAULT '09:00:00',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Performance indexes.
CREATE INDEX IF NOT EXISTS idx_referrals_child ON referrals(child_id);
CREATE INDEX IF NOT EXISTS idx_referrals_status ON referrals(status);
CREATE INDEX IF NOT EXISTS idx_referrals_deadline ON referrals(deadline);
CREATE INDEX IF NOT EXISTS idx_referrals_risk_level ON referrals(overall_risk_level);

CREATE INDEX IF NOT EXISTS idx_activities_referral ON follow_up_activities(referral_id);
CREATE INDEX IF NOT EXISTS idx_activities_child ON follow_up_activities(child_id);
CREATE INDEX IF NOT EXISTS idx_activities_role ON follow_up_activities(target_role);
CREATE INDEX IF NOT EXISTS idx_activities_due ON follow_up_activities(due_date);
CREATE INDEX IF NOT EXISTS idx_activities_status ON follow_up_activities(status);

CREATE INDEX IF NOT EXISTS idx_activity_log_date ON activity_log(log_date);
CREATE INDEX IF NOT EXISTS idx_activity_log_completed ON activity_log(completed);

-- ============================================================================
-- Functions
-- ============================================================================
CREATE OR REPLACE FUNCTION calculate_activity_progress(p_activity_id BIGINT)
RETURNS INTEGER AS $$
DECLARE
    v_target INTEGER;
    v_current INTEGER;
BEGIN
    SELECT target_completions, current_completions
    INTO v_target, v_current
    FROM follow_up_activities
    WHERE id = p_activity_id;

    IF COALESCE(v_target, 0) <= 0 THEN
        RETURN 0;
    END IF;

    RETURN GREATEST(0, LEAST(100, ((COALESCE(v_current, 0)::FLOAT / v_target::FLOAT) * 100)::INTEGER));
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_escalation()
RETURNS TABLE (
    referral_id BIGINT,
    old_level INTEGER,
    new_level INTEGER
) AS $$
BEGIN
    RETURN QUERY
    WITH overdue AS (
        UPDATE referrals
        SET escalation_level = escalation_level + 1,
            status = 'ESCALATED',
            updated_at = CURRENT_TIMESTAMP
        WHERE deadline < CURRENT_DATE
          AND status NOT IN ('COMPLETED', 'ESCALATED')
        RETURNING id, escalation_level - 1 AS old_level, escalation_level AS new_level
    )
    SELECT id, old_level, new_level FROM overdue;
END;
$$ LANGUAGE plpgsql;
