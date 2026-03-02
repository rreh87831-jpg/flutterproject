from datetime import datetime

from app.problem_b_referral_router import run_escalation_check


if __name__ == "__main__":
    result = run_escalation_check()
    print(f"{datetime.utcnow().isoformat()} escalation check -> {result}")
