#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Crew Budget Log  v0.1.0
# ─────────────────────────────────────────────────────────────
# Records token usage for an operation in .crew/usage-state.yaml.
# Called AFTER an agent dispatch completes, with the model's
# best estimate of actual tokens consumed.
#
# Inputs:
#   --op-type {key}         Operation type (matches budget-check)
#   --tokens N              Estimated total tokens (input + output)
#   [--feature-id ID]       Current feature
#   [--phase N]             Current phase
#
# Side effects:
#   - Creates .crew/usage-state.yaml if missing
#   - Updates session.estimated_tokens_used += tokens
#   - Appends entry to session.log[]
#   - Initializes session.started on first call
#
# Outputs (JSON to stdout):
#   {
#     "session_total":  4_572_000,
#     "logged_tokens":  72_000,
#     "session_start":  "2026-05-08T15:30:00Z",
#     "log_entries":    47
#   }
# ─────────────────────────────────────────────────────────────
set -euo pipefail

OP_TYPE=""
TOKENS=""
FEATURE_ID=""
PHASE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --op-type)    OP_TYPE="$2";    shift 2 ;;
    --tokens)     TOKENS="$2";     shift 2 ;;
    --feature-id) FEATURE_ID="$2"; shift 2 ;;
    --phase)      PHASE="$2";      shift 2 ;;
    *) echo "❌  Unknown option: $1" >&2; exit 3 ;;
  esac
done

[[ -z "$OP_TYPE" ]] && { echo "❌  --op-type required" >&2; exit 3; }
[[ -z "$TOKENS"  ]] && { echo "❌  --tokens required"  >&2; exit 3; }

# ── Locate .crew root ─────────────────────────────────────────
CREW_ROOT=""
DIR="$(pwd)"
while [[ "$DIR" != "/" ]]; do
  if [[ -d "$DIR/.crew" ]]; then CREW_ROOT="$DIR/.crew"; break; fi
  DIR="$(dirname "$DIR")"
done

if [[ -z "$CREW_ROOT" ]]; then
  echo '{"note":"no .crew root found; log skipped"}'
  exit 0
fi

USAGE_STATE="$CREW_ROOT/usage-state.yaml"
export USAGE_STATE OP_TYPE TOKENS FEATURE_ID PHASE

python3 - <<'PYEOF'
import os, json, yaml, datetime

state_path = os.environ['USAGE_STATE']
op_type    = os.environ['OP_TYPE']
tokens     = int(os.environ['TOKENS'])
feature_id = os.environ.get('FEATURE_ID') or ''
phase      = os.environ.get('PHASE') or ''

state = {}
if os.path.exists(state_path):
    with open(state_path) as f:
        state = yaml.safe_load(f) or {}

session = state.setdefault('session', {})
now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()

session.setdefault('started', now_iso)
session['estimated_tokens_used'] = int(session.get('estimated_tokens_used', 0)) + tokens
session['last_updated'] = now_iso

log = session.setdefault('log', [])
log.append({
    'ts':         now_iso,
    'op':         op_type,
    'tokens':     tokens,
    'feature_id': feature_id,
    'phase':      phase,
})

with open(state_path, 'w') as f:
    yaml.safe_dump(state, f, sort_keys=False)

started = session['started']
if hasattr(started, 'isoformat'):
    started = started.isoformat()

print(json.dumps({
    "session_total":   session['estimated_tokens_used'],
    "logged_tokens":   tokens,
    "session_start":   started,
    "log_entries":     len(log),
}, indent=2))
PYEOF
