from __future__ import annotations

import os
import re
import uuid
from collections import Counter
from datetime import datetime, date, timedelta
from typing import Any, Dict, List, Optional
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

if __package__:
    from .model_service import (
        load_artifacts,
        load_domain_models,
        load_neuro_behavior_models,
        predict_neuro_behavioral_risks,
        predict_domain_delays,
        predict_risk,
    )
    from .nutrition_model_service import (
        load_nutrition_model,
        predict_nutrition_risk as predict_nutrition_risk_ml,
    )
    from .intervention import generate_intervention, calculate_trend
    from .problem_b_service import ProblemBService
    from .pg_compat import get_conn
else:
    # Support running file directly: python main.py
    from model_service import (
        load_artifacts,
        load_domain_models,
        load_neuro_behavior_models,
        predict_neuro_behavioral_risks,
        predict_domain_delays,
        predict_risk,
    )
    from nutrition_model_service import (
        load_nutrition_model,
        predict_nutrition_risk as predict_nutrition_risk_ml,
    )
    from intervention import generate_intervention, calculate_trend
    from problem_b_service import ProblemBService
    from pg_compat import get_conn

try:
    if __package__:
        from .problem_b_activity_engine import (
            assign_activities_for_child,
            compute_compliance,
            derive_severity,
            determine_next_action,
            escalation_decision,
            plan_regeneration_summary,
            projection_from_compliance,
            reset_frequency_status,
            weekly_progress_rows,
        )
    else:
        from problem_b_activity_engine import (
            assign_activities_for_child,
            compute_compliance,
            derive_severity,
            determine_next_action,
            escalation_decision,
            plan_regeneration_summary,
            projection_from_compliance,
            reset_frequency_status,
            weekly_progress_rows,
        )
except ImportError:
    # Legacy module not required for problem_b_service - can be skipped
    assign_activities_for_child = None
    compute_compliance = None
    derive_severity = None
    determine_next_action = None
    escalation_decision = None
    plan_regeneration_summary = None
    projection_from_compliance = None
    reset_frequency_status = None
    weekly_progress_rows = None

DEFAULT_ECD_DATABASE_URL = "postgresql://postgres:postgres@127.0.0.1:5432/ecd_data"
_AWC_DEMO_PATTERN = re.compile(r"^(AWW|AWS)_DEMO_(\d{3,4})$")
_AWC_DEMO_REVERSED_PATTERN = re.compile(r"^DEMO_(AWW|AWS)_(\d{3,4})$")


def _normalize_awc_code(value: Optional[str], prefer_prefix: str = "AWW") -> str:
    raw = (value or "").strip().upper()
    if not raw:
        return ""
    match = _AWC_DEMO_PATTERN.fullmatch(raw)
    if not match:
        reversed_match = _AWC_DEMO_REVERSED_PATTERN.fullmatch(raw)
        if reversed_match:
            match = reversed_match
    if not match:
        return raw
    suffix = match.group(2)
    prefix = "AWS" if prefer_prefix.upper() == "AWS" else "AWW"
    return f"{prefix}_DEMO_{suffix}"


def _awc_code_variants(value: Optional[str]) -> List[str]:
    normalized = _normalize_awc_code(value, prefer_prefix="AWW")
    if not normalized:
        return []
    match = _AWC_DEMO_PATTERN.fullmatch(normalized)
    if not match:
        return [normalized]
    suffix = match.group(2)
    return [f"AWW_DEMO_{suffix}", f"AWS_DEMO_{suffix}"]


def _awc_codes_equal(left: Optional[str], right: Optional[str]) -> bool:
    left_variants = set(_awc_code_variants(left))
    right_variants = set(_awc_code_variants(right))
    if left_variants and right_variants:
        return not left_variants.isdisjoint(right_variants)
    return _normalize_awc_code(left) == _normalize_awc_code(right)


class LoginRequest(BaseModel):
    awc_code: Optional[str] = None
    mobile_number: Optional[str] = None
    password: str


class LoginResponse(BaseModel):
    token: str
    user_id: str


class RegistrationRequest(BaseModel):
    name: Optional[str] = ""
    mobile_number: Optional[str] = ""
    password: str
    awc_code: str
    mandal: Optional[str] = None
    district: Optional[str] = None


class ScreeningRequest(BaseModel):
    child_id: str
    age_months: int
    domain_responses: Dict[str, List[int]]
    aww_id: Optional[str] = None
    child_name: Optional[str] = None
    village: Optional[str] = None
    # Optional context fields if frontend sends later
    gender: Optional[str] = None
    awc_id: Optional[str] = None
    awc_code: Optional[str] = None
    sector_id: Optional[str] = None
    mandal: Optional[str] = None
    district: Optional[str] = None
    assessment_cycle: Optional[str] = "Baseline"


class ScreeningResponse(BaseModel):
    risk_level: str
    domain_scores: Dict[str, str]
    explanation: List[str]
    delay_summary: Dict[str, int]
    model_source: Optional[str] = None
    referral_created: bool = False
    referral_data: Optional[Dict[str, str]] = None


class NutritionPredictRequest(BaseModel):
    child_id: Optional[str] = None
    age_months: int
    features: Dict[str, Any] = Field(default_factory=dict)


class NutritionSubmitRequest(BaseModel):
    child_id: str
    age_months: int
    awc_code: Optional[str] = None
    aww_id: Optional[str] = None
    waz: Optional[float] = None
    haz: Optional[float] = None
    whz: Optional[float] = None
    underweight: int = 0
    stunting: int = 0
    wasting: int = 0
    anemia: int = 0
    nutrition_score: int = 0
    risk_category: str = "Low"


class ReferralRequest(BaseModel):
    child_id: str
    aww_id: str
    age_months: int
    overall_risk: str
    domain_scores: Dict[str, float]
    referral_type: str
    urgency: str
    expected_follow_up: Optional[str] = None
    notes: Optional[str] = ""
    referral_timestamp: str


class ReferralResponse(BaseModel):
    referral_id: str
    status: str
    created_at: str


class ReferralStatusUpdateRequest(BaseModel):
    status: str
    appointment_date: Optional[str] = None
    completion_date: Optional[str] = None
    worker_id: Optional[str] = None


class ReferralStatusUpdateByIdRequest(BaseModel):
    referral_id: str
    status: str
    appointment_date: Optional[str] = None
    completion_date: Optional[str] = None
    worker_id: Optional[str] = None


class ReferralEscalateRequest(BaseModel):
    worker_id: Optional[str] = None


class ChildRegisterRequest(BaseModel):
    child_id: str
    child_name: Optional[str] = None
    gender: Optional[str] = None
    age_months: Optional[int] = None
    date_of_birth: Optional[str] = None
    dob: Optional[str] = None
    awc_id: Optional[str] = None
    awc_code: Optional[str] = None
    sector_id: Optional[str] = None
    mandal_id: Optional[str] = None
    mandal: Optional[str] = None
    district_id: Optional[str] = None
    district: Optional[str] = None
    village: Optional[str] = None
    assessment_cycle: Optional[str] = None
    parent_name: Optional[str] = None
    parent_mobile: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


def _get_conn(db_url: str):
    return get_conn(db_url)


def _refresh_child_profile_filter_tables(conn) -> None:
    """Rebuild filtered child profile tables from the canonical child_profile table."""
    conn.execute("TRUNCATE TABLE child_profile_by_district")
    conn.execute(
        """
        INSERT INTO child_profile_by_district(
          child_id, dob, awc_code, district, mandal, assessment_cycle
        )
        SELECT
          child_id,
          dob,
          awc_code,
          BTRIM(district),
          NULLIF(BTRIM(mandal), ''),
          assessment_cycle
        FROM child_profile
        WHERE COALESCE(BTRIM(district), '') <> ''
        """
    )

    conn.execute("TRUNCATE TABLE child_profile_by_mandal")
    conn.execute(
        """
        INSERT INTO child_profile_by_mandal(
          child_id, dob, awc_code, district, mandal, assessment_cycle
        )
        SELECT
          child_id,
          dob,
          awc_code,
          NULLIF(BTRIM(district), ''),
          BTRIM(mandal),
          assessment_cycle
        FROM child_profile
        WHERE COALESCE(BTRIM(mandal), '') <> ''
        """
    )

    conn.execute("TRUNCATE TABLE child_profile_by_anganwadi")
    conn.execute(
        """
        INSERT INTO child_profile_by_anganwadi(
          child_id, dob, awc_code, district, mandal, assessment_cycle
        )
        SELECT
          child_id,
          dob,
          BTRIM(awc_code),
          NULLIF(BTRIM(district), ''),
          NULLIF(BTRIM(mandal), ''),
          assessment_cycle
        FROM child_profile
        WHERE COALESCE(BTRIM(awc_code), '') <> ''
        """
    )

    awc_rows = conn.execute(
        """
        SELECT DISTINCT BTRIM(awc_code) AS awc_code
        FROM child_profile_by_anganwadi
        WHERE COALESCE(BTRIM(awc_code), '') <> ''
        """
    ).fetchall()
    for row in awc_rows:
        awc_code = str(row.get("awc_code") or "").strip()
        if not awc_code:
            continue
        conn.execute(
            "SELECT refresh_anganwadi_child_table(%s)",
            (awc_code,),
        )


def _init_db(db_url: str) -> None:
    with _get_conn(db_url) as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS aww_profile (
              aww_id TEXT PRIMARY KEY,
              name TEXT,
              mobile_number TEXT UNIQUE,
              password TEXT,
              awc_code TEXT,
              mandal TEXT,
              district TEXT,
              created_at TEXT,
              updated_at TEXT
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS child_profile (
              child_id TEXT,
              dob TEXT,
              gender TEXT,
              awc_code TEXT,
              district TEXT,
              mandal TEXT,
              assessment_cycle TEXT
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS child_profile_by_district (
              child_id TEXT,
              dob TEXT,
              awc_code TEXT,
              district TEXT NOT NULL,
              mandal TEXT,
              assessment_cycle TEXT
            )
            """
        )
        conn.execute("CREATE INDEX IF NOT EXISTS idx_child_profile_by_district_district ON child_profile_by_district(district)")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS child_profile_by_mandal (
              child_id TEXT,
              dob TEXT,
              awc_code TEXT,
              district TEXT,
              mandal TEXT NOT NULL,
              assessment_cycle TEXT
            )
            """
        )
        conn.execute("CREATE INDEX IF NOT EXISTS idx_child_profile_by_mandal_mandal ON child_profile_by_mandal(mandal)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_child_profile_by_mandal_district ON child_profile_by_mandal(district)")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS child_profile_by_anganwadi (
              child_id TEXT,
              dob TEXT,
              awc_code TEXT NOT NULL,
              district TEXT,
              mandal TEXT,
              assessment_cycle TEXT
            )
            """
        )
        conn.execute("CREATE INDEX IF NOT EXISTS idx_child_profile_by_anganwadi_awc_code ON child_profile_by_anganwadi(awc_code)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_child_profile_by_anganwadi_district ON child_profile_by_anganwadi(district)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_child_profile_by_anganwadi_mandal ON child_profile_by_anganwadi(mandal)")
        conn.execute(
            """
            UPDATE child_profile cp
            SET awc_code = REPLACE(
              REPLACE(
                REPLACE(UPPER(BTRIM(cp.awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                'DEMO_AWS_',
                'AWS_DEMO_'
              ),
              'AWS_DEMO_',
              'AWW_DEMO_'
            )
            WHERE COALESCE(BTRIM(cp.awc_code), '') <> ''
              AND UPPER(BTRIM(cp.awc_code)) <> REPLACE(
                REPLACE(
                  REPLACE(UPPER(BTRIM(cp.awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                  'DEMO_AWS_',
                  'AWS_DEMO_'
                ),
                'AWS_DEMO_',
                'AWW_DEMO_'
              )
              AND NOT EXISTS (
                SELECT 1
                FROM child_profile dup
                WHERE dup.child_id = cp.child_id
                  AND UPPER(BTRIM(COALESCE(dup.awc_code, ''))) = REPLACE(
                    REPLACE(
                      REPLACE(UPPER(BTRIM(cp.awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                      'DEMO_AWS_',
                      'AWS_DEMO_'
                    ),
                    'AWS_DEMO_',
                    'AWW_DEMO_'
                  )
                  AND dup.ctid <> cp.ctid
              )
            """
        )
        conn.execute(
            """
            UPDATE child_profile_by_district cp
            SET awc_code = REPLACE(
              REPLACE(
                REPLACE(UPPER(BTRIM(cp.awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                'DEMO_AWS_',
                'AWS_DEMO_'
              ),
              'AWS_DEMO_',
              'AWW_DEMO_'
            )
            WHERE COALESCE(BTRIM(cp.awc_code), '') <> ''
              AND UPPER(BTRIM(cp.awc_code)) <> REPLACE(
                REPLACE(
                  REPLACE(UPPER(BTRIM(cp.awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                  'DEMO_AWS_',
                  'AWS_DEMO_'
                ),
                'AWS_DEMO_',
                'AWW_DEMO_'
              )
              AND NOT EXISTS (
                SELECT 1
                FROM child_profile_by_district dup
                WHERE dup.child_id = cp.child_id
                  AND UPPER(BTRIM(COALESCE(dup.awc_code, ''))) = REPLACE(
                    REPLACE(
                      REPLACE(UPPER(BTRIM(cp.awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                      'DEMO_AWS_',
                      'AWS_DEMO_'
                    ),
                    'AWS_DEMO_',
                    'AWW_DEMO_'
                  )
                  AND dup.ctid <> cp.ctid
              )
            """
        )
        conn.execute(
            """
            UPDATE child_profile_by_mandal cp
            SET awc_code = REPLACE(
              REPLACE(
                REPLACE(UPPER(BTRIM(cp.awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                'DEMO_AWS_',
                'AWS_DEMO_'
              ),
              'AWS_DEMO_',
              'AWW_DEMO_'
            )
            WHERE COALESCE(BTRIM(cp.awc_code), '') <> ''
              AND UPPER(BTRIM(cp.awc_code)) <> REPLACE(
                REPLACE(
                  REPLACE(UPPER(BTRIM(cp.awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                  'DEMO_AWS_',
                  'AWS_DEMO_'
                ),
                'AWS_DEMO_',
                'AWW_DEMO_'
              )
              AND NOT EXISTS (
                SELECT 1
                FROM child_profile_by_mandal dup
                WHERE dup.child_id = cp.child_id
                  AND UPPER(BTRIM(COALESCE(dup.awc_code, ''))) = REPLACE(
                    REPLACE(
                      REPLACE(UPPER(BTRIM(cp.awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                      'DEMO_AWS_',
                      'AWS_DEMO_'
                    ),
                    'AWS_DEMO_',
                    'AWW_DEMO_'
                  )
                  AND dup.ctid <> cp.ctid
              )
            """
        )
        conn.execute(
            """
            UPDATE child_profile_by_anganwadi cp
            SET awc_code = REPLACE(
              REPLACE(
                REPLACE(UPPER(BTRIM(cp.awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                'DEMO_AWS_',
                'AWS_DEMO_'
              ),
              'AWS_DEMO_',
              'AWW_DEMO_'
            )
            WHERE COALESCE(BTRIM(cp.awc_code), '') <> ''
              AND UPPER(BTRIM(cp.awc_code)) <> REPLACE(
                REPLACE(
                  REPLACE(UPPER(BTRIM(cp.awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                  'DEMO_AWS_',
                  'AWS_DEMO_'
                ),
                'AWS_DEMO_',
                'AWW_DEMO_'
              )
              AND NOT EXISTS (
                SELECT 1
                FROM child_profile_by_anganwadi dup
                WHERE dup.child_id = cp.child_id
                  AND UPPER(BTRIM(COALESCE(dup.awc_code, ''))) = REPLACE(
                    REPLACE(
                      REPLACE(UPPER(BTRIM(cp.awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                      'DEMO_AWS_',
                      'AWS_DEMO_'
                    ),
                    'AWS_DEMO_',
                    'AWW_DEMO_'
                  )
                  AND dup.ctid <> cp.ctid
              )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS screening_event (
              id BIGSERIAL PRIMARY KEY,
              child_id TEXT,
              awc_code TEXT,
              age_months INTEGER,
              overall_risk TEXT,
              explainability TEXT,
              assessment_cycle TEXT,
              created_at TEXT
            )
            """
        )
        conn.execute("ALTER TABLE screening_event ADD COLUMN IF NOT EXISTS awc_code TEXT")
        conn.execute(
            """
            UPDATE screening_event
            SET awc_code = REPLACE(
              REPLACE(
                REPLACE(UPPER(BTRIM(awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                'DEMO_AWS_',
                'AWS_DEMO_'
              ),
              'AWS_DEMO_',
              'AWW_DEMO_'
            )
            WHERE COALESCE(BTRIM(awc_code), '') <> ''
            """
        )
        conn.execute(
            """
            UPDATE screening_event se
            SET awc_code = cp.awc_code
            FROM (
              SELECT child_id, MIN(awc_code) AS awc_code
              FROM child_profile
              GROUP BY child_id
              HAVING COUNT(DISTINCT awc_code) = 1
            ) cp
            WHERE se.child_id = cp.child_id
              AND COALESCE(BTRIM(se.awc_code), '') = ''
            """
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_screening_event_child_awc ON screening_event(child_id, awc_code)"
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS screening_domain_score (
              id BIGSERIAL PRIMARY KEY,
              screening_id BIGINT,
              domain TEXT,
              risk_label TEXT,
              score DOUBLE PRECISION
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS developmental_risk_score (
              id BIGSERIAL PRIMARY KEY,
              screening_id BIGINT,
              child_id TEXT,
              awc_code TEXT,
              age_months INTEGER,
              gm_delay INTEGER,
              fm_delay INTEGER,
              lc_delay INTEGER,
              cog_delay INTEGER,
              se_delay INTEGER,
              num_delays INTEGER,
              created_at TEXT
            )
            """
        )
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS ux_developmental_risk_score_screening_id "
            "ON developmental_risk_score(screening_id)"
        )
        conn.execute(
            "ALTER TABLE developmental_risk_score ADD COLUMN IF NOT EXISTS awc_code TEXT"
        )
        conn.execute(
            """
            UPDATE developmental_risk_score
            SET awc_code = REPLACE(
              REPLACE(
                REPLACE(UPPER(BTRIM(awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                'DEMO_AWS_',
                'AWS_DEMO_'
              ),
              'AWS_DEMO_',
              'AWW_DEMO_'
            )
            WHERE COALESCE(BTRIM(awc_code), '') <> ''
            """
        )
        conn.execute(
            """
            UPDATE developmental_risk_score dr
            SET awc_code = UPPER(BTRIM(COALESCE(se.awc_code, '')))
            FROM screening_event se
            WHERE dr.screening_id = se.id
              AND COALESCE(BTRIM(dr.awc_code), '') = ''
              AND COALESCE(BTRIM(se.awc_code), '') <> ''
            """
        )
        conn.execute(
            """
            DELETE FROM developmental_risk_score
            WHERE COALESCE(BTRIM(child_id), '') = ''
            """
        )
        conn.execute(
            "DROP INDEX IF EXISTS idx_developmental_risk_score_child_id"
        )
        conn.execute(
            "DROP INDEX IF EXISTS ux_developmental_risk_score_child_awc"
        )
        conn.execute(
            "DROP INDEX IF EXISTS ux_developmental_risk_score_child_id"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_developmental_risk_score_child_id "
            "ON developmental_risk_score(child_id)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_developmental_risk_score_awc_code "
            "ON developmental_risk_score(awc_code)"
        )
        conn.execute(
            """
            DELETE FROM developmental_risk_score dr
            USING screening_domain_score sds
            WHERE dr.screening_id = sds.screening_id
              AND UPPER(BTRIM(COALESCE(sds.domain, ''))) IN ('BPS_AUT', 'BPS_ADHD', 'BPS_BEH')
            """
        )
        conn.execute(
            """
            WITH domain_flags AS (
              SELECT
                screening_id,
                MAX(CASE WHEN UPPER(BTRIM(COALESCE(domain, ''))) = 'GM'
                  THEN CASE WHEN UPPER(BTRIM(COALESCE(risk_label, 'LOW'))) IN ('LOW', '') THEN 0 ELSE 1 END
                  ELSE 0 END) AS gm_delay,
                MAX(CASE WHEN UPPER(BTRIM(COALESCE(domain, ''))) = 'FM'
                  THEN CASE WHEN UPPER(BTRIM(COALESCE(risk_label, 'LOW'))) IN ('LOW', '') THEN 0 ELSE 1 END
                  ELSE 0 END) AS fm_delay,
                MAX(CASE WHEN UPPER(BTRIM(COALESCE(domain, ''))) = 'LC'
                  THEN CASE WHEN UPPER(BTRIM(COALESCE(risk_label, 'LOW'))) IN ('LOW', '') THEN 0 ELSE 1 END
                  ELSE 0 END) AS lc_delay,
                MAX(CASE WHEN UPPER(BTRIM(COALESCE(domain, ''))) = 'COG'
                  THEN CASE WHEN UPPER(BTRIM(COALESCE(risk_label, 'LOW'))) IN ('LOW', '') THEN 0 ELSE 1 END
                  ELSE 0 END) AS cog_delay,
                MAX(CASE WHEN UPPER(BTRIM(COALESCE(domain, ''))) = 'SE'
                  THEN CASE WHEN UPPER(BTRIM(COALESCE(risk_label, 'LOW'))) IN ('LOW', '') THEN 0 ELSE 1 END
                  ELSE 0 END) AS se_delay,
                MAX(CASE WHEN UPPER(BTRIM(COALESCE(domain, ''))) IN ('GM', 'FM', 'LC', 'COG', 'SE')
                  THEN 1 ELSE 0 END) AS has_dev_domain
              FROM screening_domain_score
              GROUP BY screening_id
            )
            INSERT INTO developmental_risk_score(
              screening_id, child_id, awc_code, age_months,
              gm_delay, fm_delay, lc_delay, cog_delay, se_delay, num_delays,
              created_at
            )
            SELECT
              se.id,
              se.child_id,
              REPLACE(
                REPLACE(
                  REPLACE(UPPER(BTRIM(COALESCE(se.awc_code, ''))), 'DEMO_AWW_', 'AWW_DEMO_'),
                  'DEMO_AWS_',
                  'AWS_DEMO_'
                ),
                'AWS_DEMO_',
                'AWW_DEMO_'
              ) AS awc_code,
              COALESCE(se.age_months, 0),
              df.gm_delay,
              df.fm_delay,
              df.lc_delay,
              df.cog_delay,
              df.se_delay,
              (df.gm_delay + df.fm_delay + df.lc_delay + df.cog_delay + df.se_delay) AS num_delays,
              COALESCE(NULLIF(BTRIM(COALESCE(se.created_at, '')), ''), now()::text)
            FROM screening_event se
            JOIN domain_flags df
              ON df.screening_id = se.id
             AND df.has_dev_domain = 1
            LEFT JOIN developmental_risk_score dr
              ON dr.screening_id = se.id
            WHERE dr.screening_id IS NULL
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS domain_delay_table (
              id BIGSERIAL PRIMARY KEY,
              screening_id BIGINT,
              child_id TEXT,
              awc_code TEXT,
              age_months INTEGER,
              gm_delay INTEGER,
              fm_delay INTEGER,
              lc_delay INTEGER,
              cog_delay INTEGER,
              se_delay INTEGER,
              num_delays INTEGER,
              created_at TEXT
            )
            """
        )
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS ux_domain_delay_table_screening_id "
            "ON domain_delay_table(screening_id)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_domain_delay_table_child_id "
            "ON domain_delay_table(child_id)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_domain_delay_table_awc_code "
            "ON domain_delay_table(awc_code)"
        )
        conn.execute(
            """
            UPDATE domain_delay_table
            SET awc_code = REPLACE(
              REPLACE(
                REPLACE(UPPER(BTRIM(awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                'DEMO_AWS_',
                'AWS_DEMO_'
              ),
              'AWS_DEMO_',
              'AWW_DEMO_'
            )
            WHERE COALESCE(BTRIM(awc_code), '') <> ''
            """
        )
        conn.execute(
            """
            UPDATE domain_delay_table ddt
            SET awc_code = UPPER(BTRIM(COALESCE(se.awc_code, '')))
            FROM screening_event se
            WHERE ddt.screening_id = se.id
              AND COALESCE(BTRIM(ddt.awc_code), '') = ''
              AND COALESCE(BTRIM(se.awc_code), '') <> ''
            """
        )
        conn.execute(
            """
            INSERT INTO domain_delay_table(
              screening_id, child_id, awc_code, age_months,
              gm_delay, fm_delay, lc_delay, cog_delay, se_delay, num_delays,
              created_at
            )
            SELECT
              dr.screening_id,
              dr.child_id,
              REPLACE(
                REPLACE(
                  REPLACE(
                    UPPER(
                      BTRIM(
                        COALESCE(
                          NULLIF(BTRIM(dr.awc_code), ''),
                          NULLIF(BTRIM(se.awc_code), ''),
                          ''
                        )
                      )
                    ),
                    'DEMO_AWW_',
                    'AWW_DEMO_'
                  ),
                  'DEMO_AWS_',
                  'AWS_DEMO_'
                ),
                'AWS_DEMO_',
                'AWW_DEMO_'
              ) AS awc_code,
              COALESCE(dr.age_months, se.age_months, 0),
              COALESCE(dr.gm_delay, 0),
              COALESCE(dr.fm_delay, 0),
              COALESCE(dr.lc_delay, 0),
              COALESCE(dr.cog_delay, 0),
              COALESCE(dr.se_delay, 0),
              COALESCE(
                dr.num_delays,
                COALESCE(dr.gm_delay, 0) + COALESCE(dr.fm_delay, 0) + COALESCE(dr.lc_delay, 0)
                + COALESCE(dr.cog_delay, 0) + COALESCE(dr.se_delay, 0)
              ),
              COALESCE(
                NULLIF(BTRIM(COALESCE(dr.created_at, '')), ''),
                NULLIF(BTRIM(COALESCE(se.created_at, '')), ''),
                now()::text
              )
            FROM developmental_risk_score dr
            LEFT JOIN screening_event se
              ON se.id = dr.screening_id
            LEFT JOIN domain_delay_table ddt
              ON ddt.screening_id = dr.screening_id
            WHERE dr.screening_id IS NOT NULL
              AND ddt.screening_id IS NULL
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS nutrition_result (
              id BIGSERIAL PRIMARY KEY,
              child_id TEXT NOT NULL,
              awc_code TEXT,
              aww_id TEXT,
              age_months INTEGER,
              waz DOUBLE PRECISION,
              haz DOUBLE PRECISION,
              whz DOUBLE PRECISION,
              underweight INTEGER,
              stunting INTEGER,
              wasting INTEGER,
              anemia INTEGER,
              nutrition_score INTEGER,
              risk_category TEXT,
              created_at TEXT
            )
            """
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_nutrition_result_child_id ON nutrition_result(child_id)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_nutrition_result_awc_code ON nutrition_result(awc_code)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_nutrition_result_created_at ON nutrition_result(created_at)"
        )
        conn.execute(
            """
            UPDATE nutrition_result
            SET awc_code = ''
            WHERE awc_code IS NULL
            """
        )
        conn.execute(
            """
            UPDATE nutrition_result
            SET awc_code = REPLACE(
              REPLACE(
                REPLACE(UPPER(BTRIM(awc_code)), 'DEMO_AWW_', 'AWW_DEMO_'),
                'DEMO_AWS_',
                'AWS_DEMO_'
              ),
              'AWS_DEMO_',
              'AWW_DEMO_'
            )
            WHERE COALESCE(BTRIM(awc_code), '') <> ''
            """
        )
        conn.execute(
            """
            DELETE FROM nutrition_result n
            USING nutrition_result d
            WHERE n.ctid < d.ctid
              AND COALESCE(n.child_id, '') = COALESCE(d.child_id, '')
              AND COALESCE(n.awc_code, '') = COALESCE(d.awc_code, '')
            """
        )
        conn.execute(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS ux_nutrition_result_child_awc
            ON nutrition_result(child_id, awc_code)
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS neuro_logical_risk (
              child_id TEXT,
              autism_risk TEXT,
              adhd_risk TEXT,
              behavioral_risk TEXT
            )
            """
        )
        conn.execute(
            "ALTER TABLE neuro_logical_risk ADD COLUMN IF NOT EXISTS child_id TEXT"
        )
        conn.execute(
            "ALTER TABLE neuro_logical_risk ADD COLUMN IF NOT EXISTS autism_risk TEXT"
        )
        conn.execute(
            "ALTER TABLE neuro_logical_risk ADD COLUMN IF NOT EXISTS adhd_risk TEXT"
        )
        conn.execute(
            "ALTER TABLE neuro_logical_risk ADD COLUMN IF NOT EXISTS behavioral_risk TEXT"
        )
        conn.execute(
            "DROP INDEX IF EXISTS ux_neuro_logical_risk_screening_id"
        )
        conn.execute(
            "DROP INDEX IF EXISTS idx_neuro_logical_risk_child_id"
        )
        conn.execute(
            "DROP INDEX IF EXISTS ux_neuro_logical_risk_child_awc"
        )
        conn.execute(
            "ALTER TABLE neuro_logical_risk DROP CONSTRAINT IF EXISTS neuro_logical_risk_pkey"
        )
        conn.execute("ALTER TABLE neuro_logical_risk DROP COLUMN IF EXISTS id")
        conn.execute("ALTER TABLE neuro_logical_risk DROP COLUMN IF EXISTS screening_id")
        conn.execute("ALTER TABLE neuro_logical_risk DROP COLUMN IF EXISTS age_months")
        conn.execute("ALTER TABLE neuro_logical_risk DROP COLUMN IF EXISTS overall_risk")
        conn.execute("ALTER TABLE neuro_logical_risk DROP COLUMN IF EXISTS model_source")
        conn.execute("ALTER TABLE neuro_logical_risk DROP COLUMN IF EXISTS created_at")
        conn.execute(
            """
            DELETE FROM neuro_logical_risk n
            USING neuro_logical_risk d
            WHERE n.ctid < d.ctid
              AND COALESCE(n.child_id, '') = COALESCE(d.child_id, '')
            """
        )
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS ux_neuro_logical_risk_child_id "
            "ON neuro_logical_risk(child_id)"
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS referral_action (
              referral_id TEXT PRIMARY KEY,
              child_id TEXT,
              aww_id TEXT,
              referral_required INTEGER,
              referral_type TEXT,
              urgency TEXT,
              referral_status TEXT,
              referral_date TEXT,
              completion_date TEXT
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS referral_status_history (
              id BIGSERIAL PRIMARY KEY,
              referral_id TEXT,
              old_status TEXT,
              new_status TEXT,
              changed_on TEXT,
              worker_id TEXT
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS followup_outcome (
              id BIGSERIAL PRIMARY KEY,
              child_id TEXT,
              baseline_delay_months INTEGER,
              followup_delay_months INTEGER,
              improvement_status TEXT,
              followup_completed INTEGER,
              followup_date TEXT
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS follow_up_activities (
              id BIGSERIAL PRIMARY KEY,
              referral_id TEXT,
              target_user TEXT,
              domain TEXT,
              activity_title TEXT,
              activity_description TEXT,
              frequency TEXT,
              duration_days INTEGER,
              created_on TEXT
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS follow_up_log (
              id BIGSERIAL PRIMARY KEY,
              referral_id TEXT,
              activity_id BIGINT,
              completed INTEGER DEFAULT 0,
              completed_on TEXT,
              remarks TEXT
            )
            """
        )
        conn.execute("ALTER TABLE referral_action ADD COLUMN IF NOT EXISTS appointment_date TEXT")
        conn.execute("ALTER TABLE referral_action ADD COLUMN IF NOT EXISTS followup_deadline TEXT")
        conn.execute("ALTER TABLE referral_action ADD COLUMN IF NOT EXISTS escalation_level INTEGER")
        conn.execute("ALTER TABLE referral_action ADD COLUMN IF NOT EXISTS escalated_to TEXT")
        conn.execute("ALTER TABLE referral_action ADD COLUMN IF NOT EXISTS last_updated TEXT")

        # Keep only core child_profile columns used by current registration flow.
        conn.execute("ALTER TABLE child_profile DROP COLUMN IF EXISTS child_name")
        conn.execute("ALTER TABLE child_profile DROP COLUMN IF EXISTS age_months")
        conn.execute("ALTER TABLE child_profile DROP COLUMN IF EXISTS village")
        conn.execute("ALTER TABLE child_profile DROP COLUMN IF EXISTS awc_id")
        conn.execute("ALTER TABLE child_profile DROP COLUMN IF EXISTS sector_id")
        conn.execute("ALTER TABLE child_profile DROP COLUMN IF EXISTS mandal_id")
        conn.execute("ALTER TABLE child_profile DROP COLUMN IF EXISTS district_id")
        conn.execute("ALTER TABLE child_profile DROP COLUMN IF EXISTS created_at")
        conn.execute("ALTER TABLE child_profile DROP COLUMN IF EXISTS updated_at")
        conn.execute("ALTER TABLE child_profile ADD COLUMN IF NOT EXISTS gender TEXT")
        conn.execute("UPDATE child_profile SET gender = '' WHERE gender IS NULL")
        conn.execute(
            """
            UPDATE child_profile
            SET gender = CASE
              WHEN LOWER(BTRIM(gender)) IN ('m', 'male') THEN 'M'
              WHEN LOWER(BTRIM(gender)) IN ('f', 'female') THEN 'F'
              ELSE ''
            END
            """
        )
        conn.execute("UPDATE child_profile SET awc_code = '' WHERE awc_code IS NULL")
        conn.execute("UPDATE child_profile_by_district SET awc_code = '' WHERE awc_code IS NULL")
        conn.execute("UPDATE child_profile_by_mandal SET awc_code = '' WHERE awc_code IS NULL")
        conn.execute("UPDATE child_profile_by_anganwadi SET awc_code = '' WHERE awc_code IS NULL")
        conn.execute("ALTER TABLE child_profile DROP CONSTRAINT IF EXISTS child_profile_pkey")
        conn.execute("ALTER TABLE child_profile_by_district DROP CONSTRAINT IF EXISTS child_profile_by_district_pkey")
        conn.execute("ALTER TABLE child_profile_by_mandal DROP CONSTRAINT IF EXISTS child_profile_by_mandal_pkey")
        conn.execute("ALTER TABLE child_profile_by_anganwadi DROP CONSTRAINT IF EXISTS child_profile_by_anganwadi_pkey")
        conn.execute("CREATE UNIQUE INDEX IF NOT EXISTS ux_child_profile_child_awc ON child_profile(child_id, awc_code)")
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS ux_child_profile_by_district_child_awc "
            "ON child_profile_by_district(child_id, awc_code)"
        )
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS ux_child_profile_by_mandal_child_awc "
            "ON child_profile_by_mandal(child_id, awc_code)"
        )
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS ux_child_profile_by_anganwadi_child_awc "
            "ON child_profile_by_anganwadi(child_id, awc_code)"
        )
        conn.execute(
            """
            CREATE OR REPLACE FUNCTION anganwadi_child_table_name(raw_awc_code TEXT)
            RETURNS TEXT
            AS $$
            DECLARE
              code TEXT;
              normalized TEXT;
            BEGIN
              code := UPPER(BTRIM(COALESCE(raw_awc_code, '')));
              code := REGEXP_REPLACE(code, '^DEMO_(AWW|AWS)_(\\d{3,4})$', 'AWW_DEMO_\\2');
              code := REGEXP_REPLACE(code, '^AWS_DEMO_(\\d{3,4})$', 'AWW_DEMO_\\1');
              normalized := REGEXP_REPLACE(
                LOWER(COALESCE(code, '')),
                '[^a-z0-9]+',
                '_',
                'g'
              );
              normalized := BTRIM(normalized, '_');
              IF normalized = '' THEN
                normalized := 'unknown';
              END IF;
              RETURN 'child_profile_awc_' || normalized;
            END;
            $$ LANGUAGE plpgsql IMMUTABLE
            """
        )
        conn.execute(
            """
            CREATE OR REPLACE FUNCTION ensure_anganwadi_child_table(raw_awc_code TEXT)
            RETURNS TEXT
            AS $$
            DECLARE
              table_name TEXT;
            BEGIN
              table_name := anganwadi_child_table_name(raw_awc_code);
              EXECUTE format(
                'CREATE TABLE IF NOT EXISTS %I (
                  child_id TEXT PRIMARY KEY,
                  dob TEXT,
                  awc_code TEXT NOT NULL,
                  district TEXT,
                  mandal TEXT,
                  assessment_cycle TEXT
                )',
                table_name
              );
              RETURN table_name;
            END;
            $$ LANGUAGE plpgsql
            """
        )
        conn.execute(
            """
            CREATE OR REPLACE FUNCTION refresh_anganwadi_child_table(raw_awc_code TEXT)
            RETURNS TEXT
            AS $$
            DECLARE
              code TEXT;
              table_name TEXT;
            BEGIN
              code := NULLIF(BTRIM(raw_awc_code), '');
              IF code IS NULL THEN
                RETURN NULL;
              END IF;
              code := UPPER(code);
              code := REGEXP_REPLACE(code, '^DEMO_(AWW|AWS)_(\\d{3,4})$', 'AWW_DEMO_\\2');
              code := REGEXP_REPLACE(code, '^AWS_DEMO_(\\d{3,4})$', 'AWW_DEMO_\\1');
              table_name := ensure_anganwadi_child_table(code);
              EXECUTE format('TRUNCATE TABLE %I', table_name);
              EXECUTE format(
                'INSERT INTO %I (
                  child_id, dob, awc_code, district, mandal, assessment_cycle
                )
                SELECT
                  child_id, dob, awc_code, district, mandal, assessment_cycle
                FROM child_profile_by_anganwadi
                WHERE UPPER(BTRIM(COALESCE(awc_code, ''''))) = $1',
                table_name
              ) USING code;
              RETURN table_name;
            END;
            $$ LANGUAGE plpgsql
            """
        )
        conn.execute(
            """
            CREATE OR REPLACE FUNCTION anganwadi_developmental_table_name(raw_awc_code TEXT)
            RETURNS TEXT
            AS $$
            DECLARE
              code TEXT;
              normalized TEXT;
            BEGIN
              code := UPPER(BTRIM(COALESCE(raw_awc_code, '')));
              code := REGEXP_REPLACE(code, '^DEMO_(AWW|AWS)_(\\d{3,4})$', 'AWW_DEMO_\\2');
              code := REGEXP_REPLACE(code, '^AWS_DEMO_(\\d{3,4})$', 'AWW_DEMO_\\1');
              normalized := REGEXP_REPLACE(
                LOWER(COALESCE(code, '')),
                '[^a-z0-9]+',
                '_',
                'g'
              );
              normalized := BTRIM(normalized, '_');
              IF normalized = '' THEN
                normalized := 'unknown';
              END IF;
              RETURN 'developmental_risk_score_awc_' || normalized;
            END;
            $$ LANGUAGE plpgsql IMMUTABLE
            """
        )
        conn.execute(
            """
            CREATE OR REPLACE FUNCTION ensure_anganwadi_developmental_table(raw_awc_code TEXT)
            RETURNS TEXT
            AS $$
            DECLARE
              table_name TEXT;
              idx_child_name TEXT;
              idx_screening_name TEXT;
              pk_name TEXT;
              pk_def TEXT;
            BEGIN
              table_name := anganwadi_developmental_table_name(raw_awc_code);
              idx_child_name := table_name || '_child_idx';
              idx_screening_name := table_name || '_screening_idx';
              EXECUTE format(
                'CREATE TABLE IF NOT EXISTS %I (
                  id BIGSERIAL PRIMARY KEY,
                  screening_id BIGINT,
                  child_id TEXT,
                  age_months INTEGER,
                  gm_delay INTEGER,
                  fm_delay INTEGER,
                  lc_delay INTEGER,
                  cog_delay INTEGER,
                  se_delay INTEGER,
                  num_delays INTEGER,
                  created_at TEXT
                )',
                table_name
              );
              SELECT c.conname, pg_get_constraintdef(c.oid)
              INTO pk_name, pk_def
              FROM pg_constraint c
              JOIN pg_class t ON t.oid = c.conrelid
              WHERE c.contype = 'p'
                AND t.relname = table_name
              LIMIT 1;

              IF pk_name IS NOT NULL AND pk_def ILIKE '%child_id%' THEN
                EXECUTE format('ALTER TABLE %I DROP CONSTRAINT %I', table_name, pk_name);
              END IF;

              EXECUTE format(
                'CREATE INDEX IF NOT EXISTS %I ON %I(child_id)',
                idx_child_name,
                table_name
              );
              EXECUTE format(
                'CREATE INDEX IF NOT EXISTS %I ON %I(screening_id)',
                idx_screening_name,
                table_name
              );
              RETURN table_name;
            END;
            $$ LANGUAGE plpgsql
            """
        )
        conn.execute(
            """
            CREATE OR REPLACE FUNCTION upsert_anganwadi_developmental_risk(
              raw_awc_code TEXT,
              p_child_id TEXT,
              p_screening_id BIGINT,
              p_age_months INTEGER,
              p_gm_delay INTEGER,
              p_fm_delay INTEGER,
              p_lc_delay INTEGER,
              p_cog_delay INTEGER,
              p_se_delay INTEGER,
              p_num_delays INTEGER,
              p_created_at TEXT
            )
            RETURNS TEXT
            AS $$
            DECLARE
              code TEXT;
              table_name TEXT;
            BEGIN
              code := NULLIF(BTRIM(raw_awc_code), '');
              IF code IS NULL THEN
                RETURN NULL;
              END IF;
              code := UPPER(code);
              code := REGEXP_REPLACE(code, '^DEMO_(AWW|AWS)_(\\d{3,4})$', 'AWW_DEMO_\\2');
              code := REGEXP_REPLACE(code, '^AWS_DEMO_(\\d{3,4})$', 'AWW_DEMO_\\1');

              table_name := ensure_anganwadi_developmental_table(code);

              EXECUTE format(
                'INSERT INTO %I(
                  child_id, screening_id, age_months,
                  gm_delay, fm_delay, lc_delay, cog_delay, se_delay, num_delays,
                  created_at
                )
                VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)',
                table_name
              )
              USING
                p_child_id,
                p_screening_id,
                p_age_months,
                p_gm_delay,
                p_fm_delay,
                p_lc_delay,
                p_cog_delay,
                p_se_delay,
                p_num_delays,
                p_created_at;

              RETURN table_name;
            END;
            $$ LANGUAGE plpgsql
            """
        )
        conn.execute(
            """
            CREATE OR REPLACE FUNCTION anganwadi_nutrition_table_name(raw_awc_code TEXT)
            RETURNS TEXT
            AS $$
            DECLARE
              code TEXT;
              normalized TEXT;
            BEGIN
              code := UPPER(BTRIM(COALESCE(raw_awc_code, '')));
              code := REGEXP_REPLACE(code, '^DEMO_(AWW|AWS)_(\\d{3,4})$', 'AWW_DEMO_\\2');
              code := REGEXP_REPLACE(code, '^AWS_DEMO_(\\d{3,4})$', 'AWW_DEMO_\\1');
              normalized := REGEXP_REPLACE(
                LOWER(COALESCE(code, '')),
                '[^a-z0-9]+',
                '_',
                'g'
              );
              normalized := BTRIM(normalized, '_');
              IF normalized = '' THEN
                normalized := 'unknown';
              END IF;
              RETURN 'nutrition_result_awc_' || normalized;
            END;
            $$ LANGUAGE plpgsql IMMUTABLE
            """
        )
        conn.execute(
            """
            CREATE OR REPLACE FUNCTION ensure_anganwadi_nutrition_table(raw_awc_code TEXT)
            RETURNS TEXT
            AS $$
            DECLARE
              table_name TEXT;
              idx_child_name TEXT;
              idx_created_name TEXT;
            BEGIN
              table_name := anganwadi_nutrition_table_name(raw_awc_code);
              idx_child_name := table_name || '_child_idx';
              idx_created_name := table_name || '_created_idx';
              EXECUTE format(
                'CREATE TABLE IF NOT EXISTS %I (
                  id BIGSERIAL PRIMARY KEY,
                  child_id TEXT NOT NULL,
                  aww_id TEXT,
                  age_months INTEGER,
                  waz DOUBLE PRECISION,
                  haz DOUBLE PRECISION,
                  whz DOUBLE PRECISION,
                  underweight INTEGER,
                  stunting INTEGER,
                  wasting INTEGER,
                  anemia INTEGER,
                  nutrition_score INTEGER,
                  risk_category TEXT,
                  created_at TEXT
                )',
                table_name
              );
              EXECUTE format(
                'CREATE INDEX IF NOT EXISTS %I ON %I(child_id)',
                idx_child_name,
                table_name
              );
              EXECUTE format(
                'CREATE INDEX IF NOT EXISTS %I ON %I(created_at)',
                idx_created_name,
                table_name
              );
              RETURN table_name;
            END;
            $$ LANGUAGE plpgsql
            """
        )
        conn.execute(
            """
            CREATE OR REPLACE FUNCTION insert_anganwadi_nutrition_result(
              raw_awc_code TEXT,
              p_child_id TEXT,
              p_aww_id TEXT,
              p_age_months INTEGER,
              p_waz DOUBLE PRECISION,
              p_haz DOUBLE PRECISION,
              p_whz DOUBLE PRECISION,
              p_underweight INTEGER,
              p_stunting INTEGER,
              p_wasting INTEGER,
              p_anemia INTEGER,
              p_nutrition_score INTEGER,
              p_risk_category TEXT,
              p_created_at TEXT
            )
            RETURNS TEXT
            AS $$
            DECLARE
              code TEXT;
              table_name TEXT;
            BEGIN
              code := NULLIF(BTRIM(raw_awc_code), '');
              IF code IS NULL THEN
                RETURN NULL;
              END IF;
              code := UPPER(code);
              code := REGEXP_REPLACE(code, '^DEMO_(AWW|AWS)_(\\d{3,4})$', 'AWW_DEMO_\\2');
              code := REGEXP_REPLACE(code, '^AWS_DEMO_(\\d{3,4})$', 'AWW_DEMO_\\1');

              table_name := ensure_anganwadi_nutrition_table(code);

              EXECUTE format(
                'DELETE FROM %I WHERE child_id = $1',
                table_name
              )
              USING p_child_id;

              EXECUTE format(
                'INSERT INTO %I(
                  child_id, aww_id, age_months,
                  waz, haz, whz,
                  underweight, stunting, wasting, anemia,
                  nutrition_score, risk_category, created_at
                )
                VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)',
                table_name
              )
              USING
                p_child_id,
                p_aww_id,
                p_age_months,
                p_waz,
                p_haz,
                p_whz,
                p_underweight,
                p_stunting,
                p_wasting,
                p_anemia,
                p_nutrition_score,
                p_risk_category,
                p_created_at;

              RETURN table_name;
            END;
            $$ LANGUAGE plpgsql
            """
        )
        conn.execute(
            """
            CREATE OR REPLACE FUNCTION sync_child_profile_filter_tables_fn()
            RETURNS TRIGGER
            AS $$
            DECLARE
              old_awc TEXT;
              new_awc TEXT;
              old_table TEXT;
              new_table TEXT;
            BEGIN
              old_awc := NULL;
              new_awc := NULL;
              IF TG_OP IN ('UPDATE', 'DELETE') THEN
                old_awc := NULLIF(BTRIM(COALESCE(OLD.awc_code, '')), '');
              END IF;
              IF TG_OP IN ('INSERT', 'UPDATE') THEN
                new_awc := NULLIF(BTRIM(COALESCE(NEW.awc_code, '')), '');
              END IF;

              IF TG_OP = 'DELETE' THEN
                DELETE FROM child_profile_by_district
                WHERE child_id = OLD.child_id
                  AND awc_code = COALESCE(BTRIM(OLD.awc_code), '');
                DELETE FROM child_profile_by_mandal
                WHERE child_id = OLD.child_id
                  AND awc_code = COALESCE(BTRIM(OLD.awc_code), '');
                DELETE FROM child_profile_by_anganwadi
                WHERE child_id = OLD.child_id
                  AND awc_code = COALESCE(BTRIM(OLD.awc_code), '');
                IF old_awc IS NOT NULL THEN
                  old_table := ensure_anganwadi_child_table(old_awc);
                  EXECUTE format('DELETE FROM %I WHERE child_id = $1', old_table)
                  USING OLD.child_id;
                END IF;
                RETURN OLD;
              END IF;

              DELETE FROM child_profile_by_district
              WHERE child_id = NEW.child_id
                AND awc_code = COALESCE(BTRIM(NEW.awc_code), '');
              DELETE FROM child_profile_by_mandal
              WHERE child_id = NEW.child_id
                AND awc_code = COALESCE(BTRIM(NEW.awc_code), '');
              DELETE FROM child_profile_by_anganwadi
              WHERE child_id = NEW.child_id
                AND awc_code = COALESCE(BTRIM(NEW.awc_code), '');

              IF COALESCE(BTRIM(NEW.district), '') <> '' THEN
                INSERT INTO child_profile_by_district(
                  child_id, dob, awc_code, district, mandal, assessment_cycle
                )
                VALUES(
                  NEW.child_id,
                  NEW.dob,
                  NEW.awc_code,
                  BTRIM(NEW.district),
                  NULLIF(BTRIM(NEW.mandal), ''),
                  NEW.assessment_cycle
                );
              END IF;

              IF COALESCE(BTRIM(NEW.mandal), '') <> '' THEN
                INSERT INTO child_profile_by_mandal(
                  child_id, dob, awc_code, district, mandal, assessment_cycle
                )
                VALUES(
                  NEW.child_id,
                  NEW.dob,
                  NEW.awc_code,
                  NULLIF(BTRIM(NEW.district), ''),
                  BTRIM(NEW.mandal),
                  NEW.assessment_cycle
                );
              END IF;

              IF COALESCE(BTRIM(NEW.awc_code), '') <> '' THEN
                INSERT INTO child_profile_by_anganwadi(
                  child_id, dob, awc_code, district, mandal, assessment_cycle
                )
                VALUES(
                  NEW.child_id,
                  NEW.dob,
                  BTRIM(NEW.awc_code),
                  NULLIF(BTRIM(NEW.district), ''),
                  NULLIF(BTRIM(NEW.mandal), ''),
                  NEW.assessment_cycle
                );
              END IF;

              IF TG_OP = 'UPDATE' AND old_awc IS NOT NULL THEN
                old_table := ensure_anganwadi_child_table(old_awc);
                EXECUTE format('DELETE FROM %I WHERE child_id = $1', old_table)
                USING OLD.child_id;
              END IF;

              IF new_awc IS NOT NULL THEN
                new_table := ensure_anganwadi_child_table(new_awc);
                EXECUTE format(
                  'INSERT INTO %I(
                    child_id, dob, awc_code, district, mandal, assessment_cycle
                  )
                  VALUES($1, $2, $3, $4, $5, $6)
                  ON CONFLICT(child_id) DO UPDATE SET
                    dob = EXCLUDED.dob,
                    awc_code = EXCLUDED.awc_code,
                    district = EXCLUDED.district,
                    mandal = EXCLUDED.mandal,
                    assessment_cycle = EXCLUDED.assessment_cycle',
                  new_table
                )
                USING
                  NEW.child_id,
                  NEW.dob,
                  BTRIM(NEW.awc_code),
                  NULLIF(BTRIM(NEW.district), ''),
                  NULLIF(BTRIM(NEW.mandal), ''),
                  NEW.assessment_cycle;
              END IF;

              RETURN NEW;
            END;
            $$ LANGUAGE plpgsql
            """
        )
        conn.execute("DROP TRIGGER IF EXISTS trg_sync_child_profile_filter_tables ON child_profile")
        conn.execute(
            """
            CREATE TRIGGER trg_sync_child_profile_filter_tables
            AFTER INSERT OR UPDATE OR DELETE ON child_profile
            FOR EACH ROW
            EXECUTE FUNCTION sync_child_profile_filter_tables_fn()
            """
        )
        _refresh_child_profile_filter_tables(conn)


def _risk_rank(label: str) -> int:
    label = (label or "").strip().lower()
    order = {"low": 0, "medium": 1, "high": 2, "critical": 3}
    return order.get(label, 0)


def _normalize_risk(label: str) -> str:
    label = (label or "").strip().lower()
    if label in {"critical", "very high"}:
        return "Critical"
    if label == "high":
        return "High"
    if label in {"medium", "moderate"}:
        return "Medium"
    return "Low"


def _risk_score(label: str) -> float:
    return {"Low": 0.2, "Medium": 0.5, "High": 0.75, "Critical": 0.92}.get(_normalize_risk(label), 0.2)


def _extract_neuro_risk_labels(domain_scores: Dict[str, str]) -> Optional[Dict[str, str]]:
    if not domain_scores:
        return None

    by_key = {
        str(key).strip().upper(): _normalize_risk(str(value))
        for key, value in (domain_scores or {}).items()
    }

    autism = (
        by_key.get("BPS_AUT")
        or by_key.get("AUTISM")
        or by_key.get("AUT")
    )
    adhd = by_key.get("BPS_ADHD") or by_key.get("ADHD")
    behavioral = (
        by_key.get("BPS_BEH")
        or by_key.get("BEHAVIORAL")
        or by_key.get("BEHAVIOURAL")
        or by_key.get("BEHAVIOR")
    )

    if autism is None and adhd is None and behavioral is None:
        return None

    autism = autism or "Low"
    adhd = adhd or "Low"
    behavioral = behavioral or "Low"
    return {
        "autism_risk": autism,
        "adhd_risk": adhd,
        "behavioral_risk": behavioral,
    }


def _has_developmental_payload(payload: ScreeningRequest) -> bool:
    keys = {str(k).strip().upper() for k in (payload.domain_responses or {}).keys()}
    return any(k in {"GM", "FM", "LC", "COG", "SE"} for k in keys)


def _age_band(age_months: int) -> str:
    if age_months <= 12:
        return "0-12"
    if age_months <= 24:
        return "13-24"
    if age_months <= 36:
        return "25-36"
    if age_months <= 48:
        return "37-48"
    if age_months <= 60:
        return "49-60"
    return "61-72"


def _parse_date_safe(value: str | None) -> date | None:
    if not value:
        return None
    v = str(value).strip()
    if not v:
        return None
    try:
        return datetime.fromisoformat(v.replace("Z", "")).date()
    except ValueError:
        try:
            return datetime.strptime(v.split("T")[0], "%Y-%m-%d").date()
        except ValueError:
            return None


def _normalize_gender(value: Optional[str]) -> str:
    raw = (value or "").strip().lower()
    if raw in {"m", "male"}:
        return "M"
    if raw in {"f", "female"}:
        return "F"
    return ""


def _child_row_with_aliases(row: Any) -> Dict[str, Any]:
    data = dict(row)
    awc_code = _normalize_awc_code(str(data.get("awc_code") or data.get("awc_id") or ""), prefer_prefix="AWW")
    mandal = str(data.get("mandal") or "")
    district = str(data.get("district") or "")
    data["awc_code"] = awc_code
    data["awc_id"] = _normalize_awc_code(str(data.get("awc_id") or awc_code), prefer_prefix="AWW")
    data["sector_id"] = str(data.get("sector_id") or mandal)
    data["mandal_id"] = str(data.get("mandal_id") or mandal)
    data["district_id"] = str(data.get("district_id") or district)
    data["gender"] = _normalize_gender(str(data.get("gender") or ""))
    data.setdefault("child_name", "")
    data.setdefault("village", "")
    data.setdefault("age_months", 0)
    return data


def _resolve_screening_awc_code(conn: Any, payload: ScreeningRequest) -> str:
    # 1) Explicit AWC from payload always wins. Do not override it using old rows.
    explicit_awc = _normalize_awc_code(
        str(payload.awc_code or payload.awc_id or ""),
        prefer_prefix="AWW",
    )
    if explicit_awc:
        return explicit_awc

    # 2) Accept aww_id as fallback only when it is actually AWC-shaped.
    aww_fallback = _normalize_awc_code(str(payload.aww_id or ""), prefer_prefix="AWW")
    if _AWC_DEMO_PATTERN.fullmatch(aww_fallback):
        return aww_fallback

    # 3) Last fallback: infer from existing child rows.
    child_awc_rows = conn.execute(
        """
        SELECT DISTINCT UPPER(BTRIM(COALESCE(awc_code, ''))) AS awc_code
        FROM child_profile
        WHERE child_id = %s
          AND COALESCE(BTRIM(awc_code), '') <> ''
        ORDER BY UPPER(BTRIM(COALESCE(awc_code, '')))
        """,
        (payload.child_id,),
    ).fetchall()
    child_awc_codes = [
        _normalize_awc_code(str(row.get("awc_code") or ""), prefer_prefix="AWW")
        for row in child_awc_rows
    ]
    child_awc_codes = [code for code in child_awc_codes if code]
    if not child_awc_codes:
        return ""
    return child_awc_codes[0]


def _save_screening(db_path: str, payload: ScreeningRequest, result: ScreeningResponse) -> None:
    created_at = datetime.utcnow().isoformat()
    with _get_conn(db_path) as conn:
        awc_code = _resolve_screening_awc_code(conn, payload)
        awc_variants = _awc_code_variants(awc_code) or ([awc_code] if awc_code else [])
        if awc_variants:
            placeholders = ",".join("%s" for _ in awc_variants)
            existing_child = conn.execute(
                f"""
                SELECT dob, gender, awc_code
                FROM child_profile
                WHERE child_id = %s
                  AND UPPER(BTRIM(COALESCE(awc_code, ''))) IN ({placeholders})
                LIMIT 1
                """,
                tuple([payload.child_id, *awc_variants]),
            ).fetchone()
        else:
            existing_child = conn.execute(
                """
                SELECT dob, gender, awc_code
                FROM child_profile
                WHERE child_id = %s
                ORDER BY CASE WHEN COALESCE(BTRIM(awc_code), '') = '' THEN 1 ELSE 0 END,
                         UPPER(BTRIM(COALESCE(awc_code, '')))
                LIMIT 1
                """,
                (payload.child_id,),
            ).fetchone()
        safe_dob = None
        safe_gender = _normalize_gender(payload.gender)
        if existing_child is not None:
            safe_dob = str(existing_child.get("dob") or "").strip() or None
            if not safe_gender:
                safe_gender = _normalize_gender(str(existing_child.get("gender") or ""))
            if not awc_code:
                awc_code = _normalize_awc_code(
                    str(existing_child.get("awc_code") or ""),
                    prefer_prefix="AWW",
                )
        if not safe_dob:
            safe_dob = datetime.utcnow().date().isoformat()
        conn.execute(
            """
            INSERT INTO child_profile(
              child_id, dob, gender, awc_code, district, mandal, assessment_cycle
            )
            VALUES(%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT(child_id, awc_code) DO UPDATE SET
              gender=COALESCE(NULLIF(excluded.gender, ''), child_profile.gender),
              mandal=COALESCE(NULLIF(excluded.mandal, ''), child_profile.mandal),
              district=COALESCE(NULLIF(excluded.district, ''), child_profile.district),
              assessment_cycle=COALESCE(NULLIF(excluded.assessment_cycle, ''), child_profile.assessment_cycle),
              dob=COALESCE(excluded.dob, child_profile.dob)
            """,
            (
                payload.child_id,
                safe_dob,
                safe_gender,
                awc_code,
                payload.district or "",
                payload.mandal or "",
                payload.assessment_cycle or "Baseline",
            ),
        )
        cur = conn.execute(
            """
            INSERT INTO screening_event(child_id, awc_code, age_months, overall_risk, explainability, assessment_cycle, created_at)
            VALUES(%s,%s,%s,%s,%s,%s,%s)
            RETURNING id
            """,
            (
                payload.child_id,
                awc_code,
                payload.age_months,
                _normalize_risk(result.risk_level),
                "; ".join(result.explanation),
                payload.assessment_cycle or "Baseline",
                created_at,
            ),
        )
        screening_row = cur.fetchone()
        screening_id = int(screening_row["id"]) if screening_row else 0
        for domain, risk in result.domain_scores.items():
            conn.execute(
                """
                INSERT INTO screening_domain_score(screening_id, domain, risk_label, score)
                VALUES(%s,%s,%s,%s)
                """,
                (screening_id, domain, _normalize_risk(risk), _risk_score(risk)),
            )

        delay_summary = result.delay_summary or {}
        gm_delay = int(delay_summary.get("GM_delay", 0) or 0)
        fm_delay = int(delay_summary.get("FM_delay", 0) or 0)
        lc_delay = int(delay_summary.get("LC_delay", 0) or 0)
        cog_delay = int(delay_summary.get("COG_delay", 0) or 0)
        se_delay = int(delay_summary.get("SE_delay", 0) or 0)
        num_delays = gm_delay + fm_delay + lc_delay + cog_delay + se_delay

        if screening_id and _has_developmental_payload(payload):
            conn.execute(
                """
                INSERT INTO developmental_risk_score(
                  screening_id, child_id, awc_code, age_months,
                  gm_delay, fm_delay, lc_delay, cog_delay, se_delay, num_delays,
                  created_at
                )
                VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                (
                    screening_id,
                    payload.child_id,
                    awc_code,
                    payload.age_months,
                    gm_delay,
                    fm_delay,
                    lc_delay,
                    cog_delay,
                    se_delay,
                    num_delays,
                    created_at,
                ),
            )
            conn.execute(
                """
                INSERT INTO domain_delay_table(
                  screening_id, child_id, awc_code, age_months,
                  gm_delay, fm_delay, lc_delay, cog_delay, se_delay, num_delays,
                  created_at
                )
                VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT(screening_id) DO UPDATE SET
                  child_id = EXCLUDED.child_id,
                  awc_code = COALESCE(NULLIF(EXCLUDED.awc_code, ''), domain_delay_table.awc_code),
                  age_months = EXCLUDED.age_months,
                  gm_delay = EXCLUDED.gm_delay,
                  fm_delay = EXCLUDED.fm_delay,
                  lc_delay = EXCLUDED.lc_delay,
                  cog_delay = EXCLUDED.cog_delay,
                  se_delay = EXCLUDED.se_delay,
                  num_delays = EXCLUDED.num_delays,
                  created_at = EXCLUDED.created_at
                """,
                (
                    screening_id,
                    payload.child_id,
                    awc_code,
                    payload.age_months,
                    gm_delay,
                    fm_delay,
                    lc_delay,
                    cog_delay,
                    se_delay,
                    num_delays,
                    created_at,
                ),
            )
            conn.execute(
                """
                SELECT upsert_anganwadi_developmental_risk(
                  %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s
                )
                """,
                (
                    awc_code,
                    payload.child_id,
                    screening_id,
                    payload.age_months,
                    gm_delay,
                    fm_delay,
                    lc_delay,
                    cog_delay,
                    se_delay,
                    num_delays,
                    created_at,
                ),
            )

        neuro_risks = _extract_neuro_risk_labels(result.domain_scores or {})
        if neuro_risks is not None:
            conn.execute(
                """
                INSERT INTO neuro_logical_risk(
                  child_id, autism_risk, adhd_risk, behavioral_risk
                )
                VALUES(%s,%s,%s,%s)
                ON CONFLICT(child_id) DO UPDATE SET
                  autism_risk = EXCLUDED.autism_risk,
                  adhd_risk = EXCLUDED.adhd_risk,
                  behavioral_risk = EXCLUDED.behavioral_risk
                """,
                (
                    payload.child_id,
                    neuro_risks["autism_risk"],
                    neuro_risks["adhd_risk"],
                    neuro_risks["behavioral_risk"],
                ),
            )

        # Create/refresh a follow-up row so Problem D can start tracking outcomes.
        delay_months = int(num_delays) * 2
        existing = conn.execute(
            """
            SELECT id FROM followup_outcome
            WHERE child_id=%s
            ORDER BY id DESC
            LIMIT 1
            """,
            (payload.child_id,),
        ).fetchone()
        if existing is None:
            conn.execute(
                """
                INSERT INTO followup_outcome(child_id, baseline_delay_months, followup_delay_months, improvement_status, followup_completed, followup_date)
                VALUES(%s,%s,%s,%s,%s,%s)
                """,
                (
                    payload.child_id,
                    delay_months,
                    delay_months,
                    "No Change",
                    0,
                    datetime.utcnow().date().isoformat(),
                ),
            )


def _risk_to_referral_policy(risk_level: str) -> Dict[str, str] | None:
    risk = _normalize_risk(risk_level)
    if risk == "Critical":
        return {
            "referral_type": "PHC",
            "referral_type_label": "Immediate Specialist Referral",
            "urgency": "Immediate",
            "followup_days": "2",
            "facility": "District Specialist",
        }
    if risk == "High":
        return {
            "referral_type": "PHC",
            "referral_type_label": "Specialist Evaluation",
            "urgency": "Priority",
            "followup_days": "10",
            "facility": "Block Specialist",
        }
    # Strict Problem B mapping: no referral for Medium/Low.
    return None


def _build_domain_reason(domain_scores: Dict[str, str]) -> str:
    if not domain_scores:
        return "General developmental risk"
    severity = {"low": 0, "medium": 1, "high": 2, "critical": 3}
    best_domain = None
    best_risk = "low"
    best_score = -1
    for domain, risk in domain_scores.items():
        score = severity.get(str(risk).strip().lower(), 0)
        if score > best_score:
            best_score = score
            best_domain = domain
            best_risk = str(risk)
    if best_domain is None:
        return "General developmental risk"
    return f"{best_domain} ({_normalize_risk(best_risk)})"


def _domain_display(domain: str) -> str:
    mapping = {
        "GM": "Gross Motor",
        "FM": "Fine Motor",
        "LC": "Speech & Language",
        "COG": "Cognitive",
        "SE": "Social-Emotional",
    }
    return mapping.get(str(domain).strip().upper(), str(domain))


def _risk_points(label: str) -> int:
    normalized = _normalize_risk(label)
    return {"Low": 1, "Medium": 2, "High": 3, "Critical": 4}.get(normalized, 1)


def _status_to_frontend(status: str) -> str:
    normalized = str(status or "").strip().lower()
    if normalized in {"pending"}:
        return "PENDING"
    if normalized in {"appointment scheduled", "scheduled"}:
        return "SCHEDULED"
    if normalized in {"under treatment", "visited"}:
        return "VISITED"
    if normalized in {"completed"}:
        return "COMPLETED"
    if normalized in {"missed"}:
        return "MISSED"
    return "PENDING"


def _status_to_db(status: str) -> str:
    normalized = str(status or "").strip().upper()
    if normalized == "PENDING":
        return "Pending"
    if normalized == "SCHEDULED":
        return "Appointment Scheduled"
    if normalized == "VISITED":
        return "Under Treatment"
    if normalized == "COMPLETED":
        return "Completed"
    if normalized == "MISSED":
        return "Missed"
    raise HTTPException(status_code=400, detail="Invalid referral status")


def _today_iso() -> str:
    return datetime.utcnow().date().isoformat()


def _escalation_target(level: int) -> str:
    if level <= 0:
        return "Block Medical Officer"
    if level == 1:
        return "Block Medical Officer"
    if level == 2:
        return "District Health Officer"
    return "State Supervisor"


def _apply_overdue_escalation(
    conn: Any,
    *,
    referral_id: str,
    status: str,
    followup_deadline: str | None,
    escalation_level: int | None,
) -> None:
    if not followup_deadline:
        return
    normalized = _status_to_frontend(status)
    if normalized == "COMPLETED":
        return
    deadline = _parse_date_safe(followup_deadline)
    if deadline is None:
        return
    today = datetime.utcnow().date()
    if today <= deadline:
        return
    level = int(escalation_level or 0) + 1
    new_deadline = today + timedelta(days=2)
    conn.execute(
        """
        UPDATE referral_action
        SET escalation_level = %s,
            followup_deadline = %s,
            last_updated = %s
        WHERE referral_id = %s
        """,
        (level, new_deadline.isoformat(), today.isoformat(), referral_id),
    )


def _create_referral_action(
    db_path: str,
    *,
    child_id: str,
    aww_id: str,
    risk_level: str,
    domain_scores: Dict[str, str],
) -> Dict[str, str] | None:
    policy = _risk_to_referral_policy(risk_level)
    if policy is None:
        return None
    referral_id = f"ref_{uuid.uuid4().hex[:12]}"
    created_on = datetime.utcnow().date()
    followup_by = created_on + timedelta(days=int(policy["followup_days"]))
    with _get_conn(db_path) as conn:
        conn.execute(
            """
            INSERT INTO referral_action(
                referral_id,
                child_id,
                aww_id,
                referral_required,
                referral_type,
                urgency,
                referral_status,
                referral_date,
                completion_date,
                followup_deadline,
                escalation_level,
                escalated_to,
                last_updated
            )
            VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                referral_id,
                child_id,
                aww_id,
                1,
                policy["referral_type"],
                policy["urgency"],
                "Pending",
                created_on.isoformat(),
                None,
                followup_by.isoformat(),
                0,
                None,
                created_on.isoformat(),
            ),
        )
    return {
        "referral_id": referral_id,
        "risk_level": _normalize_risk(risk_level),
        "referral_type": policy["referral_type"],
        "referral_type_label": policy["referral_type_label"],
        "urgency": policy["urgency"],
        "status": "Pending",
        "created_on": created_on.isoformat(),
        "followup_by": followup_by.isoformat(),
        "domain_reason": _build_domain_reason(domain_scores),
    }


def _compute_monitoring(db_path: str, role: str, location_id: str) -> dict:
    role_to_column = {"aww": "awc_id", "supervisor": "sector_id", "cdpo": "mandal_id", "district": "district_id", "state": ""}
    filter_column = role_to_column.get(role, "")
    with _get_conn(db_path) as conn:
        children = [_child_row_with_aliases(c) for c in conn.execute("SELECT * FROM child_profile").fetchall()]
        if filter_column and location_id:
            if filter_column == "awc_id":
                children = [c for c in children if _awc_codes_equal(c.get(filter_column), location_id)]
            else:
                children = [c for c in children if (c.get(filter_column) or "") == location_id]
        child_ids = [c["child_id"] for c in children]
        child_map = {c["child_id"]: c for c in children}

        screenings = conn.execute("SELECT * FROM screening_event ORDER BY created_at DESC, id DESC").fetchall()
        latest_screen_by_child: Dict[str, Dict[str, Any]] = {}
        for s in screenings:
            cid = s["child_id"]
            if cid in child_map and cid not in latest_screen_by_child:
                latest_screen_by_child[cid] = s

        latest_ids = [row["id"] for row in latest_screen_by_child.values()]
        domain_rows: List[Dict[str, Any]] = []
        if latest_ids:
            placeholders = ",".join("%s" for _ in latest_ids)
            domain_rows = conn.execute(
                f"SELECT * FROM screening_domain_score WHERE screening_id IN ({placeholders})",
                tuple(latest_ids),
            ).fetchall()
        domain_rows_by_screen: Dict[int, List[Dict[str, Any]]] = {}
        for row in domain_rows:
            domain_rows_by_screen.setdefault(int(row["screening_id"]), []).append(row)

        risk_distribution = Counter({"Low": 0, "Medium": 0, "High": 0, "Critical": 0})
        age_band_rows = {k: {"age_band": k, "low": 0, "medium": 0, "high": 0, "critical": 0} for k in ["0-12", "13-24", "25-36", "37-48", "49-60", "61-72"]}
        for cid, s in latest_screen_by_child.items():
            risk = _normalize_risk(s["overall_risk"])
            risk_distribution[risk] += 1
            age_band_rows[_age_band(int(s["age_months"] or 0))][risk.lower()] += 1

        domain_burden = Counter({"GM": 0, "FM": 0, "LC": 0, "COG": 0, "SE": 0})
        for row in domain_rows:
            label = _normalize_risk(row["risk_label"])
            if label in {"High", "Critical"}:
                domain_burden[row["domain"]] += 1

        referrals = conn.execute("SELECT * FROM referral_action").fetchall()
        referrals = [r for r in referrals if r["child_id"] in child_map]
        pending_referrals = sum(1 for r in referrals if int(r["referral_required"] or 0) == 1 and (r["referral_status"] or "") == "Pending")
        completed_referrals = sum(1 for r in referrals if (r["referral_status"] or "") == "Completed")
        under_treatment_referrals = sum(1 for r in referrals if (r["referral_status"] or "") == "Under Treatment")

        followups = conn.execute("SELECT * FROM followup_outcome").fetchall()
        followups = [f for f in followups if f["child_id"] in child_map]
        followup_due = sum(1 for f in followups if int(f["followup_completed"] or 0) == 0)
        followup_done = sum(1 for f in followups if int(f["followup_completed"] or 0) == 1)
        followup_improving = sum(1 for f in followups if (f["improvement_status"] or "") == "Improving")
        followup_worsening = sum(1 for f in followups if (f["improvement_status"] or "") == "Worsening")
        followup_same = sum(1 for f in followups if (f["improvement_status"] or "") == "No Change")

        # Active intervention proxy:
        # child has unfinished follow-up OR referral under treatment/pending.
        intervention_active_ids = set(
            f["child_id"] for f in followups if int(f["followup_completed"] or 0) == 0
        )
        intervention_active_ids.update(
            r["child_id"] for r in referrals if (r["referral_status"] or "") in {"Pending", "Under Treatment"}
        )
        intervention_active_children = len(intervention_active_ids)

        today = datetime.utcnow().date()
        overdue_referrals = []
        for r in referrals:
            if (r["referral_status"] or "") != "Pending":
                continue
            r_date = _parse_date_safe(r["referral_date"])
            if r_date and (today - r_date).days > 14:
                overdue_referrals.append(
                    {
                        "child_id": r["child_id"],
                        "days_pending": (today - r_date).days,
                        "urgency": r["urgency"] or "",
                        "referral_type": r["referral_type"] or "",
                    }
                )

        latest_referral_by_child: Dict[str, Dict[str, Any]] = {}
        for r in sorted(referrals, key=lambda x: (x["referral_date"] or "", x["referral_id"] or ""), reverse=True):
            if r["child_id"] not in latest_referral_by_child:
                latest_referral_by_child[r["child_id"]] = r
        latest_followup_by_child: Dict[str, Dict[str, Any]] = {}
        for f in sorted(followups, key=lambda x: (x["followup_date"] or "", x["id"] or 0), reverse=True):
            if f["child_id"] not in latest_followup_by_child:
                latest_followup_by_child[f["child_id"]] = f

        high_risk_children = []
        priority_children = []
        for cid, s in latest_screen_by_child.items():
            risk = _normalize_risk(s["overall_risk"])
            c = child_map[cid]
            referral = latest_referral_by_child.get(cid)
            followup = latest_followup_by_child.get(cid)
            days_since_flagged = 0
            s_date = _parse_date_safe(s["created_at"])
            if s_date:
                days_since_flagged = max((today - s_date).days, 0)

            if risk in {"High", "Critical"}:
                affected_domains = []
                for d in domain_rows_by_screen.get(int(s["id"]), []):
                    if _normalize_risk(d["risk_label"]) in {"High", "Critical"}:
                        affected_domains.append(d["domain"])
                high_risk_children.append(
                    {
                        "child_id": cid,
                        "child_name": cid,
                        "age_months": s["age_months"],
                        "risk_category": risk,
                        "domain_affected": ", ".join(affected_domains) if affected_domains else "General",
                        "referral_status": (referral["referral_status"] if referral else "Pending"),
                        "days_since_flagged": days_since_flagged,
                    }
                )

            referral_status = (referral["referral_status"] if referral else "Pending")
            followup_completed = int(followup["followup_completed"] or 0) == 1 if followup else False
            improvement_status = (followup["improvement_status"] if followup else "No Change")
            if risk == "Critical":
                rank = 1
            elif risk == "High" and referral_status == "Pending":
                rank = 2
            elif risk == "High" and not followup_completed:
                rank = 3
            elif risk == "Medium" and improvement_status == "Worsening":
                rank = 4
            else:
                rank = 9
            if rank == 9:
                continue
            priority_children.append(
                {
                    "child_id": cid,
                    "risk": risk,
                    "age_months": s["age_months"],
                    "awc_id": c.get("awc_id", ""),
                    "mandal_id": c.get("mandal_id", ""),
                    "district_id": c.get("district_id", ""),
                    "rank": rank,
                }
            )
        priority_children.sort(key=lambda x: (x["rank"], -_risk_rank(x["risk"])))
        high_risk_children.sort(key=lambda x: (_risk_rank(x["risk_category"]), x["days_since_flagged"]), reverse=True)

        mandal_counts = Counter()
        mandal_high = Counter()
        for cid, s in latest_screen_by_child.items():
            c = child_map[cid]
            mandal = c.get("mandal_id") or "UNKNOWN"
            mandal_counts[mandal] += 1
            if _normalize_risk(s["overall_risk"]) in {"High", "Critical"}:
                mandal_high[mandal] += 1
        hotspots = []
        for mandal, total in mandal_counts.items():
            pct = (mandal_high[mandal] * 100 / total) if total else 0
            if pct > 15:
                hotspots.append({"mandal_id": mandal, "high_risk_pct": round(pct, 2)})
        hotspots.sort(key=lambda x: x["high_risk_pct"], reverse=True)

        by_awc_children = Counter((child_map[cid].get("awc_id") or "N/A") for cid in child_map.keys())
        by_awc_screened = Counter((child_map[cid].get("awc_id") or "N/A") for cid in latest_screen_by_child.keys())
        by_awc_risk = Counter()
        for cid, s in latest_screen_by_child.items():
            if _normalize_risk(s["overall_risk"]) in {"High", "Critical"}:
                by_awc_risk[(child_map[cid].get("awc_id") or "N/A")] += 1

        by_awc_ref_pending = Counter((child_map[r["child_id"]].get("awc_id") or "N/A") for r in referrals if (r["referral_status"] or "") == "Pending")
        by_awc_ref_done = Counter((child_map[r["child_id"]].get("awc_id") or "N/A") for r in referrals if (r["referral_status"] or "") == "Completed")
        by_awc_follow_due = Counter((child_map[f["child_id"]].get("awc_id") or "N/A") for f in followups if int(f["followup_completed"] or 0) == 0)
        by_awc_follow_done = Counter((child_map[f["child_id"]].get("awc_id") or "N/A") for f in followups if int(f["followup_completed"] or 0) == 1)

        aww_performance = []
        for awc_id, total in by_awc_children.items():
            screened = by_awc_screened[awc_id]
            coverage = (screened * 100 / total) if total else 0
            ref_done = by_awc_ref_done[awc_id]
            ref_pending = by_awc_ref_pending[awc_id]
            ref_rate = (ref_done * 100 / (ref_done + ref_pending)) if (ref_done + ref_pending) else 0
            fu_done = by_awc_follow_done[awc_id]
            fu_due = by_awc_follow_due[awc_id]
            fu_rate = (fu_done * 100 / (fu_done + fu_due)) if (fu_done + fu_due) else 0
            score = round(ref_rate * 0.4 + fu_rate * 0.3 + coverage * 0.3, 2)
            aww_performance.append(
                {
                    "awc_id": awc_id,
                    "total_children": total,
                    "high_risk_children": by_awc_risk[awc_id],
                    "screening_coverage": round(coverage, 2),
                    "referral_completion_rate": round(ref_rate, 2),
                    "followup_compliance_rate": round(fu_rate, 2),
                    "performance_score": score,
                    "underperforming": score < 60,
                }
            )
        aww_performance.sort(key=lambda x: x["performance_score"])

        district_counts = Counter()
        district_high = Counter()
        for cid, s in latest_screen_by_child.items():
            district = child_map[cid].get("district_id") or "UNKNOWN"
            district_counts[district] += 1
            if _normalize_risk(s["overall_risk"]) in {"High", "Critical"}:
                district_high[district] += 1
        district_ranking = []
        for district, total in district_counts.items():
            pct = (district_high[district] * 100 / total) if total else 0
            district_ranking.append(
                {
                    "district_id": district,
                    "total_children": total,
                    "high_risk_count": district_high[district],
                    "high_risk_pct": round(pct, 2),
                }
            )
        district_ranking.sort(key=lambda x: x["high_risk_pct"], reverse=True)

        trend_counter_total = Counter()
        trend_counter_high = Counter()
        for cid, s in latest_screen_by_child.items():
            month = str(s["created_at"])[:7]
            trend_counter_total[month] += 1
            if _normalize_risk(s["overall_risk"]) in {"High", "Critical"}:
                trend_counter_high[month] += 1
        trend_rows = []
        for month in sorted(trend_counter_total.keys()):
            total = trend_counter_total[month]
            high = trend_counter_high[month]
            trend_rows.append({"month": month, "screenings": total, "high_risk": high, "high_risk_pct": round((high * 100 / total) if total else 0, 2)})

    total_children = len(children)
    total_screened = len(latest_screen_by_child)
    coverage = round((total_screened * 100 / total_children), 2) if total_children else 0.0
    referral_completion = round((completed_referrals * 100 / (completed_referrals + pending_referrals)), 2) if (completed_referrals + pending_referrals) else 0.0
    followup_compliance = round((followup_done * 100 / (followup_done + followup_due)), 2) if (followup_done + followup_due) else 0.0
    avg_referral_days = 0.0
    referral_durations = []
    for r in referrals:
        if (r["referral_status"] or "") != "Completed":
            continue
        d1 = _parse_date_safe(r["referral_date"])
        d2 = _parse_date_safe(r["completion_date"])
        if d1 and d2:
            referral_durations.append((d2 - d1).days)
    if referral_durations:
        avg_referral_days = round(sum(referral_durations) / len(referral_durations), 2)

    alerts: List[dict] = []
    if risk_distribution["High"] + risk_distribution["Critical"] > 0:
        alerts.append({"level": "red", "message": "High/Critical risk children detected. Immediate action required."})
    if overdue_referrals:
        alerts.append({"level": "yellow", "message": f"{len(overdue_referrals)} referral(s) pending for more than 14 days."})
    if hotspots:
        alerts.append({"level": "orange", "message": f"{len(hotspots)} mandal hotspot(s) detected above 15% high-risk threshold."})

    return {
        "role": role,
        "location_id": location_id,
        "total_children": total_children,
        "total_screened": total_screened,
        "high_risk_children": risk_distribution["High"] + risk_distribution["Critical"],
        "intervention_active_children": intervention_active_children,
        "risk_distribution": dict(risk_distribution),
        "pending_referrals": pending_referrals,
        "total_referred_children": sum(1 for r in referrals if int(r["referral_required"] or 0) == 1),
        "completed_referrals": completed_referrals,
        "under_treatment_referrals": under_treatment_referrals,
        "avg_referral_days": avg_referral_days,
        "followup_due": followup_due,
        "followup_done": followup_done,
        "followup_improving": followup_improving,
        "followup_worsening": followup_worsening,
        "followup_same": followup_same,
        "screening_coverage": coverage,
        "coverage_warning": coverage < 80,
        "followup_compliance": followup_compliance,
        "referral_completion": referral_completion,
        "age_band_risk_rows": list(age_band_rows.values()),
        "hotspots": hotspots,
        "aww_performance": sorted(aww_performance, key=lambda x: x["performance_score"]),
        "underperforming_awcs": [x for x in aww_performance if x["underperforming"]],
        "district_ranking": district_ranking,
        "alerts": alerts,
        "domain_burden": dict(domain_burden),
        "high_risk_children_rows": high_risk_children[:50],
        "priority_children": priority_children[:5],
        "overdue_referrals": sorted(overdue_referrals, key=lambda x: x["days_pending"], reverse=True),
        "trend_rows": trend_rows,
        "aww_trained": True if role == "aww" else None,
        "training_mode": "Blended" if role == "aww" else "",
    }


def _compute_impact(db_path: str, role: str, location_id: str) -> dict:
    role_to_column = {
        "aww": "awc_id",
        "supervisor": "sector_id",
        "cdpo": "mandal_id",
        "district": "district_id",
        "state": "",
    }
    column = role_to_column.get(role, "")
    where_clause = ""
    params: tuple = ()
    if column and location_id:
        where_clause = f" WHERE c.{column} = %s "
        params = (location_id,)
    with _get_conn(db_path) as conn:
        children = [_child_row_with_aliases(c) for c in conn.execute("SELECT * FROM child_profile").fetchall()]
        if column and location_id:
            if column == "awc_id":
                children = [c for c in children if _awc_codes_equal(c.get(column), location_id)]
            else:
                children = [c for c in children if (c.get(column) or "") == location_id]
        child_ids = [c["child_id"] for c in children]
        child_map = {c["child_id"]: c for c in children}
        rows = conn.execute("SELECT * FROM followup_outcome").fetchall()
        rows = [r for r in rows if r["child_id"] in child_map]
        screenings = conn.execute("SELECT * FROM screening_event ORDER BY created_at ASC, id ASC").fetchall()
        by_child: Dict[str, List[Dict[str, Any]]] = {}
        for s in screenings:
            if s["child_id"] in child_map:
                by_child.setdefault(s["child_id"], []).append(s)

    improving = sum(1 for r in rows if (r["improvement_status"] or "") == "Improving")
    worsening = sum(1 for r in rows if (r["improvement_status"] or "") == "Worsening")
    no_change = sum(1 for r in rows if (r["improvement_status"] or "") == "No Change")
    diffs = [int(r["baseline_delay_months"] or 0) - int(r["followup_delay_months"] or 0) for r in rows]
    avg_reduction = round(sum(diffs) / len(diffs), 2) if diffs else 0.0
    followup_done = sum(1 for r in rows if int(r["followup_completed"] or 0) == 1)
    followup_compliance = round((followup_done * 100 / len(rows)), 2) if rows else 0.0

    exit_from_high = 0
    for _, screens in by_child.items():
        if len(screens) < 2:
            continue
        start = _normalize_risk(screens[0]["overall_risk"])
        end = _normalize_risk(screens[-1]["overall_risk"])
        if start in {"High", "Critical"} and end in {"Low", "Medium"}:
            exit_from_high += 1

    trend_counter = Counter()
    for r in rows:
        month = str(r["followup_date"] or "")[:7]
        if month:
            trend_counter[(month, r["improvement_status"] or "No Change")] += 1
    months = sorted({k[0] for k in trend_counter.keys()})
    trend_rows = []
    for m in months:
        trend_rows.append(
            {
                "month": m,
                "improving": trend_counter[(m, "Improving")],
                "worsening": trend_counter[(m, "Worsening")],
                "no_change": trend_counter[(m, "No Change")],
            }
        )

    return {
        "role": role,
        "location_id": location_id,
        "improving": improving,
        "worsening": worsening,
        "no_change": no_change,
        "avg_delay_reduction": avg_reduction,
        "followup_compliance": followup_compliance,
        "exit_from_high_risk": exit_from_high,
        "trend_rows": trend_rows,
        "current_screened": len(by_child),
    }


def _generate_follow_up_activities(db_path: str, referral_id: str, child_id: str, risk_level: str, domain_scores: Dict[str, str], autism_risk: str = "Low", nutrition_risk: str = "Low") -> List[Dict]:
    """Generate domain-specific home activities based on referral risk profile."""
    activities = []
    activity_id = 1

    def _domain_has_delay(raw_score: Any) -> bool:
        # Accept both label-based scores ("High") and numeric scores (0/1 or 0.0-1.0).
        normalized = _normalize_risk(str(raw_score))
        if normalized in {"Medium", "High", "Critical"}:
            return True
        try:
            value = float(raw_score)
        except (TypeError, ValueError):
            return False
        # Binary format: 1 means delayed.
        if value in {0.0, 1.0}:
            return int(value) == 1
        # App convention in referral payloads:
        # lower score indicates higher concern (e.g., 0.35 delayed, 0.9 normal).
        return value <= 0.5

    # Extract delay information from domain scores
    delayed_domains = []
    for domain, risk in domain_scores.items():
        domain_upper = str(domain).upper().strip()
        if domain_upper in {"GM", "FM", "LC", "COG", "SE"}:
            if _domain_has_delay(risk):
                delayed_domains.append(domain_upper)

    # Rule 1: Gross Motor Delay → Daily floor play activities
    if "GM" in delayed_domains:
        activities.append({
            "id": activity_id,
            "referral_id": referral_id,
            "target_user": "CAREGIVER",
            "domain": "GM",
            "activity_title": "Daily Floor Play & Standing Support",
            "activity_description": "Encourage crawling and standing with support. Let child practice weight-shifting. 20-30 mins daily.",
            "frequency": "DAILY",
            "duration_days": 30,
            "created_on": datetime.utcnow().date().isoformat(),
        })
        activity_id += 1

        # Add AWW monitoring activity
        activities.append({
            "id": activity_id,
            "referral_id": referral_id,
            "target_user": "AWW",
            "domain": "GM",
            "activity_title": "Weekly Motor Development Check",
            "activity_description": "Observe and assess child's motor milestones. Document progress. Counsel caregiver.",
            "frequency": "WEEKLY",
            "duration_days": 30,
            "created_on": datetime.utcnow().date().isoformat(),
        })
        activity_id += 1

    # Rule 2: Fine Motor Delay → Hand activities
    if "FM" in delayed_domains:
        activities.append({
            "id": activity_id,
            "referral_id": referral_id,
            "target_user": "CAREGIVER",
            "domain": "FM",
            "activity_title": "Hand & Finger Exercises",
            "activity_description": "Practice grasping, finger play, and self-feeding. Use household items (spoons, balls). 15 mins daily.",
            "frequency": "DAILY",
            "duration_days": 30,
            "created_on": datetime.utcnow().date().isoformat(),
        })
        activity_id += 1

    # Rule 3: Language & Communication Delay → Speech activities
    if "LC" in delayed_domains:
        activities.append({
            "id": activity_id,
            "referral_id": referral_id,
            "target_user": "CAREGIVER",
            "domain": "LC",
            "activity_title": "Language Stimulation Activities",
            "activity_description": "Talk to child, name objects, sing songs. Encourage babbling and word repetition. 20 mins daily.",
            "frequency": "DAILY",
            "duration_days": 30,
            "created_on": datetime.utcnow().date().isoformat(),
        })
        activity_id += 1

    # Rule 4: Cognitive Delay → Problem-solving activities
    if "COG" in delayed_domains:
        activities.append({
            "id": activity_id,
            "referral_id": referral_id,
            "target_user": "CAREGIVER",
            "domain": "COG",
            "activity_title": "Cognitive Play & Problem Solving",
            "activity_description": "Hide-and-seek games, shape sorting, stacking toys. Encourage exploration and discovery. 20 mins daily.",
            "frequency": "DAILY",
            "duration_days": 30,
            "created_on": datetime.utcnow().date().isoformat(),
        })
        activity_id += 1

    # Rule 5: Social-Emotional Delay → Interaction activities
    if "SE" in delayed_domains or autism_risk in {"Moderate", "High"}:
        activities.append({
            "id": activity_id,
            "referral_id": referral_id,
            "target_user": "CAREGIVER",
            "domain": "SE",
            "activity_title": "Social Interaction & Eye Contact Practice",
            "activity_description": "Call child's name, maintain eye contact during play. Practice greeting gestures. 10-15 mins, 3x daily.",
            "frequency": "DAILY",
            "duration_days": 30,
            "created_on": datetime.utcnow().date().isoformat(),
        })
        activity_id += 1

    # Rule 6: Nutrition Risk → Feeding guidance
    if nutrition_risk in {"High", "Severe", "Critical"}:
        activities.append({
            "id": activity_id,
            "referral_id": referral_id,
            "target_user": "AWW",
            "domain": "Nutrition",
            "activity_title": "Weekly Weight Monitoring & Nutrition Counseling",
            "activity_description": "Check child's weight weekly. Monitor growth. Counsel caregiver on nutrition, fortified foods, supplementation.",
            "frequency": "WEEKLY",
            "duration_days": 30,
            "created_on": datetime.utcnow().date().isoformat(),
        })
        activity_id += 1

    # Fallback: keep follow-up tracking meaningful even when domain score format
    # is sparse/legacy and no domain activity was inferred.
    if not activities and _normalize_risk(risk_level) in {"Medium", "High", "Critical"}:
        activities.append({
            "id": activity_id,
            "referral_id": referral_id,
            "target_user": "CAREGIVER",
            "domain": "General",
            "activity_title": "Daily Guided Stimulation at Home",
            "activity_description": "Practice age-appropriate play, communication, and interaction tasks daily. Track changes and concerns.",
            "frequency": "DAILY",
            "duration_days": 30,
            "created_on": datetime.utcnow().date().isoformat(),
        })
        activity_id += 1
        activities.append({
            "id": activity_id,
            "referral_id": referral_id,
            "target_user": "AWW",
            "domain": "General",
            "activity_title": "Weekly Follow-Up Counselling & Review",
            "activity_description": "Review caregiver adherence, reinforce techniques, and document weekly developmental observations.",
            "frequency": "WEEKLY",
            "duration_days": 30,
            "created_on": datetime.utcnow().date().isoformat(),
        })

    # Save activities to database
    with _get_conn(db_path) as conn:
        for activity in activities:
            conn.execute(
                """
                INSERT INTO follow_up_activities (
                    referral_id, target_user, domain, activity_title,
                    activity_description, frequency, duration_days, created_on
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    activity["referral_id"],
                    activity["target_user"],
                    activity["domain"],
                    activity["activity_title"],
                    activity["activity_description"],
                    activity["frequency"],
                    activity["duration_days"],
                    activity["created_on"],
                ),
            )
    return activities


def create_app() -> FastAPI:
    app = FastAPI(title="ECD AI Backend", version="1.0.0")

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    model_dir = os.getenv(
        "ECD_MODEL_DIR",
        os.path.abspath(
            os.path.join(
                os.path.dirname(__file__),
                "..",
                "model_assets",
                "model",
                "trained_models",
            )
        ),
    )
    artifacts = None
    model_load_error: Optional[str] = None
    try:
        artifacts = load_artifacts(model_dir)
    except Exception as exc:
        model_load_error = str(exc)

    domain_models = None
    domain_model_load_error: Optional[str] = None
    domain_model_dir = os.getenv("ECD_DOMAIN_MODEL_DIR")
    try:
        domain_models = load_domain_models(domain_model_dir)
    except Exception as exc:
        domain_model_load_error = str(exc)

    neuro_behavior_models = None
    neuro_behavior_model_load_error: Optional[str] = None
    neuro_behavior_model_dir = os.getenv("ECD_NEURO_MODEL_DIR")
    try:
        neuro_behavior_models = load_neuro_behavior_models(neuro_behavior_model_dir)
    except Exception as exc:
        neuro_behavior_model_load_error = str(exc)

    nutrition_model = None
    nutrition_model_load_error: Optional[str] = None
    nutrition_model_dir = os.getenv("ECD_NUTRITION_MODEL_DIR")
    try:
        nutrition_model = load_nutrition_model(nutrition_model_dir)
    except Exception as exc:
        nutrition_model_load_error = str(exc)

    db_path = os.getenv(
        "ECD_DATABASE_URL",
        os.getenv("DATABASE_URL", DEFAULT_ECD_DATABASE_URL),
    )
    try:
        _init_db(db_path)
    except Exception as exc:
        raise RuntimeError(
            "Database initialization failed. Set ECD_DATABASE_URL (or DATABASE_URL) "
            "to a reachable PostgreSQL database, for example "
            "'postgresql://<user>:<password>@127.0.0.1:5432/ecd_data'."
        ) from exc

    # Simple in-memory store for tasks/checklists (child_id -> data)
    tasks_store: Dict[str, Dict] = {}
    # In-memory activity assignment + tracking store for Problem B engine
    activity_tracking_store: Dict[str, List[Dict]] = {}
    activity_plan_summary_store: Dict[str, Dict] = {}
    # In-memory referral appointments (referral_id -> list of appointments)
    appointments_store: Dict[str, List[Dict]] = {}
    # In-memory referral status override (referral_id -> status)
    referral_status_store: Dict[str, str] = {}

    def _is_neuro_behavioral_payload(payload: ScreeningRequest) -> bool:
        keys = {str(k).strip().upper() for k in (payload.domain_responses or {}).keys()}
        has_bps = any(k in {"BPS_AUT", "BPS_ADHD", "BPS_BEH"} for k in keys)
        has_developmental = any(k in {"GM", "FM", "LC", "COG", "SE"} for k in keys)
        return has_bps and not has_developmental

    def _predict_screening_result(payload: ScreeningRequest) -> Dict[str, Any]:
        if _is_neuro_behavioral_payload(payload):
            if neuro_behavior_models is not None:
                return predict_neuro_behavioral_risks(payload.model_dump(), neuro_behavior_models)

            # Fallback heuristic for neuro-behavioral payloads when model files are unavailable.
            domain_scores = {}
            explanation = []
            for domain in ["BPS_AUT", "BPS_ADHD", "BPS_BEH"]:
                answers = payload.domain_responses.get(domain, [])
                if not isinstance(answers, list):
                    answers = []
                misses = sum(1 for v in answers if int(v) == 0)
                ratio = misses / max(len(answers), 1)
                if ratio >= 0.60:
                    label = "High"
                elif ratio >= 0.30:
                    label = "Medium"
                else:
                    label = "Low"
                domain_scores[domain] = label
                explanation.append(f"{domain}: {label.lower()} heuristic risk")

            if any(v == "High" for v in domain_scores.values()):
                risk_level = "High"
            elif any(v == "Medium" for v in domain_scores.values()):
                risk_level = "Medium"
            else:
                risk_level = "Low"

            delay_summary = {
                f"{d}_delay": 1 if domain_scores.get(d, "Low") in {"Medium", "High", "Critical"} else 0
                for d in ["BPS_AUT", "BPS_ADHD", "BPS_BEH"]
            }
            delay_summary["num_delays"] = sum(delay_summary.values())
            if neuro_behavior_model_load_error:
                explanation.append(
                    "Neuro behavioral models not loaded; using fallback heuristic engine."
                )
            return {
                "risk_level": risk_level,
                "domain_scores": domain_scores,
                "explanation": explanation,
                "delay_summary": delay_summary,
                "model_source": "fallback_heuristic",
            }

        if domain_models is not None:
            result = predict_domain_delays(payload.model_dump(), domain_models)
            if model_load_error:
                explanation = list(result.get("explanation") or [])
                explanation.append(
                    "Using domain delay models because combined risk model is unavailable."
                )
                result["explanation"] = explanation
            return result

        if artifacts is not None:
            return predict_risk(payload.model_dump(), artifacts)

        # Fallback heuristic when model artifacts are unavailable.
        domain_scores = {}
        explanation = []
        total_delay_flags = 0
        for domain, answers in payload.domain_responses.items():
            misses = sum(1 for v in answers if int(v) == 0)
            ratio = misses / max(len(answers), 1)
            if ratio >= 0.75:
                label = "critical"
            elif ratio >= 0.5:
                label = "high"
            elif ratio >= 0.25:
                label = "medium"
            else:
                label = "low"
            domain_scores[domain] = label
            if label in {"critical", "high", "medium"}:
                total_delay_flags += 1
            explanation.append(f"{domain}: {label}")
        if total_delay_flags >= 3:
            risk_level = "critical"
        elif total_delay_flags == 2:
            risk_level = "high"
        elif total_delay_flags == 1:
            risk_level = "medium"
        else:
            risk_level = "low"
        delay_summary = {
            f"{d}_delay": 1
            if domain_scores.get(d, "low") in {"critical", "high", "medium"}
            else 0
            for d in ["GM", "FM", "LC", "COG", "SE"]
        }
        delay_summary["num_delays"] = sum(delay_summary.values())
        if model_load_error:
            explanation.append("Using fallback risk engine due to model load issue.")
        if domain_model_load_error:
            explanation.append(
                "Domain models not loaded; using fallback heuristic engine."
            )
        return {
            "risk_level": risk_level,
            "domain_scores": domain_scores,
            "explanation": explanation,
            "delay_summary": delay_summary,
        }

    def _fallback_nutrition_risk(features: Dict[str, Any]) -> Dict[str, Any]:
        def _to_float(value: Any) -> Optional[float]:
            if value is None:
                return None
            if isinstance(value, bool):
                return 1.0 if value else 0.0
            try:
                return float(value)
            except Exception:
                return None

        def _to_bool(value: Any) -> bool:
            if isinstance(value, bool):
                return value
            if isinstance(value, (int, float)):
                return float(value) != 0.0
            text = str(value or "").strip().lower()
            return text in {"1", "true", "yes", "y"}

        score = 0
        edema = _to_bool(features.get("bilateral_edema"))
        if edema:
            score += 4
        muac = _to_float(features.get("muac_cm"))
        if muac is not None:
            if muac < 11.5:
                score += 4
            elif muac < 12.5:
                score += 2
        hb = _to_float(features.get("hemoglobin_gdl"))
        if hb is not None:
            if hb < 7:
                score += 4
            elif hb < 11:
                score += 2
        weight = _to_float(features.get("weight_kg"))
        height = _to_float(features.get("height_cm"))
        if weight is not None and weight <= 0:
            score += 1
        if height is not None and height <= 0:
            score += 1
        if _to_bool(features.get("low_birth_weight")):
            score += 1
        if _to_bool(features.get("recent_illness")):
            score += 1
        if _to_bool(features.get("poor_appetite")):
            score += 1
        if _to_bool(features.get("diarrhea")):
            score += 1
        if _to_bool(features.get("vomiting")):
            score += 1
        if _to_bool(features.get("convulsions")):
            score += 3

        if score >= 8:
            risk = "High"
        elif score >= 4:
            risk = "Medium"
        else:
            risk = "Low"

        confidence = min(0.95, 0.55 + (score / 20.0))
        return {
            "nutrition_risk": risk,
            "confidence": float(round(confidence, 4)),
            "class_probabilities": {},
            "model_source": "nutrition_fallback_rules",
        }

    def _problem_b_status_display(raw_status: str) -> str:
        normalized = str(raw_status or "").strip().lower().replace("_", " ")
        if normalized in {"pending"}:
            return "Pending"
        if normalized in {"appointment scheduled", "scheduled"}:
            return "Appointment Scheduled"
        if normalized in {"under treatment", "undertreatment", "visited"}:
            return "Under Treatment"
        if normalized in {"completed"}:
            return "Completed"
        if normalized in {"missed"}:
            return "Missed"
        return "Pending"

    def _problem_b_status_rank(status: str) -> int:
        normalized = _problem_b_status_display(status)
        return {
            "Pending": 0,
            "Appointment Scheduled": 1,
            "Under Treatment": 2,
            "Missed": 2,
            "Completed": 3,
        }.get(normalized, 0)

    def _problem_b_status_from_db(referral_id: str) -> Optional[str]:
        with _get_conn(db_path) as conn:
            row = conn.execute(
                """
                SELECT referral_status
                FROM referral_action
                WHERE referral_id = %s
                LIMIT 1
                """,
                (referral_id,),
            ).fetchone()
        if row is None:
            return None
        return _problem_b_status_display(str(row["referral_status"] or ""))

    def _suggested_referral_status(referral_id: str) -> str:
        db_status = _problem_b_status_from_db(referral_id)
        appointments = appointments_store.get(referral_id, [])
        if not appointments:
            return db_status or "Pending"

        completed = sum(1 for a in appointments if str(a.get("status") or "").upper() == "COMPLETED")
        if completed == 0:
            suggested = "Appointment Scheduled"
        elif completed >= 1 and len(appointments) == 1:
            suggested = "Completed"
        elif len(appointments) > 1:
            suggested = "Under Treatment"
        else:
            suggested = "Appointment Scheduled"

        if not db_status:
            return suggested
        if db_status == "Completed":
            return "Completed"
        if db_status == "Missed" and suggested in {"Pending", "Appointment Scheduled"}:
            return "Missed"
        if _problem_b_status_rank(db_status) > _problem_b_status_rank(suggested):
            return db_status
        return suggested

    def _current_referral_status(referral_id: str) -> str:
        if referral_id in referral_status_store:
            return _problem_b_status_display(referral_status_store[referral_id])
        db_status = _problem_b_status_from_db(referral_id)
        if db_status:
            return db_status
        return _suggested_referral_status(referral_id)

    def _phase_payload(child_id: str) -> Dict:
        rows = activity_tracking_store.get(child_id, [])
        summary = activity_plan_summary_store.get(child_id, {
            "child_id": child_id,
            "domains": [],
            "total_activities": 0,
            "daily_count": 0,
            "weekly_count": 0,
            "phase_duration_weeks": 1,
        })
        compliance = compute_compliance(rows)
        phase_weeks = int(summary.get("phase_duration_weeks", 1) or 1)
        weekly_rows = weekly_progress_rows(rows, phase_weeks)
        weeks_completed = len([r for r in weekly_rows if int(r.get("completion_percentage", 0)) > 0])
        adherence_percent = int(compliance.get("completion_percent", 0))
        improvement = 0
        action = determine_next_action(improvement, adherence_percent, weeks_completed)
        regen = plan_regeneration_summary(len(rows), action, summary.get("domains", []))
        return {
            "summary": summary,
            "activities": rows,
            "compliance": compliance,
            "weekly_progress": weekly_rows,
            "projection": projection_from_compliance(int(compliance.get("completion_percent", 0))),
            "escalation_decision": escalation_decision(weekly_rows),
            "next_action": action,
            "plan_regeneration": regen,
        }

    @app.get("/health")
    def health() -> dict:
        return {"status": "ok", "time": datetime.utcnow().isoformat()}

    @app.post("/auth/login", response_model=LoginResponse)
    def login(payload: LoginRequest) -> LoginResponse:
        awc_code = _normalize_awc_code(payload.awc_code or payload.mobile_number or "", prefer_prefix="AWW")
        if not awc_code:
            raise HTTPException(status_code=400, detail="AWC code is required")
        if not _AWC_DEMO_PATTERN.fullmatch(awc_code):
            raise HTTPException(
                status_code=400,
                detail="Invalid AWC code. Use format AWW_DEMO_XXXX",
            )
        if not payload.password.strip():
            raise HTTPException(status_code=400, detail="Password is required")

        awc_variants = _awc_code_variants(awc_code)
        if not awc_variants:
            awc_variants = [awc_code]
        placeholders = ",".join("%s" for _ in awc_variants)
        with get_conn(db_path) as conn:
            row = conn.execute(
                f"""
                SELECT password
                FROM aww_profile
                WHERE UPPER(BTRIM(awc_code)) IN ({placeholders})
                LIMIT 1
                """,
                tuple(awc_variants),
            ).fetchone()
            if row is not None:
                saved_password = str(row.get("password") or "")
                if saved_password != payload.password:
                    raise HTTPException(status_code=401, detail="Invalid credentials")

        token = f"demo_jwt_{uuid.uuid4().hex}"
        return LoginResponse(token=token, user_id=f"aww_{awc_code.lower()}")

    @app.get("/auth/profile")
    def get_aww_profile(awc_code: str) -> dict:
        normalized_awc_code = _normalize_awc_code(awc_code, prefer_prefix="AWW")
        if not normalized_awc_code:
            raise HTTPException(status_code=400, detail="AWC code is required")

        awc_variants = _awc_code_variants(normalized_awc_code) or [normalized_awc_code]
        placeholders = ",".join("%s" for _ in awc_variants)
        with get_conn(db_path) as conn:
            profile_row = conn.execute(
                f"""
                SELECT
                    aww_id,
                    name,
                    mobile_number,
                    awc_code,
                    mandal,
                    district,
                    created_at,
                    updated_at
                FROM aww_profile
                WHERE UPPER(BTRIM(awc_code)) IN ({placeholders})
                ORDER BY COALESCE(NULLIF(BTRIM(updated_at), ''), NULLIF(BTRIM(created_at), '')) DESC,
                         aww_id DESC
                LIMIT 1
                """,
                tuple(awc_variants),
            ).fetchone()

            if profile_row is not None:
                profile = dict(profile_row)
                profile["awc_code"] = _normalize_awc_code(
                    profile.get("awc_code") or normalized_awc_code,
                    prefer_prefix="AWW",
                ) or normalized_awc_code
                profile["district"] = str(profile.get("district") or "").strip()
                profile["mandal"] = str(profile.get("mandal") or "").strip()
                return {"status": "ok", "source": "aww_profile", "profile": profile}

            inferred_row = conn.execute(
                f"""
                SELECT
                    NULLIF(BTRIM(district), '') AS district,
                    NULLIF(BTRIM(mandal), '') AS mandal,
                    COUNT(*) AS row_count
                FROM child_profile
                WHERE UPPER(BTRIM(awc_code)) IN ({placeholders})
                  AND (
                      COALESCE(BTRIM(district), '') <> ''
                      OR COALESCE(BTRIM(mandal), '') <> ''
                  )
                GROUP BY NULLIF(BTRIM(district), ''), NULLIF(BTRIM(mandal), '')
                ORDER BY row_count DESC, district NULLS LAST, mandal NULLS LAST
                LIMIT 1
                """,
                tuple(awc_variants),
            ).fetchone()

            if inferred_row is None:
                raise HTTPException(status_code=404, detail="AWW profile not found")

            profile = {
                "aww_id": f"aww_{normalized_awc_code.lower()}",
                "name": normalized_awc_code,
                "mobile_number": "",
                "awc_code": normalized_awc_code,
                "district": str(inferred_row.get("district") or "").strip(),
                "mandal": str(inferred_row.get("mandal") or "").strip(),
                "created_at": "",
                "updated_at": "",
            }
            return {"status": "ok", "source": "child_profile", "profile": profile}

    @app.post("/auth/register")
    def register_aww(payload: RegistrationRequest) -> dict:
        """Register a new AWW (Anganwadi Worker) to PostgreSQL database."""
        try:
            if not payload.password.strip():
                raise HTTPException(status_code=400, detail="Password is required")
            normalized_awc_code = _normalize_awc_code(payload.awc_code, prefer_prefix="AWW")
            if not normalized_awc_code:
                raise HTTPException(status_code=400, detail="AWC code is required")
            district = (payload.district or "").strip()
            mandal = (payload.mandal or "").strip()
            if not district or not mandal:
                raise HTTPException(
                    status_code=400,
                    detail="District and mandal are required",
                )
            display_name = (payload.name or "").strip() or normalized_awc_code
            mobile_number = (payload.mobile_number or "").strip()
            awc_variants = _awc_code_variants(normalized_awc_code) or [normalized_awc_code]

            aww_id = f"aww_{uuid.uuid4().hex[:12]}"
            created_at = datetime.utcnow().isoformat()
            updated_at = datetime.utcnow().isoformat()

            # Insert into PostgreSQL ecd_data.aww_profile.
            # Enforce one-time registration for the same AWC + district + mandal tuple.
            with get_conn(db_path) as conn:
                placeholders = ",".join("%s" for _ in awc_variants)
                existing = conn.execute(
                    f"""
                    SELECT aww_id
                    FROM aww_profile
                    WHERE UPPER(BTRIM(awc_code)) IN ({placeholders})
                      AND LOWER(BTRIM(COALESCE(district, ''))) = LOWER(%s)
                      AND LOWER(BTRIM(COALESCE(mandal, ''))) = LOWER(%s)
                    LIMIT 1
                    """,
                    tuple([*awc_variants, district, mandal]),
                ).fetchone()
                if existing is not None:
                    raise HTTPException(
                        status_code=409,
                        detail=(
                            "AWW already registered for this AWC code, district and mandal"
                        ),
                    )

                conn.execute(
                    """
                    INSERT INTO aww_profile(
                      aww_id, name, mobile_number, password, awc_code, 
                      mandal, district, created_at, updated_at
                    )
                    VALUES(%s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        aww_id,
                        display_name,
                        mobile_number or None,
                        payload.password,
                        normalized_awc_code,
                        mandal,
                        district,
                        created_at,
                        updated_at,
                    ),
                )
             
            return {
                "status": "ok",
                "message": "AWW registered successfully",
                "aww_id": aww_id,
                "created_at": created_at,
            }
        except HTTPException:
            raise
        except Exception as exc:
            print(f"❌ Registration error: {exc}")
            raise HTTPException(status_code=500, detail=f"Registration failed: {str(exc)}")

    @app.post("/children/register")
    def register_child(payload: ChildRegisterRequest) -> dict:
        """Register child profile to PostgreSQL ecd_data.child_profile table."""
        child_id = (payload.child_id or "").strip()
        if not child_id:
            raise HTTPException(status_code=400, detail="child_id is required")

        dob = (payload.date_of_birth or payload.dob or "").strip() or None
        gender = _normalize_gender(payload.gender)
        awc_code = _normalize_awc_code(payload.awc_id or payload.awc_code or "", prefer_prefix="AWW") or "AWW_DEMO_001"
        district = (payload.district_id or payload.district or "").strip() or ""
        mandal = (payload.mandal_id or payload.mandal or "").strip() or ""
        assessment_cycle = (payload.assessment_cycle or "Baseline").strip()
        awc_variants = _awc_code_variants(awc_code) or [awc_code]

        try:
            with _get_conn(db_path) as conn:
                placeholders = ",".join("%s" for _ in awc_variants)
                existing = conn.execute(
                    f"""
                    SELECT child_id, awc_code
                    FROM child_profile
                    WHERE child_id = %s
                      AND UPPER(BTRIM(awc_code)) IN ({placeholders})
                    LIMIT 1
                    """,
                    tuple([child_id, *awc_variants]),
                ).fetchone()
                if existing is not None:
                    raise HTTPException(
                        status_code=409,
                        detail=(
                            f"child_id '{child_id}' already exists in anganwadi '{awc_code}'. "
                            "Use a different child_id for this anganwadi."
                        ),
                    )

                conn.execute(
                    """
                    INSERT INTO child_profile(
                      child_id, dob, gender, awc_code, district, mandal, assessment_cycle
                    )
                    VALUES(%s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        child_id,
                        dob,
                        gender,
                        awc_code,
                        district,
                        mandal,
                        assessment_cycle,
                    ),
                )

                row = conn.execute(
                    """
                    SELECT child_id, dob, gender, awc_code, district, mandal, assessment_cycle
                    FROM child_profile
                    WHERE child_id = %s AND awc_code = %s
                    LIMIT 1
                    """,
                    (child_id, awc_code),
                ).fetchone()

            return {
                "status": "ok",
                "message": "Child profile registered successfully",
                "child": dict(row) if row else {"child_id": child_id}
            }
        except HTTPException:
            raise
        except Exception as exc:
            print(f"❌ Child registration error: {exc}")
            raise HTTPException(status_code=500, detail=f"Child registration failed: {str(exc)}")

    @app.get("/children/{child_id}")
    def get_child(child_id: str) -> dict:
        with _get_conn(db_path) as conn:
            row = conn.execute(
                """
                SELECT
                    c.child_id,
                    c.dob,
                    c.gender,
                    c.awc_code,
                    c.mandal,
                    c.district,
                    c.assessment_cycle,
                    se.age_months,
                    EXISTS(
                        SELECT 1
                        FROM screening_event sx
                        WHERE sx.child_id = c.child_id
                          AND EXISTS(
                            SELECT 1
                            FROM screening_domain_score sdx
                            WHERE sdx.screening_id = sx.id
                              AND UPPER(BTRIM(COALESCE(sdx.domain, ''))) IN ('GM', 'FM', 'LC', 'COG', 'SE')
                          )
                          AND REGEXP_REPLACE(
                                UPPER(BTRIM(COALESCE(sx.awc_code, ''))),
                                '^(AWW|AWS)_DEMO_|^DEMO_(AWW|AWS)_',
                                'DEMO_'
                              ) = REGEXP_REPLACE(
                                UPPER(BTRIM(COALESCE(c.awc_code, ''))),
                                '^(AWW|AWS)_DEMO_|^DEMO_(AWW|AWS)_',
                                'DEMO_'
                              )
                    ) AS has_screening
                FROM child_profile c
                LEFT JOIN LATERAL (
                    SELECT sx.age_months
                    FROM screening_event sx
                        WHERE sx.child_id = c.child_id
                          AND EXISTS(
                            SELECT 1
                            FROM screening_domain_score sdx
                            WHERE sdx.screening_id = sx.id
                              AND UPPER(BTRIM(COALESCE(sdx.domain, ''))) IN ('GM', 'FM', 'LC', 'COG', 'SE')
                          )
                          AND REGEXP_REPLACE(
                                UPPER(BTRIM(COALESCE(sx.awc_code, ''))),
                                '^(AWW|AWS)_DEMO_|^DEMO_(AWW|AWS)_',
                                'DEMO_'
                              ) = REGEXP_REPLACE(
                                UPPER(BTRIM(COALESCE(c.awc_code, ''))),
                                '^(AWW|AWS)_DEMO_|^DEMO_(AWW|AWS)_',
                                'DEMO_'
                              )
                    ORDER BY sx.created_at DESC, sx.id DESC
                    LIMIT 1
                ) se ON TRUE
                WHERE c.child_id = %s
                LIMIT 1
                """,
                (child_id,),
            ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Child not found")
        child = _child_row_with_aliases(row)
        age_months = int(child.get("age_months") or 0)
        return {
            "child_id": child["child_id"],
            "child_name": child.get("child_name") or child["child_id"],
            "gender": child.get("gender") or "",
            "age_months": age_months,
            "dob": child.get("dob"),
            "awc_id": child.get("awc_id") or "",
            "awc_code": child.get("awc_code") or "",
            "mandal_id": child.get("mandal_id") or "",
            "mandal": child.get("mandal") or "",
            "district_id": child.get("district_id") or "",
            "district": child.get("district") or "",
            "assessment_cycle": child.get("assessment_cycle") or "Baseline",
            "has_screening": bool(child.get("has_screening") or False),
            "created_at": None,
            "updated_at": None,
        }

    @app.get("/children")
    def list_children(limit: int = 200, awc_code: Optional[str] = None) -> dict:
        safe_limit = max(1, min(limit, 1000))
        awc_variants = _awc_code_variants(awc_code)
        where_sql = ""
        query_params: List[Any] = []
        if awc_variants:
            placeholders = ",".join("%s" for _ in awc_variants)
            where_sql = f"WHERE UPPER(BTRIM(c.awc_code)) IN ({placeholders})"
            query_params.extend(awc_variants)
        query_params.append(safe_limit)
        with _get_conn(db_path) as conn:
            rows = conn.execute(
                f"""
                SELECT
                    c.child_id,
                    c.dob,
                    c.gender,
                    c.awc_code,
                    c.mandal,
                    c.district,
                    c.assessment_cycle,
                    se.age_months,
                    EXISTS(
                        SELECT 1
                        FROM screening_event sx
                        WHERE sx.child_id = c.child_id
                          AND EXISTS(
                            SELECT 1
                            FROM screening_domain_score sdx
                            WHERE sdx.screening_id = sx.id
                              AND UPPER(BTRIM(COALESCE(sdx.domain, ''))) IN ('GM', 'FM', 'LC', 'COG', 'SE')
                          )
                          AND REGEXP_REPLACE(
                                UPPER(BTRIM(COALESCE(sx.awc_code, ''))),
                                '^(AWW|AWS)_DEMO_|^DEMO_(AWW|AWS)_',
                                'DEMO_'
                              ) = REGEXP_REPLACE(
                                UPPER(BTRIM(COALESCE(c.awc_code, ''))),
                                '^(AWW|AWS)_DEMO_|^DEMO_(AWW|AWS)_',
                                'DEMO_'
                              )
                    ) AS has_screening
                FROM child_profile c
                LEFT JOIN LATERAL (
                    SELECT sx.age_months
                    FROM screening_event sx
                        WHERE sx.child_id = c.child_id
                          AND EXISTS(
                            SELECT 1
                            FROM screening_domain_score sdx
                            WHERE sdx.screening_id = sx.id
                              AND UPPER(BTRIM(COALESCE(sdx.domain, ''))) IN ('GM', 'FM', 'LC', 'COG', 'SE')
                          )
                          AND REGEXP_REPLACE(
                                UPPER(BTRIM(COALESCE(sx.awc_code, ''))),
                                '^(AWW|AWS)_DEMO_|^DEMO_(AWW|AWS)_',
                                'DEMO_'
                              ) = REGEXP_REPLACE(
                                UPPER(BTRIM(COALESCE(c.awc_code, ''))),
                                '^(AWW|AWS)_DEMO_|^DEMO_(AWW|AWS)_',
                                'DEMO_'
                              )
                    ORDER BY sx.created_at DESC, sx.id DESC
                    LIMIT 1
                ) se ON TRUE
                {where_sql}
                ORDER BY c.child_id DESC
                LIMIT %s
                """,
                tuple(query_params),
            ).fetchall()
        items = []
        for row in rows:
            child = _child_row_with_aliases(row)
            items.append(
                {
                    "child_id": child["child_id"],
                    "child_name": child.get("child_name") or child["child_id"],
                    "gender": child.get("gender") or "",
                    "age_months": int(child.get("age_months") or 0),
                    "dob": child.get("dob"),
                    "awc_id": child.get("awc_id") or "",
                    "awc_code": child.get("awc_code") or "",
                    "mandal_id": child.get("mandal_id") or "",
                    "mandal": child.get("mandal") or "",
                    "district_id": child.get("district_id") or "",
                    "district": child.get("district") or "",
                    "assessment_cycle": child.get("assessment_cycle") or "Baseline",
                    "has_screening": bool(child.get("has_screening") or False),
                    "created_at": None,
                    "updated_at": None,
                }
            )
        return {"count": len(items), "items": items}

    @app.delete("/children/{child_id}")
    def delete_child(child_id: str, awc_code: Optional[str] = None) -> dict:
        target_child_id = (child_id or "").strip()
        if not target_child_id:
            raise HTTPException(status_code=400, detail="child_id is required")

        awc_variants = _awc_code_variants(awc_code)
        where_sql = "child_id = %s"
        where_params: List[Any] = [target_child_id]
        if awc_variants:
            placeholders = ",".join("%s" for _ in awc_variants)
            where_sql += f" AND UPPER(BTRIM(awc_code)) IN ({placeholders})"
            where_params.extend(awc_variants)

        with _get_conn(db_path) as conn:
            def _resolve_nutrition_tables(codes: Optional[List[str]] = None) -> List[str]:
                table_names: List[str] = []
                if codes:
                    try:
                        for code in codes:
                            row = conn.execute(
                                "SELECT anganwadi_nutrition_table_name(%s) AS table_name",
                                (code,),
                            ).fetchone()
                            table_name = str((row or {}).get("table_name") or "").strip()
                            if re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", table_name):
                                table_names.append(table_name)
                    except Exception:
                        return _resolve_nutrition_tables(None)
                else:
                    rows = conn.execute(
                        """
                        SELECT table_name
                        FROM information_schema.tables
                        WHERE table_schema = 'public'
                          AND table_name LIKE 'nutrition_result_awc_%'
                        """
                    ).fetchall()
                    for row in rows:
                        table_name = str(row.get("table_name") or "").strip()
                        if re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", table_name):
                            table_names.append(table_name)
                # Preserve order while removing duplicates.
                return list(dict.fromkeys(table_names))

            def _resolve_improvement_view_tables() -> List[str]:
                rows = conn.execute(
                    """
                    SELECT t.table_name
                    FROM information_schema.tables t
                    JOIN information_schema.columns c
                      ON c.table_schema = t.table_schema
                     AND c.table_name = t.table_name
                    WHERE t.table_schema = 'public'
                      AND t.table_name LIKE 'improvement_view_%'
                      AND t.table_name <> 'improvement_view_registry'
                      AND c.column_name = 'child_id'
                    """
                ).fetchall()
                table_names: List[str] = []
                for row in rows:
                    table_name = str(row.get("table_name") or "").strip()
                    if re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", table_name):
                        table_names.append(table_name)
                # Preserve order while removing duplicates.
                return list(dict.fromkeys(table_names))

            def _table_exists(table_name: str) -> bool:
                row = conn.execute(
                    """
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = 'public' AND table_name = %s
                    LIMIT 1
                    """,
                    (table_name,),
                ).fetchone()
                return row is not None

            existing_row = conn.execute(
                f"""
                SELECT 1
                FROM child_profile
                WHERE {where_sql}
                LIMIT 1
                """,
                tuple(where_params),
            ).fetchone()
            if existing_row is None:
                raise HTTPException(status_code=404, detail="Child not found")

            deleted_profiles = conn.execute(
                f"DELETE FROM child_profile WHERE {where_sql}",
                tuple(where_params),
            ).rowcount

            screening_where_sql = "child_id = %s"
            screening_where_params: List[Any] = [target_child_id]
            if awc_variants:
                screening_placeholders = ",".join("%s" for _ in awc_variants)
                screening_where_sql += (
                    " AND ("
                    f"UPPER(BTRIM(COALESCE(awc_code, ''))) IN ({screening_placeholders}) "
                    "OR COALESCE(BTRIM(awc_code), '') = ''"
                    ")"
                )
                screening_where_params.extend(awc_variants)

            screening_rows = conn.execute(
                f"""
                SELECT id
                FROM screening_event
                WHERE {screening_where_sql}
                """,
                tuple(screening_where_params),
            ).fetchall()
            screening_ids = [
                int(r.get("id"))
                for r in screening_rows
                if r.get("id") is not None
            ]
            if screening_ids:
                scoring_placeholders = ",".join("%s" for _ in screening_ids)
                conn.execute(
                    f"DELETE FROM screening_domain_score WHERE screening_id IN ({scoring_placeholders})",
                    tuple(screening_ids),
                )
                conn.execute(
                    f"DELETE FROM developmental_risk_score WHERE screening_id IN ({scoring_placeholders})",
                    tuple(screening_ids),
                )
                conn.execute(
                    f"DELETE FROM domain_delay_table WHERE screening_id IN ({scoring_placeholders})",
                    tuple(screening_ids),
                )
            conn.execute(
                "DELETE FROM neuro_logical_risk WHERE child_id = %s",
                (target_child_id,),
            )
            deleted_screenings = conn.execute(
                f"DELETE FROM screening_event WHERE {screening_where_sql}",
                tuple(screening_where_params),
            ).rowcount

            deleted_nutrition = 0
            deleted_improvement_records = 0
            nutrition_where_sql = "child_id = %s"
            nutrition_where_params: List[Any] = [target_child_id]
            if awc_variants:
                nutrition_placeholders = ",".join("%s" for _ in awc_variants)
                nutrition_where_sql += (
                    f" AND UPPER(BTRIM(COALESCE(awc_code, ''))) IN ({nutrition_placeholders})"
                )
                nutrition_where_params.extend(awc_variants)
            deleted_nutrition += conn.execute(
                f"DELETE FROM nutrition_result WHERE {nutrition_where_sql}",
                tuple(nutrition_where_params),
            ).rowcount
            for table_name in _resolve_nutrition_tables(awc_variants or None):
                deleted_nutrition += conn.execute(
                    f"DELETE FROM {table_name} WHERE child_id = %s",
                    (target_child_id,),
                ).rowcount

            remaining_row = conn.execute(
                """
                SELECT COUNT(*) AS remaining_count
                FROM child_profile
                WHERE child_id = %s
                """,
                (target_child_id,),
            ).fetchone()
            remaining_count = int((remaining_row or {}).get("remaining_count") or 0)

            deleted_scope = "profile_only"
            if remaining_count == 0:
                deleted_scope = "profile_and_related_records"

                referral_rows = conn.execute(
                    """
                    SELECT referral_id
                    FROM referral_action
                    WHERE child_id = %s
                    """,
                    (target_child_id,),
                ).fetchall()
                referral_ids = [
                    str(r.get("referral_id") or "").strip()
                    for r in referral_rows
                    if str(r.get("referral_id") or "").strip()
                ]
                if referral_ids:
                    referral_placeholders = ",".join("%s" for _ in referral_ids)
                    conn.execute(
                        f"DELETE FROM follow_up_log WHERE referral_id IN ({referral_placeholders})",
                        tuple(referral_ids),
                    )
                    conn.execute(
                        f"DELETE FROM follow_up_activities WHERE referral_id IN ({referral_placeholders})",
                        tuple(referral_ids),
                    )
                    conn.execute(
                        f"DELETE FROM referral_status_history WHERE referral_id IN ({referral_placeholders})",
                        tuple(referral_ids),
                    )

                conn.execute(
                    "DELETE FROM referral_action WHERE child_id = %s",
                    (target_child_id,),
                )
                conn.execute(
                    "DELETE FROM developmental_risk_score WHERE child_id = %s",
                    (target_child_id,),
                )
                conn.execute(
                    "DELETE FROM domain_delay_table WHERE child_id = %s",
                    (target_child_id,),
                )
                conn.execute(
                    "DELETE FROM followup_outcome WHERE child_id = %s",
                    (target_child_id,),
                )
                if awc_variants:
                    deleted_nutrition += conn.execute(
                        "DELETE FROM nutrition_result WHERE child_id = %s",
                        (target_child_id,),
                    ).rowcount
                    for table_name in _resolve_nutrition_tables():
                        deleted_nutrition += conn.execute(
                            f"DELETE FROM {table_name} WHERE child_id = %s",
                            (target_child_id,),
                        ).rowcount

                # Problem-B improvement cleanup for this child across shared and
                # AWC-specific improvement view tables.
                for table_name in (
                    "improvement_images",
                    "improvement_summary",
                    "improvement_snapshots",
                    "improvement_table",
                    "milestone_tracking",
                ):
                    if _table_exists(table_name):
                        deleted_improvement_records += conn.execute(
                            f"DELETE FROM {table_name} WHERE child_id = %s",
                            (target_child_id,),
                        ).rowcount
                for table_name in _resolve_improvement_view_tables():
                    deleted_improvement_records += conn.execute(
                        f"DELETE FROM {table_name} WHERE child_id = %s",
                        (target_child_id,),
                    ).rowcount

        return {
            "status": "ok",
            "child_id": target_child_id,
            "deleted_profiles": int(deleted_profiles or 0),
            "deleted_screenings": int(deleted_screenings or 0),
            "deleted_nutrition_records": int(deleted_nutrition or 0),
            "deleted_improvement_records": int(deleted_improvement_records or 0),
            "deleted_scope": deleted_scope,
        }

    @app.post("/screening/predict-domain-delays")
    def predict_domain_delays_for_screen(payload: ScreeningRequest) -> dict:
        result = _predict_screening_result(payload)
        return {
            "status": "ok",
            "risk_level": str(result.get("risk_level", "low")),
            "domain_scores": dict(result.get("domain_scores") or {}),
            "explanation": list(result.get("explanation") or []),
            "delay_summary": dict(result.get("delay_summary") or {}),
            "model_source": str(result.get("model_source") or ""),
        }

    @app.post("/nutrition/predict-risk")
    def predict_nutrition_risk_for_screen(payload: NutritionPredictRequest) -> dict:
        features = dict(payload.features or {})
        features.setdefault("age_months", payload.age_months)

        if nutrition_model is not None:
            try:
                result = predict_nutrition_risk_ml(features, nutrition_model)
                return {"status": "ok", **result}
            except Exception as exc:
                fallback = _fallback_nutrition_risk(features)
                fallback["status"] = "ok"
                fallback["warning"] = f"Nutrition model prediction failed; fallback used: {exc}"
                return fallback

        fallback = _fallback_nutrition_risk(features)
        fallback["status"] = "ok"
        if nutrition_model_load_error:
            fallback["warning"] = (
                "Nutrition model unavailable; fallback rules used: "
                f"{nutrition_model_load_error}"
            )
        return fallback

    @app.post("/nutrition/submit")
    def submit_nutrition_result(payload: NutritionSubmitRequest) -> dict:
        child_id = str(payload.child_id or "").strip()
        if not child_id:
            raise HTTPException(status_code=400, detail="child_id is required")

        awc_code = _normalize_awc_code(
            payload.awc_code or payload.aww_id or "",
            prefer_prefix="AWW",
        )
        created_at = datetime.utcnow().isoformat()

        with _get_conn(db_path) as conn:
            cur = conn.execute(
                """
                INSERT INTO nutrition_result(
                  child_id, awc_code, aww_id, age_months,
                  waz, haz, whz,
                  underweight, stunting, wasting, anemia,
                  nutrition_score, risk_category, created_at
                )
                VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT(child_id, awc_code) DO UPDATE SET
                  aww_id = COALESCE(NULLIF(EXCLUDED.aww_id, ''), nutrition_result.aww_id),
                  age_months = EXCLUDED.age_months,
                  waz = EXCLUDED.waz,
                  haz = EXCLUDED.haz,
                  whz = EXCLUDED.whz,
                  underweight = EXCLUDED.underweight,
                  stunting = EXCLUDED.stunting,
                  wasting = EXCLUDED.wasting,
                  anemia = EXCLUDED.anemia,
                  nutrition_score = EXCLUDED.nutrition_score,
                  risk_category = EXCLUDED.risk_category,
                  created_at = EXCLUDED.created_at
                RETURNING id
                """,
                (
                    child_id,
                    awc_code,
                    str(payload.aww_id or "").strip() or None,
                    int(payload.age_months or 0),
                    payload.waz,
                    payload.haz,
                    payload.whz,
                    int(payload.underweight or 0),
                    int(payload.stunting or 0),
                    int(payload.wasting or 0),
                    int(payload.anemia or 0),
                    int(payload.nutrition_score or 0),
                    _normalize_risk(payload.risk_category),
                    created_at,
                ),
            )
            row = cur.fetchone()
            nutrition_id = int(row["id"]) if row and row.get("id") is not None else None
            conn.execute(
                """
                SELECT insert_anganwadi_nutrition_result(
                  %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s
                )
                """,
                (
                    awc_code,
                    child_id,
                    str(payload.aww_id or "").strip() or None,
                    int(payload.age_months or 0),
                    payload.waz,
                    payload.haz,
                    payload.whz,
                    int(payload.underweight or 0),
                    int(payload.stunting or 0),
                    int(payload.wasting or 0),
                    int(payload.anemia or 0),
                    int(payload.nutrition_score or 0),
                    _normalize_risk(payload.risk_category),
                    created_at,
                ),
            )

        return {
            "status": "ok",
            "id": nutrition_id,
            "child_id": child_id,
            "awc_code": awc_code,
            "risk_category": _normalize_risk(payload.risk_category),
        }

    @app.post("/screening/submit", response_model=ScreeningResponse)
    def submit_screening(payload: ScreeningRequest) -> ScreeningResponse:
        result = _predict_screening_result(payload)
        risk_level = str(result.get("risk_level", "low"))
        domain_scores = dict(result.get("domain_scores") or {})
        referral_data = _create_referral_action(
            db_path,
            child_id=payload.child_id,
            aww_id=(payload.aww_id or payload.awc_id or "").strip() or "unknown_aww",
            risk_level=risk_level,
            domain_scores=domain_scores,
        )
        result["referral_created"] = referral_data is not None
        result["referral_data"] = referral_data
        response = ScreeningResponse(**result)
        _save_screening(db_path, payload, response)
        return response

    @app.post("/referral/create", response_model=ReferralResponse)
    def create_referral(payload: ReferralRequest) -> ReferralResponse:
        if payload.referral_type not in {"PHC", "RBSK"}:
            raise HTTPException(status_code=400, detail="Referral type must be PHC or RBSK")
        referral_id = f"ref_{uuid.uuid4().hex[:12]}"
        created_on = datetime.utcnow().date()
        followup_days = 2 if _normalize_risk(payload.overall_risk) == "Critical" else 10
        followup_by = created_on + timedelta(days=followup_days)
        response = ReferralResponse(
            referral_id=referral_id,
            status="Pending",
            created_at=datetime.utcnow().isoformat(),
        )
        with _get_conn(db_path) as conn:
            conn.execute(
                """
                INSERT INTO referral_action(
                    referral_id,
                    child_id,
                    aww_id,
                    referral_required,
                    referral_type,
                    urgency,
                    referral_status,
                    referral_date,
                    completion_date,
                    followup_deadline,
                    escalation_level,
                    escalated_to,
                    last_updated
                )
                VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                (
                    referral_id,
                    payload.child_id,
                    payload.aww_id,
                    1,
                    payload.referral_type,
                    payload.urgency,
                    "Pending",
                    created_on.isoformat(),
                    None,
                    followup_by.isoformat(),
                    0,
                    None,
                    created_on.isoformat(),
                ),
            )
        
        # Generate follow-up activities based on risk profile
        domain_scores_dict = getattr(payload, 'domain_scores', {})
        if not isinstance(domain_scores_dict, dict):
            domain_scores_dict = {}
        
        _generate_follow_up_activities(
            db_path,
            referral_id=referral_id,
            child_id=payload.child_id,
            risk_level=payload.overall_risk,
            domain_scores=domain_scores_dict,
            autism_risk=getattr(payload, 'autism_risk', 'Low'),
            nutrition_risk=getattr(payload, 'nutrition_risk', 'Low'),
        )
        
        return response

    @app.get("/referral/list")
    def list_referrals(aww_id: str = "", limit: int = 200):
        normalized_aww = (aww_id or "").strip().upper()
        safe_limit = max(1, min(int(limit or 200), 1000))

        def _normalized_aww_key(value: str) -> str:
            raw = (value or "").strip().upper()
            if not raw:
                return ""
            m = re.match(r"^(AWW|AWS)_DEMO_(\d{3,4})$", raw)
            if m:
                return f"DEMO_{int(m.group(2))}"
            m = re.match(r"^DEMO_(AWW|AWS)_(\d{3,4})$", raw)
            if m:
                return f"DEMO_{int(m.group(2))}"
            return raw

        target_key = _normalized_aww_key(normalized_aww)
        with _get_conn(db_path) as conn:
            rows = conn.execute(
                """
                SELECT
                    ra.referral_id,
                    ra.child_id,
                    ra.aww_id,
                    ra.referral_type,
                    ra.urgency,
                    ra.referral_status,
                    ra.referral_date,
                    ra.followup_deadline,
                    ra.escalation_level,
                    ra.escalated_to,
                    ra.last_updated,
                    se.overall_risk
                FROM referral_action ra
                LEFT JOIN LATERAL (
                    SELECT overall_risk
                    FROM screening_event s
                    WHERE s.child_id = ra.child_id
                    ORDER BY s.created_at DESC, s.id DESC
                    LIMIT 1
                ) se ON TRUE
                ORDER BY ra.referral_date DESC, ra.referral_id DESC
                LIMIT %s
                """,
                (safe_limit,),
            ).fetchall()

        if target_key:
            rows = [
                r
                for r in rows
                if _normalized_aww_key(str(r["aww_id"] or "")) == target_key
            ]

        items = []
        for row in rows:
            severity = _normalize_risk(str(row["overall_risk"] or "Medium"))
            severity_upper = severity.upper()
            referral_date = _parse_date_safe(row["referral_date"]) or datetime.utcnow().date()
            followup_by = _parse_date_safe(row["followup_deadline"]) or (
                referral_date + timedelta(days=(2 if severity_upper == "CRITICAL" else 10))
            )
            urgency = str(row["urgency"] or ("Immediate" if severity_upper == "CRITICAL" else "Priority"))

            if severity_upper == "CRITICAL":
                referral_type_label = "Immediate Specialist Referral"
            else:
                referral_type_label = "Specialist Evaluation"

            items.append(
                {
                    "referral_id": row["referral_id"],
                    "child_id": row["child_id"],
                    "aww_id": row["aww_id"],
                    "overall_risk": severity,
                    "referral_type": row["referral_type"],
                    "referral_type_label": referral_type_label,
                    "urgency": urgency,
                    "status": _status_to_frontend(row["referral_status"]),
                    "created_on": referral_date.isoformat(),
                    "followup_by": followup_by.isoformat(),
                    "escalation_level": int(row["escalation_level"] or 0),
                    "escalated_to": row["escalated_to"],
                    "last_updated": row["last_updated"] or referral_date.isoformat(),
                }
            )

        return {"count": len(items), "items": items}

    @app.get("/referral/by-child/{child_id}")
    def get_referral_by_child(child_id: str):
        with _get_conn(db_path) as conn:
            row = conn.execute(
                """
                SELECT referral_id, child_id, aww_id, referral_type, urgency, referral_status,
                       referral_date, followup_deadline, escalation_level, escalated_to, last_updated
                FROM referral_action
                WHERE child_id = %s
                ORDER BY referral_date DESC, referral_id DESC
                LIMIT 1
                """,
                (child_id,),
            ).fetchone()
            screen = conn.execute(
                """
                SELECT overall_risk
                FROM screening_event
                WHERE child_id = %s
                ORDER BY created_at DESC, id DESC
                LIMIT 1
                """,
                (child_id,),
            ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Referral not found for child")

        referral_type = (row["referral_type"] or "").strip().upper()
        severity = _normalize_risk(screen["overall_risk"] if screen else "")
        if severity == "Critical":
            urgency = "Immediate"
            referral_type_label = "Immediate Specialist Referral"
            followup_days = 2
            facility = "District Specialist"
        else:
            urgency = "Priority"
            referral_type_label = "Specialist Evaluation"
            followup_days = 10
            facility = "Block Specialist"

        referral_date = _parse_date_safe(row["referral_date"]) or datetime.utcnow().date()
        followup_by = _parse_date_safe(row["followup_deadline"]) or (
            referral_date + timedelta(days=followup_days)
        )

        with _get_conn(db_path) as conn:
            _apply_overdue_escalation(
                conn,
                referral_id=row["referral_id"],
                status=row["referral_status"],
                followup_deadline=followup_by.isoformat(),
                escalation_level=row["escalation_level"],
            )

        return {
            "referral_id": row["referral_id"],
            "child_id": row["child_id"],
            "aww_id": row["aww_id"],
            "referral_type": referral_type,
            "referral_type_label": referral_type_label,
            "urgency": urgency,
            "facility": facility,
            "status": _current_referral_status(row["referral_id"]),
            "created_on": referral_date.isoformat(),
            "followup_by": followup_by.isoformat(),
            "escalation_level": int(row["escalation_level"] or 0),
            "escalated_to": row["escalated_to"],
            "last_updated": row["last_updated"] or referral_date.isoformat(),
        }

    @app.get("/referral/child/{child_id}/details")
    def get_referral_details(child_id: str):
        with _get_conn(db_path) as conn:
            referral = conn.execute(
                """
                SELECT referral_id, child_id, aww_id, referral_type, urgency, referral_status,
                       referral_date, completion_date, appointment_date, followup_deadline,
                       escalation_level, escalated_to, last_updated
                FROM referral_action
                WHERE child_id = %s
                ORDER BY referral_date DESC, referral_id DESC
                LIMIT 1
                """,
                (child_id,),
            ).fetchone()
            if referral is None:
                raise HTTPException(status_code=404, detail="Referral not found for child")

            child = conn.execute(
                """
                SELECT
                    c.child_id,
                    c.dob,
                    c.awc_code,
                    c.mandal,
                    c.district,
                    c.assessment_cycle,
                    se.age_months
                FROM child_profile c
                LEFT JOIN LATERAL (
                    SELECT age_months
                    FROM screening_event s
                    WHERE s.child_id = c.child_id
                    ORDER BY s.created_at DESC, s.id DESC
                    LIMIT 1
                ) se ON TRUE
                WHERE c.child_id = %s
                LIMIT 1
                """,
                (child_id,),
            ).fetchone()
            screen = conn.execute(
                """
                SELECT id, overall_risk, explainability, age_months
                FROM screening_event
                WHERE child_id = %s
                ORDER BY created_at DESC, id DESC
                LIMIT 1
                """,
                (child_id,),
            ).fetchone()
            domain_rows = []
            if screen is not None:
                domain_rows = conn.execute(
                    """
                    SELECT domain, risk_label
                    FROM screening_domain_score
                    WHERE screening_id = %s
                    """,
                    (screen["id"],),
                ).fetchall()

        severity = _normalize_risk(screen["overall_risk"] if screen else "Low").upper()
        risk_score = int(sum(_risk_points(r["risk_label"]) for r in domain_rows) * 2)

        delayed_domains = [
            _domain_display(r["domain"])
            for r in domain_rows
            if str(r["domain"]).upper() in {"GM", "FM", "LC", "COG", "SE"}
            and _risk_rank(str(r["risk_label"])) >= 1
        ]
        # Preserve order and remove duplicates.
        delayed_domains = list(dict.fromkeys(delayed_domains))

        autism_label = "No Significant Risk"
        adhd_label = "No Significant Risk"
        for r in domain_rows:
            domain_key = str(r["domain"]).upper()
            value = _normalize_risk(str(r["risk_label"]))
            if domain_key == "BPS_AUT":
                autism_label = f"{value} Risk" if value in {"Medium", "High", "Critical"} else "No Significant Risk"
            if domain_key == "BPS_ADHD":
                adhd_label = f"{value} Risk" if value in {"Medium", "High", "Critical"} else "No Significant Risk"

        behavior_flags = []
        explainability = str(screen["explainability"] if screen else "").strip()
        if explainability:
            for token in [t.strip() for t in explainability.replace("\n", ";").split(";") if t.strip()]:
                # Skip raw domain labels like "GM: high", keep meaningful notes.
                if ":" in token and token.split(":", 1)[0].strip().upper() in {"GM", "FM", "LC", "COG", "SE"}:
                    continue
                behavior_flags.append(token)
                if len(behavior_flags) >= 3:
                    break
        if not behavior_flags:
            behavior_flags = ["No behavioral red flags observed."]

        if severity == "CRITICAL":
            urgency = "Immediate"
            facility = "District specialist"
            followup_days = 2
        else:
            urgency = "Priority"
            facility = "Block / District specialist"
            followup_days = 10

        created_on = _parse_date_safe(referral["referral_date"]) or datetime.utcnow().date()
        deadline = _parse_date_safe(referral["followup_deadline"])
        if deadline is None:
            deadline = created_on + timedelta(days=followup_days)
        appointment_date = _parse_date_safe(referral["appointment_date"])
        completion_date = _parse_date_safe(referral["completion_date"])

        with _get_conn(db_path) as conn:
            _apply_overdue_escalation(
                conn,
                referral_id=referral["referral_id"],
                status=referral["referral_status"],
                followup_deadline=deadline.isoformat(),
                escalation_level=referral["escalation_level"],
            )

        child_info_row = _child_row_with_aliases(child) if child else {}
        age_value = int(child_info_row.get("age_months") or 0)
        if age_value <= 0 and screen is not None:
            age_value = int(screen["age_months"] or 0)

        return {
            "referral_id": referral["referral_id"],
            "child_info": {
                "name": str(child_info_row.get("child_name") or child_id),
                "child_id": child_id,
                "age": age_value,
                "gender": str(child_info_row.get("gender") or "Unknown"),
                "village_or_awc_id": str(
                    child_info_row.get("village")
                    or child_info_row.get("awc_id")
                    or "N/A"
                ),
                "assigned_worker": str(referral["aww_id"] or "N/A"),
            },
            "risk_summary": {
                "severity": severity,
                "risk_score": risk_score,
                "delayed_domains": delayed_domains,
                "autism_risk": autism_label,
                "adhd_risk": adhd_label,
                "behavior_flags": behavior_flags,
            },
            "decision": {
                "urgency": urgency.upper(),
                "facility": facility,
                "created_on": created_on.isoformat(),
                "deadline": deadline.isoformat(),
                "escalation_level": int(referral["escalation_level"] or 0),
                "escalated_to": referral["escalated_to"],
            },
            "status": _status_to_frontend(referral["referral_status"]),
            "appointment_date": appointment_date.isoformat() if appointment_date else None,
            "completion_date": completion_date.isoformat() if completion_date else None,
            "last_updated": referral["last_updated"] or created_on.isoformat(),
        }

    @app.get("/analytics/monitoring")
    def analytics_monitoring(role: str = "state", location_id: str = "") -> dict:
        return _compute_monitoring(db_path, role=role, location_id=location_id)

    @app.get("/analytics/impact")
    def analytics_impact(role: str = "state", location_id: str = "") -> dict:
        return _compute_impact(db_path, role=role, location_id=location_id)

    @app.post("/intervention/plan")
    def intervention_plan(payload: Dict):
        # Accept raw dict payload to avoid pydantic nesting issues in runtime
        data = payload or {}
        # Normalize numeric domain scores into severity labels expected by generator
        ds = data.get("domain_scores")
        if isinstance(ds, dict):
            normalized = {}
            for k, v in ds.items():
                try:
                    val = float(v)
                except Exception:
                    normalized[k] = v
                    continue
                # map 0-1 score (lower worse) to severity
                if val <= 0.25:
                    normalized[k] = "Critical"
                elif val <= 0.5:
                    normalized[k] = "High"
                elif val <= 0.75:
                    normalized[k] = "Mild"
                else:
                    normalized[k] = "Normal"
            data["domain_scores"] = normalized
        result = generate_intervention(data)
        return result

    class FollowupRequest(BaseModel):
        child_id: str
        baseline_delay: int
        followup_delay: int

    @app.post("/followup/assess")
    def followup_assess(payload: FollowupRequest):
        return calculate_trend(payload.baseline_delay, payload.followup_delay)

    class ProblemBPlanRequest(BaseModel):
        child_id: str
        gm_delay: int = 0
        fm_delay: int = 0
        lc_delay: int = 0
        cog_delay: int = 0
        se_delay: int = 0
        risk_category: str = "Low"

    @app.post("/problem-b/intervention-plan")
    def problem_b_intervention_plan(payload: ProblemBPlanRequest):
        return generate_intervention_plan(payload.model_dump())

    class ProblemBTrendRequest(BaseModel):
        baseline_delay: int
        followup_delay: int

    @app.post("/problem-b/trend")
    def problem_b_trend(payload: ProblemBTrendRequest):
        reduction, trend = calculate_trend(payload.baseline_delay, payload.followup_delay)
        return {
            "delay_reduction": reduction,
            "trend": trend,
        }

    class ProblemBAdjustRequest(BaseModel):
        current_intensity: str
        trend: str
        delay_reduction: int = 0

    @app.post("/problem-b/adjust-intensity")
    def problem_b_adjust(payload: ProblemBAdjustRequest):
        adjusted = adjust_intensity(payload.current_intensity, payload.trend)
        decision = next_review_decision(adjusted, payload.delay_reduction, payload.trend)
        return {
            "adjusted_intensity": adjusted,
            "next_review_decision": decision,
        }

    @app.get("/problem-b/rules")
    def problem_b_rules():
        return rule_logic_table()

    @app.get("/problem-b/system-flow")
    def problem_b_system_flow():
        return {
            "flow": [
                "Assessment Data",
                "Risk Calculation",
                "Intervention Generator",
                "Referral Decision",
                "Caregiver Engagement Engine",
                "Follow-Up Assessment",
                "Trend Analysis",
                "Intensity Adjustment",
                "Dashboard Reporting",
            ]
        }

    class ActivityGenerationRequest(BaseModel):
        child_id: str
        age_months: int
        delayed_domains: List[str]
        autism_risk: Optional[str] = "Low"
        baseline_risk_category: Optional[str] = "Low"
        severity_level: Optional[str] = None

    @app.post("/problem-b/activities/generate")
    def generate_problem_b_activities(payload: ActivityGenerationRequest):
        delayed = [d for d in payload.delayed_domains if d in {"GM", "FM", "LC", "COG", "SE"}]
        severity = payload.severity_level or derive_severity(
            delayed,
            autism_risk=payload.autism_risk or "Low",
            baseline_risk_category=payload.baseline_risk_category or "Low",
        )
        assigned, summary = assign_activities_for_child(
            child_id=payload.child_id,
            age_months=payload.age_months,
            delayed_domains=delayed,
            severity_level=severity,
        )
        activity_tracking_store[payload.child_id] = assigned
        activity_plan_summary_store[payload.child_id] = summary
        return _phase_payload(payload.child_id)

    @app.get("/problem-b/activities/{child_id}")
    def get_problem_b_activities(child_id: str):
        return _phase_payload(child_id)

    class ActivityStatusUpdateRequest(BaseModel):
        child_id: str
        activity_id: str
        status: str = Field(default="completed")

    @app.post("/problem-b/activities/mark-status")
    def update_activity_status(payload: ActivityStatusUpdateRequest):
        rows = activity_tracking_store.get(payload.child_id, [])
        status = payload.status.strip().lower()
        if status not in {"pending", "completed", "skipped"}:
            raise HTTPException(status_code=400, detail="Invalid status")
        updated = False
        for row in rows:
            if row.get("activity_id") == payload.activity_id:
                row["status"] = status
                row["completion_date"] = datetime.utcnow().isoformat() if status == "completed" else None
                required = max(int(row.get("required_count", 1)), 1)
                row["completed_count"] = required if status == "completed" else 0
                row["compliance_score"] = 1 if status == "completed" else 0
                updated = True
                break
        if not updated:
            raise HTTPException(status_code=404, detail="Activity not found")
        return {
            "status": "ok",
            "child_id": payload.child_id,
            "activity_id": payload.activity_id,
            "updated_status": status,
            **_phase_payload(payload.child_id),
        }

    @app.get("/problem-b/compliance/{child_id}")
    def get_problem_b_compliance(child_id: str):
        rows = activity_tracking_store.get(child_id, [])
        compliance = compute_compliance(rows)
        summary = activity_plan_summary_store.get(child_id, {})
        phase_weeks = int(summary.get("phase_duration_weeks", 1) or 1)
        weekly_rows = weekly_progress_rows(rows, phase_weeks)
        return {
            "child_id": child_id,
            **compliance,
            "projection": projection_from_compliance(int(compliance.get("completion_percent", 0))),
            "escalation_decision": escalation_decision(weekly_rows),
        }

    class ResetFrequencyRequest(BaseModel):
        child_id: str
        frequency_type: str

    @app.post("/problem-b/activities/reset-frequency")
    def reset_frequency(payload: ResetFrequencyRequest):
        freq = payload.frequency_type.strip().lower()
        if freq not in {"daily", "weekly"}:
            raise HTTPException(status_code=400, detail="frequency_type must be daily or weekly")
        rows = activity_tracking_store.get(payload.child_id, [])
        updated_count = reset_frequency_status(rows, freq)
        phase = _phase_payload(payload.child_id)
        return {
            "status": "ok",
            "child_id": payload.child_id,
            "frequency_type": freq,
            "updated_count": updated_count,
            **phase,
        }

    class AppointmentCreateRequest(BaseModel):
        referral_id: str
        child_id: str
        scheduled_date: str
        appointment_type: str
        notes: Optional[str] = ""
        created_by: Optional[str] = "aww"

    class AppointmentUpdateRequest(BaseModel):
        status: str
        notes: Optional[str] = ""

    @app.post("/appointments")
    def create_appointment(payload: AppointmentCreateRequest):
        appointment_id = f"appt_{uuid.uuid4().hex[:10]}"
        record = {
            "appointment_id": appointment_id,
            "referral_id": payload.referral_id,
            "child_id": payload.child_id,
            "scheduled_date": payload.scheduled_date,
            "appointment_type": payload.appointment_type,
            "status": "SCHEDULED",
            "created_by": payload.created_by or "aww",
            "created_on": datetime.utcnow().isoformat(),
            "notes": payload.notes or "",
        }
        appointments_store.setdefault(payload.referral_id, []).append(record)
        return {
            "status": "ok",
            "appointment": record,
            "suggested_status": _suggested_referral_status(payload.referral_id),
            "current_status": _current_referral_status(payload.referral_id),
        }

    @app.put("/appointments/{appointment_id}")
    def update_appointment(appointment_id: str, payload: AppointmentUpdateRequest):
        new_status = payload.status.strip().upper()
        if new_status not in {"SCHEDULED", "COMPLETED", "CANCELLED", "RESCHEDULED", "MISSED"}:
            raise HTTPException(status_code=400, detail="Invalid appointment status")
        for referral_id, records in appointments_store.items():
            for record in records:
                if record.get("appointment_id") == appointment_id:
                    record["status"] = new_status
                    if payload.notes:
                        record["notes"] = payload.notes
                    return {
                        "status": "ok",
                        "appointment": record,
                        "suggested_status": _suggested_referral_status(referral_id),
                        "current_status": _current_referral_status(referral_id),
                    }
        raise HTTPException(status_code=404, detail="Appointment not found")

    @app.get("/referral/{referral_id}/appointments")
    def list_appointments(referral_id: str):
        try:
            records = appointments_store.get(referral_id, [])
            next_scheduled = None
            scheduled = [r for r in records if r.get("status") == "SCHEDULED"]
            if scheduled:
                next_scheduled = sorted(scheduled, key=lambda r: r.get("scheduled_date") or "")[0]
            return {
                "referral_id": referral_id,
                "appointments": records,
                "suggested_status": _suggested_referral_status(referral_id),
                "current_status": _current_referral_status(referral_id),
                "next_appointment": next_scheduled,
            }
        except Exception as e:
            print(f"Error listing appointments: {e}")
            raise HTTPException(status_code=500, detail=str(e))

    @app.post("/referral/{referral_id}/status")
    def update_referral_status(referral_id: str, payload: ReferralStatusUpdateRequest):
        status = _status_to_db(payload.status)
        today = _today_iso()
        with _get_conn(db_path) as conn:
            row = conn.execute(
                "SELECT referral_id, referral_status FROM referral_action WHERE referral_id = %s LIMIT 1",
                (referral_id,),
            ).fetchone()
            if row is None:
                raise HTTPException(status_code=404, detail="Referral not found")
            completion_date = payload.completion_date or (
                today if status == "Completed" else None
            )
            appointment_date = payload.appointment_date or (
                today if status in {"Appointment Scheduled", "Under Treatment"} else None
            )
            escalation_level = None
            followup_deadline = None
            if status == "Missed":
                current = conn.execute(
                    "SELECT escalation_level FROM referral_action WHERE referral_id = %s",
                    (referral_id,),
                ).fetchone()
                level = int(current["escalation_level"] or 0) + 1 if current else 1
                escalation_level = level
                followup_deadline = (
                    datetime.utcnow().date() + timedelta(days=2)
                ).isoformat()
            conn.execute(
                """
                UPDATE referral_action
                SET referral_status = %s,
                    completion_date = COALESCE(%s, completion_date),
                    appointment_date = COALESCE(%s, appointment_date),
                    followup_deadline = COALESCE(%s, followup_deadline),
                    escalation_level = COALESCE(%s, escalation_level),
                    last_updated = %s
                WHERE referral_id = %s
                """,
                (
                    status,
                    completion_date,
                    appointment_date,
                    followup_deadline,
                    escalation_level,
                    today,
                    referral_id,
                ),
            )
            conn.execute(
                """
                INSERT INTO referral_status_history(
                    referral_id, old_status, new_status, changed_on, worker_id
                )
                VALUES(%s,%s,%s,%s,%s)
                """,
                (
                    referral_id,
                    row["referral_status"],
                    status,
                    today,
                    payload.worker_id,
                ),
            )

            # Keep activity tracking in sync with referral lifecycle.
            # If referral is completed, mark any pending follow-up activities completed.
            if status == "Completed":
                activity_rows = conn.execute(
                    """
                    SELECT id
                    FROM follow_up_activities
                    WHERE referral_id = %s
                    """,
                    (referral_id,),
                ).fetchall()
                completed_rows = conn.execute(
                    """
                    SELECT DISTINCT activity_id
                    FROM follow_up_log
                    WHERE referral_id = %s AND completed = 1
                    """,
                    (referral_id,),
                ).fetchall()
                completed_ids = {int(r["activity_id"]) for r in completed_rows}
                completion_stamp = completion_date or today
                for r in activity_rows:
                    activity_id = int(r["id"])
                    if activity_id in completed_ids:
                        continue
                    conn.execute(
                        """
                        INSERT INTO follow_up_log (
                            referral_id, activity_id, completed, completed_on, remarks
                        ) VALUES (%s, %s, %s, %s, %s)
                        """,
                        (
                            referral_id,
                            activity_id,
                            1,
                            completion_stamp,
                            "Auto-completed when referral status moved to Completed.",
                        ),
                    )
        referral_status_store[referral_id] = _status_to_frontend(status)
        return {
            "status": "ok",
            "referral_id": referral_id,
            "current_status": _status_to_frontend(status),
            "suggested_status": _suggested_referral_status(referral_id),
        }

    @app.put("/referral/update-status")
    def update_referral_status_by_id(payload: ReferralStatusUpdateByIdRequest):
        return update_referral_status(
            payload.referral_id,
            ReferralStatusUpdateRequest(
                status=payload.status,
                appointment_date=payload.appointment_date,
                completion_date=payload.completion_date,
                worker_id=payload.worker_id,
            ),
        )

    @app.post("/referral/{referral_id}/escalate")
    def escalate_referral(referral_id: str, payload: ReferralEscalateRequest):
        today = _today_iso()
        with _get_conn(db_path) as conn:
            row = conn.execute(
                """
                SELECT escalation_level, referral_status
                FROM referral_action
                WHERE referral_id = %s
                """,
                (referral_id,),
            ).fetchone()
            if row is None:
                raise HTTPException(status_code=404, detail="Referral not found")
            level = int(row["escalation_level"] or 0) + 1
            escalated_to = _escalation_target(level)
            new_deadline = (datetime.utcnow().date() + timedelta(days=2)).isoformat()
            conn.execute(
                """
                UPDATE referral_action
                SET escalation_level = %s,
                    escalated_to = %s,
                    followup_deadline = %s,
                    last_updated = %s
                WHERE referral_id = %s
                """,
                (level, escalated_to, new_deadline, today, referral_id),
            )
        return {
            "status": "ok",
            "referral_id": referral_id,
            "escalation_level": level,
            "escalated_to": escalated_to,
            "followup_deadline": new_deadline,
        }

    @app.get("/referral/{referral_id}/history")
    def get_referral_history(referral_id: str):
        with _get_conn(db_path) as conn:
            rows = conn.execute(
                """
                SELECT id, referral_id, old_status, new_status, changed_on, worker_id
                FROM referral_status_history
                WHERE referral_id = %s
                ORDER BY changed_on DESC, id DESC
                """,
                (referral_id,),
            ).fetchall()
        history = [
            {
                "id": r["id"],
                "referral_id": r["referral_id"],
                "old_status": _status_to_frontend(r["old_status"]),
                "new_status": _status_to_frontend(r["new_status"]),
                "changed_on": r["changed_on"],
                "worker_id": r["worker_id"],
            }
            for r in rows
        ]
        return {"referral_id": referral_id, "history": history}

    # ============================================================================
    # Problem B: Follow-Up Tracking Endpoints
    # ============================================================================

    @app.get("/follow-up/{referral_id}")
    def get_follow_up_page(referral_id: str):
        """Get complete follow-up page data: referral summary + activities"""
        with _get_conn(db_path) as conn:
            # Get referral details
            referral = conn.execute(
                """
                SELECT referral_id, child_id, aww_id, referral_type, urgency,
                       referral_status, referral_date, followup_deadline,
                       escalation_level, escalated_to
                FROM referral_action
                WHERE referral_id = %s
                """,
                (referral_id,),
            ).fetchone()

            if referral is None:
                raise HTTPException(status_code=404, detail="Referral not found")

            # Get follow-up activities
            activities = conn.execute(
                """
                SELECT id, referral_id, target_user, domain, activity_title,
                       activity_description, frequency, duration_days, created_on
                FROM follow_up_activities
                WHERE referral_id = %s
                ORDER BY target_user, domain
                """,
                (referral_id,),
            ).fetchall()

            # Get activity completion logs
            activity_logs = conn.execute(
                """
                SELECT activity_id, completed, completed_on, remarks
                FROM follow_up_log
                WHERE referral_id = %s
                ORDER BY completed_on DESC
                """,
                (referral_id,),
            ).fetchall()

        # Build activity completion map
        log_map = {int(log["activity_id"]): log for log in activity_logs}
        status_frontend = _status_to_frontend(referral["referral_status"])
        force_completed = status_frontend == "COMPLETED"

        # Format response
        formatted_activities = []
        for act in activities:
            log = log_map.get(act["id"], {})
            is_completed = force_completed or (log.get("completed", 0) == 1)
            formatted_activities.append({
                "id": act["id"],
                "target_user": act["target_user"],
                "domain": act["domain"],
                "title": act["activity_title"],
                "description": act["activity_description"],
                "frequency": act["frequency"],
                "duration_days": act["duration_days"],
                "completed": is_completed,
                "completed_on": log.get("completed_on"),
                "remarks": log.get("remarks"),
            })

        # Determine days to deadline
        deadline = _parse_date_safe(referral["followup_deadline"])
        today = datetime.utcnow().date()
        days_remaining = (deadline - today).days if deadline else 0
        is_overdue = days_remaining < 0 and status_frontend != "COMPLETED"
        total_activities = len(formatted_activities)
        completed_activities = sum(1 for a in formatted_activities if a["completed"])
        if total_activities > 0:
            completion_percent = int((completed_activities / total_activities) * 100)
        else:
            completion_percent = 100 if status_frontend == "COMPLETED" else 0

        return {
            "referral_id": referral_id,
            "child_id": referral["child_id"],
            "facility": referral["referral_type"],
            "urgency": referral["urgency"],
            "status": status_frontend,
            "created_on": referral["referral_date"],
            "deadline": referral["followup_deadline"],
            "days_remaining": days_remaining,
            "is_overdue": is_overdue,
            "escalation_level": referral["escalation_level"],
            "escalated_to": referral["escalated_to"],
            "activities": formatted_activities,
            "total_activities": total_activities,
            "completed_activities": completed_activities,
            "completion_percent": completion_percent,
            "progress": float(completion_percent),
        }

    class CompleteActivityRequest(BaseModel):
        remarks: Optional[str] = None

    @app.post("/follow-up/{referral_id}/activity/{activity_id}/complete")
    def complete_activity(referral_id: str, activity_id: int, payload: CompleteActivityRequest):
        """Mark an activity as completed"""
        today = datetime.utcnow().date().isoformat()

        with _get_conn(db_path) as conn:
            # Verify activity exists
            activity = conn.execute(
                """
                SELECT id FROM follow_up_activities
                WHERE id = %s AND referral_id = %s
                """,
                (activity_id, referral_id),
            ).fetchone()

            if activity is None:
                raise HTTPException(status_code=404, detail="Activity not found")

            # Insert completion log
            conn.execute(
                """
                INSERT INTO follow_up_log (
                    referral_id, activity_id, completed, completed_on, remarks
                ) VALUES (%s, %s, %s, %s, %s)
                """,
                (referral_id, activity_id, 1, today, payload.remarks or ""),
            )

        return {
            "status": "ok",
            "activity_id": activity_id,
            "completed_on": today,
        }

    @app.get("/follow-up/{referral_id}/progress")
    def get_follow_up_progress(referral_id: str):
        """Get follow-up completion progress"""
        with _get_conn(db_path) as conn:
            # Count total activities
            total = conn.execute(
                """
                SELECT COUNT(*) as cnt FROM follow_up_activities
                WHERE referral_id = %s
                """,
                (referral_id,),
            ).fetchone()["cnt"]

            # Count completed activities
            completed = conn.execute(
                """
                SELECT COUNT(DISTINCT activity_id) as cnt FROM follow_up_log
                WHERE referral_id = %s AND completed = 1
                """,
                (referral_id,),
            ).fetchone()["cnt"]

        completion_percent = int((completed / total * 100) if total > 0 else 0)

        return {
            "referral_id": referral_id,
            "total_activities": total,
            "completed_activities": completed,
            "completion_percent": completion_percent,
        }

    @app.post("/follow-up/auto-escalate-overdue")
    def auto_escalate_overdue():
        """Auto-escalate all overdue referrals that haven't been completed"""
        today = datetime.utcnow().date()
        escalated_count = 0

        with _get_conn(db_path) as conn:
            # Find all overdue referrals
            overdue = conn.execute(
                """
                SELECT referral_id, escalation_level, referral_status
                FROM referral_action
                WHERE followup_deadline < %s AND referral_status != 'Completed'
                """,
                (today.isoformat(),),
            ).fetchall()

            for referral in overdue:
                referral_id = referral["referral_id"]
                current_level = int(referral["escalation_level"] or 0)
                new_level = current_level + 1
                escalated_to = _escalation_target(new_level)
                new_deadline = (today + timedelta(days=2)).isoformat()

                # Update referral
                conn.execute(
                    """
                    UPDATE referral_action
                    SET escalation_level = %s,
                        escalated_to = %s,
                        followup_deadline = %s,
                        last_updated = %s
                    WHERE referral_id = %s
                    """,
                    (new_level, escalated_to, new_deadline, today.isoformat(), referral_id),
                )

                # Log in status history
                conn.execute(
                    """
                    INSERT INTO referral_status_history (
                        referral_id, old_status, new_status, changed_on, worker_id
                    ) VALUES (%s, %s, %s, %s, %s)
                    """,
                    (
                        referral_id,
                        referral["referral_status"],
                        "Escalated (Overdue)",
                        today.isoformat(),
                        "SYSTEM_AUTO",
                    ),
                )

                escalated_count += 1

        return {
            "status": "ok",
            "escalated_count": escalated_count,
            "timestamp": datetime.utcnow().isoformat(),
            "message": f"Auto-escalated {escalated_count} overdue referral(s)",
        }

    class CaregiverEngagementRequest(BaseModel):
        child_id: str
        mode: str
        contact: Optional[Dict[str, str]] = None

    @app.post("/caregiver/engage")
    def caregiver_engage(payload: CaregiverEngagementRequest):
        mode = payload.mode.lower()
        if "phone" in mode and payload.contact:
            return {"status": "queued", "mode": payload.mode, "note": "IVR/WhatsApp message scheduled"}
        return {"status": "ok", "mode": payload.mode, "note": "Printed material to be provided"}

    class TasksSaveRequest(BaseModel):
        child_id: str
        aww_checks: Optional[Dict[str, bool]] = None
        parent_checks: Optional[Dict[str, bool]] = None
        caregiver_checks: Optional[Dict[str, bool]] = None
        aww_remarks: Optional[str] = None
        caregiver_remarks: Optional[str] = None

    @app.post("/tasks/save")
    def save_tasks(payload: TasksSaveRequest):
        data = payload.model_dump()
        child = data.pop("child_id")
        tasks_store[child] = data
        return {"status": "saved", "child_id": child}

    @app.get("/tasks/{child_id}")
    def get_tasks(child_id: str):
        return tasks_store.get(child_id, {
            "aww_checks": {},
            "parent_checks": {},
            "caregiver_checks": {},
            "aww_remarks": "",
            "caregiver_remarks": "",
        })

    # ============================================================================
    # Problem B: Intervention Plan Management Endpoints
    # ============================================================================

    class InterventionPlanCreateRequest(BaseModel):
        child_id: str
        domain: str
        risk_level: str
        baseline_delay_months: Optional[int] = 3
        age_months: int

    @app.post("/intervention/plan/create")
    def create_intervention(payload: InterventionPlanCreateRequest):
        """Create intervention phase from risk assessment - starts strict 7-phase lifecycle"""
        try:
            from .problem_b_service import problem_b_service
        except ImportError:
            from problem_b_service import problem_b_service

        result = problem_b_service.create_intervention_phase(
            child_id=payload.child_id,
            domain=payload.domain,
            severity=payload.risk_level,  # risk_level -> severity
            baseline_delay=float(payload.baseline_delay_months),
            age_months=payload.age_months
        )
        return result

    class WeeklyProgressLogRequest(BaseModel):
        phase_id: str
        current_delay_months: float
        aww_completed: Optional[int] = 0
        caregiver_completed: Optional[int] = 0
        notes: Optional[str] = ""

    @app.post("/intervention/{phase_id}/progress/log")
    def log_weekly_progress(phase_id: str, payload: WeeklyProgressLogRequest):
        """Log activity completion and get review decision"""
        try:
            from .problem_b_service import problem_b_service
        except ImportError:
            from problem_b_service import problem_b_service

        # Persist weekly task logs from AWW/Caregiver completion counts.
        # This keeps compliance engine aligned with submitted weekly progress.
        try:
            with problem_b_service._get_conn(problem_b_service.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    """
                    SELECT activity_id, role FROM activities
                    WHERE phase_id = %s
                    ORDER BY role, created_at ASC
                    """,
                    (phase_id,),
                )
                activities = cursor.fetchall()
                aww_ids = [r["activity_id"] for r in activities if str(r["role"]).strip().lower() == "aww"]
                caregiver_ids = [r["activity_id"] for r in activities if str(r["role"]).strip().lower() != "aww"]
                aww_completed = max(int(payload.aww_completed or 0), 0)
                caregiver_completed = max(int(payload.caregiver_completed or 0), 0)
                now = datetime.utcnow().isoformat()

                def _log(activity_ids, completed_count):
                    for idx, activity_id in enumerate(activity_ids):
                        task_id = f"task_{uuid.uuid4().hex[:12]}"
                        done = 1 if idx < completed_count else 0
                        cursor.execute(
                            """
                            INSERT INTO task_logs(task_id, activity_id, date_logged, completed)
                            VALUES (%s, %s, %s, %s)
                            """,
                            (task_id, activity_id, now, done),
                        )

                _log(aww_ids, aww_completed)
                _log(caregiver_ids, caregiver_completed)
                conn.commit()
        except Exception:
            # Keep review flow non-blocking if task log insert has issues.
            pass

        # Calculate compliance for this phase
        compliance = problem_b_service.calculate_compliance(phase_id)
        
        # Run review if at review date
        review_result = problem_b_service.run_review_engine(phase_id, payload.current_delay_months)

        return {
            "phase_id": phase_id,
            "decision": review_result.get("decision", "CONTINUE"),
            "reason": review_result.get("reason", "Progress on track"),
            "adherence": float(compliance),
            "improvement": float(review_result.get("improvement", 0.0) or 0.0),
            "review_id": review_result.get("review_id", ""),
            "review_count": int(review_result.get("review_count", 0) or 0),
            "compliance": compliance,
            "review_decision": review_result,
            "notes": payload.notes
        }

    @app.get("/intervention/{phase_id}/activities")
    def get_intervention_activities(phase_id: str):
        """Fetch generated activities for a phase."""
        try:
            with problem_b_service._get_conn(problem_b_service.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    """
                    SELECT activity_id, phase_id, domain, role, name, frequency_per_week, created_at
                    FROM activities
                    WHERE phase_id = %s
                    ORDER BY role, created_at ASC
                    """,
                    (phase_id,),
                )
                rows = [dict(r) for r in cursor.fetchall()]
            return {"phase_id": phase_id, "activities": rows}
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

    @app.get("/intervention/{phase_id}/history")
    def get_intervention_history(phase_id: str):
        """Fetch full phase history: status, activities, review decisions, task logs."""
        try:
            phase_status = problem_b_service.get_phase_status(phase_id)
            if phase_status.get("status") == "error":
                raise HTTPException(status_code=404, detail=phase_status.get("message", "Phase not found"))

            with problem_b_service._get_conn(problem_b_service.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    """
                    SELECT activity_id, phase_id, domain, role, name, frequency_per_week, created_at
                    FROM activities
                    WHERE phase_id = %s
                    ORDER BY role, created_at ASC
                    """,
                    (phase_id,),
                )
                activities = [dict(r) for r in cursor.fetchall()]

                cursor.execute(
                    """
                    SELECT review_id, phase_id, review_date, compliance, improvement, decision_action, decision_reason
                    FROM review_log
                    WHERE phase_id = %s
                    ORDER BY review_date DESC
                    """,
                    (phase_id,),
                )
                reviews = [dict(r) for r in cursor.fetchall()]

                cursor.execute(
                    """
                    SELECT t.task_id, t.activity_id, t.date_logged, t.completed, a.role, a.name
                    FROM task_logs t
                    JOIN activities a ON a.activity_id = t.activity_id
                    WHERE a.phase_id = %s
                    ORDER BY t.date_logged DESC
                    LIMIT 200
                    """,
                    (phase_id,),
                )
                task_logs = [dict(r) for r in cursor.fetchall()]

            return {
                "phase_id": phase_id,
                "phase_status": phase_status,
                "activities": activities,
                "reviews": reviews,
                "task_logs": task_logs,
            }
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

    @app.get("/intervention/{phase_id}/status")
    def get_phase_status(phase_id: str):
        """Get current phase status with metrics"""
        try:
            from .problem_b_service import problem_b_service
        except ImportError:
            from problem_b_service import problem_b_service

        result = problem_b_service.get_phase_status(phase_id)
        return result

    @app.post("/intervention/{phase_id}/review")
    def trigger_review(phase_id: str, payload: WeeklyProgressLogRequest):
        """Trigger review engine - automatic decision point"""
        try:
            from .problem_b_service import problem_b_service
        except ImportError:
            from problem_b_service import problem_b_service

        result = problem_b_service.run_review_engine(phase_id, payload.current_delay_months)
        return result

    class PlanClosureRequest(BaseModel):
        closure_status: str = "success"  # success, referred, extended
        final_notes: Optional[str] = ""

    @app.post("/intervention/{phase_id}/complete")
    def complete_intervention_phase(phase_id: str, payload: PlanClosureRequest):
        """Mark intervention phase as completed"""
        try:
            try:
                from .problem_b_service import problem_b_service
            except ImportError:
                from problem_b_service import problem_b_service
            with _get_conn(problem_b_service.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    "UPDATE intervention_phase SET status = 'COMPLETED' WHERE phase_id = %s",
                    (phase_id,),
                )
                if cursor.rowcount == 0:
                    raise HTTPException(status_code=404, detail="Phase not found")

                conn.commit()
                return {
                    "phase_id": phase_id,
                    "status": "COMPLETED",
                    "closure_type": payload.closure_status,
                    "completed_at": datetime.utcnow().isoformat(),
                }
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

    # Problem B (additive API namespace): /api/referrals, /api/activities, /api/escalation
    try:
        if __package__:
            from .problem_b_referral_router import router as problem_b_referral_router
        else:
            from problem_b_referral_router import router as problem_b_referral_router
        app.include_router(problem_b_referral_router)
    except Exception:
        # Keep legacy endpoints available even if additive router import fails.
        pass

    try:
        if __package__:
            from .problem_b_improvement_router import router as problem_b_improvement_router
        else:
            from problem_b_improvement_router import router as problem_b_improvement_router
        app.include_router(problem_b_improvement_router)
    except Exception:
        pass

    try:
        if __package__:
            from .problem_b_timeline_router import router as problem_b_timeline_router
        else:
            from problem_b_timeline_router import router as problem_b_timeline_router
        app.include_router(problem_b_timeline_router)
    except Exception:
        pass

    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn
    from pathlib import Path

    # Pick an import path that matches the current working directory.
    cwd = Path.cwd()
    if (cwd / "backend" / "app" / "main.py").exists():
        app_path = "backend.app.main:app"
    elif (cwd / "app" / "main.py").exists():
        app_path = "app.main:app"
    else:
        app_path = "main:app"

    uvicorn.run(app_path, host="127.0.0.1", port=8000, reload=True)
