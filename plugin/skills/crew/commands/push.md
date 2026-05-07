# /crew push — GitHub Projects Sync

Creates or updates a draft card on a GitHub Projects v2 board for the current feature. Smart: detects whether a card already exists for this feature and chooses **create** vs **update-status** automatically.

Mirrors Gang's `/gang push` pattern but adapted for Crew's continuous-flow model: **one live card per feature** whose Status field tracks the current phase, instead of two discrete cards per evaluation.

> **Cardinality + no-duplication design:** see [`hierarchy-mapping.md`](../references/hierarchy-mapping.md) for the canonical rules — ONE card per shippable unit (story / feature / enhancement / bug / spike); epics, sprints, and tasks NEVER get their own cards. Identity = `feature_id`; the cache file `.crew/github-cards.yaml` prevents duplicates across all entry points (`/crew feature`, `/crew drive`, `/crew gang-import`, `/crew gaps`, phase auto-triggers, manual `/crew push`).

---

## Prerequisites

- `gh` CLI installed and authenticated with `project` and `repo` scopes:
  ```
  gh auth login --scopes project,repo
  ```
- `.crew/config.yaml` exists with at least one entry under `github.projects[]`. If not, suggest running `/crew setup-mcp github` or directly populate the config.
- A current feature is set in `.crew/current-feature.yaml`. If not, the command can target any feature listed in `.crew/roadmap.yaml` (ask the user).

---

## Step 0 — Load state

1. Read `.crew/current-phase.yaml` → `phase`, `project_type`
2. Read `.crew/current-feature.yaml` → `feature_id`, `card_type` (default `feature`)
3. Read `.crew/roadmap.yaml` → look up the entry for `feature_id`
4. Read `.crew/config.yaml` → load `github.enabled` and `github.projects[]`
5. Read `.crew/github-cards.yaml` (create if missing) → look up the existing card for `feature_id`, if any

If `github.enabled: false` ask the user:
> GitHub integration is disabled. Enable it now and continue?

If yes, set `enabled: true` and proceed. If no, exit gracefully.

If `github.projects[]` is empty, run the **Board discovery** sub-flow below.

---

## Step 1 — Determine logical status from current phase

Use the mapping in `.crew/config.yaml` under `github.phase_to_logical_status`:

```yaml
github:
  phase_to_logical_status:
    "1":    "Planned"      # Strategy
    "2":    "Planned"      # Design
    "2.25": "Planned"      # Hi-fi (optional)
    "2.5":  "Planned"      # Contract
    "3":    "Building"     # Implementation
    "4":    "In Review"    # Quality
    "5":    "Shipped"      # Launch (after deploy success)
    "6":    "Shipped"      # Enhancement
```

**Special case:** Phase 5 maps to `Shipped` *only after `/crew deploy` succeeds*. If Phase 5 is set but deploy hasn't run yet, treat as `In Review`. Read `.crew/current-feature.yaml#deploy_status` if present.

The result is `{logical_status}` — one of `Planned`, `Building`, `In Review`, `Shipped`.

---

## Step 2 — Resolve target boards

Load `github.projects[]` from `.crew/config.yaml`. Each entry has:

```yaml
- project_number: 5
  project_node_id: PVT_kwDO...
  owner: ebnrdwan
  status_field_id: PVTSSF_lADO...
  logical_state_options:
    Planned:    {id: f75ad846-..., name: "Todo"}
    Building:   {id: 47fc9ee4-..., name: "In Progress"}
    "In Review": {id: 73a91a7e-..., name: "In Review"}
    Shipped:    {id: 98765432-..., name: "Done"}
```

**If the array has 1 entry** → use it directly.

**If the array has 2+ entries** → present `AskUserQuestion`:
- Header: "Push to which board(s)?"
- Options: each board by `"#{number} — {name}"`, plus `"All boards"`

`TARGET_BOARDS = [ selected ]`

---

## Step 3 — Create or update?

For each `board` in `TARGET_BOARDS`:

Look up `.crew/github-cards.yaml#features.{feature_id}.boards` — find the entry whose `project_number` matches `board.project_number`.

- **If found** → record exists, **mode = update-status**, use cached `item_id`.
- **If not found** → **mode = create**, will need to fill the card body and create the item.

---

## Step 4a — Mode: create

### Resolve the Status option ID for the current logical status

```
status_option_id = board.logical_state_options[logical_status].id
status_option_name = board.logical_state_options[logical_status].name
```

If the logical status has no mapping (e.g., the board didn't have an "In Review" option), warn:
> Board #{number} has no option mapped to '{logical_status}'. Card will be created without a Status field set; please map manually.

Set `status_option_id = ""` to skip the field set in the script.

### Fill the card body skeleton

Read `{plugin_root}/skills/crew/references/card-skeletons.md`. Locate the section matching `card_type`.

Fill placeholders:

| Placeholder | Source |
|---|---|
| `{feature_id}` | `current-feature.yaml` |
| `{phase_label}` | `current-phase.yaml` (e.g., "PHASE 3 BUILD") |
| `{logical_status}` | from Step 1 |
| `{YYYY-MM-DD HH:MM}` | now |
| `{scope_summary}` | `roadmap.yaml#features[id].description` |
| `{in_scope_items}` / `{out_of_scope_items}` | `roadmap.yaml#features[id].scope` |
| `{acceptance_criteria}` | `roadmap.yaml#features[id].acceptance_criteria` (markdown checklist) |
| `{pages_list}` | `roadmap.yaml#features[id].pages` |
| `{endpoints_list}` | `roadmap.yaml#features[id].endpoints` |
| `{api_contract_url}` | constructed from repo URL + `docs/api-contract.md` |
| `{conditions}` | `roadmap.yaml#features[id].source.conditions` (only if origin = gang and verdict = CONDITIONAL-GO) |
| `{source_origin}` | `roadmap.yaml#features[id].source.origin` (manual / gang / gaps) |
| `{gang_link_line}` | only when source.origin = gang; format: `**Gang origin:** [\`{slug}\`]({gang_url}) · verdict {verdict_badge} · imported via gang-bridge` |
| `{phase_N_check}` | from `current-feature.yaml#phase_status[N]`: `⏳ Pending` / `🟡 In progress` / `✅ Done` / `⏭ Skipped` |

**Hierarchy placeholders (NEW — see [hierarchy-mapping.md](../references/hierarchy-mapping.md)):**

| Placeholder | Source |
|---|---|
| `{epic_name}` | `roadmap.yaml#epics[].name` for the epic that owns this story |
| `{sprint_label}` | `roadmap.yaml#epics[].sprint` (or sprint name from a separate sprint table if your project uses one) |
| `{points}` | `roadmap.yaml#stories[id].points` (or `–` if not estimated) |
| `{priority}` | `roadmap.yaml#stories[id].priority` (P1 / P2 / P3) |
| `{parent_story_id}` | `roadmap.yaml#stories[id].parent_story` (or `–` for top-level stories) |
| `{tasks_checklist}` | from `current-feature.yaml#tasks[]` — see format below |

**Tasks checklist format**:

For each task in `current-feature.yaml#tasks[]`, render one line:

```
- [{x or space}] {task_id}: {title} (assigned: {agent}){completion_marker}
```

Where:
- `[x]` if `task.done == true`, else `[ ]`
- `{completion_marker}` is ` ✓ {YYYY-MM-DD}` if done, empty otherwise

Example:
```
- [x] T-01: Build LoginForm component (assigned: ui-engineer) ✓ 2026-05-08
- [ ] T-02: Add `/auth/login` endpoint (assigned: api-engineer)
```

Phase status defaults: phases before current phase = `✅ Done`, current phase = `🟡 In progress`, future phases = `⏳ Pending`.

Write the filled body to `/tmp/crew-card-{feature_id}.md`.

### Compose the title

```
[Crew][{Card_Type_Cap}] {feature_id}: {phase_label}
```

Examples:
- `[Crew][Feature] login: PHASE 3 BUILD`
- `[Crew][Bug] cart-checkout-error: PHASE 4 QUALITY`

### Run the sync script

```bash
bash {plugin_root}/scripts/github-project-sync.sh create \
  --title             "$TITLE" \
  --body-file         /tmp/crew-card-{feature_id}.md \
  --project-number    {board.project_number} \
  --project-node-id   {board.project_node_id} \
  --owner             {board.owner} \
  --status-field-id   {board.status_field_id} \
  --status-option-id  {status_option_id} \
  [--assignee     {github_user}] \
  [--priority     {P1|P2|P3}] \
  [--size         {S|M|L|XL}] \
  [--epic         {epic_name}] \
  [--sprint       {sprint_label}] \
  [--story-points {N}] \
  [--source       {manual|gang|gaps}] \
  [--parent-story {parent_feature_id}]
```

The `--epic` / `--sprint` / `--source` / `--parent-story` / `--story-points` flags map to **custom fields** on the GitHub Projects board. The script smart-detects the field type:

- If the board has an "Epic" Single-select field, the value is matched to an existing option (case-insensitive).
- If "Epic" is a Text field, the value is written directly.
- If the field doesn't exist on the board, the flag is silently ignored — no error, no card delay.

For the full mapping rationale see [`hierarchy-mapping.md`](../references/hierarchy-mapping.md).

Capture `ITEM_ID=...` and `ITEM_URL=...` from stdout.

### Cache the result

Append to `.crew/github-cards.yaml`:

```yaml
features:
  {feature_id}:
    card_type: feature
    boards:
      - project_number: 5
        project_node_id: PVT_kwDO...
        item_id: PVTI_lADO...        # ← captured
        item_url: https://github.com/users/ebnrdwan/projects/5/views/1?pane=item&itemId=...
        last_status: Planned
        last_phase: "1"
        created_at: 2026-05-07T22:00:00Z
        updated_at: 2026-05-07T22:00:00Z
```

---

## Step 4b — Mode: update-status

```bash
bash {plugin_root}/scripts/github-project-sync.sh update-status \
  --project-node-id   {board.project_node_id} \
  --item-id           {cached.item_id} \
  --status-field-id   {board.status_field_id} \
  --status-option-id  {status_option_id}
```

If the script returns 0, update the cache:

```yaml
features:
  {feature_id}:
    boards:
      - project_number: 5
        item_id: PVTI_lADO...
        last_status: Building       # ← changed from Planned
        last_phase: "3"             # ← changed from "1"
        updated_at: 2026-05-07T22:30:00Z   # ← refreshed
```

If `last_status` is unchanged from the new logical status, **skip the API call** — the card is already in the right state. Print:
> Status already '{logical_status}' on board #{number}; nothing to update.

---

## Step 5 — Optional: update the card body

If `config.github.update_body_on_phase_change` is true (default: `false` to minimise GraphQL load), regenerate the body using the skeleton with new `{phase_N_check}` values, then call:

```bash
gh api graphql -f query='mutation {
  updateProjectV2DraftIssue(input: {
    draftIssueId: "{draft_issue_id}"
    body: "{new_body}"
  }) { draftIssue { id } }
}'
```

Note: `draft_issue_id` is *not* the same as `item_id`. Resolve it on first update:

```graphql
query { node(id: "{item_id}") { ... on ProjectV2Item { content { ... on DraftIssue { id } } } } }
```

Cache `draft_issue_id` in `.crew/github-cards.yaml` after first lookup so subsequent updates skip the lookup.

---

## Board discovery sub-flow

If `github.projects[]` is empty:

1. Run `gh project list --owner {owner} --format json` (or `--owner @me` if no repo)
2. Show boards in an `AskUserQuestion` multi-select
3. For each selected board, run:

   ```bash
   bash {plugin_root}/scripts/github-project-fields.sh \
     --project-number {N} \
     --owner {owner}
   ```

   This emits JSON with the discovered Status field + the fuzzy-matched logical state mapping. Exit code 4 means some logical states are unmapped — present them for manual mapping.

4. Append each board to `.crew/config.yaml#github.projects[]` with the discovered IDs and the mapping from step 3.

---

## Auto-trigger points

These are the places in Crew's flow where `/crew push` is called automatically (via the SKILL.md orchestrator). Each trigger is wired into the corresponding command file — `feature.md`, `drive.md`, `gaps.md`, `gang-import.md` — at the noted step.

| Trigger | Mode | Logical status | Card type | Wired in |
|---|---|---|---|---|
| `/crew feature {name}` | create | Planned | `feature` | `feature.md` Step 2.5 |
| `/crew gang-import {slug}` | create | Planned | `feature` (with `gang_link_line`) | `gang-import.md` Step 7 |
| `/crew drive` Step 1.6 (after feature input) | create | Planned | `feature` | `drive.md` Step 1.6 |
| `/crew gaps` Phase 3 (per fix or per batch) | create | Building | `enhancement` | `gaps.md` Phase 3 step 8 |
| `/crew drive` Phase 5 start (build) | update-status | Building | — | `drive.md` Phase 5 |
| Phase 2.5 → Phase 3 transition (any path) | update-status | Building | — | phase orchestrator |
| `/crew drive` Phase 6 start (QA) | update-status | In Review | — | `drive.md` Phase 6 |
| Phase 3 → Phase 4 transition (any path) | update-status | In Review | — | phase orchestrator |
| `/crew deploy` succeeds | update-status | Shipped | — | `deploy.md` |
| `/crew drive` Completion (after merge + successful deploy) | update-status | Shipped | — | `drive.md` Completion step 4 |
| Phase 4 → Phase 5 transition (without deploy) | update-status | In Review (unchanged; no-op) | — | phase orchestrator |

**Card type rules:**
- Default: `feature` (covers `/crew feature`, `/crew drive`, `/crew gang-import`)
- `gaps`: always `enhancement` (gap fixes are improvements, not new builds)
- Manual override: set `current-feature.yaml#card_type` to one of `feature` / `enhancement` / `bug` / `infra` / `spike` before running `/crew push`

**Disabling auto-triggers:**

If `config.github.auto_push: false` (default: `true`) the auto-triggers are suppressed — the user must run `/crew push` manually at each transition. Useful when the user wants to push selectively (e.g., only at major milestones, not every phase change).

---

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `gh CLI not authenticated` (exit 2) | Missing scopes | `gh auth login --scopes project,repo` |
| `Project #N not found` | Wrong project number or owner | `gh project list --owner {owner}` |
| `no Status field found` | Board has no Status field | Add one in GitHub Projects UI; re-run discovery |
| `unmapped_states` non-empty | Board option names don't match patterns | Edit `.crew/config.yaml#github.projects[].logical_state_options` manually |
| `Failed to update status: ... permission denied` | Token lacks `project` scope | `gh auth refresh -s project` |
| `Status already '{logical_status}'` | No actual phase change | Not an error — silent skip |
