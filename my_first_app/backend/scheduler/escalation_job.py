import os
import sys
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.append(ROOT)

from app.timeline_engine import TimelineEngine  # noqa: E402


def run_daily_escalation_check() -> None:
    engine = TimelineEngine()
    print(f"[{datetime.utcnow().isoformat()}] starting escalation check")
    escalated = engine.check_escalation()
    print(f"[{datetime.utcnow().isoformat()}] escalated count: {len(escalated)}")
    for item in escalated:
        print(
            f"referral={item['referral_id']} level={item['new_level']} to={item['escalated_to']} reasons={'; '.join(item['reasons'])}"
        )


if __name__ == "__main__":
    run_daily_escalation_check()
