#!/usr/bin/env bash
# Run the farmer at most once per local day.
#
# The bot is written to be re-runnable: every task checks whether it is already
# complete before acting, so a second run on the same day mostly re-reads the
# page. This script adds the cheap outer guard so an unattended schedule does
# not open a browser at all once the day's work is done.
#
# Run it by hand any time; it is safe to do so.
#
#	./scripts/run_daily.sh
#
# Works on Linux and macOS. For the scheduler that calls it see scripts/systemd
# (Linux), scripts/windows (Task Scheduler) and scripts/macos (launchd).
#
# State lives in $HOME/.local/state/rewards-farmer, not in the repo, so nothing
# here can be committed by accident and `git status` stays clean.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Deliberately $HOME and not $XDG_STATE_HOME. The whole point of this script is
# that the timer and a manual run agree on where "today" is recorded, and
# XDG_STATE_HOME turns out to be set to all sorts of values by sandboxes and
# wrappers while a systemd service often leaves it unset. Honouring it means two
# invocations can look at two different markers and both decide today is
# unfinished. $HOME is the one thing both are guaranteed to agree on.
STATE_DIR="$HOME/.local/state/rewards-farmer"
LOG_DIR="$STATE_DIR/logs"

TODAY="$(date +%F)"
MARKER="$STATE_DIR/last-success-$TODAY"
LOCK="$STATE_DIR/run.lock"

mkdir -p "$STATE_DIR" "$LOG_DIR"
LOG_FILE="$LOG_DIR/run-$TODAY.log"

# One farmer at a time. Two Edge instances sharing data-dir/ makes the second
# one fail to start, and a scheduled run that collides with a manual one would
# report a browser error rather than anything useful.
#
# flock(1) is util-linux and macOS does not ship it, so fall back to an atomic
# mkdir, which every POSIX filesystem provides. flock is released by the kernel
# when the process dies; a mkdir lock is not, so the fallback needs a trap to
# clean up after itself and a staleness check for the case where the machine
# was powered off mid-run.
if command -v flock >/dev/null 2>&1; then
	exec 9>"$LOCK"

	if ! flock -n 9; then
		echo "run_daily: another run holds $LOCK, nothing to do." >&2
		exit 0
	fi
else
	mkdir "$LOCK" 2>/dev/null || {
		echo "run_daily: another run holds $LOCK, nothing to do." >&2
		exit 0
	}

	# Any run is minutes at most, so an hour-old lock can only be a leftover.
	find "$LOCK" -maxdepth 0 -mmin +60 -exec rmdir {} + 2>/dev/null && mkdir "$LOCK" 2>/dev/null || true
	trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
fi

if [ -f "$MARKER" ]; then
	echo "run_daily: already ran today ($TODAY), skipping. Log: $LOG_FILE"
	exit 0
fi

# A venv is what the README's poetry commands end up using, and it is what the
# working install has. Fall back to poetry so a fresh clone still runs.
if [ -x "$REPO_ROOT/.venv/bin/python" ]; then
	PYTHON=("$REPO_ROOT/.venv/bin/python")
elif command -v poetry >/dev/null 2>&1; then
	PYTHON=(poetry run python)
else
	echo "run_daily: no .venv and no poetry on PATH." >&2
	exit 2
fi

# Headless is what makes this schedulable, and it is the mode the Docker image
# already uses. Two reasons:
#
#   - main.py waits on input("Press Enter to exit...") when not headless, and a
#     timer has no terminal, so that raises EOFError after the day's work is
#     already done and the service exits non-zero for no reason.
#   - it needs no graphical session, so the run does not depend on the display
#     being logged in at that hour.
#
# main.py loads .env with python-dotenv's default override=False, so exporting
# this wins over the REWARDS_HEADLESS=false in .env.
export REWARDS_HEADLESS=true

echo "run_daily: starting $TODAY, logging to $LOG_FILE"

cd "$REPO_ROOT"
if "${PYTHON[@]}" src/main.py >>"$LOG_FILE" 2>&1; then
	# main.py returns 0 when the browser started and the run finished, 1 when
	# it never started, 2 on bad config. Only the first is worth remembering.
	: >"$MARKER"
	echo "run_daily: finished, marked $TODAY done."
	exit 0
else
	# Captured inside the else, not after the fi: a bash `if` whose condition
	# never held and which has no else reports 0, so reading $? out here would
	# claim success for a run that just failed.
	status=$?
	echo "run_daily: run failed (exit $status), not marking $TODAY done so a later" >&2
	echo "run_daily: run today still tries. Log: $LOG_FILE" >&2
	exit "$status"
fi
