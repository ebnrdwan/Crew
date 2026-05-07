#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Crew Budget Check  v0.1.0
# ─────────────────────────────────────────────────────────────
# Pre-dispatch gate: estimates whether the next operation will
# push session token usage past the stop threshold. If yes,
# writes a checkpoint to .crew/checkpoints/ and emits a
# scheduled-task instruction the caller (model) must execute.
#
# Inputs:
#   --op-type {key}     Operation type — looked up in
#                       .crew/config.yaml#usage.op_costs.
#   [--op-cost N]       Override estimate in tokens for this op.
#   [--feature-id ID]   Current feature (default: read from
#                       .crew/current-feature.yaml).
#   [--phase N]         Current phase (default: read from
#                       .crew/current-phase.yaml).
#   [--next-step LABEL] Step the caller is about to execute,
#                       used in the checkpoint for resume.
#
# Outputs (JSON to stdout):
#   {
#     "status": "ok" | "warn" | "stop",
#     "current_estimated_tokens": 4500000,
#     "after_op_tokens":          4570000,
#     "max_tokens":               5000000,
#     "percent_before":           90,
#     "percent_after":            91,
#     "warn_threshold":           90,
#     "stop_threshold":           98,
#     "checkpoint_path":          ".crew/checkpoints/2026-05-08T...yaml"  // only when stop
#     "schedule_at":              "2026-05-08T20:40:00Z"                  // only when stop
#     "schedule_command":         "/crew resume"                           // only when stop
#   }
#
# Exit codes:
#   0  ok      — caller may proceed
#   1  warn    — caller may proceed but should consider lighter mode
#   2  stop    — checkpoint written; caller MUST schedule resume task
#                via mcp__scheduled-tasks__create_scheduled_task and exit
#   3  config / state error
# ─────────────────────────────────────────────────────────────
set -euo pipefail

OP_TYPE=""
OP_COST_OVERRIDE=""
FEATURE_ID=""
PHASE=""
NEXT_STEP=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --op-type)     OP_TYPE="$2";        shift 2 ;;
    --op-cost)     OP_COST_OVERRIDE="$2"; shift 2 ;;
    --feature-id)  FEATURE_ID="$2";     shift 2 ;;
    --phase)       PHASE="$2";          shift 2 ;;
    --next-step)   NEXT_STEP="$2";      shift 2 ;;
    *) echo "❌  Unknown option: $1" >&2; exit 3 ;;
  esac
done

[[ -z "$OP_TYPE" ]] && { echo "❌  --op-type required" >&2; exit 3; }

# ── Locate .crew root (walk up from cwd) ──────────────────────
CREW_ROOT=""
DIR="$(pwd)"
while [[ "$DIR" != "/" ]]; do
  if [[ -d "$DIR/.crew" ]]; then CREW_ROOT="$DIR/.crew"; break; fi
  DIR="$(dirname "$DIR")"
done

if [[ -z "$CREW_ROOT" ]]; then
  echo '{"status":"ok","note":"no .crew root found; budget tracking disabled"}'
  exit 0
fi

CONFIG="$CREW_ROOT/config.yaml"
USAGE_STATE="$CREW_ROOT/usage-state.yaml"
CHECKPOINT_DIR="$CREW_ROOT/checkpoints"
mkdir -p "$CHECKPOINT_DIR"

# ── Run all logic in python (yaml parsing + datetime) ─────────
export OP_TYPE OP_COST_OVERRIDE FEATURE_ID PHASE NEXT_STEP CONFIG USAGE_STATE CHECKPOINT_DIR CREW_ROOT

python3 - <<'PYEOF'
import os, sys, json, yaml, datetime, hashlib

cfg_path     = os.environ['CONFIG']
state_path   = os.environ['USAGE_STATE']
ckpt_dir     = os.environ['CHECKPOINT_DIR']
crew_root    = os.environ['CREW_ROOT']
op_type      = os.environ['OP_TYPE']
op_override  = os.environ.get('OP_COST_OVERRIDE') or ''
feature_id   = os.environ.get('FEATURE_ID') or ''
phase        = os.environ.get('PHASE') or ''
next_step    = os.environ.get('NEXT_STEP') or ''

# ── Load config ──────────────────────────────────────────────
def load_yaml(path, default):
    if not os.path.exists(path):
        return default
    with open(path) as f:
        return yaml.safe_load(f) or default

cfg   = load_yaml(cfg_path, {})
state = load_yaml(state_path, {})

usage_cfg = (cfg.get('usage') or {})
if not usage_cfg.get('enabled', False):
    print(json.dumps({"status": "ok", "note": "usage tracking disabled in config"}))
    sys.exit(0)

# ── Defaults (Max-plan tuned) ─────────────────────────────────
defaults = {
    "max_tokens_per_session": 5_000_000,
    "warn_threshold_percent": 90,
    "stop_threshold_percent": 98,
    "reset_window":           "5h",          # "5h" | "1h" | "daily" | "custom:HH:MM"
    "resume_buffer_minutes":  10,
    "estimation_mode":        "static",
    "budget_scope":           "session",     # session | feature | both
    "op_costs": {
        "pm_architect_discovery":     80_000,
        "pm_architect_architecture":  60_000,
        "pm_architect_brd":           50_000,
        "ui_engineer_full_feature":   50_000,
        "api_engineer_full_feature":  45_000,
        "qa_engineer":                30_000,
        "pm_maestro_reviewer":        20_000,
        "code_reviewer":              25_000,
        "performance_optimizer":      30_000,
        "gap_finder_audit":           70_000,
        "ux_designer":                40_000,
        "dsl_generator":              15_000,
        "api_contract_architect":     35_000,
        "doc_writer":                 20_000,
        "feature_planner":            15_000,
        "product_strategist":         20_000,
        "light_dispatch":              8_000,
        "deep_dispatch":              25_000,
        "default":                    20_000,
    },
}

def get(key):
    return usage_cfg.get(key, defaults.get(key))

max_tokens = int(get("max_tokens_per_session"))
warn_pct   = float(get("warn_threshold_percent"))
stop_pct   = float(get("stop_threshold_percent"))
buffer_min = int(get("resume_buffer_minutes"))
reset_win  = str(get("reset_window"))
op_costs   = {**defaults["op_costs"], **(usage_cfg.get('op_costs') or {})}

# ── Resolve op cost ──────────────────────────────────────────
if op_override:
    op_cost = int(op_override)
else:
    op_cost = int(op_costs.get(op_type, op_costs.get("default", 20_000)))

# ── Compute usage ────────────────────────────────────────────
session = state.get('session', {})
current_tokens = int(session.get('estimated_tokens_used', 0))
after_tokens   = current_tokens + op_cost
percent_before = round(current_tokens / max_tokens * 100, 2) if max_tokens else 0
percent_after  = round(after_tokens   / max_tokens * 100, 2) if max_tokens else 0

# ── Determine status ─────────────────────────────────────────
if percent_after >= stop_pct:
    status = "stop"
elif percent_after >= warn_pct:
    status = "warn"
else:
    status = "ok"

result = {
    "status":                   status,
    "op_type":                  op_type,
    "op_cost":                  op_cost,
    "current_estimated_tokens": current_tokens,
    "after_op_tokens":          after_tokens,
    "max_tokens":               max_tokens,
    "percent_before":           percent_before,
    "percent_after":            percent_after,
    "warn_threshold":           warn_pct,
    "stop_threshold":           stop_pct,
}

# ── On stop: write checkpoint + compute resume schedule ──────
if status == "stop":
    now = datetime.datetime.now(datetime.timezone.utc)

    # Compute resume time
    raw_start = session.get('started')
    session_start = now
    if isinstance(raw_start, str):
        try:
            session_start = datetime.datetime.fromisoformat(raw_start.replace('Z', '+00:00'))
        except Exception:
            session_start = now
    elif isinstance(raw_start, datetime.datetime):
        session_start = raw_start if raw_start.tzinfo else raw_start.replace(tzinfo=datetime.timezone.utc)
    elif isinstance(raw_start, datetime.date):
        # bare date — promote to midnight UTC
        session_start = datetime.datetime(raw_start.year, raw_start.month, raw_start.day,
                                          tzinfo=datetime.timezone.utc)

    if reset_win.endswith('h'):
        hours = int(reset_win[:-1])
        reset_at = session_start + datetime.timedelta(hours=hours)
    elif reset_win == 'hourly':
        # next top of hour
        reset_at = (now.replace(minute=0, second=0, microsecond=0)
                    + datetime.timedelta(hours=1))
    elif reset_win == 'daily':
        reset_at = (now.replace(hour=0, minute=0, second=0, microsecond=0)
                    + datetime.timedelta(days=1))
    elif reset_win.startswith('custom:'):
        hh, mm = reset_win.split(':')[1:]
        reset_at = now.replace(hour=int(hh), minute=int(mm), second=0, microsecond=0)
        if reset_at <= now:
            reset_at += datetime.timedelta(days=1)
    else:
        reset_at = now + datetime.timedelta(hours=5)

    # Never schedule in the past
    if reset_at <= now:
        reset_at = now + datetime.timedelta(hours=1)

    schedule_at = reset_at + datetime.timedelta(minutes=buffer_min)

    # Write checkpoint
    ckpt_id = now.strftime("%Y%m%dT%H%M%SZ")
    if feature_id:
        ckpt_id += f"-{feature_id}"
    ckpt_path = f"{ckpt_dir}/{ckpt_id}.yaml"

    checkpoint = {
        "timestamp":               now.isoformat(),
        "reason":                  "budget_stop",
        "feature_id":              feature_id,
        "phase":                   phase,
        "next_step":               next_step,
        "estimated_tokens_used":   current_tokens,
        "blocked_op": {
            "op_type": op_type,
            "op_cost": op_cost,
        },
        "max_tokens":              max_tokens,
        "percent_used":            percent_before,
        "percent_after_blocked":   percent_after,
        "session_started":         session.get('started'),
        "reset_window":            reset_win,
        "scheduled_resume_at":     schedule_at.isoformat(),
        "schedule_command":        f"/crew resume {ckpt_id}",
    }
    with open(ckpt_path, 'w') as f:
        yaml.safe_dump(checkpoint, f, sort_keys=False)

    result["checkpoint_path"]  = os.path.relpath(ckpt_path, start=os.path.dirname(crew_root))
    result["checkpoint_id"]    = ckpt_id
    result["schedule_at"]      = schedule_at.isoformat()
    result["schedule_command"] = f"/crew resume {ckpt_id}"
    result["instructions_for_caller"] = (
        f"Call mcp__scheduled-tasks__create_scheduled_task with:\n"
        f"  prompt:    '/crew resume {ckpt_id}'\n"
        f"  schedule:  '{schedule_at.isoformat()}'\n"
        f"Then exit gracefully — do NOT proceed with the blocked op."
    )

print(json.dumps(result, indent=2))

# Exit codes: ok=0, warn=1, stop=2
sys.exit({"ok": 0, "warn": 1, "stop": 2}[status])
PYEOF
