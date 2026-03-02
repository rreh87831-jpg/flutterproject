-- ============================================================================
-- PROBLEM B - IMPROVEMENT TRACKING TABLES (additive)
-- Compatible with existing schema in this project.
-- ============================================================================

CREATE TABLE IF NOT EXISTS improvement_snapshots (
    id BIGSERIAL PRIMARY KEY,
    child_id TEXT NOT NULL,
    referral_id BIGINT REFERENCES referrals(id) ON DELETE CASCADE,

    snapshot_type VARCHAR(20) NOT NULL CHECK (snapshot_type IN ('BASELINE', 'FOLLOWUP')),

    overall_score INTEGER,
    overall_risk_level VARCHAR(20),

    gm_score INTEGER,
    fm_score INTEGER,
    lc_score INTEGER,
    cog_score INTEGER,
    se_score INTEGER,

    autism_score INTEGER,
    adhd_score INTEGER,

    domain_breakdown JSONB DEFAULT '{}'::jsonb,
    milestones_achieved JSONB DEFAULT '[]'::jsonb,

    activities_completed INTEGER DEFAULT 0,
    total_activities INTEGER DEFAULT 0,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(referral_id, snapshot_type)
);

CREATE TABLE IF NOT EXISTS milestone_tracking (
    id BIGSERIAL PRIMARY KEY,
    child_id TEXT NOT NULL,
    milestone_id VARCHAR(50) NOT NULL,
    milestone_name VARCHAR(200),
    domain VARCHAR(20),
    achieved_date DATE NOT NULL DEFAULT CURRENT_DATE,
    achieved_through_activity_id BIGINT REFERENCES follow_up_activities(id),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS improvement_summary (
    id BIGSERIAL PRIMARY KEY,
    child_id TEXT NOT NULL,
    referral_id BIGINT REFERENCES referrals(id) ON DELETE CASCADE,

    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    total_days INTEGER,

    overall_improvement INTEGER,
    overall_improvement_percentage DECIMAL(5,2),
    risk_level_change VARCHAR(50),

    gm_improvement INTEGER,
    fm_improvement INTEGER,
    lc_improvement INTEGER,
    cog_improvement INTEGER,
    se_improvement INTEGER,

    autism_improvement INTEGER,
    adhd_improvement INTEGER,

    activities_assigned INTEGER DEFAULT 0,
    activities_completed INTEGER DEFAULT 0,
    completion_rate DECIMAL(5,2) DEFAULT 0,

    milestones_achieved_count INTEGER DEFAULT 0,
    milestones_list JSONB DEFAULT '[]'::jsonb,
    recommendations JSONB DEFAULT '[]'::jsonb,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS improvement_table (
    id BIGSERIAL PRIMARY KEY,
    child_id TEXT NOT NULL,
    referral_id BIGINT REFERENCES referrals(id) ON DELETE CASCADE,
    improvement_status INTEGER DEFAULT 0,
    completion DECIMAL(5,2) DEFAULT 0,
    completition DECIMAL(5,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS improvement_view_registry (
    awc_code TEXT PRIMARY KEY,
    table_name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE improvement_table ADD COLUMN IF NOT EXISTS improvement INTEGER DEFAULT 0;
ALTER TABLE improvement_table ADD COLUMN IF NOT EXISTS improvement_status INTEGER DEFAULT 0;
ALTER TABLE improvement_table ADD COLUMN IF NOT EXISTS completion DECIMAL(5,2) DEFAULT 0;
ALTER TABLE improvement_table ADD COLUMN IF NOT EXISTS completition DECIMAL(5,2) DEFAULT 0;
UPDATE improvement_table
SET improvement_status = COALESCE(NULLIF(improvement_status, 0), NULLIF(improvement, 0), 0),
    improvement = COALESCE(NULLIF(improvement, 0), NULLIF(improvement_status, 0), 0),
    completion = COALESCE(completion, completition, 0),
    completition = COALESCE(completition, completion, 0)
WHERE improvement_status IS NULL
   OR improvement IS NULL
   OR (improvement_status = 0 AND COALESCE(improvement, 0) <> 0)
   OR (improvement = 0 AND COALESCE(improvement_status, 0) <> 0)
   OR completion IS NULL
   OR completition IS NULL;

CREATE TABLE IF NOT EXISTS improvement_images (
    id BIGSERIAL PRIMARY KEY,
    child_id TEXT NOT NULL,
    summary_id BIGINT REFERENCES improvement_summary(id) ON DELETE CASCADE,
    image_type VARCHAR(50) CHECK (image_type IN ('RADAR_CHART', 'PROGRESS_BAR', 'BEFORE_AFTER')),
    image_url TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_improvement_child ON improvement_summary(child_id);
CREATE INDEX IF NOT EXISTS idx_improvement_table_child ON improvement_table(child_id);
CREATE INDEX IF NOT EXISTS idx_snapshots_child ON improvement_snapshots(child_id);
CREATE INDEX IF NOT EXISTS idx_milestones_child ON milestone_tracking(child_id);
