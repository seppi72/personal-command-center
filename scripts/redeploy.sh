#!/bin/sh
# The "change it at will and redeploy" entrypoint for running Personal
# Command Center on this Mac for daily use — see docs/adr/0010. Safe to
# run repeatedly: the first run also sets up the LaunchAgent and secrets
# file; every run after that just rebuilds and restarts/refreshes what's
# already there.
#
# Usage: ./scripts/redeploy.sh

set -eu
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

LABEL="com.seppi72.personal-command-center"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
ENV_FILE="$HOME/.pcc.env"
LOG_DIR="$HOME/Library/Logs/personal-command-center"
APP_BUNDLE="/Applications/PCCDesktop.app"
DOMAIN_TARGET="gui/$(id -u)/$LABEL"

# --- one-time: backend secrets file, outside the repo (ADR-0010, Q6/Q12) --
if [ ! -f "$ENV_FILE" ]; then
    echo "[redeploy] creating $ENV_FILE"
    cat >"$ENV_FILE" <<'EOF'
# Personal Command Center backend secrets — sourced by
# scripts/run-backend.sh, kept outside the repo entirely (ADR-0010).
#
# AUTH_TOKENS is deliberately left as the literal "mac-token" default that
# PCCUI's HTTP clients and PCCDesktop's own fallback already use — the
# backend only listens on 127.0.0.1 (ADR-0010, Q4), so randomizing it buys
# no real protection today. Revisit this the day the backend is exposed
# beyond this Mac.
AUTH_TOKENS=mac-token

# CALDAV_* intentionally left unset (ADR-0010, Q7) — Personal Commitments
# stays a documented no-op (see README's "CalDAV setup") until CalDAV is
# wired up separately with a real Apple ID + app-specific password.
EOF
    chmod 600 "$ENV_FILE"
fi
mkdir -p "$LOG_DIR"

# --- LaunchAgent plist (rewritten every run in case paths/label change) ---
cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$REPO_ROOT/scripts/run-backend.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$REPO_ROOT</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/backend.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/backend.error.log</string>
</dict>
</plist>
EOF

# --- rebuild (release — ADR-0010, Q3) --------------------------------------
echo "[redeploy] building App (release)…"
swift build -c release --product App
echo "[redeploy] building PCCDesktop (release)…"
swift build -c release --product PCCDesktop

# --- (re)start the backend service -----------------------------------------
if launchctl print "$DOMAIN_TARGET" >/dev/null 2>&1; then
    echo "[redeploy] restarting backend service…"
    launchctl kickstart -k "$DOMAIN_TARGET"
else
    echo "[redeploy] bootstrapping backend service…"
    launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
fi

# --- refresh the PCCDesktop.app bundle (ADR-0010, Q8/Q13) ------------------
echo "[redeploy] refreshing $APP_BUNDLE ..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$REPO_ROOT/scripts/PCCDesktop-Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$REPO_ROOT/.build/release/PCCDesktop" "$APP_BUNDLE/Contents/MacOS/PCCDesktop"

echo "[redeploy] done."
echo "[redeploy] backend status: launchctl print $DOMAIN_TARGET | grep state"
echo "[redeploy] backend logs:   $LOG_DIR/"
echo "[redeploy] quit and relaunch PCCDesktop.app (Applications/Spotlight) to pick up the new build."
