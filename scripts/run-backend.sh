#!/bin/sh
# Wrapper the LaunchAgent (docs/adr/0010) execs to run the release backend
# with secrets sourced from ~/.pcc.env — kept out of the repo entirely
# (ADR-0010, Q6/Q12), since a launchd job doesn't inherit your shell.
#
# Not meant to be run by hand for daily use — scripts/redeploy.sh is the
# entrypoint for "change code, redeploy" and manages the LaunchAgent that
# runs this script.

set -eu
cd "$(dirname "$0")/.."

ENV_FILE="$HOME/.pcc.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    . "$ENV_FILE"
    set +a
fi

exec .build/release/App serve
