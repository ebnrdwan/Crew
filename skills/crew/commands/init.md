# /crew init — Initialize Crew in a Project

Lightweight command for setting up Crew in a new or existing project.

## Usage
```
/crew init              → Initialize Crew in the current project
```

## Prerequisites
- Must be run from the project's root directory

---

## Flow

### Step 0: Initialize Git (MANDATORY)

Before creating any Crew files:

1. Check if git is already initialized:
   ```bash
   git rev-parse --is-inside-work-tree 2>/dev/null
   ```

2. If NOT initialized, ask user:
   "Initialize git repository? [Yes / No]"
   - If Yes: `git init`
   - If No: WARN "Crew strongly recommends git. Proceeding without it."

3. After `.crew/` files are created (end of Step 3), make the initial commit:
   ```bash
   git add .crew/
   git commit -m "chore: initialize crew (Phase 1)"
   ```

---

### Step 1: Check If Already Initialized

Check if `.crew/current-phase.yaml` exists in the project root.

**If it exists:**
```
Crew is already initialized in this project.

Current phase: [N] ([Phase Name])
Project type: [type]

Run /crew to see available commands.
```
Done — exit the command.

---

### Step 2: New Project or Existing Codebase?

Ask the user:
```
Is this a new project or an existing codebase?
```

Options:
- **Existing codebase** — Has source code that needs to be analyzed and onboarded
- **New project** — Starting from scratch, no existing code

#### If "Existing codebase"

Redirect to the full onboarding wizard:
```
For existing codebases, use the full onboarding wizard which analyzes
your code, imports context from external tools, and determines the
correct development phase.
```
Then load and follow `skills/crew/commands/onboard.md`.

---

#### If "New project"

Proceed to Step 3.

### Step 3: Create Project State Files

1. **Create `.crew/` directory** if it doesn't exist:
```bash
mkdir -p .crew
```

2. **Create `.crew/current-phase.yaml`** with Phase 1 defaults:
```yaml
phase: 1
phase_name: "Strategy & Planning"
phase_file: "phases/phase-1-strategy.md"

# Project metadata
project_type: null  # Will be set during Phase 1
onboarded: false

# Phase tracking
phases_completed: []
phases_partial: []
phases_skipped: []
phases_not_applicable: []

# Gaps
gaps: []

# Git workflow
git_workflow: "workflow.md"

# Feature tracking
current_feature: null
feature_status: "ready"
status: "initialized"
```

### Step 4: Update Project CLAUDE.md

If `CLAUDE.md` does NOT exist in the project root, create it:

```markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Crew Framework

This project uses the [Crew](https://github.com/AZidan/archflow) phase-based development framework.

- **Current Phase**: 1 (Strategy & Planning) — see `.crew/current-phase.yaml`

Commands:
- `/crew` — Show status and available commands
- `/crew feature` — Start a new feature from the roadmap
```

If `CLAUDE.md` ALREADY exists, append the Crew section to the end:

```markdown

## Crew Framework

This project uses the [Crew](https://github.com/AZidan/archflow) phase-based development framework.

- **Current Phase**: 1 (Strategy & Planning) — see `.crew/current-phase.yaml`

Commands:
- `/crew` — Show status and available commands
- `/crew feature` — Start a new feature from the roadmap
```

### Step 5: Print Summary

```
Crew initialized at Phase 1 (Strategy & Planning).

Created:
  .crew/current-phase.yaml
  CLAUDE.md [created / updated with Crew section]

Next steps:
  - Run Phase 1 to define your product strategy
  - The product-strategist agent will create:
    → .crew/project-context.md (business goals, tech stack, architecture)
    → .crew/roadmap.yaml (feature roadmap and sprint planning)
```

---

## Notes
- This command is idempotent — it won't overwrite existing `.crew/current-phase.yaml`
- For existing codebases, always use `/crew onboard` instead (it determines the correct phase via audit)
- The `project_type` field is left as `null` and will be set during Phase 1
