# /crew features — Feature Dashboard

Display all features from the roadmap with status, context, and navigation information.

## Usage
```
/crew features                        → Show all features
/crew features --status in_progress   → Filter by status
/crew features --status done          → Show completed features
/crew features --epic E3              → Filter by epic
/crew features --priority Critical    → Filter by priority
```

## Prerequisites
- `.crew/roadmap.yaml` must exist

---

## Flow

### Step 1: Load Roadmap

1. Read `.crew/roadmap.yaml`
2. If missing → HALT: "No roadmap found. Run `/crew onboard` or `/crew init` first."
3. Read `.crew/current-feature.yaml` if it exists (to highlight active feature)

### Step 2: Parse Filters

Parse any flags from the command arguments:
- `--status {value}` → Filter stories by status: `backlog`, `in_progress`, `review`, `done`
- `--epic {id}` → Filter stories by epic ID: `E1`, `E2`, etc.
- `--priority {value}` → Filter by priority: `Critical`, `High`, `Medium`, `Low`

Multiple filters can be combined: `/crew features --status in_progress --epic E3`

### Step 3: Extract Page/Route Information

For each story, scan these fields for route/page references:
- `title` — Look for page names (e.g., "Dashboard page", "Settings screen")
- `description` — Look for URL patterns (`/path`, route names)
- `acceptance_criteria[].text` — Look for navigation references:
  - URL patterns: `/dashboard`, `/settings/notifications`, `/api/v1/*`
  - Page references: "on the dashboard", "settings page", "login screen"
  - Navigation: "navigate to", "redirect to", "clicking X goes to"
- `subtasks[].text` — Same pattern matching

Build a navigation context for each feature:
- **Pages touched** — Which pages/routes this feature affects
- **Entry point** — Where the user starts (e.g., "Sidebar → Settings")
- **Navigates to** — Where the feature takes the user

### Step 4: Generate Display

#### Header
```
Crew Feature Dashboard
Project: {project name} ({project_type})
Phase: {current phase from current-phase.yaml}
{If filters active}: Filters: {list active filters}
```

#### Per-Epic Section

For each epic (sorted by epic ID):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Epic {id}: {name}  ({scope})
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

#### Per-Story Display

Within each epic, stories sorted by priority (Critical → High → Medium → Low):

```
  {status_icon} {id}: {title}  [{priority}]
     {description — first 100 chars}...
     Acceptance: {met}/{total} criteria met
     Subtasks:   {completed}/{total} done
     Assigned:   {assigned}
     Pages:      {comma-separated list of pages/routes, or "—" if none detected}
     Entry:      {entry point, or "—"}
     Navigates:  {destination, or "—"}
```

**Active feature highlight:** If the story matches the current feature from `current-feature.yaml`, prefix with `>>> ACTIVE`:
```
  >>> ACTIVE
  {status_icon} S3-02: User Authentication  [Critical]
     ...
```

#### Status Icons

| Status | Icon |
|--------|------|
| `backlog` | `[ ]` |
| `in_progress` | `[~]` |
| `review` | `[?]` |
| `done` | `[x]` |

#### Summary Footer

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Summary: {total} features across {N} epics
  [x] Done:        {count}  ({percentage}%)
  [~] In Progress: {count}  ({percentage}%)
  [?] In Review:   {count}  ({percentage}%)
  [ ] Backlog:     {count}  ({percentage}%)

{If active feature exists}:
  Active: {feature name} (Phase: {drive_phase or gaps_phase or "implementation"})
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 5: Interactive Options

After displaying, offer:
```
Options:
  1. View details for a specific story (enter story ID)
  2. Start working on a story (/crew feature {id})
  3. Drive a new feature (/crew drive)
  4. Run gap audit (/crew gaps)
  5. Exit
```

#### Story Detail View

If user enters a story ID, show full details:

```
Story {id}: {title}
Epic: {epic_name} ({epic_id})
Status: {status}  |  Priority: {priority}  |  Assigned: {assigned}

Description:
  {full description}

Acceptance Criteria:
  {met_icon} {criterion 1}
  {met_icon} {criterion 2}
  ...

Subtasks:
  {done_icon} {subtask 1}
  {done_icon} {subtask 2}
  ...

Pages/Routes:
  - {page 1}: {context of how it relates}
  - {page 2}: {context}

Navigation Flow:
  Entry: {where user comes from}
  → Feature: {what happens}
  → Navigates to: {where user goes}

{Back to list / Start this feature / Exit}
```
