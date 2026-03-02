#!/bin/bash
# Add to crontab (Linux):
# 0 9 * * * /path/to/my_first_app/cron_job.sh

cd "$(dirname "$0")/backend" || exit 1
if [ -f "venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source venv/bin/activate
fi
python scheduler.py
