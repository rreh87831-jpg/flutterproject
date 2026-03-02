from __future__ import annotations

import json
import os
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional

from .pg_compat import get_conn

DEFAULT_ECD_DATABASE_URL = "postgresql://postgres:postgres@127.0.0.1:5432/ecd_data"


class TimelineEngine:
    RISK_CONFIG = {
        "CRITICAL": {
            "referral_deadline_days": 2,
            "follow_up_duration_days": 7,
            "review_frequency": "DAILY",
            "follow_up_step_days": 1,
            "caregiver_domains_per_followup": 3,
            "target_improvement": 50,
        },
        "HIGH": {
            "referral_deadline_days": 4,
            "follow_up_duration_days": 7,
            "review_frequency": "EVERY_2_DAYS",
            "follow_up_step_days": 2,
            "caregiver_domains_per_followup": 2,
            "target_improvement": 30,
        },
        "MEDIUM": {
            "referral_deadline_days": 7,
            "follow_up_duration_days": 7,
            "review_frequency": "MONTHLY",
            "follow_up_step_days": 7,
            "caregiver_domains_per_followup": 1,
            "target_improvement": 15,
        },
        "LOW": {
            "referral_deadline_days": 10,
            "follow_up_duration_days": 7,
            "review_frequency": "MONTHLY",
            "follow_up_step_days": 7,
            "caregiver_domains_per_followup": 1,
            "target_improvement": 10,
        },
    }

    def __init__(self, db_url: Optional[str] = None):
        self.db_url = db_url or os.getenv(
            "ECD_DATABASE_URL",
            os.getenv("DATABASE_URL", DEFAULT_ECD_DATABASE_URL),
        )

    def _get_delayed_domains(self, domain_breakdown: Dict[str, Any]) -> List[str]:
        delayed: List[str] = []
        normalized = {str(k).strip().upper(): int(v or 0) for k, v in (domain_breakdown or {}).items()}
        for domain in ["GM", "FM", "LC", "COG", "SE"]:
            if normalized.get(domain, 100) < 50:
                delayed.append(domain)
        return delayed

    def _activity_template(self, domain: str) -> Dict[str, Any]:
        activities = {
            "GM": {
                "title": "Gross Motor Exercise",
                "description": "Daily physical activity",
                "instructions_english": "Practice walking, running, or jumping.",
                "instructions_telugu": "నడక, పరుగు, దూకడం ప్రాక్టీస్ చేయండి.",
                "time": 10,
            },
            "FM": {
                "title": "Fine Motor Practice",
                "description": "Hand and finger exercises",
                "instructions_english": "Practice stacking blocks and scribbling.",
                "instructions_telugu": "బ్లాకులు పేర్చడం, గీతలు గీయడం ప్రాక్టీస్ చేయండి.",
                "time": 5,
            },
            "LC": {
                "title": "Language Activity",
                "description": "Communication practice",
                "instructions_english": "Read books, name objects, and practice words.",
                "instructions_telugu": "పుస్తకాలు చదవండి, వస్తువులకు పేర్లు చెప్పండి.",
                "time": 10,
            },
            "COG": {
                "title": "Cognitive Game",
                "description": "Thinking and problem-solving",
                "instructions_english": "Play matching games and simple puzzles.",
                "instructions_telugu": "జతపరచే ఆటలు, పజిల్స్ ఆడండి.",
                "time": 5,
            },
            "SE": {
                "title": "Social-Emotional Activity",
                "description": "Social interaction practice",
                "instructions_english": "Practice turn-taking and positive interactions.",
                "instructions_telugu": "వంతులు మార్చుకోవడం, సానుకూల పరస్పర చర్యలు ప్రాక్టీస్ చేయండి.",
                "time": 5,
            },
            "GENERAL": {
                "title": "General Stimulation",
                "description": "Play and interaction",
                "instructions_english": "Spend quality time playing with the child.",
                "instructions_telugu": "పిల్లలతో నాణ్యమైన సమయం గడపండి.",
                "time": 15,
            },
        }
        return activities.get(domain, activities["GENERAL"])

    def create_timeline(self, referral_id: int) -> Dict[str, Any]:
        with get_conn(self.db_url) as conn:
            referral = conn.execute(
                "SELECT * FROM referrals WHERE id = %s",
                (referral_id,),
            ).fetchone()
            if referral is None:
                return {"error": "Referral not found"}
            ref = dict(referral)
            child_id = str(ref.get("child_id") or "")
            risk_level = (ref.get("overall_risk_level") or "MEDIUM").upper()
            cfg = self.RISK_CONFIG.get(risk_level, self.RISK_CONFIG["MEDIUM"])

            screening_date = ref.get("screening_date") or ref.get("follow_up_start_date") or date.today()
            deadline = screening_date + timedelta(days=int(cfg["referral_deadline_days"]))
            follow_up_start = deadline
            end_date = follow_up_start + timedelta(days=int(cfg["follow_up_duration_days"]))

            conn.execute(
                """
                UPDATE referrals
                SET referral_deadline = %s,
                    screening_date = %s,
                    follow_up_start_date = %s,
                    follow_up_end_date = %s,
                    review_frequency = %s,
                    status = COALESCE(status, 'PENDING'),
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                """,
                (deadline, screening_date, follow_up_start, end_date, cfg["review_frequency"], referral_id),
            )

            # Follow-up dates start on deadline day (Level 0), then by configured step.
            followup_dates: List[date] = []
            step = int(cfg["follow_up_step_days"])
            current = follow_up_start
            while current <= end_date:
                followup_dates.append(current)
                current += timedelta(days=step)

            delayed = self._get_delayed_domains(ref.get("domain_breakdown") or {})
            caregiver_domains = delayed[: int(cfg.get("caregiver_domains_per_followup", 1))] or ["GENERAL"]

            activity_count = 0
            review_count = 0
            for idx, review_date in enumerate(followup_dates):
                level = idx  # Level 0 on deadline date.

                # Caregiver activities (domain-specific) for each follow-up slot.
                for domain in caregiver_domains:
                    tpl = self._activity_template(domain)
                    conn.execute(
                        """
                        INSERT INTO follow_up_activities (
                            referral_id, child_id, scheduled_date, day_number, activity_title, activity_description,
                            title, description, due_date, frequency,
                            domain, target_role, instructions_english, instructions_telugu,
                            time_required_minutes, status, updated_at
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'ONCE', %s, 'CAREGIVER', %s, %s, %s, 'PENDING', CURRENT_TIMESTAMP)
                        ON CONFLICT DO NOTHING
                        """,
                        (
                            str(referral_id),
                            child_id,
                            review_date,
                            level,
                            f"{domain} Caregiver Activity - Level {level}",
                            tpl["description"],
                            f"{domain} Caregiver Activity - Level {level}",
                            tpl["description"],
                            review_date,
                            domain,
                            tpl["instructions_english"],
                            tpl["instructions_telugu"],
                            int(tpl["time"]),
                        ),
                    )
                    activity_count += 1

                if level == 0:
                    title = "Level 0 - Escalation and OK Check"
                    description = "Initial follow-up on deadline day: check referral completion and escalation need."
                    instructions_en = "Verify specialist referral action. Mark OK if done; trigger escalation if not done."
                    instructions_te = "రిఫరల్ పూర్తయిందో చూడండి. పూర్తైతే OK గుర్తించండి; కాకపోతే ఎస్కలేట్ చేయండి."
                else:
                    title = f"Level {level} - Follow-up Review"
                    description = "Scheduled timeline follow-up review."
                    instructions_en = "Review child progress and caregiver adherence for this follow-up level."
                    instructions_te = "ఈ ఫాలో-అప్ లెవెల్‌లో పురోగతి మరియు సంరక్షకుడి అనుసరణను సమీక్షించండి."

                conn.execute(
                    """
                    INSERT INTO follow_up_activities (
                        referral_id, child_id, scheduled_date, day_number, activity_title, activity_description,
                        title, description, due_date, frequency,
                        domain, target_role, instructions_english, instructions_telugu,
                        time_required_minutes, status, updated_at
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'ONCE', 'GENERAL', 'AWW', %s, %s, %s, 'PENDING', CURRENT_TIMESTAMP)
                    ON CONFLICT DO NOTHING
                    """,
                    (
                        str(referral_id),
                        child_id,
                        review_date,
                        level,
                        title,
                        description,
                        title,
                        description,
                        review_date,
                        instructions_en,
                        instructions_te,
                        10,
                    ),
                )
                activity_count += 1

                conn.execute(
                    """
                    INSERT INTO follow_up_reviews (
                        referral_id, scheduled_date, review_type, week_number, status
                    ) VALUES (%s, %s, 'AWW', %s, 'PENDING')
                    ON CONFLICT (referral_id, scheduled_date, review_type) DO NOTHING
                    """,
                    (referral_id, review_date, level),
                )
                review_count += 1

            conn.execute(
                """
                INSERT INTO compliance_summary (
                    referral_id, total_activities, completed_activities,
                    total_reviews, completed_reviews, specialist_visit_completed, last_updated
                ) VALUES (%s, 0, 0, 0, 0, FALSE, CURRENT_TIMESTAMP)
                ON CONFLICT (referral_id)
                DO NOTHING
                """,
                (referral_id,),
            )

        return {
            "referral_id": referral_id,
            "risk_level": risk_level,
            "screening_date": screening_date.isoformat(),
            "deadline": deadline.isoformat(),
            "end_date": end_date.isoformat(),
            "activities_generated": activity_count,
            "reviews_generated": review_count,
            "frequency": cfg["review_frequency"],
            "schedule_dates": [d.isoformat() for d in followup_dates],
        }

    def update_compliance(self, referral_id: int) -> Dict[str, Any]:
        with get_conn(self.db_url) as conn:
            total_activities = conn.execute(
                "SELECT COUNT(*) AS cnt FROM follow_up_activities WHERE referral_id = %s",
                (str(referral_id),),
            ).fetchone()["cnt"]
            completed_activities = conn.execute(
                """
                SELECT COUNT(*) AS cnt FROM follow_up_activities
                WHERE referral_id = %s AND status = 'COMPLETED'
                """,
                (str(referral_id),),
            ).fetchone()["cnt"]

            total_reviews = conn.execute(
                "SELECT COUNT(*) AS cnt FROM follow_up_reviews WHERE referral_id = %s",
                (referral_id,),
            ).fetchone()["cnt"]
            completed_reviews = conn.execute(
                """
                SELECT COUNT(*) AS cnt FROM follow_up_reviews
                WHERE referral_id = %s AND status = 'COMPLETED'
                """,
                (referral_id,),
            ).fetchone()["cnt"]

            referral = conn.execute(
                "SELECT specialist_visit_completed FROM referrals WHERE id = %s",
                (referral_id,),
            ).fetchone()
            specialist_visited = bool(referral["specialist_visit_completed"]) if referral else False

            compliance_pct = (completed_activities / total_activities * 100) if total_activities else 0.0
            review_pct = (completed_reviews / total_reviews * 100) if total_reviews else 0.0

            conn.execute(
                """
                INSERT INTO compliance_summary (
                    referral_id, total_activities, completed_activities,
                    compliance_percentage, total_reviews, completed_reviews,
                    review_compliance, specialist_visit_completed, last_updated
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
                ON CONFLICT (referral_id)
                DO UPDATE SET
                    total_activities = EXCLUDED.total_activities,
                    completed_activities = EXCLUDED.completed_activities,
                    compliance_percentage = EXCLUDED.compliance_percentage,
                    total_reviews = EXCLUDED.total_reviews,
                    completed_reviews = EXCLUDED.completed_reviews,
                    review_compliance = EXCLUDED.review_compliance,
                    specialist_visit_completed = EXCLUDED.specialist_visit_completed,
                    last_updated = CURRENT_TIMESTAMP
                """,
                (
                    referral_id,
                    int(total_activities),
                    int(completed_activities),
                    round(compliance_pct, 2),
                    int(total_reviews),
                    int(completed_reviews),
                    round(review_pct, 2),
                    specialist_visited,
                ),
            )

        return {
            "referral_id": referral_id,
            "compliance_percentage": round(compliance_pct, 2),
            "review_compliance": round(review_pct, 2),
            "specialist_visited": specialist_visited,
        }

    def check_escalation(self) -> List[Dict[str, Any]]:
        today = date.today()
        escalated: List[Dict[str, Any]] = []
        with get_conn(self.db_url) as conn:
            referrals = conn.execute(
                """
                SELECT * FROM referrals
                WHERE COALESCE(status, 'PENDING') IN ('PENDING', 'IN_PROGRESS', 'ACTIVE')
                """
            ).fetchall()

            for row in referrals:
                referral = dict(row)
                referral_id = int(referral["id"])
                compliance = conn.execute(
                    "SELECT * FROM compliance_summary WHERE referral_id = %s",
                    (referral_id,),
                ).fetchone()

                reasons: List[str] = []
                should_escalate = False

                deadline = referral.get("referral_deadline")
                visited = bool(referral.get("specialist_visit_completed") or False)
                if deadline and (not visited) and today > deadline:
                    should_escalate = True
                    reasons.append(f"Specialist visit deadline missed ({deadline})")

                compliance_pct = float(compliance["compliance_percentage"]) if compliance else 0.0
                if compliance and compliance_pct < 40:
                    should_escalate = True
                    reasons.append(f"Low activity compliance: {compliance_pct:.1f}%")

                missed_reviews = conn.execute(
                    """
                    SELECT COUNT(*) AS cnt
                    FROM follow_up_reviews
                    WHERE referral_id = %s
                      AND scheduled_date < %s
                      AND status = 'PENDING'
                    """,
                    (referral_id, today),
                ).fetchone()["cnt"]
                if int(missed_reviews) >= 2:
                    should_escalate = True
                    reasons.append(f"{int(missed_reviews)} reviews missed")

                if not should_escalate:
                    continue

                new_level = int(referral.get("escalation_level") or 0) + 1
                if new_level == 1:
                    escalate_to = "PHC"
                elif new_level == 2:
                    escalate_to = "DISTRICT"
                else:
                    escalate_to = "STATE"

                conn.execute(
                    """
                    INSERT INTO timeline_escalation_logs (
                        referral_id, escalation_level, escalation_reason, escalated_to,
                        previous_compliance, previous_review_status
                    ) VALUES (%s, %s, %s, %s, %s, %s)
                    """,
                    (
                        referral_id,
                        new_level,
                        "; ".join(reasons)[:100],
                        escalate_to,
                        round(compliance_pct, 2),
                        "PENDING",
                    ),
                )

                conn.execute(
                    """
                    UPDATE referrals
                    SET escalation_level = %s,
                        last_escalation_date = %s,
                        status = CASE WHEN %s >= 3 THEN 'ESCALATED' ELSE COALESCE(status, 'PENDING') END,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = %s
                    """,
                    (new_level, today, new_level, referral_id),
                )

                escalated.append(
                    {
                        "referral_id": referral_id,
                        "new_level": new_level,
                        "reasons": reasons,
                        "escalated_to": escalate_to,
                    }
                )
        return escalated

    def calculate_improvement(self, referral_id: int, current_score: int) -> Dict[str, Any]:
        with get_conn(self.db_url) as conn:
            row = conn.execute(
                "SELECT overall_risk_score FROM referrals WHERE id = %s",
                (referral_id,),
            ).fetchone()
            if row is None:
                return {"error": "Referral not found"}
            baseline = int(row["overall_risk_score"] or 0)
            improvement = int(current_score) - baseline
            pct = (improvement / baseline * 100) if baseline > 0 else 0.0

            if pct >= 30:
                status = "IMPROVED"
            elif pct <= -10:
                status = "WORSENED"
            else:
                status = "NO_CHANGE"

            conn.execute(
                """
                INSERT INTO improvement_tracking (
                    referral_id, baseline_score, current_score,
                    score_improvement, improvement_percentage, improvement_status
                ) VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (referral_id)
                DO UPDATE SET
                    baseline_score = EXCLUDED.baseline_score,
                    current_score = EXCLUDED.current_score,
                    score_improvement = EXCLUDED.score_improvement,
                    improvement_percentage = EXCLUDED.improvement_percentage,
                    improvement_status = EXCLUDED.improvement_status,
                    calculated_at = CURRENT_TIMESTAMP
                """,
                (referral_id, baseline, int(current_score), improvement, round(pct, 2), status),
            )

        return {
            "referral_id": referral_id,
            "baseline": baseline,
            "current": int(current_score),
            "improvement": improvement,
            "improvement_percent": round(pct, 2),
            "status": status,
        }
