#!/bin/zsh
# Phase 5a experiment hook. Claude Code runs this for a hook event and pipes a
# JSON object on stdin (session_id, cwd, hook_event_name, transcript_path, ...).
# We turn that into a tiny per-session status file the app can watch.
#
# The app will later ship an equivalent script; this one just proves the wiring:
# that hooks fire, that stdin carries cwd + event, and that we can key a status
# file by the project folder.

set -e

STATUS_DIR="${AI_CONTROL_STATUS_DIR:?AI_CONTROL_STATUS_DIR not set}"
mkdir -p "$STATUS_DIR"

# Read the whole stdin payload once.
payload="$(cat)"

cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty')"
event="$(printf '%s' "$payload" | jq -r '.hook_event_name // empty')"
session="$(printf '%s' "$payload" | jq -r '.session_id // empty')"

# Key the file by a hash of cwd so one file == one project folder, stable across
# events. (The app can recompute the same key, or just read cwd from the file.)
key="$(printf '%s' "$cwd" | shasum | cut -d' ' -f1)"

# Map the raw hook event to our coarse activity state.
case "$event" in
  UserPromptSubmit) state="working" ;;
  Stop)             state="awaitingInput" ;;
  SessionStart)     state="working" ;;
  SessionEnd)       state="stopped" ;;
  Notification)     state="awaitingInput" ;;
  *)                state="unknown" ;;
esac

# Write atomically (write temp, then move) so the watcher never sees a partial file.
tmp="$STATUS_DIR/.$key.tmp"
jq -n --arg cwd "$cwd" --arg event "$event" --arg state "$state" --arg session "$session" \
  '{cwd:$cwd, event:$event, state:$state, session:$session}' > "$tmp"
mv "$tmp" "$STATUS_DIR/$key.json"

# Also append to a log so the experiment can show the full event sequence.
printf '%s\t%s\t%s\n' "$event" "$state" "$cwd" >> "$STATUS_DIR/events.log"
