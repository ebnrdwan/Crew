#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Crew GitHub Project Sync  v0.1.0
# ─────────────────────────────────────────────────────────────
# Two modes:
#
#   create         Create a draft item on a Projects v2 board
#                  AND set initial Status field. Emits item_id.
#
#   update-status  Update Status field on an existing item.
#                  Item ID + new logical state required.
#
# Logical states map to board options via .crew/config.yaml
# (populated by github-project-fields.sh).
#
# Requirements:
#   gh CLI authenticated with project + repo scopes:
#     gh auth login --scopes project,repo
#
# Usage:
#   create:
#     ./github-project-sync.sh create \
#       --title          "[Crew][Feature] login: PHASE 1" \
#       --body-file      /tmp/crew-card.md \
#       --project-number 5 \
#       --project-node-id PVT_kwDO... \
#       --status-field-id PVTSSF_lADO... \
#       --status-option-id f75ad846-... \
#       [--owner ebnrdwan]   (default: auto-detect)
#       [--assignee user]
#       [--priority P1]
#       [--size S]
#
#   update-status:
#     ./github-project-sync.sh update-status \
#       --project-node-id PVT_kwDO... \
#       --item-id         PVTI_lADO... \
#       --status-field-id PVTSSF_lADO... \
#       --status-option-id 47fc9ee4-...
#
# Exit codes:
#   0  success
#   1  bad arguments
#   2  gh CLI not authenticated
#   3  not a GitHub repo (issue fallback only)
#   4  GraphQL / project operation failed
# ─────────────────────────────────────────────────────────────
set -euo pipefail

MODE="${1:-}"
shift || true

[[ -z "$MODE" ]] && { echo "❌  First arg must be 'create' or 'update-status'" >&2; exit 1; }

# ── Defaults ──────────────────────────────────────────────────
TITLE=""
BODY_FILE=""
PROJECT_NUMBER="0"
PROJECT_NODE_ID=""
ITEM_ID=""
STATUS_FIELD_ID=""
STATUS_OPTION_ID=""
OWNER=""
ASSIGNEE=""
PRIORITY=""
SIZE=""
EPIC=""
SPRINT=""
STORY_POINTS=""
SOURCE=""
PARENT_STORY=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --title)             TITLE="$2";             shift 2 ;;
    --body-file)         BODY_FILE="$2";         shift 2 ;;
    --project-number)    PROJECT_NUMBER="$2";    shift 2 ;;
    --project-node-id)   PROJECT_NODE_ID="$2";   shift 2 ;;
    --item-id)           ITEM_ID="$2";           shift 2 ;;
    --status-field-id)   STATUS_FIELD_ID="$2";   shift 2 ;;
    --status-option-id)  STATUS_OPTION_ID="$2";  shift 2 ;;
    --owner)             OWNER="$2";             shift 2 ;;
    --assignee)          ASSIGNEE="$2";          shift 2 ;;
    --priority)          PRIORITY="$2";          shift 2 ;;
    --size)              SIZE="$2";              shift 2 ;;
    --epic)              EPIC="$2";              shift 2 ;;
    --sprint)            SPRINT="$2";            shift 2 ;;
    --story-points)      STORY_POINTS="$2";      shift 2 ;;
    --source)            SOURCE="$2";            shift 2 ;;
    --parent-story)      PARENT_STORY="$2";      shift 2 ;;
    --dry-run)           DRY_RUN=true;           shift   ;;
    *) echo "❌  Unknown option: $1" >&2; exit 1   ;;
  esac
done

# ── Pre-flight: gh CLI ────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  echo "❌  gh CLI not found. Install: https://cli.github.com" >&2
  exit 2
fi

if ! gh auth status &>/dev/null; then
  echo "❌  gh CLI not authenticated. Run: gh auth login --scopes project,repo" >&2
  exit 2
fi

# ── Resolve owner if missing ──────────────────────────────────
if [[ -z "$OWNER" ]]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  if [[ -n "$REPO" ]]; then OWNER="${REPO%%/*}"; else OWNER="@me"; fi
fi

# ─────────────────────────────────────────────────────────────
# MODE: update-status
# ─────────────────────────────────────────────────────────────
if [[ "$MODE" == "update-status" ]]; then
  [[ -z "$PROJECT_NODE_ID"  ]] && { echo "❌  --project-node-id required"  >&2; exit 1; }
  [[ -z "$ITEM_ID"          ]] && { echo "❌  --item-id required"          >&2; exit 1; }
  [[ -z "$STATUS_FIELD_ID"  ]] && { echo "❌  --status-field-id required"  >&2; exit 1; }
  [[ -z "$STATUS_OPTION_ID" ]] && { echo "❌  --status-option-id required" >&2; exit 1; }

  if $DRY_RUN; then
    echo "DRY RUN: would set Status of item $ITEM_ID to option $STATUS_OPTION_ID"
    exit 0
  fi

  RESULT=$(gh api graphql -f query="mutation {
    updateProjectV2ItemFieldValue(input: {
      projectId: \"$PROJECT_NODE_ID\"
      itemId:    \"$ITEM_ID\"
      fieldId:   \"$STATUS_FIELD_ID\"
      value: { singleSelectOptionId: \"$STATUS_OPTION_ID\" }
    }) {
      projectV2Item { id }
    }
  }" 2>&1) || {
    echo "❌  Failed to update status: $RESULT" >&2
    exit 4
  }

  echo "✓  Status updated for item $ITEM_ID"
  exit 0
fi

# ─────────────────────────────────────────────────────────────
# MODE: create
# ─────────────────────────────────────────────────────────────
if [[ "$MODE" != "create" ]]; then
  echo "❌  Unknown mode: $MODE (expected 'create' or 'update-status')" >&2
  exit 1
fi

[[ -z "$TITLE"          ]] && { echo "❌  --title is required"          >&2; exit 1; }
[[ -z "$BODY_FILE"      ]] && { echo "❌  --body-file is required"      >&2; exit 1; }
[[ -f "$BODY_FILE"      ]] || { echo "❌  Body file not found: $BODY_FILE" >&2; exit 1; }
[[ "$PROJECT_NUMBER" == "0" ]] && { echo "❌  --project-number required for create" >&2; exit 1; }

BODY=$(cat "$BODY_FILE")

if $DRY_RUN; then
  cat <<EOF
════════════════════════════════════════
  DRY RUN — no card created
════════════════════════════════════════
  Mode:           create draft item
  Project:        #$PROJECT_NUMBER
  Owner:          $OWNER
  Title:          $TITLE
  Status option:  ${STATUS_OPTION_ID:-(none — will not set)}
  Assignee:       ${ASSIGNEE:-(none)}
  Priority:       ${PRIORITY:-(none)}
  Size:           ${SIZE:-(none)}
── Body ────────────────────────────────
EOF
  cat "$BODY_FILE"
  echo "════════════════════════════════════════"
  exit 0
fi

# ── Create the draft item ─────────────────────────────────────
RESULT=$(gh project item-create "$PROJECT_NUMBER" \
  --owner "$OWNER" \
  --title "$TITLE" \
  --body  "$BODY"  \
  --format json 2>&1) || {
  echo "❌  Failed to create project item: $RESULT" >&2
  exit 4
}

ITEM_URL=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || true)
NEW_ITEM_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)

[[ -z "$NEW_ITEM_ID" ]] && { echo "❌  Could not parse new item ID from gh response" >&2; exit 4; }

echo "✓  Draft item created on project #$PROJECT_NUMBER"
[[ -n "$ITEM_URL" ]] && echo "   $ITEM_URL"

# ── Set Status field if provided ──────────────────────────────
if [[ -n "$STATUS_FIELD_ID" && -n "$STATUS_OPTION_ID" && -n "$PROJECT_NODE_ID" ]]; then
  STATUS_RESULT=$(gh api graphql -f query="mutation {
    updateProjectV2ItemFieldValue(input: {
      projectId: \"$PROJECT_NODE_ID\"
      itemId:    \"$NEW_ITEM_ID\"
      fieldId:   \"$STATUS_FIELD_ID\"
      value: { singleSelectOptionId: \"$STATUS_OPTION_ID\" }
    }) {
      projectV2Item { id }
    }
  }" 2>&1) || {
    echo "  ⚠  Could not set initial Status: $STATUS_RESULT" >&2
  }
  if echo "$STATUS_RESULT" | grep -q '"id"'; then
    echo "  ✓ Initial Status set"
  fi
fi

# ── Set Priority / Size / Epic / Sprint / Source / Parent Story / Points / Assignee ─
if [[ -n "$PRIORITY" || -n "$SIZE" || -n "$ASSIGNEE" || -n "$EPIC" || -n "$SPRINT" || -n "$STORY_POINTS" || -n "$SOURCE" || -n "$PARENT_STORY" ]]; then
  FIELDS_JSON=$(gh project field-list "$PROJECT_NUMBER" \
    --owner "$OWNER" --format json 2>/dev/null || true)

  if [[ -n "$FIELDS_JSON" && -n "$PROJECT_NODE_ID" ]]; then
    export FIELDS_JSON PROJECT_NODE_ID NEW_ITEM_ID PRIORITY SIZE ASSIGNEE EPIC SPRINT STORY_POINTS SOURCE PARENT_STORY
    python3 - <<'PYEOF'
import json, os, subprocess, sys

data = json.loads(os.environ.get('FIELDS_JSON', '{}'))
item_id = os.environ['NEW_ITEM_ID']
proj_id = os.environ['PROJECT_NODE_ID']

def find_field(name):
    """Return the field dict whose name matches case-insensitively, or None."""
    for f in data.get('fields', []):
        if f.get('name', '').lower() == name.lower():
            return f
    return None

def set_select(field_name, want):
    """Set a single-select field by matching option name."""
    if not want:
        return
    f = find_field(field_name)
    if not f:
        return  # field doesn't exist on this board — silent skip
    for opt in f.get('options', []):
        if opt['name'].lower() == want.lower():
            r = subprocess.run([
                'gh', 'project', 'item-edit',
                '--id', item_id,
                '--project-id', proj_id,
                '--field-id', f['id'],
                '--single-select-option-id', opt['id']
            ], capture_output=True, text=True)
            if r.returncode == 0:
                print(f"  ✓ {field_name} → {opt['name']}")
            else:
                print(f"  ⚠ {field_name} failed: {r.stderr.strip()}", file=sys.stderr)
            return
    # No matching option — warn user; don't auto-create (not all teams want that)
    print(f"  ⚠ {field_name} option '{want}' not found on board. Add it manually or "
          f"switch the field to a text type.", file=sys.stderr)

def set_text(field_name, want):
    """Set a text field directly."""
    if not want:
        return
    f = find_field(field_name)
    if not f:
        return
    r = subprocess.run([
        'gh', 'project', 'item-edit',
        '--id', item_id,
        '--project-id', proj_id,
        '--field-id', f['id'],
        '--text', want
    ], capture_output=True, text=True)
    if r.returncode == 0:
        print(f"  ✓ {field_name} → {want}")
    else:
        print(f"  ⚠ {field_name} failed: {r.stderr.strip()}", file=sys.stderr)

def set_number(field_name, want):
    if not want:
        return
    f = find_field(field_name)
    if not f:
        return
    try:
        n = float(want)
    except (TypeError, ValueError):
        print(f"  ⚠ {field_name}: '{want}' not numeric", file=sys.stderr)
        return
    r = subprocess.run([
        'gh', 'project', 'item-edit',
        '--id', item_id,
        '--project-id', proj_id,
        '--field-id', f['id'],
        '--number', str(n)
    ], capture_output=True, text=True)
    if r.returncode == 0:
        print(f"  ✓ {field_name} → {n}")
    else:
        print(f"  ⚠ {field_name} failed: {r.stderr.strip()}", file=sys.stderr)

def set_smart(field_name, want):
    """Try single-select first; fall back to text. Lets users pick either field type."""
    if not want:
        return
    f = find_field(field_name)
    if not f:
        return
    field_type = (f.get('type') or '').upper()
    if 'SINGLE_SELECT' in field_type:
        set_select(field_name, want)
    elif 'TEXT' in field_type or field_type == 'PROJECT_V2_FIELD':
        set_text(field_name, want)
    else:
        # Iteration / Date / unknown — can't auto-set without more logic.
        print(f"  ⚠ {field_name}: field type '{field_type}' not supported for "
              f"auto-set. Set manually or use a Text/Single-select field.", file=sys.stderr)

# Hard-coded single-select fields (well-known)
set_select('Priority', os.environ.get('PRIORITY', ''))
set_select('Size',     os.environ.get('SIZE', ''))

# Hierarchy fields — try single-select OR text (whichever the board has)
set_smart('Epic',         os.environ.get('EPIC', ''))
set_smart('Sprint',       os.environ.get('SPRINT', ''))
set_text ('Source',       os.environ.get('SOURCE', ''))
set_text ('Parent Story', os.environ.get('PARENT_STORY', ''))
set_number('Story Points', os.environ.get('STORY_POINTS', ''))

# Assignee via GraphQL on draft issue content
assignee = os.environ.get('ASSIGNEE', '')
if assignee:
    user_id = subprocess.run(
        ['gh', 'api', 'graphql', '-f',
         f'query=query {{ user(login: "{assignee}") {{ id }} }}',
         '-q', '.data.user.id'],
        capture_output=True, text=True
    ).stdout.strip()
    if user_id:
        draft_id = subprocess.run(
            ['gh', 'api', 'graphql', '-f',
             f'query=query {{ node(id: "{item_id}") {{ ... on ProjectV2Item {{ content {{ ... on DraftIssue {{ id }} }} }} }} }}',
             '-q', '.data.node.content.id'],
            capture_output=True, text=True
        ).stdout.strip()
        if draft_id:
            subprocess.run(
                ['gh', 'api', 'graphql', '-f',
                 f'query=mutation {{ updateProjectV2DraftIssue(input: {{ draftIssueId: "{draft_id}", assigneeIds: ["{user_id}"] }}) {{ draftIssue {{ assignees(first: 1) {{ nodes {{ login }} }} }} }} }}'],
                capture_output=True, text=True
            )
            print(f"  ✓ Assignee → {assignee}")
PYEOF
  fi
fi

echo ""
echo "ITEM_ID=$NEW_ITEM_ID"
echo "ITEM_URL=$ITEM_URL"
