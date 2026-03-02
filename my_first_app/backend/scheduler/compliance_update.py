import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.append(ROOT)

from app.pg_compat import get_conn  # noqa: E402
from app.timeline_engine import DEFAULT_ECD_DATABASE_URL, TimelineEngine  # noqa: E402


def run_compliance_update() -> None:
    db_url = os.getenv("ECD_DATABASE_URL", os.getenv("DATABASE_URL", DEFAULT_ECD_DATABASE_URL))
    engine = TimelineEngine(db_url)
    with get_conn(db_url) as conn:
        rows = conn.execute("SELECT id FROM referrals").fetchall()
    for row in rows:
        engine.update_compliance(int(row["id"]))


if __name__ == "__main__":
    run_compliance_update()
