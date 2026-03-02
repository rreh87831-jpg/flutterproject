"""
Problem B Service: Strict Intervention Lifecycle Implementation
Core logic follows: Risk → Phase → Activities → Compliance → Review → Decision → Referral
"""

from __future__ import annotations

import os
import uuid
from datetime import datetime, timedelta
from typing import Dict, List, Optional
try:
    from .pg_compat import get_conn
except Exception:
    from pg_compat import get_conn


class ProblemBService:
    """
    Strict Problem B lifecycle engine.
    
    Flow:
    1. Create phase from risk
    2. Auto-generate activities
    3. Track compliance weekly
    4. Run review on interval
    5. Auto-escalate if needed
    6. Create referral only if escalation triggered
    """

    # Fixed thresholds (non-negotiable)
    ADHERENCE_THRESHOLD = 0.6  # 60%
    ESCALATION_THRESHOLD = 0.4  # 40%
    REVIEW_INTERVAL_DAYS = 42  # 6 weeks
    IMPROVEMENT_THRESHOLD = 1.0  # 1 month

    def __init__(
        self,
        db_path: str = os.getenv(
            "ECD_DATABASE_URL",
            os.getenv("DATABASE_URL", "postgresql://postgres:postgres@127.0.0.1:5432/ecd_data"),
        ),
    ):
        self.db_path = db_path
        self._ensure_db()

    def _get_conn(self, db_path: str):
        return get_conn(db_path)

    def _ensure_db(self):
        """Ensure database tables exist."""
        with self._get_conn(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT to_regclass('public.intervention_phase') AS table_name"
            )
            existing = cursor.fetchone()
            if not existing or not existing.get("table_name"):
                print(
                    "Warning: Problem B tables are missing. "
                    "Run database setup/migrations before using Problem B endpoints."
                )

    # =========================================================================
    # PHASE 1: CREATE INTERVENTION PHASE
    # =========================================================================

    def create_intervention_phase(self, child_id: str, domain: str, severity: str,
                                baseline_delay: float, age_months: int) -> Dict:
        """
        Create intervention phase from risk assessment.
        Automatically triggers activity generation.
        """
        try:
            phase_id = f"phase_{uuid.uuid4().hex[:12]}"
            start_date = datetime.now()
            end_date = start_date + timedelta(days=self.REVIEW_INTERVAL_DAYS)
            next_review = end_date

            with self._get_conn(self.db_path) as conn:
                cursor = conn.cursor()

                # Insert phase
                cursor.execute(
                    """
                    INSERT INTO intervention_phase 
                    (phase_id, child_id, domain, severity, baseline_delay, 
                     start_date, review_date, status)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, 'ACTIVE')
                    """,
                    (phase_id, child_id, domain, severity, baseline_delay,
                     start_date.isoformat(), next_review.isoformat()),
                )
                conn.commit()

            # AUTO-GENERATE ACTIVITIES
            activities = self._generate_activities_auto(domain, severity, age_months)

            with self._get_conn(self.db_path) as conn:
                cursor = conn.cursor()
                for act in activities:
                    activity_id = f"act_{uuid.uuid4().hex[:12]}"
                    cursor.execute(
                        """
                        INSERT INTO activities
                        (activity_id, phase_id, domain, role, name, frequency_per_week)
                        VALUES (%s, %s, %s, %s, %s, %s)
                        """,
                        (activity_id, phase_id, domain, act["role"], 
                         act["name"], act["frequency_per_week"]),
                    )
                conn.commit()

            return {
                "phase_id": phase_id,
                "status": "ACTIVE",
                "domain": domain,
                "severity": severity,
                "baseline_delay": baseline_delay,
                "start_date": start_date.isoformat(),
                "review_date": next_review.isoformat(),
                "activities_generated": len(activities),
            }
        except Exception as e:
            return {"status": "error", "message": str(e)}

    # =========================================================================
    # PHASE 2: AUTO-GENERATE ACTIVITIES (AI Engine)
    # =========================================================================

    def _generate_activities_auto(self, domain: str, severity: str, 
                                 age_months: int) -> List[Dict]:
        """
        Automatically generate activities based on:
        - Domain (FM, GM, LC, COG, SE)
        - Severity (LOW, MEDIUM, HIGH, CRITICAL)
        - Age band
        
        Returns list of activities ready to insert.
        """
        activities = []

        # Determine frequency based on severity
        if severity == "CRITICAL":
            aww_freq = 5  # 5 days/week
            cg_freq = 5
        elif severity == "HIGH":
            aww_freq = 5
            cg_freq = 4
        else:
            aww_freq = 3
            cg_freq = 3

        # Domain-specific template
        templates = {
            "FM": [  # Fine Motor
                {"role": "AWW", "name": "Grip strengthening exercises"},
                {"role": "Caregiver", "name": "Play dough manipulation"},
            ],
            "GM": [  # Gross Motor
                {"role": "AWW", "name": "Core strength building"},
                {"role": "Caregiver", "name": "Walking and climbing practice"},
            ],
            "LC": [  # Language & Communication
                {"role": "AWW", "name": "Vocabulary building"},
                {"role": "Caregiver", "name": "Story and rhyme practice"},
            ],
            "COG": [  # Cognitive
                {"role": "AWW", "name": "Object recognition"},
                {"role": "Caregiver", "name": "Problem solving puzzles"},
            ],
            "SE": [  # Social-Emotional
                {"role": "AWW", "name": "Emotion recognition"},
                {"role": "Caregiver", "name": "Bonding and play activities"},
            ],
        }

        # Get templates for this domain
        domain_templates = templates.get(domain, [])

        for template in domain_templates:
            freq = aww_freq if template["role"] == "AWW" else cg_freq
            activities.append({
                "role": template["role"],
                "name": template["name"],
                "frequency_per_week": freq,
            })

        return activities

    # =========================================================================
    # PHASE 3: COMPLIANCE CALCULATION (Weekly)
    # =========================================================================

    def calculate_compliance(self, phase_id: str) -> float:
        """
        Calculate weekly compliance percentage.
        compliance = (completed_tasks / total_tasks) * 100
        """
        try:
            with self._get_conn(self.db_path) as conn:
                cursor = conn.cursor()

                # Total tasks this week
                cursor.execute(
                    """
                    SELECT COUNT(*) as total FROM activities WHERE phase_id = %s
                    """,
                    (phase_id,),
                )
                total = cursor.fetchone()["total"]

                if total == 0:
                    return 0.0

                # Completed tasks this week
                week_ago = (datetime.now() - timedelta(days=7)).isoformat()
                cursor.execute(
                    """
                    SELECT COUNT(*) as completed FROM task_logs 
                    WHERE activity_id IN (SELECT activity_id FROM activities WHERE phase_id = %s)
                    AND completed = 1 
                    AND date_logged > %s
                    """,
                    (phase_id, week_ago),
                )
                completed = cursor.fetchone()["completed"]

                compliance = (completed / total) * 100
                return compliance / 100  # Return as decimal (0.75 = 75%)

        except Exception as e:
            print(f"Error calculating compliance: {e}")
            return 0.0

    # =========================================================================
    # PHASE 4: IMPROVEMENT CALCULATION
    # =========================================================================

    def calculate_improvement(self, phase_id: str, current_delay: float) -> float:
        """
        improvement = baseline_delay - current_delay
        """
        try:
            with self._get_conn(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    "SELECT baseline_delay FROM intervention_phase WHERE phase_id = %s",
                    (phase_id,),
                )
                row = cursor.fetchone()
                if not row:
                    return 0.0

                baseline = row["baseline_delay"]
                improvement = baseline - current_delay
                return improvement

        except Exception as e:
            print(f"Error calculating improvement: {e}")
            return 0.0

    # =========================================================================
    # PHASE 5: REVIEW ENGINE (Core Problem B Logic)
    # =========================================================================

    def run_review_engine(self, phase_id: str, current_delay: float) -> Dict:
        """
        Core decision engine. Runs every review interval.
        
        Rules:
        1. If compliance < 40% → INTENSIFY
        2. If no improvement after 2 reviews → ESCALATE  
        3. If worsening trend → ESCALATE
        4. Else → CONTINUE
        """
        try:
            compliance = self.calculate_compliance(phase_id)
            improvement = self.calculate_improvement(phase_id, current_delay)

            # Check previous reviews
            with self._get_conn(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    "SELECT COUNT(*) as count FROM review_log WHERE phase_id = %s",
                    (phase_id,),
                )
                review_count = cursor.fetchone()["count"]

            decision = "CONTINUE"
            reason = "Progress on track"

            # RULE 1: Poor adherence
            if compliance < self.ESCALATION_THRESHOLD:
                decision = "INTENSIFY"
                reason = f"Low adherence: {compliance*100:.1f}% < {self.ESCALATION_THRESHOLD*100}%"
                # Auto-intensify plan
                self._intensify_plan(phase_id)

            # RULE 2: No improvement after 2 reviews
            elif improvement <= 0 and review_count >= 2:
                decision = "ESCALATE"
                reason = "No improvement after multiple reviews - escalating to specialist"
                # Auto-create referral
                self._create_referral(phase_id)

            # RULE 3: Worsening trend
            elif improvement < 0:
                decision = "ESCALATE"
                reason = "Worsening trend detected - requires specialist intervention"
                # Auto-create referral
                self._create_referral(phase_id)

            # Store review
            review_id = f"review_{uuid.uuid4().hex[:12]}"
            with self._get_conn(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    """
                    INSERT INTO review_log
                    (review_id, phase_id, review_date, compliance, improvement, decision_action, decision_reason)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    """,
                    (review_id, phase_id, datetime.now().isoformat(),
                     compliance * 100, improvement, decision, reason),
                )
                conn.commit()

            return {
                "review_id": review_id,
                "compliance": compliance,
                "improvement": improvement,
                "decision": decision,
                "reason": reason,
                "review_count": review_count + 1,
            }

        except Exception as e:
            return {"status": "error", "message": str(e)}

    # =========================================================================
    # PHASE 6: AUTO-INTENSIFY PLAN
    # =========================================================================

    def _intensify_plan(self, phase_id: str) -> None:
        """
        Automatically increase activity frequency when adherence is low.
        """
        try:
            with self._get_conn(self.db_path) as conn:
                cursor = conn.cursor()
                # Increase frequency by 1 for all activities
                cursor.execute(
                    """
                    UPDATE activities 
                    SET frequency_per_week = frequency_per_week + 1
                    WHERE phase_id = %s
                    """,
                    (phase_id,),
                )
                conn.commit()
                print(f"Plan intensified for phase {phase_id}")

        except Exception as e:
            print(f"Error intensifying plan: {e}")

    # =========================================================================
    # PHASE 7: AUTO-CREATE REFERRAL (on escalation)
    # =========================================================================

    def _create_referral(self, phase_id: str) -> Dict:
        """
        Automatically create referral when escalation is triggered.
        This is CONDITIONAL - only called during escalation decision.
        """
        try:
            with self._get_conn(self.db_path) as conn:
                cursor = conn.cursor()

                # Get phase details
                cursor.execute(
                    "SELECT child_id, domain, severity FROM intervention_phase WHERE phase_id = %s",
                    (phase_id,),
                )
                phase = cursor.fetchone()

                if not phase:
                    return {"status": "error", "message": "Phase not found"}

                # Create referral
                referral_id = f"ref_{uuid.uuid4().hex[:12]}"
                cursor.execute(
                    """
                    INSERT INTO referral
                    (referral_id, child_id, domain, urgency, status, created_on)
                    VALUES (%s, %s, %s, 'IMMEDIATE', 'PENDING', %s)
                    """,
                    (referral_id, phase["child_id"], phase["domain"],
                     datetime.now().isoformat()),
                )

                # Update phase status
                cursor.execute(
                    "UPDATE intervention_phase SET status = 'ESCALATED' WHERE phase_id = %s",
                    (phase_id,),
                )
                conn.commit()

                return {
                    "referral_id": referral_id,
                    "child_id": phase["child_id"],
                    "domain": phase["domain"],
                    "status": "PENDING",
                    "urgency": "IMMEDIATE",
                }

        except Exception as e:
            return {"status": "error", "message": str(e)}

    # =========================================================================
    # UTILITY: Log Activity Completion
    # =========================================================================

    def log_activity_completion(self, activity_id: str) -> Dict:
        """
        Log when AWW or Caregiver completes an activity.
        """
        try:
            with self._get_conn(self.db_path) as conn:
                cursor = conn.cursor()
                task_id = f"task_{uuid.uuid4().hex[:12]}"
                cursor.execute(
                    """
                    INSERT INTO task_logs
                    (task_id, activity_id, date_logged, completed)
                    VALUES (%s, %s, %s, 1)
                    """,
                    (task_id, activity_id, datetime.now().isoformat()),
                )
                conn.commit()

            return {"status": "ok", "task_id": task_id}

        except Exception as e:
            return {"status": "error", "message": str(e)}

    # =========================================================================
    # UTILITY: Get Phase Status
    # =========================================================================

    def get_phase_status(self, phase_id: str) -> Dict:
        """
        Get current phase status with all metrics.
        """
        try:
            with self._get_conn(self.db_path) as conn:
                cursor = conn.cursor()

                # Get phase
                cursor.execute(
                    "SELECT * FROM intervention_phase WHERE phase_id = %s",
                    (phase_id,),
                )
                phase = cursor.fetchone()

                if not phase:
                    return {"status": "error", "message": "Phase not found"}

                # Get activities
                cursor.execute(
                    "SELECT COUNT(*) as count FROM activities WHERE phase_id = %s",
                    (phase_id,),
                )
                activity_count = cursor.fetchone()["count"]

                compliance = self.calculate_compliance(phase_id)

                # Get latest review
                cursor.execute(
                    """
                    SELECT * FROM review_log WHERE phase_id = %s 
                    ORDER BY review_date DESC LIMIT 1
                    """,
                    (phase_id,),
                )
                latest_review = cursor.fetchone()

                return {
                    "phase_id": phase_id,
                    "child_id": phase["child_id"],
                    "domain": phase["domain"],
                    "severity": phase["severity"],
                    "status": phase["status"],
                    "baseline_delay": phase["baseline_delay"],
                    "activities_count": activity_count,
                    "compliance": compliance,
                    "latest_review": dict(latest_review) if latest_review else None,
                    "review_date": phase["review_date"],
                }

        except Exception as e:
            return {"status": "error", "message": str(e)}


class _ProblemBServiceProxy:
    """Lazily initialize ProblemBService to avoid import-time DB failures."""

    def __init__(self):
        self._service: Optional[ProblemBService] = None

    def _ensure(self) -> ProblemBService:
        if self._service is None:
            self._service = ProblemBService()
        return self._service

    def __getattr__(self, name):
        return getattr(self._ensure(), name)


# Singleton proxy instance
problem_b_service = _ProblemBServiceProxy()


def _normalize_severity(value: str) -> str:
    v = (value or "").strip().lower()
    if v in {"critical", "high", "medium", "low", "mild", "normal"}:
        return v
    return "low"


def generate_intervention_plan(payload: Dict) -> Dict:
    """Compatibility wrapper used by main.py endpoints."""
    child_id = str(payload.get("child_id") or "").strip()
    if not child_id:
        return {"status": "error", "message": "child_id is required"}

    delays = {
        "GM": int(payload.get("gm_delay", 0) or 0),
        "FM": int(payload.get("fm_delay", 0) or 0),
        "LC": int(payload.get("lc_delay", 0) or 0),
        "COG": int(payload.get("cog_delay", 0) or 0),
        "SE": int(payload.get("se_delay", 0) or 0),
    }
    delayed_domains = [d for d, m in delays.items() if m > 0]

    risk = _normalize_severity(str(payload.get("risk_category", "low")))
    if risk in {"critical", "high"}:
        intensity = "High"
    elif risk in {"medium", "mild"}:
        intensity = "Moderate"
    else:
        intensity = "Low"

    return {
        "child_id": child_id,
        "status": "ok",
        "risk_category": payload.get("risk_category", "Low"),
        "delayed_domains": delayed_domains,
        "total_delays": len(delayed_domains),
        "recommended_intensity": intensity,
        "next_review_weeks": 6,
        "referral_required": "YES" if risk in {"critical", "high"} else "NO",
    }


def adjust_intensity(current_intensity: str, trend: str) -> str:
    levels = ["Low", "Moderate", "High"]
    cur = (current_intensity or "Moderate").strip().title()
    tr = (trend or "No Change").strip().lower()
    try:
        idx = levels.index(cur)
    except ValueError:
        idx = 1

    if tr in {"worsened", "worsening", "declined"}:
        idx = min(idx + 1, 2)
    elif tr in {"improved", "improving"}:
        idx = max(idx - 1, 0)

    return levels[idx]


def next_review_decision(adjusted_intensity: str, delay_reduction: int, trend: str) -> str:
    t = (trend or "no change").lower()
    if t in {"worsened", "worsening"}:
        return "Escalate to specialist referral"
    if int(delay_reduction or 0) >= 1 and adjusted_intensity == "Low":
        return "Continue maintenance plan"
    if adjusted_intensity == "High":
        return "Reassess in 2 weeks"
    return "Continue current plan and review in 6 weeks"


def rule_logic_table() -> Dict:
    return {
        "rules": [
            {"condition": "trend = worsened", "action": "escalate"},
            {"condition": "adherence < 40%", "action": "intensify"},
            {"condition": "delay reduction >= 1 and intensity low", "action": "maintenance"},
        ]
    }

