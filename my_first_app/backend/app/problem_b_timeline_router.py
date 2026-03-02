from __future__ import annotations

import json
import os
from datetime import date, datetime, timedelta
from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from .pg_compat import get_conn
from .timeline_engine import TimelineEngine, DEFAULT_ECD_DATABASE_URL

router = APIRouter(prefix="/api/referrals", tags=["problem-b-timeline"])


class RiskDataSchema(BaseModel):
    child_id: str
    overall_risk_score: int
    overall_risk_level: str
    num_delays: int
    screening_date: Optional[date] = None
    autism_score: Optional[int] = 0
    adhd_score: Optional[int] = 0
    domain_breakdown: Dict[str, Any]


class ReviewCompletePayload(BaseModel):
    notes: Optional[str] = None


class SpecialistVisitPayload(BaseModel):
    visit_date: Optional[date] = None


class ImprovementPayload(BaseModel):
    overall_score: int


def _db_url() -> str:
    return os.getenv("ECD_DATABASE_URL", os.getenv("DATABASE_URL", DEFAULT_ECD_DATABASE_URL))


def _ensure_schema() -> None:
    schema_path = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", "database", "timeline_schema.sql")
    )
    if not os.path.exists(schema_path):
        return
    with open(schema_path, "r", encoding="utf-8") as f:
        script = f.read()
    with get_conn(_db_url()) as conn:
        conn.executescript(script)


@router.post("/create")
def create_referral(risk_data: RiskDataSchema):
    _ensure_schema()
    level = risk_data.overall_risk_level.upper()
    if level == "CRITICAL":
        facility, urgency = "DISTRICT SPECIALIST", "IMMEDIATE"
    elif level == "HIGH":
        facility, urgency = "DISTRICT HOSPITAL", "PRIORITY"
    else:
        facility, urgency = "PHC", "ROUTINE"
    screening_date = risk_data.screening_date or date.today()
    legacy_deadline = (
        screening_date
        + (
            timedelta(days=2)
            if level == "CRITICAL"
            else timedelta(days=4)
            if level == "HIGH"
            else timedelta(days=7)
            if level == "MEDIUM"
            else timedelta(days=10)
        )
    )

    with get_conn(_db_url()) as conn:
        row = conn.execute(
            """
            INSERT INTO referrals (
                child_id, overall_risk_score, overall_risk_level, num_delays,
                autism_score, adhd_score, domain_breakdown, facility_type, urgency,
                deadline, screening_date, follow_up_start_date, status, specialist_visit_completed
            ) VALUES (%s, %s, %s, %s, %s, %s, %s::jsonb, %s, %s, %s, %s, %s, 'PENDING', FALSE)
            RETURNING id, referral_id, child_id, overall_risk_level, facility_type, urgency,
                      referral_deadline, follow_up_end_date, review_frequency, status, escalation_level
            """,
            (
                str(risk_data.child_id),
                int(risk_data.overall_risk_score),
                level,
                int(risk_data.num_delays),
                int(risk_data.autism_score or 0),
                int(risk_data.adhd_score or 0),
                json.dumps(risk_data.domain_breakdown or {}),
                facility,
                urgency,
                legacy_deadline,
                screening_date,
                screening_date,
            ),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=500, detail="Referral create failed")

    referral_id = int(row["id"])
    engine = TimelineEngine(_db_url())
    timeline = engine.create_timeline(referral_id)
    if "error" in timeline:
        raise HTTPException(status_code=500, detail=timeline["error"])

    with get_conn(_db_url()) as conn:
        saved = conn.execute(
            """
            SELECT id, referral_id, child_id, overall_risk_level, facility_type, urgency,
                   referral_deadline, follow_up_end_date, review_frequency, status, escalation_level
            FROM referrals WHERE id = %s
            """,
            (referral_id,),
        ).fetchone()
    s = dict(saved)
    return {
        "id": int(s["id"]),
        "referral_id": s["referral_id"],
        "child_id": s["child_id"],
        "screening_date": screening_date.isoformat(),
        "overall_risk_level": s["overall_risk_level"],
        "facility_type": s["facility_type"],
        "urgency": s["urgency"],
        "referral_deadline": s["referral_deadline"].isoformat() if s.get("referral_deadline") else None,
        "follow_up_end_date": s["follow_up_end_date"].isoformat() if s.get("follow_up_end_date") else None,
        "review_frequency": s.get("review_frequency"),
        "status": s["status"],
        "escalation_level": int(s.get("escalation_level") or 0),
    }


@router.get("/{referral_id}/timeline")
def get_timeline(referral_id: int):
    _ensure_schema()
    with get_conn(_db_url()) as conn:
        referral = conn.execute(
            """
            SELECT id, overall_risk_level, screening_date, referral_deadline, follow_up_end_date, review_frequency, escalation_level
            FROM referrals WHERE id = %s
            """,
            (referral_id,),
        ).fetchone()
        if referral is None:
            raise HTTPException(status_code=404, detail="Referral not found")

        activities = conn.execute(
            "SELECT status FROM follow_up_activities WHERE referral_id = %s",
            (str(referral_id),),
        ).fetchall()
        reviews = conn.execute(
            "SELECT status FROM follow_up_reviews WHERE referral_id = %s",
            (referral_id,),
        ).fetchall()
        compliance = conn.execute(
            "SELECT compliance_percentage FROM compliance_summary WHERE referral_id = %s",
            (referral_id,),
        ).fetchone()

    total_activities = len(activities)
    completed_activities = sum(1 for a in activities if (a.get("status") or "").upper() == "COMPLETED")
    reviews_completed = sum(1 for r in reviews if (r.get("status") or "").upper() == "COMPLETED")
    compliance_pct = float(compliance["compliance_percentage"]) if compliance else 0.0

    r = dict(referral)
    return {
        "referral": {
            "id": int(r["id"]),
            "risk_level": r["overall_risk_level"],
            "screening_date": r["screening_date"].isoformat() if r.get("screening_date") else None,
            "deadline": r["referral_deadline"].isoformat() if r.get("referral_deadline") else None,
            "end_date": r["follow_up_end_date"].isoformat() if r.get("follow_up_end_date") else None,
            "frequency": r.get("review_frequency"),
        },
        "stats": {
            "total_activities": total_activities,
            "completed_activities": completed_activities,
            "compliance": compliance_pct,
            "reviews_completed": reviews_completed,
            "escalation_level": int(r.get("escalation_level") or 0),
        },
    }


@router.post("/{referral_id}/complete-activity/{activity_id}")
def complete_activity(referral_id: int, activity_id: int):
    _ensure_schema()
    with get_conn(_db_url()) as conn:
        activity = conn.execute(
            """
            SELECT id FROM follow_up_activities
            WHERE id = %s AND referral_id = %s
            """,
            (activity_id, str(referral_id)),
        ).fetchone()
        if activity is None:
            raise HTTPException(status_code=404, detail="Activity not found")
        conn.execute(
            """
            UPDATE follow_up_activities
            SET status = 'COMPLETED', completed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
            """,
            (activity_id,),
        )
    return TimelineEngine(_db_url()).update_compliance(referral_id)


@router.post("/{referral_id}/complete-review/{review_id}")
def complete_review(referral_id: int, review_id: int, payload: ReviewCompletePayload):
    _ensure_schema()
    with get_conn(_db_url()) as conn:
        review = conn.execute(
            """
            SELECT id FROM follow_up_reviews
            WHERE id = %s AND referral_id = %s
            """,
            (review_id, referral_id),
        ).fetchone()
        if review is None:
            raise HTTPException(status_code=404, detail="Review not found")
        conn.execute(
            """
            UPDATE follow_up_reviews
            SET status = 'COMPLETED', completed_at = CURRENT_TIMESTAMP, notes = %s, updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
            """,
            (payload.notes, review_id),
        )
    return TimelineEngine(_db_url()).update_compliance(referral_id)


@router.post("/{referral_id}/mark-specialist-visit")
def mark_specialist_visit(referral_id: int, payload: SpecialistVisitPayload):
    _ensure_schema()
    with get_conn(_db_url()) as conn:
        row = conn.execute(
            "SELECT id FROM referrals WHERE id = %s",
            (referral_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Referral not found")
        conn.execute(
            """
            UPDATE referrals
            SET specialist_visit_completed = TRUE,
                specialist_visit_date = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
            """,
            (payload.visit_date or date.today(), referral_id),
        )
    TimelineEngine(_db_url()).update_compliance(referral_id)
    return {"status": "success", "message": "Specialist visit recorded"}


@router.post("/run-escalation-check")
def run_escalation_check():
    _ensure_schema()
    escalated = TimelineEngine(_db_url()).check_escalation()
    return {"status": "success", "escalated_count": len(escalated), "details": escalated}


@router.get("/timeline/escalations")
def list_escalations(limit: int = 100):
    _ensure_schema()
    with get_conn(_db_url()) as conn:
        rows = conn.execute(
            """
            SELECT r.id AS referral_id, r.referral_id AS referral_code, r.child_id, r.overall_risk_level,
                   r.escalation_level, e.escalated_to, e.escalation_reason, e.created_at
            FROM referrals r
            JOIN timeline_escalation_logs e ON e.referral_id = r.id
            ORDER BY e.created_at DESC
            LIMIT %s
            """,
            (max(1, min(limit, 1000)),),
        ).fetchall()
    return [dict(r) for r in rows]


@router.post("/{referral_id}/improvement")
def calculate_referral_improvement(referral_id: int, payload: ImprovementPayload):
    _ensure_schema()
    result = TimelineEngine(_db_url()).calculate_improvement(referral_id, int(payload.overall_score))
    if "error" in result:
        raise HTTPException(status_code=404, detail=result["error"])
    return result
