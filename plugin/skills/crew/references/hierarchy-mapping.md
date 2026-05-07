# Crew → GitHub Projects Hierarchy Mapping

How Crew's 4-level hierarchy (epic → sprint → story → task) maps onto GitHub Projects v2 boards **without creating duplicate cards** and while still preserving the relationships.

> **Sister docs:**
> - [`commands/push.md`](../commands/push.md) — runtime behaviour of `/crew push`
> - [`references/card-skeletons.md`](./card-skeletons.md) — body templates per card type

---

## The mapping

| Crew concept | GitHub representation | Rationale |
|---|---|---|
| **Epic** | Custom Single-select field on each card | An epic is a theme; stories under it ship, the epic itself doesn't. Group cards by Epic to see the theme view. |
| **Sprint** | **Iteration field** if the board has one, else Custom Single-select | Iteration is the native GH field type for timeboxes; fallback to single-select keeps it usable on plain boards. |
| **Story / Feature** | **The card itself** — one card per story | Stories are the unit teams ship. The board is a list of stories. |
| **Task** | Markdown checklist inside the card body | Tasks are how one engineer breaks down a story. Putting them on the board floods PM view with implementation detail. |
| **Status** | Status field (mapped from current phase) | One logical Status per story, updated as phase advances. See `card-skeletons.md`. |
| **Priority** | Custom Single-select field (P1 / P2 / P3) | Derived from RICE score or risk weight in roadmap. |
| **Story Points** | Custom Number field (if board has one) | Optional; populated from roadmap.yaml#stories[].points if present. |
| **Source** | Custom Text field | `manual` / `gang` / `gaps` — provenance, surface to stakeholders. |
| **Parent Story** | Custom Text field with parent `feature_id` | For nested stories (sub-stories of a larger one); empty when story is top-level. |

---

## The cardinality rule

> **ONE card per shippable unit (story / feature / enhancement / bug / spike).**
> Epics, sprints, and tasks NEVER get their own cards.

**Why:**

- Boards stay readable. 50 stories = 50 cards. NOT 50 stories + 10 epics + 5 sprints + 200 tasks = chaos.
- Hierarchy shows up via **grouping/filtering** — group by Epic in the Projects UI to see all stories under each epic; group by Sprint/Iteration for the current timebox.
- Tasks live in `.crew/current-feature.yaml#tasks[]` (Crew side) and as checkboxes inside the story card body (GitHub side). They don't pollute the board.
- Stakeholders see "what's shipping" (stories); engineers see "what's being worked on internally" (tasks in checklist).

---

## The no-duplication rule

> **Identity = `feature_id`.** The cache file `.crew/github-cards.yaml` is the single source of truth.

Every `/crew push` follows this decision tree:

```
1. Look up .crew/github-cards.yaml#features[{feature_id}].boards[{board_n}]

2. If entry exists with item_id:
     → mode = update
     → run: github-project-sync.sh update-status [+ optional field updates]
     → never create a second card

3. If no entry:
     → mode = create
     → run: github-project-sync.sh create
     → on success, append { project_number, item_id, item_url, ... } to cache
```

This works whether the push was triggered by:
- `/crew feature {name}` (Step 2.5)
- `/crew drive {name}` (Step 1.6)
- `/crew gang-import {slug}` (Step 7)
- `/crew gaps` (Phase 3 step 8)
- A phase transition (auto-trigger)
- Manual `/crew push`

All six paths produce a single card per feature_id, with subsequent pushes updating it.

### Drift detection

If the cache says a card exists but the actual GitHub item is missing (deleted in the UI), `update-status` will fail. The push command should detect that, warn the user, and offer to re-create:

```
⚠ Card item_id PVTI_lADO... no longer exists on board #5.
  Re-create the card? [Yes, create / No, remove from cache]
```

If the cache is **missing an entry** but a card with matching title already exists on the board (e.g. someone created it manually), creating again would duplicate. The script does NOT auto-detect this — it relies on the cache. To recover, manually link by editing `github-cards.yaml`:

```yaml
features:
  user-auth:
    card_type: feature
    boards:
      - project_number: 5
        project_node_id: PVT_kwDO...
        item_id: PVTI_lADO...        # paste from existing card URL
        last_status: Building
        last_phase: "3"
```

---

## Custom field auto-discovery

When `/crew setup-mcp github` runs, `crew-discover-board-fields` (planned, see [issue]) inspects the board for these custom fields and caches their IDs:

```yaml
# .crew/config.yaml#github.projects[N]
- project_number: 5
  status_field_id:    PVTSSF_lADO...
  priority_field_id:  PVTSSF_lADO...   # from "Priority" single-select
  size_field_id:      PVTSSF_lADO...   # from "Size" single-select
  epic_field_id:      PVTSSF_lADO...   # from "Epic" single-select; null if absent
  sprint_field_id:    PVTSSF_lADO...   # from "Sprint" or "Iteration"; null if absent
  sprint_field_type:  iteration         # iteration | single_select | text
  story_points_field_id: PVTSSF_lADO... # null if absent
  source_field_id:    PVTSSF_lADO...   # null if absent
  parent_story_field_id: PVTSSF_lADO...# null if absent
  logical_state_options:
    Planned:    {id: ..., name: "Todo"}
    Building:   {id: ..., name: "In Progress"}
    "In Review": {id: ..., name: "In Review"}
    Shipped:    {id: ..., name: "Done"}
```

Fields not present on the board are skipped silently — push still works, the card just doesn't get those metadata bits.

---

## Epic / Sprint option creation

For Single-select fields, **options are not auto-created**. If `roadmap.yaml` has Epic "Authentication" but the GitHub board's Epic field doesn't have that option yet, the script falls back to:

1. **If the board has Sprint as a single-select**: log a warning, leave the field unset on the card; tell the user to add the option manually.

2. **If the board has Sprint as Iteration**: Iteration values are dates, not user-defined names. Crew maps Sprint name → Iteration that contains today's date (or the sprint's start date if recorded in roadmap).

3. **For Text fields**: write the value as-is.

A future v0.2 enhancement: auto-create missing Single-select options via `addProjectV2DraftIssueAssignee` mutation. For v0.1, prefer Text fields if you want zero-friction ingestion.

**Recommendation:** in your project's GitHub Projects board, set Epic and Sprint as **Text fields** initially. They're the most flexible. If your team prefers controlled vocabularies, switch to Single-select once the epic list stabilises (usually after 2-3 sprints).

---

## Tasks: the checklist pattern

Tasks live inside the story card body, in a section the skeleton produces from `roadmap.yaml#stories[{story_id}].tasks[]`:

```markdown
## ✅ Tasks

- [ ] T-01: Build LoginForm component (assigned: ui-engineer)
- [ ] T-02: Add `/auth/login` endpoint with rate limit (assigned: api-engineer)
- [ ] T-03: Wire form → API + handle 401 errors (assigned: ui-engineer)
- [x] T-04: Add e2e test for happy path (assigned: qa-engineer) ✓ 2026-05-08
```

When `/crew push` updates a card, it can optionally rewrite the checklist to reflect current task status from `current-feature.yaml#tasks[]`. This is gated by `config.github.update_body_on_phase_change: true` (default `false`) because rewriting body requires the GraphQL `updateProjectV2DraftIssue` mutation, which is one extra API call per push.

**The model is:** tasks visible in body for anyone who opens the card; status of the *story* visible to anyone scanning the board.

---

## Worked example

Suppose your roadmap has:

```yaml
# .crew/roadmap.yaml
epics:
  - id: E1
    name: "Authentication"
    sprint: "Sprint 5"
    stories:
      - id: S1-01
        title: "Email/password login"
        points: 5
        priority: P1
        status: in_progress
        tasks:
          - {id: T-01, title: "Build LoginForm component", agent: ui-engineer, done: true}
          - {id: T-02, title: "Add /auth/login endpoint", agent: api-engineer, done: false}
          - {id: T-03, title: "Wire form ↔ API",          agent: ui-engineer, done: false}
      - id: S1-02
        title: "OAuth Google"
        points: 8
        priority: P2
        parent_story: S1-01    # nested under email/password
```

When you run `/crew push` with `current-feature.yaml#feature_id = S1-01`:

1. **Lookup**: `.crew/github-cards.yaml#features.S1-01.boards[]` → empty → mode = create
2. **Body**: filled from `card-skeletons.md#feature` template, including:
   - Epic field-set: "Authentication"
   - Sprint field-set: "Sprint 5"
   - Priority field-set: "P1"
   - Story Points: 5 (if Number field exists)
   - Tasks checklist in body (one of three checked)
   - Status field: mapped from current phase (e.g. "Building" if Phase 3)
3. **Custom fields**: script sets Epic, Sprint, Priority, Story Points, Source via `set_select` / `set_text` / `set_number` GraphQL mutations
4. **Cache write**: `github-cards.yaml#features.S1-01.boards[0]` records the new `item_id`

When you later push S1-02:

1. **Lookup**: empty → mode = create
2. **Body** includes a "Parent Story: S1-01" line in the metadata footer
3. **Parent Story field-set**: text value `S1-01`
4. **Hierarchy**: in the Projects UI, you can filter by "Parent Story = S1-01" to see all sub-stories of email/password login

When Phase 3 completes and Phase 4 begins, `/crew push` runs in update-status mode:

1. **Lookup**: `S1-01.boards[0].item_id` → exists → mode = update
2. **Sync**: only changes Status field from "Building" → "In Review"
3. **No new card** — same item_id, same URL, just the Status column moves

---

## What this design rejects

These were considered and rejected:

| Approach | Why rejected |
|---|---|
| One card per epic + cards under it | Epics don't ship; their cards become permanent "in progress" phantoms |
| One card per task | Boards become unreadable; PM view drowns in implementation detail |
| Sub-issue hierarchy (real GitHub Issues) | Requires creating real issues (more API churn, extra cleanup), and Crew's natural unit is draft items |
| Linked items via "Closes #N" in body | No structured query; can't filter "show me everything under Epic X" reliably |
| Re-creating cards on each push | Breaks URLs, loses comments, breaks notifications the team relied on |

The flat-card-with-grouping-fields model is what every mature tool (Linear, Jira, Asana) uses for the same reason: the board stays readable and the hierarchy is queryable.
