from __future__ import annotations

import os
import json
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from .pg_compat import get_conn

DEFAULT_ECD_DATABASE_URL = "postgresql://postgres:postgres@127.0.0.1:5432/ecd_data"

router = APIRouter(prefix="/api", tags=["problem-b-referral"])


class RiskDataSchema(BaseModel):
    child_id: str
    overall_risk_score: int
    overall_risk_level: str
    num_delays: int = 0
    gm_score: int = 0
    fm_score: int = 0
    lc_score: int = 0
    cog_score: int = 0
    se_score: int = 0
    autism_score: int = 0
    adhd_score: int = 0
    domain_breakdown: Dict[str, Any] = Field(default_factory=dict)


class ActivityCompleteRequest(BaseModel):
    notes: Optional[str] = None
    difficulty: Optional[int] = None
    reported_by: str = "CAREGIVER"


def _db_url() -> str:
    return os.getenv(
        "ECD_DATABASE_URL",
        os.getenv("DATABASE_URL", DEFAULT_ECD_DATABASE_URL),
    )


def _ensure_problem_b_tables() -> None:
    ddl = """
    CREATE SEQUENCE IF NOT EXISTS referrals_seq START 1;
    CREATE SEQUENCE IF NOT EXISTS activities_seq START 1;

    CREATE TABLE IF NOT EXISTS referrals (
        id BIGSERIAL PRIMARY KEY,
        referral_id VARCHAR(50) UNIQUE NOT NULL
            DEFAULT ('REF-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(nextval('referrals_seq')::TEXT, 4, '0')),
        child_id TEXT NOT NULL,
        overall_risk_score INTEGER NOT NULL,
        overall_risk_level VARCHAR(20) NOT NULL CHECK (overall_risk_level IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
        num_delays INTEGER NOT NULL DEFAULT 0,
        gm_score INTEGER DEFAULT 0,
        fm_score INTEGER DEFAULT 0,
        lc_score INTEGER DEFAULT 0,
        cog_score INTEGER DEFAULT 0,
        se_score INTEGER DEFAULT 0,
        autism_score INTEGER DEFAULT 0,
        adhd_score INTEGER DEFAULT 0,
        domain_breakdown JSONB NOT NULL DEFAULT '{}'::JSONB,
        facility_type VARCHAR(50) NOT NULL,
        urgency VARCHAR(20) NOT NULL,
        deadline DATE NOT NULL,
        status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
            CHECK (status IN ('PENDING', 'IN_PROGRESS', 'COMPLETED', 'ESCALATED')),
        escalation_level INTEGER NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

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

    CREATE TABLE IF NOT EXISTS escalation_logs (
        id BIGSERIAL PRIMARY KEY,
        referral_id BIGINT NOT NULL REFERENCES referrals(id) ON DELETE CASCADE,
        previous_level INTEGER NOT NULL,
        new_level INTEGER NOT NULL,
        reason TEXT NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

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

    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS activity_id VARCHAR(50);
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS child_id TEXT;
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS title VARCHAR(200);
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS description TEXT;
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS due_date DATE;
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS frequency VARCHAR(20);
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS target_role VARCHAR(20);
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS instructions_english TEXT;
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS instructions_telugu TEXT;
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS materials_needed TEXT;
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS time_required_minutes INTEGER;
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS visual_aid_url TEXT;
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'PENDING';
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP;
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS target_completions INTEGER DEFAULT 1;
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS current_completions INTEGER DEFAULT 0;
    ALTER TABLE follow_up_activities ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

    UPDATE follow_up_activities
    SET title = COALESCE(title, activity_title),
        description = COALESCE(description, activity_description),
        target_role = COALESCE(target_role, target_user),
        updated_at = COALESCE(updated_at, CURRENT_TIMESTAMP)
    WHERE title IS NULL OR description IS NULL OR target_role IS NULL OR updated_at IS NULL;

    UPDATE follow_up_activities
    SET activity_id = COALESCE(activity_id, 'ACT-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || id::text)
    WHERE activity_id IS NULL;
    """
    with get_conn(_db_url()) as conn:
        conn.executescript(ddl)


def _map_facility(risk_level: str) -> tuple[str, str, date]:
    normalized = (risk_level or "").strip().upper()
    today = date.today()
    if normalized == "CRITICAL":
        return "DISTRICT_SPECIALIST", "IMMEDIATE", today + timedelta(days=3)
    if normalized == "HIGH":
        return "DISTRICT_HOSPITAL", "PRIORITY", today + timedelta(days=7)
    if normalized == "MEDIUM":
        return "PHC", "ROUTINE", today + timedelta(days=10)
    return "PHC", "ROUTINE", today + timedelta(days=14)


def _get_library_rows(domain: str, target_role: str, risk_level: str) -> List[Dict[str, Any]]:
    with get_conn(_db_url()) as conn:
        rows = conn.execute(
            """
            SELECT id, title, description, instructions_english, instructions_telugu,
                   domain, target_role, frequency, materials_needed,
                   time_required_minutes, visual_aid_url, target_completions
            FROM activity_library
            WHERE domain = %s
              AND (target_role = %s OR target_role = 'BOTH')
              AND (risk_bucket = 'ALL' OR risk_bucket = %s)
            ORDER BY id
            LIMIT 4
            """,
            (domain, target_role, risk_level),
        ).fetchall()
    return [dict(r) for r in rows]


def _generate_activities(referral_row: Dict[str, Any], risk_data: RiskDataSchema) -> int:
    risk_level = (risk_data.overall_risk_level or "").strip().upper()
    delayed_domains: List[str] = []
    if risk_data.gm_score < 50:
        delayed_domains.append("GM")
    if risk_data.fm_score < 50:
        delayed_domains.append("FM")
    if risk_data.lc_score < 50:
        delayed_domains.append("LC")
    if risk_data.cog_score < 50:
        delayed_domains.append("COG")
    if risk_data.se_score < 50:
        delayed_domains.append("SE")

    today = date.today()
    assignments: List[Dict[str, Any]] = []

    for domain in delayed_domains:
        for row in _get_library_rows(domain, "CAREGIVER", risk_level)[:3]:
            assignments.append(
                {
                    "title": row["title"],
                    "description": row.get("description"),
                    "instructions_english": row.get("instructions_english"),
                    "instructions_telugu": row.get("instructions_telugu"),
                    "domain": domain,
                    "target_role": "CAREGIVER",
                    "frequency": row.get("frequency") or "DAILY",
                    "due_date": today + timedelta(days=7),
                    "materials_needed": row.get("materials_needed"),
                    "time_required_minutes": row.get("time_required_minutes"),
                    "visual_aid_url": row.get("visual_aid_url"),
                    "target_completions": max(
                        1,
                        int(
                            row.get("target_completions")
                            or (7 if (row.get("frequency") or "DAILY") == "DAILY" else 2)
                        ),
                    ),
                }
            )

    for domain in ["GM", "FM", "LC", "COG", "SE"]:
        aww_rows = _get_library_rows(domain, "AWW", risk_level)
        if not aww_rows:
            continue
        row = aww_rows[0]
        assignments.append(
            {
                "title": row["title"],
                "description": row.get("description"),
                "instructions_english": row.get("instructions_english"),
                "instructions_telugu": row.get("instructions_telugu"),
                "domain": domain,
                "target_role": "AWW",
                "frequency": "WEEKLY",
                "due_date": today + timedelta(days=7),
                "materials_needed": row.get("materials_needed"),
                "time_required_minutes": row.get("time_required_minutes"),
                "visual_aid_url": row.get("visual_aid_url"),
                "target_completions": 2,
            }
        )

    if risk_data.autism_score >= 50 or risk_data.adhd_score >= 50:
        for row in _get_library_rows("NEURO", "CAREGIVER", "HIGH")[:3]:
            assignments.append(
                {
                    "title": row["title"],
                    "description": row.get("description"),
                    "instructions_english": row.get("instructions_english"),
                    "instructions_telugu": row.get("instructions_telugu"),
                    "domain": "NEURO",
                    "target_role": "CAREGIVER",
                    "frequency": row.get("frequency") or "WEEKLY",
                    "due_date": today + timedelta(days=7),
                    "materials_needed": row.get("materials_needed"),
                    "time_required_minutes": row.get("time_required_minutes"),
                    "visual_aid_url": row.get("visual_aid_url"),
                    "target_completions": max(1, int(row.get("target_completions") or 2)),
                }
            )

    if not assignments:
        assignments.append(
            {
                "title": "Daily Guided Stimulation",
                "description": "Practice age-appropriate play, speech, and social interaction daily.",
                "instructions_english": "Do 20 minutes of guided play and language interaction daily.",
                "instructions_telugu": "ప్రతిరోజూ 20 నిమిషాలు మార్గదర్శక ఆట మరియు మాటల చర్యలు చేయండి.",
                "domain": "GENERAL",
                "target_role": "CAREGIVER",
                "frequency": "DAILY",
                "due_date": today + timedelta(days=7),
                "materials_needed": "Household objects",
                "time_required_minutes": 20,
                "visual_aid_url": "/visuals/daily_guided.jpg",
                "target_completions": 7,
            }
        )

    with get_conn(_db_url()) as conn:
        for item in assignments:
            conn.execute(
                """
                INSERT INTO follow_up_activities (
                    referral_id, child_id, title, description,
                    instructions_english, instructions_telugu, domain,
                    target_role, frequency, due_date, materials_needed,
                    time_required_minutes, visual_aid_url, target_completions
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    str(referral_row["id"]),
                    str(referral_row["child_id"]),
                    item["title"],
                    item.get("description"),
                    item.get("instructions_english"),
                    item.get("instructions_telugu"),
                    item.get("domain"),
                    item.get("target_role"),
                    item.get("frequency"),
                    item.get("due_date"),
                    item.get("materials_needed"),
                    item.get("time_required_minutes"),
                    item.get("visual_aid_url"),
                    item.get("target_completions"),
                ),
            )
    return len(assignments)


def _serialize_referral(row: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": int(row["id"]),
        "referral_id": row["referral_id"],
        "child_id": row["child_id"],
        "overall_risk_level": row["overall_risk_level"],
        "facility_type": row["facility_type"],
        "urgency": row["urgency"],
        "deadline": row["deadline"].isoformat() if row.get("deadline") else None,
        "status": row["status"],
        "escalation_level": int(row.get("escalation_level") or 0),
    }


@router.post("/referrals")
def create_referral(risk_data: RiskDataSchema):
    _ensure_problem_b_tables()
    level = (risk_data.overall_risk_level or "").strip().upper()
    if level not in {"LOW", "MEDIUM", "HIGH", "CRITICAL"}:
        raise HTTPException(status_code=400, detail="overall_risk_level must be LOW/MEDIUM/HIGH/CRITICAL")

    facility_type, urgency, deadline = _map_facility(level)
    with get_conn(_db_url()) as conn:
        row = conn.execute(
            """
            INSERT INTO referrals (
                child_id, overall_risk_score, overall_risk_level, num_delays,
                gm_score, fm_score, lc_score, cog_score, se_score, autism_score, adhd_score,
                domain_breakdown, facility_type, urgency, deadline
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s::jsonb, %s, %s, %s)
            RETURNING id, referral_id, child_id, overall_risk_level, facility_type, urgency, deadline, status, escalation_level
            """,
            (
                str(risk_data.child_id),
                int(risk_data.overall_risk_score),
                level,
                int(risk_data.num_delays),
                int(risk_data.gm_score),
                int(risk_data.fm_score),
                int(risk_data.lc_score),
                int(risk_data.cog_score),
                int(risk_data.se_score),
                int(risk_data.autism_score),
                int(risk_data.adhd_score),
                json.dumps(risk_data.domain_breakdown or {}),
                facility_type,
                urgency,
                deadline,
            ),
        ).fetchone()

    if row is None:
        raise HTTPException(status_code=500, detail="Unable to create referral")

    referral = dict(row)
    generated = _generate_activities(referral, risk_data)
    payload = _serialize_referral(referral)
    payload["generated_activities"] = generated
    return payload


@router.get("/referrals/{referral_id}")
def get_referral(referral_id: int):
    _ensure_problem_b_tables()
    with get_conn(_db_url()) as conn:
        row = conn.execute(
            """
            SELECT id, referral_id, child_id, overall_risk_level, facility_type, urgency,
                   deadline, status, escalation_level
            FROM referrals
            WHERE id = %s
            """,
            (referral_id,),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Referral not found")
    return _serialize_referral(dict(row))


@router.get("/referrals/{referral_id}/activities")
def get_referral_activities(referral_id: int, target_role: Optional[str] = None):
    _ensure_problem_b_tables()
    where_sql = "WHERE referral_id = %s"
    params: List[Any] = [str(referral_id)]
    if target_role:
        normalized_role = target_role.strip().upper()
        if normalized_role not in {"CAREGIVER", "AWW", "BOTH"}:
            raise HTTPException(status_code=400, detail="target_role must be CAREGIVER/AWW/BOTH")
        where_sql += " AND target_role = %s"
        params.append(normalized_role)

    with get_conn(_db_url()) as conn:
        rows = conn.execute(
            f"""
            SELECT id, activity_id, title, description, instructions_english, instructions_telugu,
                   domain, target_role, frequency, due_date, status,
                   current_completions, target_completions
            FROM follow_up_activities
            {where_sql}
            ORDER BY due_date, id
            """,
            tuple(params),
        ).fetchall()

    response = []
    for row in rows:
        current = int(row.get("current_completions") or 0)
        target = int(row.get("target_completions") or 0)
        progress = int((current / target) * 100) if target > 0 else 0
        response.append(
            {
                "id": int(row["id"]),
                "activity_id": row["activity_id"],
                "title": row["title"],
                "description": row.get("description"),
                "instructions_english": row.get("instructions_english"),
                "instructions_telugu": row.get("instructions_telugu"),
                "domain": row.get("domain") or "GENERAL",
                "target_role": row["target_role"],
                "frequency": row.get("frequency") or "DAILY",
                "due_date": row["due_date"].isoformat() if row.get("due_date") else None,
                "status": row["status"],
                "progress": max(0, min(100, progress)),
            }
        )
    return response


@router.post("/activities/{activity_id}/complete")
def complete_activity(activity_id: int, payload: ActivityCompleteRequest):
    _ensure_problem_b_tables()
    with get_conn(_db_url()) as conn:
        activity = conn.execute(
            """
            SELECT id, referral_id, child_id, current_completions, target_completions, status
            FROM follow_up_activities
            WHERE id = %s
            """,
            (activity_id,),
        ).fetchone()
        if activity is None:
            raise HTTPException(status_code=404, detail="Activity not found")

        # Timeline-generated rows may have NULL child_id in legacy data.
        # Resolve from referrals and persist so logging never fails.
        child_id = activity.get("child_id")
        if child_id is None:
            referral_row = conn.execute(
                """
                SELECT child_id
                FROM referrals
                WHERE id = %s
                """,
                (str(activity.get("referral_id")),),
            ).fetchone()
            child_id = referral_row.get("child_id") if referral_row else None
            if child_id is not None:
                conn.execute(
                    """
                    UPDATE follow_up_activities
                    SET child_id = %s,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = %s
                    """,
                    (str(child_id), activity_id),
                )
        if child_id is None:
            raise HTTPException(status_code=500, detail="Activity missing child mapping")

        difficulty = payload.difficulty
        if difficulty is not None and (difficulty < 1 or difficulty > 5):
            raise HTTPException(status_code=400, detail="difficulty must be between 1 and 5")

        conn.execute(
            """
            INSERT INTO activity_log (
                activity_id, child_id, log_date, completed, completed_at,
                caregiver_notes, difficulty_rating, reported_by
            ) VALUES (%s, %s, CURRENT_DATE, TRUE, CURRENT_TIMESTAMP, %s, %s, %s)
            ON CONFLICT (activity_id, log_date)
            DO UPDATE SET
                completed = EXCLUDED.completed,
                completed_at = EXCLUDED.completed_at,
                caregiver_notes = EXCLUDED.caregiver_notes,
                difficulty_rating = EXCLUDED.difficulty_rating,
                reported_by = EXCLUDED.reported_by
            """,
            (
                activity_id,
                str(child_id),
                payload.notes,
                difficulty,
                (payload.reported_by or "CAREGIVER").strip().upper(),
            ),
        )

        updated = conn.execute(
            """
            UPDATE follow_up_activities
            SET current_completions = current_completions + 1,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
            RETURNING id, current_completions, target_completions
            """,
            (activity_id,),
        ).fetchone()
        if updated is None:
            raise HTTPException(status_code=500, detail="Activity update failed")

        current = int(updated["current_completions"] or 0)
        target = int(updated["target_completions"] or 0)
        if target > 0 and current >= target:
            conn.execute(
                """
                UPDATE follow_up_activities
                SET status = 'COMPLETED',
                    completed_at = CURRENT_TIMESTAMP,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                """,
                (activity_id,),
            )

    return {
        "status": "success",
        "message": "Activity completed",
        "progress": current,
    }


@router.get("/referrals/{referral_id}/progress")
def get_referral_progress(referral_id: int):
    _ensure_problem_b_tables()
    with get_conn(_db_url()) as conn:
        rows = conn.execute(
            """
            SELECT target_role, status
            FROM follow_up_activities
            WHERE referral_id = %s
            """,
            (str(referral_id),),
        ).fetchall()
    total = len(rows)
    if total == 0:
        return {
            "total": 0,
            "completed": 0,
            "percentage": 0,
            "activities_by_role": {"CAREGIVER": 0, "AWW": 0},
        }
    completed = sum(1 for row in rows if (row.get("status") or "").upper() == "COMPLETED")
    caregiver_done = sum(
        1
        for row in rows
        if (row.get("target_role") or "").upper() == "CAREGIVER" and (row.get("status") or "").upper() == "COMPLETED"
    )
    aww_done = sum(
        1
        for row in rows
        if (row.get("target_role") or "").upper() == "AWW" and (row.get("status") or "").upper() == "COMPLETED"
    )
    return {
        "total": total,
        "completed": completed,
        "percentage": int((completed / total) * 100),
        "activities_by_role": {"CAREGIVER": caregiver_done, "AWW": aww_done},
    }


@router.post("/escalation/check")
def run_escalation_check():
    _ensure_problem_b_tables()
    with get_conn(_db_url()) as conn:
        rows = conn.execute(
            """
            WITH escalated AS (
                UPDATE referrals
                SET escalation_level = escalation_level + 1,
                    status = 'ESCALATED',
                    updated_at = CURRENT_TIMESTAMP
                WHERE deadline < CURRENT_DATE
                  AND status NOT IN ('COMPLETED', 'ESCALATED')
                RETURNING id, escalation_level - 1 AS previous_level, escalation_level AS new_level
            )
            INSERT INTO escalation_logs (referral_id, previous_level, new_level, reason)
            SELECT id, previous_level, new_level, 'Deadline missed'
            FROM escalated
            RETURNING referral_id, previous_level, new_level
            """
        ).fetchall()
    return {
        "escalated": len(rows),
        "details": [dict(r) for r in rows],
    }


@router.get("/health")
def health_check():
    try:
        _ensure_problem_b_tables()
        with get_conn(_db_url()) as conn:
            conn.execute("SELECT 1")
        return {
            "status": "healthy",
            "database": "connected",
            "timestamp": datetime.utcnow().isoformat(),
        }
    except Exception as exc:
        return {
            "status": "unhealthy",
            "database": "disconnected",
            "error": str(exc),
        }
