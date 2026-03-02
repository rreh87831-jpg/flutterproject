from __future__ import annotations

import json
import os
import re
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from .pg_compat import get_conn

DEFAULT_ECD_DATABASE_URL = "postgresql://postgres:postgres@127.0.0.1:5432/ecd_data"

router = APIRouter(prefix="/api/improvement", tags=["problem-b-improvement"])


class CalculateRequest(BaseModel):
    referral_id: Optional[int] = None
    awc_code: Optional[str] = None


class MilestoneCreate(BaseModel):
    milestone_id: str
    milestone_name: str
    domain: str
    notes: Optional[str] = None


def _db_url() -> str:
    return os.getenv(
        "ECD_DATABASE_URL",
        os.getenv("DATABASE_URL", DEFAULT_ECD_DATABASE_URL),
    )


def _ensure_tables() -> None:
    ddl = """
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
    """
    with get_conn(_db_url()) as conn:
        conn.executescript(ddl)


def _risk_level_from_score(score: int) -> str:
    if score >= 75:
        return "LOW"
    if score >= 50:
        return "MEDIUM"
    if score >= 25:
        return "HIGH"
    return "CRITICAL"


def _risk_level_rank(level: str) -> int:
    order = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3}
    return order.get((level or "").upper(), 0)


def _apply_completion_boost(
    raw_risk_level: str,
    current_overall: int,
    completion_rate: float,
    overall_improvement: int,
) -> str:
    """
    Product rule:
    - If all assigned activities are completed and improvement is positive,
      do not keep the child stuck at severe risk solely due threshold gaps.
    - Promote to at least MEDIUM, and to LOW for strong improvement.
    """
    level = (raw_risk_level or "CRITICAL").upper()
    if completion_rate >= 100.0 and overall_improvement > 0:
        target = "LOW" if (current_overall >= 30 and overall_improvement >= 10) else "MEDIUM"
        if _risk_level_rank(target) > _risk_level_rank(level):
            return target
    return level


def _core_overall_score(
    gm_score: int,
    fm_score: int,
    lc_score: int,
    cog_score: int,
    se_score: int,
) -> int:
    return int((int(gm_score) + int(fm_score) + int(lc_score) + int(cog_score) + int(se_score)) / 5)


def _calculate_current_score(baseline_score: int, activities: List[Dict[str, Any]], domain: str) -> int:
    domain_acts = [a for a in activities if (a.get("domain") or "").upper() == domain.upper()]
    if not domain_acts:
        return baseline_score
    completed = sum(1 for a in domain_acts if (a.get("status") or "").upper() == "COMPLETED")
    total = len(domain_acts)
    if total == 0:
        return baseline_score
    improvement = min(30, int((completed / total) * 30))
    return max(0, min(100, int(baseline_score) + improvement))


def _calculate_neuro_score(baseline_score: int, activities: List[Dict[str, Any]], keyword: str) -> int:
    if baseline_score <= 0:
        return 0
    neuro_acts = [
        a
        for a in activities
        if (a.get("domain") or "").upper() == "NEURO"
        and keyword.lower() in (a.get("title") or "").lower()
    ]
    if not neuro_acts:
        return baseline_score
    completed = sum(1 for a in neuro_acts if (a.get("status") or "").upper() == "COMPLETED")
    total = len(neuro_acts)
    if total == 0:
        return baseline_score
    reduction = min(30, int((completed / total) * 30))
    return max(0, int(baseline_score) - reduction)


def _recommendations(improvements: Dict[str, int], followup: Dict[str, Any]) -> List[Dict[str, str]]:
    rec: List[Dict[str, str]] = []
    overall = int(improvements.get("overall", 0))
    if overall >= 20:
        rec.append(
            {
                "type": "success",
                "title": "Excellent Progress",
                "description": "Child has shown strong improvement. Continue maintenance activities.",
            }
        )
    elif overall >= 10:
        rec.append(
            {
                "type": "good",
                "title": "Good Progress",
                "description": "Improvement is steady. Continue the current plan.",
            }
        )
    elif overall >= 5:
        rec.append(
            {
                "type": "moderate",
                "title": "Moderate Progress",
                "description": "Increase completion consistency for better gains.",
            }
        )
    else:
        rec.append(
            {
                "type": "attention",
                "title": "Needs Attention",
                "description": "Limited improvement. Consider specialist review and tighter follow-up.",
            }
        )

    if int(improvements.get("gm", 0)) < 5 and int(followup.get("gm_score", 0)) < 50:
        rec.append(
            {
                "type": "domain",
                "title": "Gross Motor Focus",
                "description": "Increase GM activities and coaching frequency.",
            }
        )
    if int(improvements.get("lc", 0)) < 5 and int(followup.get("lc_score", 0)) < 50:
        rec.append(
            {
                "type": "domain",
                "title": "Language Focus",
                "description": "Increase language stimulation and reading sessions.",
            }
        )
    rec.append(
        {
            "type": "next",
            "title": "Next Assessment",
            "description": "Schedule reassessment in ~3 months.",
        }
    )
    return rec


_AWC_DEMO_PATTERN = re.compile(r"^(AWW|AWS)_DEMO_(\d{3,4})$")
_AWC_DEMO_REVERSED_PATTERN = re.compile(r"^DEMO_(AWW|AWS)_(\d{3,4})$")


def _normalize_awc_code(value: Optional[str]) -> str:
    raw = (value or "").strip().upper()
    if not raw:
        return ""
    m = _AWC_DEMO_PATTERN.fullmatch(raw)
    if not m:
        rm = _AWC_DEMO_REVERSED_PATTERN.fullmatch(raw)
        if rm:
            m = rm
    if not m:
        return raw
    return f"AWW_DEMO_{m.group(2)}"


def _improvement_view_table_name(awc_code: str) -> str:
    sanitized = re.sub(r"[^a-z0-9]+", "_", awc_code.lower()).strip("_")
    if not sanitized:
        sanitized = "unknown"
    return f"improvement_view_{sanitized}"


def _resolve_child_awc_code(conn, child_id: str) -> Optional[str]:
    lookups = [
        """
        SELECT awc_code AS code
        FROM child_profile
        WHERE child_id = %s AND COALESCE(BTRIM(awc_code), '') <> ''
        ORDER BY awc_code
        LIMIT 1
        """,
        """
        SELECT awc_code AS code
        FROM child_profile_by_anganwadi
        WHERE child_id = %s AND COALESCE(BTRIM(awc_code), '') <> ''
        ORDER BY awc_code
        LIMIT 1
        """,
        """
        SELECT aww_id AS code
        FROM referral_action
        WHERE child_id = %s AND COALESCE(BTRIM(aww_id), '') <> ''
        ORDER BY referral_date DESC, referral_id DESC
        LIMIT 1
        """,
    ]
    for q in lookups:
        try:
            row = conn.execute(q, (child_id,)).fetchone()
        except Exception:
            continue
        if row is None:
            continue
        awc_code = _normalize_awc_code(str(row.get("code") or ""))
        if awc_code:
            return awc_code
    return None


def _sync_awc_improvement_view(
    conn,
    child_id: str,
    referral_id: int,
    improvement_status: int,
    completion_rate: float,
    awc_code: Optional[str] = None,
) -> Optional[str]:
    normalized_awc = _normalize_awc_code(awc_code)
    if not normalized_awc:
        normalized_awc = _resolve_child_awc_code(conn, child_id)
    if not normalized_awc:
        return None

    table_name = _improvement_view_table_name(normalized_awc)
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
            child_id TEXT PRIMARY KEY,
            referral_id BIGINT,
            awc_code TEXT NOT NULL,
            aww_code TEXT NOT NULL,
            improvement_status INTEGER DEFAULT 0,
            completion DECIMAL(5,2) DEFAULT 0,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    conn.execute(f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS awc_code TEXT")
    conn.execute(f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS aww_code TEXT")
    conn.execute(
        f"""
        UPDATE {table_name}
        SET
            aww_code = COALESCE(NULLIF(aww_code, ''), NULLIF(awc_code, ''), %s),
            awc_code = COALESCE(NULLIF(awc_code, ''), NULLIF(aww_code, ''), %s)
        WHERE COALESCE(aww_code, '') = '' OR COALESCE(awc_code, '') = ''
        """,
        (normalized_awc, normalized_awc),
    )
    conn.execute(
        """
        INSERT INTO improvement_view_registry (awc_code, table_name, updated_at)
        VALUES (%s, %s, CURRENT_TIMESTAMP)
        ON CONFLICT (awc_code)
        DO UPDATE SET table_name = EXCLUDED.table_name, updated_at = CURRENT_TIMESTAMP
        """,
        (normalized_awc, table_name),
    )
    conn.execute(
        f"""
        INSERT INTO {table_name} (
            child_id, referral_id, awc_code, aww_code, improvement_status, completion, updated_at
        )
        VALUES (%s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
        ON CONFLICT (child_id)
        DO UPDATE SET
            referral_id = EXCLUDED.referral_id,
            awc_code = EXCLUDED.awc_code,
            aww_code = EXCLUDED.aww_code,
            improvement_status = EXCLUDED.improvement_status,
            completion = EXCLUDED.completion,
            updated_at = CURRENT_TIMESTAMP
        """,
        (
            child_id,
            referral_id,
            normalized_awc,
            normalized_awc,
            int(improvement_status),
            round(float(completion_rate), 2),
        ),
    )
    return table_name


def _latest_referral(child_id: str, referral_id: Optional[int]) -> Optional[Dict[str, Any]]:
    with get_conn(_db_url()) as conn:
        if referral_id is not None:
            row = conn.execute(
                "SELECT * FROM referrals WHERE id = %s",
                (referral_id,),
            ).fetchone()
            return dict(row) if row else None
        row = conn.execute(
            """
            SELECT * FROM referrals
            WHERE child_id = %s
            ORDER BY created_at DESC, id DESC
            LIMIT 1
            """,
            (child_id,),
        ).fetchone()
        return dict(row) if row else None


@router.post("/calculate/{child_id}")
def calculate_improvement(child_id: str, payload: CalculateRequest):
    _ensure_tables()
    referral = _latest_referral(child_id, payload.referral_id)
    if referral is None:
        raise HTTPException(status_code=404, detail="No referral found")
    referral_id = int(referral["id"])
    improvement_view_table: Optional[str] = None

    with get_conn(_db_url()) as conn:
        baseline = conn.execute(
            """
            SELECT * FROM improvement_snapshots
            WHERE referral_id = %s AND snapshot_type = 'BASELINE'
            """,
            (referral_id,),
        ).fetchone()

        if baseline is None:
            baseline_gm = int(referral.get("gm_score") or 0)
            baseline_fm = int(referral.get("fm_score") or 0)
            baseline_lc = int(referral.get("lc_score") or 0)
            baseline_cog = int(referral.get("cog_score") or 0)
            baseline_se = int(referral.get("se_score") or 0)
            baseline_overall = _core_overall_score(
                baseline_gm,
                baseline_fm,
                baseline_lc,
                baseline_cog,
                baseline_se,
            )
            baseline_risk = _risk_level_from_score(baseline_overall)

            baseline = conn.execute(
                """
                INSERT INTO improvement_snapshots (
                    child_id, referral_id, snapshot_type, overall_score, overall_risk_level,
                    gm_score, fm_score, lc_score, cog_score, se_score, autism_score, adhd_score,
                    domain_breakdown, activities_completed, total_activities
                )
                VALUES (%s, %s, 'BASELINE', %s, %s, %s, %s, %s, %s, %s, %s, %s, %s::jsonb, 0, 0)
                RETURNING *
                """,
                (
                    child_id,
                    referral_id,
                    baseline_overall,
                    baseline_risk,
                    baseline_gm,
                    baseline_fm,
                    baseline_lc,
                    baseline_cog,
                    baseline_se,
                    int(referral.get("autism_score") or 0),
                    int(referral.get("adhd_score") or 0),
                    json.dumps(referral.get("domain_breakdown") or {}),
                ),
            ).fetchone()

        activities = conn.execute(
            """
            SELECT id, title, domain, status
            FROM follow_up_activities
            WHERE referral_id = %s
            """,
            (str(referral_id),),
        ).fetchall()
        activity_rows = [dict(r) for r in activities]
        total_activities = len(activity_rows)
        completed_activities = sum(1 for a in activity_rows if (a.get("status") or "").upper() == "COMPLETED")
        domain_activity_counts = {
            "GM": sum(1 for a in activity_rows if (a.get("domain") or "").upper() == "GM"),
            "FM": sum(1 for a in activity_rows if (a.get("domain") or "").upper() == "FM"),
            "LC": sum(1 for a in activity_rows if (a.get("domain") or "").upper() == "LC"),
            "COG": sum(1 for a in activity_rows if (a.get("domain") or "").upper() == "COG"),
            "SE": sum(1 for a in activity_rows if (a.get("domain") or "").upper() == "SE"),
        }

        b = dict(baseline)
        baseline_domain_scores = {
            "GM": int(b.get("gm_score") or 0),
            "FM": int(b.get("fm_score") or 0),
            "LC": int(b.get("lc_score") or 0),
            "COG": int(b.get("cog_score") or 0),
            "SE": int(b.get("se_score") or 0),
        }

        current_gm = _calculate_current_score(int(b.get("gm_score") or 0), activity_rows, "GM")
        current_fm = _calculate_current_score(int(b.get("fm_score") or 0), activity_rows, "FM")
        current_lc = _calculate_current_score(int(b.get("lc_score") or 0), activity_rows, "LC")
        current_cog = _calculate_current_score(int(b.get("cog_score") or 0), activity_rows, "COG")
        current_se = _calculate_current_score(int(b.get("se_score") or 0), activity_rows, "SE")
        current_autism = _calculate_neuro_score(int(b.get("autism_score") or 0), activity_rows, "autism")
        current_adhd = _calculate_neuro_score(int(b.get("adhd_score") or 0), activity_rows, "adhd")
        current_domain_scores = {
            "GM": current_gm,
            "FM": current_fm,
            "LC": current_lc,
            "COG": current_cog,
            "SE": current_se,
        }

        active_domains = [
            d
            for d in ["GM", "FM", "LC", "COG", "SE"]
            if baseline_domain_scores[d] > 0 or domain_activity_counts[d] > 0
        ]
        if not active_domains:
            active_domains = ["GM", "FM", "LC", "COG", "SE"]

        baseline_overall = int(
            sum(baseline_domain_scores[d] for d in active_domains) / len(active_domains)
        )
        if baseline_overall <= 0 and total_activities > 0:
            fallback_by_risk = {
                "CRITICAL": 20,
                "HIGH": 40,
                "MEDIUM": 60,
                "LOW": 80,
            }
            baseline_seed_level = str(b.get("overall_risk_level") or "CRITICAL").upper()
            baseline_overall = fallback_by_risk.get(
                baseline_seed_level,
                20,
            )

        current_overall = int(
            sum(current_domain_scores[d] for d in active_domains) / len(active_domains)
        )
        current_risk = _risk_level_from_score(current_overall)
        b["overall_score"] = baseline_overall
        b["overall_risk_level"] = _risk_level_from_score(baseline_overall)

        followup = conn.execute(
            """
            INSERT INTO improvement_snapshots (
                child_id, referral_id, snapshot_type, overall_score, overall_risk_level,
                gm_score, fm_score, lc_score, cog_score, se_score, autism_score, adhd_score,
                domain_breakdown, activities_completed, total_activities
            )
            VALUES (%s, %s, 'FOLLOWUP', %s, %s, %s, %s, %s, %s, %s, %s, %s, %s::jsonb, %s, %s)
            ON CONFLICT (referral_id, snapshot_type)
            DO UPDATE SET
                overall_score = EXCLUDED.overall_score,
                overall_risk_level = EXCLUDED.overall_risk_level,
                gm_score = EXCLUDED.gm_score,
                fm_score = EXCLUDED.fm_score,
                lc_score = EXCLUDED.lc_score,
                cog_score = EXCLUDED.cog_score,
                se_score = EXCLUDED.se_score,
                autism_score = EXCLUDED.autism_score,
                adhd_score = EXCLUDED.adhd_score,
                domain_breakdown = EXCLUDED.domain_breakdown,
                activities_completed = EXCLUDED.activities_completed,
                total_activities = EXCLUDED.total_activities,
                created_at = CURRENT_TIMESTAMP
            RETURNING *
            """,
            (
                child_id,
                referral_id,
                current_overall,
                current_risk,
                current_gm,
                current_fm,
                current_lc,
                current_cog,
                current_se,
                current_autism,
                current_adhd,
                json.dumps(
                    {
                        "gm": current_gm,
                        "fm": current_fm,
                        "lc": current_lc,
                        "cog": current_cog,
                        "se": current_se,
                        "autism": current_autism,
                        "adhd": current_adhd,
                    }
                ),
                completed_activities,
                total_activities,
            ),
        ).fetchone()

        start_date = referral.get("created_at").date() if referral.get("created_at") else date.today()
        milestones = conn.execute(
            """
            SELECT id, milestone_id, milestone_name, domain, achieved_date
            FROM milestone_tracking
            WHERE child_id = %s AND achieved_date >= %s
            ORDER BY achieved_date DESC
            """,
            (child_id, start_date),
        ).fetchall()
        milestone_rows = [
            {
                "id": int(m["id"]),
                "milestone_id": m["milestone_id"],
                "name": m["milestone_name"],
                "domain": m["domain"],
                "date": m["achieved_date"].isoformat() if m.get("achieved_date") else None,
            }
            for m in milestones
        ]

        improvements = {
            "overall": int((followup.get("overall_score") or 0) - baseline_overall),
            "gm": int(current_gm - (b.get("gm_score") or 0)),
            "fm": int(current_fm - (b.get("fm_score") or 0)),
            "lc": int(current_lc - (b.get("lc_score") or 0)),
            "cog": int(current_cog - (b.get("cog_score") or 0)),
            "se": int(current_se - (b.get("se_score") or 0)),
            "autism": int((b.get("autism_score") or 0) - current_autism),
            "adhd": int((b.get("adhd_score") or 0) - current_adhd),
        }
        overall_pct = 0.0
        if baseline_overall > 0:
            overall_pct = (improvements["overall"] / baseline_overall) * 100
        completion_rate = (completed_activities / total_activities * 100) if total_activities else 0.0
        boosted_risk = _apply_completion_boost(
            raw_risk_level=str(followup.get("overall_risk_level") or current_risk),
            current_overall=current_overall,
            completion_rate=completion_rate,
            overall_improvement=improvements["overall"],
        )

        if boosted_risk != str(followup.get("overall_risk_level") or ""):
            followup = conn.execute(
                """
                UPDATE improvement_snapshots
                SET overall_risk_level = %s
                WHERE id = %s
                RETURNING *
                """,
                (boosted_risk, int(followup["id"])),
            ).fetchone()

        # Sync latest computed status back to referral so Follow-Up badge reflects improvements.
        conn.execute(
            """
            UPDATE referrals
            SET overall_risk_score = %s,
                overall_risk_level = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
            """,
            (
                int(followup.get("overall_score") or current_overall),
                str(followup.get("overall_risk_level") or boosted_risk),
                referral_id,
            ),
        )

        recs = _recommendations(improvements, dict(followup))

        # Keep only the latest history entry per child/referral.
        conn.execute(
            """
            DELETE FROM improvement_summary
            WHERE child_id = %s AND referral_id = %s
            """,
            (child_id, referral_id),
        )

        summary = conn.execute(
            """
            INSERT INTO improvement_summary (
                child_id, referral_id, start_date, end_date, total_days,
                overall_improvement, overall_improvement_percentage, risk_level_change,
                gm_improvement, fm_improvement, lc_improvement, cog_improvement, se_improvement,
                autism_improvement, adhd_improvement,
                activities_assigned, activities_completed, completion_rate,
                milestones_achieved_count, milestones_list, recommendations
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s::jsonb, %s::jsonb)
            RETURNING *
            """,
            (
                child_id,
                referral_id,
                start_date,
                date.today(),
                int((date.today() - start_date).days),
                improvements["overall"],
                round(overall_pct, 2),
                f"{b.get('overall_risk_level') or 'UNKNOWN'} -> {followup.get('overall_risk_level') or 'UNKNOWN'}",
                improvements["gm"],
                improvements["fm"],
                improvements["lc"],
                improvements["cog"],
                improvements["se"],
                improvements["autism"],
                improvements["adhd"],
                total_activities,
                completed_activities,
                round(completion_rate, 2),
                len(milestone_rows),
                json.dumps(milestone_rows),
                json.dumps(recs),
            ),
        ).fetchone()

        conn.execute(
            """
            INSERT INTO improvement_table (
                child_id, referral_id, improvement_status, completion, completition, improvement
            )
            VALUES (%s, %s, %s, %s, %s, %s)
            """,
            (
                child_id,
                referral_id,
                int(improvements["overall"]),
                round(completion_rate, 2),
                round(completion_rate, 2),
                int(improvements["overall"]),
            ),
        )
        improvement_view_table = _sync_awc_improvement_view(
            conn=conn,
            child_id=child_id,
            referral_id=referral_id,
            improvement_status=int(improvements["overall"]),
            completion_rate=round(completion_rate, 2),
            awc_code=payload.awc_code,
        )

    return {
        "status": "success",
        "data": {
            "summary_id": int(summary["id"]),
            "child_id": child_id,
            "child_name": None,
            "referral_id": referral_id,
            "improvement_view_table": improvement_view_table,
            "period_days": int(summary.get("total_days") or 0),
            "completion_rate": float(summary.get("completion_rate") or 0),
            "baseline": {
                "overall_score": int(b.get("overall_score") or 0),
                "risk_level": b.get("overall_risk_level"),
                "gm": int(b.get("gm_score") or 0),
                "fm": int(b.get("fm_score") or 0),
                "lc": int(b.get("lc_score") or 0),
                "cog": int(b.get("cog_score") or 0),
                "se": int(b.get("se_score") or 0),
                "autism": int(b.get("autism_score") or 0),
                "adhd": int(b.get("adhd_score") or 0),
                "date": b.get("created_at").isoformat() if b.get("created_at") else None,
            },
            "current": {
                "overall_score": int(followup.get("overall_score") or 0),
                "risk_level": followup.get("overall_risk_level"),
                "gm": int(followup.get("gm_score") or 0),
                "fm": int(followup.get("fm_score") or 0),
                "lc": int(followup.get("lc_score") or 0),
                "cog": int(followup.get("cog_score") or 0),
                "se": int(followup.get("se_score") or 0),
                "autism": int(followup.get("autism_score") or 0),
                "adhd": int(followup.get("adhd_score") or 0),
                "date": followup.get("created_at").isoformat() if followup.get("created_at") else None,
            },
            "improvements": {
                "overall": improvements["overall"],
                "overall_percentage": round(overall_pct, 2),
                "gm": improvements["gm"],
                "fm": improvements["fm"],
                "lc": improvements["lc"],
                "cog": improvements["cog"],
                "se": improvements["se"],
                "autism": improvements["autism"],
                "adhd": improvements["adhd"],
            },
            "milestones": milestone_rows,
            "recommendations": recs,
            "activities": {
                "assigned": total_activities,
                "completed": completed_activities,
                "rate": round(completion_rate, 2),
            },
            "risk_level_change": f"{b.get('overall_risk_level') or 'UNKNOWN'} -> {followup.get('overall_risk_level') or 'UNKNOWN'}",
        },
    }


@router.get("/summary/{child_id}")
def get_summary(child_id: str):
    _ensure_tables()
    with get_conn(_db_url()) as conn:
        summary = conn.execute(
            """
            SELECT * FROM improvement_summary
            WHERE child_id = %s
            ORDER BY created_at DESC
            LIMIT 1
            """,
            (child_id,),
        ).fetchone()
        if summary is None:
            raise HTTPException(status_code=404, detail="No improvement summary found")
        referral_id = int(summary["referral_id"])
        baseline = conn.execute(
            """
            SELECT * FROM improvement_snapshots
            WHERE referral_id = %s AND snapshot_type = 'BASELINE'
            """,
            (referral_id,),
        ).fetchone()
        followup = conn.execute(
            """
            SELECT * FROM improvement_snapshots
            WHERE referral_id = %s AND snapshot_type = 'FOLLOWUP'
            """,
            (referral_id,),
        ).fetchone()
    s = dict(summary)
    milestones = s.get("milestones_list") or []
    recs = s.get("recommendations") or []
    return {
        "summary_id": int(s["id"]),
        "child_id": child_id,
        "child_name": None,
        "referral_id": referral_id,
        "period_days": int(s.get("total_days") or 0),
        "completion_rate": float(s.get("completion_rate") or 0),
        "baseline": {
            "overall_score": int((baseline or {}).get("overall_score") or 0),
            "risk_level": (baseline or {}).get("overall_risk_level"),
            "gm": int((baseline or {}).get("gm_score") or 0),
            "fm": int((baseline or {}).get("fm_score") or 0),
            "lc": int((baseline or {}).get("lc_score") or 0),
            "cog": int((baseline or {}).get("cog_score") or 0),
            "se": int((baseline or {}).get("se_score") or 0),
            "autism": int((baseline or {}).get("autism_score") or 0),
            "adhd": int((baseline or {}).get("adhd_score") or 0),
            "date": (baseline or {}).get("created_at").isoformat() if (baseline or {}).get("created_at") else None,
        },
        "current": {
            "overall_score": int((followup or {}).get("overall_score") or 0),
            "risk_level": (followup or {}).get("overall_risk_level"),
            "gm": int((followup or {}).get("gm_score") or 0),
            "fm": int((followup or {}).get("fm_score") or 0),
            "lc": int((followup or {}).get("lc_score") or 0),
            "cog": int((followup or {}).get("cog_score") or 0),
            "se": int((followup or {}).get("se_score") or 0),
            "autism": int((followup or {}).get("autism_score") or 0),
            "adhd": int((followup or {}).get("adhd_score") or 0),
            "date": (followup or {}).get("created_at").isoformat() if (followup or {}).get("created_at") else None,
        },
        "improvements": {
            "overall": int(s.get("overall_improvement") or 0),
            "overall_percentage": float(s.get("overall_improvement_percentage") or 0),
            "gm": int(s.get("gm_improvement") or 0),
            "fm": int(s.get("fm_improvement") or 0),
            "lc": int(s.get("lc_improvement") or 0),
            "cog": int(s.get("cog_improvement") or 0),
            "se": int(s.get("se_improvement") or 0),
            "autism": int(s.get("autism_improvement") or 0),
            "adhd": int(s.get("adhd_improvement") or 0),
        },
        "milestones": milestones,
        "recommendations": recs,
        "activities": {
            "assigned": int(s.get("activities_assigned") or 0),
            "completed": int(s.get("activities_completed") or 0),
            "rate": float(s.get("completion_rate") or 0),
        },
        "risk_level_change": s.get("risk_level_change"),
    }


@router.get("/radar/{child_id}")
def get_radar(child_id: str):
    _ensure_tables()
    with get_conn(_db_url()) as conn:
        summary = conn.execute(
            """
            SELECT referral_id FROM improvement_summary
            WHERE child_id = %s
            ORDER BY created_at DESC
            LIMIT 1
            """,
            (child_id,),
        ).fetchone()
        if summary is None:
            raise HTTPException(status_code=404, detail="No improvement data found")
        referral_id = int(summary["referral_id"])
        baseline = conn.execute(
            """
            SELECT gm_score, fm_score, lc_score, cog_score, se_score
            FROM improvement_snapshots
            WHERE referral_id = %s AND snapshot_type = 'BASELINE'
            """,
            (referral_id,),
        ).fetchone()
        followup = conn.execute(
            """
            SELECT gm_score, fm_score, lc_score, cog_score, se_score
            FROM improvement_snapshots
            WHERE referral_id = %s AND snapshot_type = 'FOLLOWUP'
            """,
            (referral_id,),
        ).fetchone()
    if baseline is None or followup is None:
        raise HTTPException(status_code=404, detail="Snapshot data not found")
    return {
        "categories": ["Gross Motor", "Fine Motor", "Language", "Cognitive", "Social-Emotional"],
        "before": [
            float(baseline.get("gm_score") or 0),
            float(baseline.get("fm_score") or 0),
            float(baseline.get("lc_score") or 0),
            float(baseline.get("cog_score") or 0),
            float(baseline.get("se_score") or 0),
        ],
        "after": [
            float(followup.get("gm_score") or 0),
            float(followup.get("fm_score") or 0),
            float(followup.get("lc_score") or 0),
            float(followup.get("cog_score") or 0),
            float(followup.get("se_score") or 0),
        ],
    }


@router.post("/milestone/{child_id}")
def add_milestone(child_id: str, milestone: MilestoneCreate):
    _ensure_tables()
    with get_conn(_db_url()) as conn:
        row = conn.execute(
            """
            INSERT INTO milestone_tracking (
                child_id, milestone_id, milestone_name, domain, notes, achieved_date
            ) VALUES (%s, %s, %s, %s, %s, CURRENT_DATE)
            RETURNING *
            """,
            (
                child_id,
                milestone.milestone_id,
                milestone.milestone_name,
                milestone.domain,
                milestone.notes,
            ),
        ).fetchone()
    return {
        "status": "success",
        "milestone": {
            "id": int(row["id"]),
            "name": row["milestone_name"],
            "domain": row["domain"],
            "date": row["achieved_date"].isoformat() if row.get("achieved_date") else None,
        },
    }


@router.get("/milestones/{child_id}")
def get_milestones(child_id: str, days: int = 30):
    _ensure_tables()
    since = date.today() - timedelta(days=max(0, days))
    with get_conn(_db_url()) as conn:
        rows = conn.execute(
            """
            SELECT id, milestone_name, domain, achieved_date, notes
            FROM milestone_tracking
            WHERE child_id = %s AND achieved_date >= %s
            ORDER BY achieved_date DESC, id DESC
            """,
            (child_id, since),
        ).fetchall()
    return [
        {
            "id": int(r["id"]),
            "name": r["milestone_name"],
            "domain": r["domain"],
            "date": r["achieved_date"].isoformat() if r.get("achieved_date") else None,
            "notes": r.get("notes"),
        }
        for r in rows
    ]


@router.get("/history/{child_id}")
def get_history(child_id: str, limit: int = 5, awc_code: str = ""):
    _ensure_tables()
    safe_limit = max(1, min(int(limit or 5), 100))
    with get_conn(_db_url()) as conn:
        resolved_awc = _normalize_awc_code(awc_code) or _resolve_child_awc_code(conn, child_id)
        rows = []
        if resolved_awc:
            table_name = _improvement_view_table_name(resolved_awc)
            table_exists = conn.execute(
                "SELECT to_regclass(%s) AS rel",
                (table_name,),
            ).fetchone()
            if table_exists and table_exists.get("rel"):
                rows = conn.execute(
                    f"""
                    SELECT
                        updated_at AS created_at,
                        COALESCE(improvement_status, 0) AS overall_improvement,
                        COALESCE(completion, 0) AS completion_rate,
                        NULL::TEXT AS risk_level_change,
                        COALESCE(aww_code, awc_code, %s) AS aww_code
                    FROM {table_name}
                    WHERE UPPER(child_id) = UPPER(%s)
                    ORDER BY updated_at DESC
                    LIMIT %s
                    """,
                    (resolved_awc, child_id, safe_limit),
                ).fetchall()

        if not rows:
            rows = conn.execute(
                """
                SELECT
                    created_at,
                    CASE
                        WHEN COALESCE(improvement_status, 0) = 0 AND COALESCE(improvement, 0) <> 0 THEN improvement
                        ELSE COALESCE(improvement_status, 0)
                    END AS overall_improvement,
                    COALESCE(completion, completition, 0) AS completion_rate,
                    NULL::TEXT AS risk_level_change,
                    NULL::TEXT AS aww_code
                FROM improvement_table
                WHERE UPPER(child_id) = UPPER(%s)
                ORDER BY created_at DESC
                LIMIT %s
                """,
                (child_id, safe_limit),
            ).fetchall()
        if not rows:
            rows = conn.execute(
                """
                SELECT created_at, overall_improvement, completion_rate, risk_level_change, NULL::TEXT AS aww_code
                FROM improvement_summary
                WHERE UPPER(child_id) = UPPER(%s)
                ORDER BY created_at DESC
                LIMIT %s
                """,
                (child_id, safe_limit),
            ).fetchall()
    return [
        {
            "date": r["created_at"].isoformat() if r.get("created_at") else None,
            "overall_improvement": int(r.get("overall_improvement") or 0),
            "completion_rate": float(r.get("completion_rate") or 0),
            "risk_level_change": r.get("risk_level_change"),
            "aww_code": r.get("aww_code"),
        }
        for r in rows
    ]
