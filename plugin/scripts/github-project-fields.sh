#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Crew GitHub Project Field Discovery  v0.1.0
# ─────────────────────────────────────────────────────────────
# Discovers a GitHub Projects v2 board's Status field and its
# option IDs, then fuzzy-maps them to Crew's 4 logical states:
#
#   Planned   → "todo", "backlog", "planned", "ready"
#   Building  → "progress", "doing", "build", "wip"
#   In Review → "review", "qa", "testing", "verify"
#   Shipped   → "done", "shipped", "complete", "closed"
#
# Output: JSON to stdout with the discovered mapping for
# Crew to cache in .crew/config.yaml under github.projects[].
#
# Usage:
#   ./github-project-fields.sh \
#     --project-number 5 \
#     [--owner ebnrdwan]   (default: auto-detect)
#
# Exit codes:
#   0  success
#   1  bad arguments
#   2  gh CLI not authenticated / missing scope
#   3  project not found or no Status field on board
#   4  unmapped status options (output still emitted; user must edit)
# ─────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT_NUMBER=""
OWNER=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --project-number) PROJECT_NUMBER="$2"; shift 2 ;;
    --owner)          OWNER="$2";          shift 2 ;;
    *) echo "❌  Unknown option: $1" >&2; exit 1   ;;
  esac
done

[[ -z "$PROJECT_NUMBER" ]] && { echo "❌  --project-number is required" >&2; exit 1; }

if ! gh auth status &>/dev/null; then
  echo "❌  gh CLI is not authenticated. Run: gh auth login --scopes project,repo" >&2
  exit 2
fi

# ── Resolve owner ─────────────────────────────────────────────
if [[ -z "$OWNER" ]]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  if [[ -n "$REPO" ]]; then
    OWNER="${REPO%%/*}"
  else
    OWNER="@me"
  fi
fi

# ── Get project node ID and fields ────────────────────────────
PROJECT_NODE_ID=$(gh project view "$PROJECT_NUMBER" \
  --owner "$OWNER" --format json -q '.id' 2>/dev/null || true)

if [[ -z "$PROJECT_NODE_ID" ]]; then
  echo "❌  Project #$PROJECT_NUMBER not found for owner '$OWNER'" >&2
  echo "    Check: gh project list --owner $OWNER" >&2
  exit 3
fi

FIELDS_JSON=$(gh project field-list "$PROJECT_NUMBER" \
  --owner "$OWNER" --format json 2>/dev/null || true)

if [[ -z "$FIELDS_JSON" ]]; then
  echo "❌  Could not fetch fields for project #$PROJECT_NUMBER" >&2
  exit 3
fi

# ── Fuzzy-match Status options to Crew's 4 logical states ─────
# Pass FIELDS_JSON via env var because heredoc claims stdin.
export FIELDS_JSON
python3 - "$PROJECT_NODE_ID" "$PROJECT_NUMBER" "$OWNER" <<'PYEOF'
import json, sys, os

project_node_id = sys.argv[1]
project_number  = sys.argv[2]
owner           = sys.argv[3]

fields_json = os.environ.get('FIELDS_JSON', '')
if not fields_json.strip():
    print(json.dumps({"error": "no fields JSON in FIELDS_JSON env var"}))
    sys.exit(3)

data = json.loads(fields_json)

# Logical state → list of substring patterns (lowercase, ordered by preference)
LOGICAL_STATES = {
    "Planned":   ["todo", "backlog", "planned", "ready", "to do", "new"],
    "Building":  ["in progress", "progress", "doing", "build", "wip", "active"],
    "In Review": ["in review", "review", "qa", "testing", "verify", "validation"],
    "Shipped":   ["done", "shipped", "complete", "completed", "closed", "released"],
}

status_field = None
for f in data.get('fields', []):
    if f.get('name', '').lower() == 'status':
        status_field = f
        break

if not status_field:
    print(json.dumps({
        "error": "no Status field found on this board",
        "hint":  "Add a Status field via GitHub Projects UI, then re-run."
    }))
    sys.exit(3)

options = status_field.get('options', [])
options_by_id = {opt['id']: opt['name'] for opt in options}

# Fuzzy match each logical state to the best option
mapping = {}
unmapped = []

for logical, patterns in LOGICAL_STATES.items():
    matched_id = None
    matched_name = None
    for opt in options:
        opt_name_lower = opt['name'].lower()
        for pat in patterns:
            if pat in opt_name_lower:
                matched_id = opt['id']
                matched_name = opt['name']
                break
        if matched_id:
            break
    if matched_id:
        mapping[logical] = {"id": matched_id, "name": matched_name}
    else:
        unmapped.append(logical)
        mapping[logical] = None

result = {
    "project_number":  int(project_number),
    "project_node_id": project_node_id,
    "owner":           owner,
    "status_field": {
        "id":   status_field['id'],
        "name": status_field['name'],
    },
    "available_options": [{"id": o['id'], "name": o['name']} for o in options],
    "logical_state_mapping": mapping,
    "unmapped_states": unmapped,
}

print(json.dumps(result, indent=2))

# Exit 4 if anything unmapped — caller can choose to handle or ignore.
# The JSON has already been printed; caller reads stdout regardless.
if unmapped:
    sys.exit(4)
PYEOF
