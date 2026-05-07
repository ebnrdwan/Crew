#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Crew User Profile Set  v0.1.0
# ─────────────────────────────────────────────────────────────
# Records the user's knowledge level for one technology in
# .crew/profile.yaml (creating it if missing). Called by the
# model after AskUserQuestion returns the user's choice.
#
# Inputs:
#   --tech NAME         e.g. python, typescript, react-native
#   --level LEVEL       none | low | intermediate | high
#   [--context STR]     What we were doing when we asked, e.g.
#                        "service", "feature: user-auth"
#
# Side effect: writes .crew/profile.yaml. Recomputes flags
# (has_low_or_none, plain_english_required) at the top level.
#
# Output (JSON to stdout):
#   {
#     "tech":                     "python",
#     "level":                    "low",
#     "asked_at":                 "2026-05-08T...",
#     "has_low_or_none":          true,
#     "plain_english_required":   true,
#     "learning_mode_recommended": "detailed"
#   }
# ─────────────────────────────────────────────────────────────
set -euo pipefail

TECH=""
LEVEL=""
CONTEXT=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --tech)    TECH="$2";    shift 2 ;;
    --level)   LEVEL="$2";   shift 2 ;;
    --context) CONTEXT="$2"; shift 2 ;;
    *) echo "❌  Unknown option: $1" >&2; exit 3 ;;
  esac
done

[[ -z "$TECH"  ]] && { echo "❌  --tech required"  >&2; exit 3; }
[[ -z "$LEVEL" ]] && { echo "❌  --level required" >&2; exit 3; }

LEVEL_LOWER=$(echo "$LEVEL" | tr '[:upper:]' '[:lower:]')
case "$LEVEL_LOWER" in
  none|low|intermediate|high) ;;
  *) echo "❌  --level must be one of: none, low, intermediate, high" >&2; exit 3 ;;
esac

# ── Locate .crew root ─────────────────────────────────────────
CREW_ROOT=""
DIR="$(pwd)"
while [[ "$DIR" != "/" ]]; do
  if [[ -d "$DIR/.crew" ]]; then CREW_ROOT="$DIR/.crew"; break; fi
  DIR="$(dirname "$DIR")"
done

[[ -z "$CREW_ROOT" ]] && { echo '{"error":"no .crew root found"}' >&2; exit 3; }

PROFILE="$CREW_ROOT/profile.yaml"
export CREW_ROOT PROFILE TECH LEVEL_LOWER CONTEXT

python3 - <<'PYEOF'
import os, yaml, json, datetime

profile_path = os.environ['PROFILE']
tech    = os.environ['TECH']
level   = os.environ['LEVEL_LOWER']
context = os.environ.get('CONTEXT', '')

profile = {}
if os.path.exists(profile_path):
    try:
        with open(profile_path) as f:
            profile = yaml.safe_load(f) or {}
    except Exception:
        profile = {}

up = profile.setdefault('user_profile', {})
techs = up.setdefault('technologies', {})

now = datetime.datetime.now(datetime.timezone.utc).isoformat()
entry = techs.get(tech, {})
entry['level']    = level
entry['asked_at'] = now
contexts = entry.setdefault('contexts', [])
if context and context not in contexts:
    contexts.append(context)
techs[tech] = entry

# Recompute flags
has_low = any(
    (info.get('level') or '').lower() in ('low', 'none')
    for info in techs.values()
)
flags = up.setdefault('flags', {})
flags['has_low_or_none']         = has_low
flags['plain_english_required']  = has_low
flags['learning_mode_recommended'] = 'detailed' if has_low else None
flags['last_updated']            = now

with open(profile_path, 'w') as f:
    yaml.safe_dump(profile, f, sort_keys=False)

print(json.dumps({
    'tech':                       tech,
    'level':                      level,
    'asked_at':                   now,
    'has_low_or_none':            has_low,
    'plain_english_required':     has_low,
    'learning_mode_recommended':  flags['learning_mode_recommended'],
}, indent=2))
PYEOF
