#!/bin/sh
# Watches Sources/PCCUI and Sources/PCCDesktop for changes and rebuilds +
# relaunches the PCCDesktop preview app (see the target comment in
# Package.swift and the README's "Consumers (Mac/iOS)" section) so editing a
# view is a save-and-see-it loop without opening Xcode.
#
# Not a hot-swap: each change triggers a full incremental `swift build` and
# a fresh process launch, so any in-window state (a scroll position, an open
# sheet) resets. Typically a few seconds per cycle.
#
# The backend must be running separately first — this script doesn't manage
# it (see README's "Local setup", step 4: `swift run App serve`).
#
# Usage:
#   PCC_AUTH_TOKEN=mac-token ./scripts/dev-dashboard.sh
# (PCC_AUTH_TOKEN must match one of the backend's AUTH_TOKENS values, and
# PCC_BASE_URL defaults to http://127.0.0.1:8080 — see main.swift.)

set -eu
cd "$(dirname "$0")/.."

WATCH_DIRS="Sources/PCCUI Sources/PCCDesktop"
STAMP_FILE=$(mktemp)
touch "$STAMP_FILE"
APP_PID=""

cleanup() {
    [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null || true
    rm -f "$STAMP_FILE"
}
trap cleanup EXIT INT TERM

build_and_launch() {
    [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null || true
    echo "[dev-dashboard] building…"
    if swift build --product PCCDesktop; then
        echo "[dev-dashboard] launching…"
        .build/debug/PCCDesktop &
        APP_PID=$!
    else
        echo "[dev-dashboard] build failed — fix the error and save again"
        APP_PID=""
    fi
}

build_and_launch

while true; do
    sleep 1
    if [ -n "$(find $WATCH_DIRS -type f -name '*.swift' -newer "$STAMP_FILE" 2>/dev/null)" ]; then
        touch "$STAMP_FILE"
        build_and_launch
    fi
    # If the window was closed by hand, don't keep respawning it silently —
    # wait for the next source change instead.
    if [ -n "$APP_PID" ] && ! kill -0 "$APP_PID" 2>/dev/null; then
        APP_PID=""
    fi
done
