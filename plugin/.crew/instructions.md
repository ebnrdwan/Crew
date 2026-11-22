# Crew — Phase-Based Development Instructions
Dynamic phase-based instruction loading for token-efficient development.

## 🎯 Core Agents (Always Available)

**Phase 1: Strategy & Planning**
- `product-strategist` - Business strategy, personas, KPIs → .crew/project-context.md
- `feature-planner` - Feature roadmaps, user stories, sprint planning → .crew/roadmap.yaml

**Phase 2: Design**
- `ux-designer` - User flows, design systems, themes, wireframes → design-artifacts/
- `dsl-generator` - Component specifications with styling → design-artifacts/styled-dsl.yaml

**Phase 2.25: High-Fidelity Design**
- SuperDesign MCP - Hi-fi screen generation from styled-dsl.yaml → design-artifacts/hifi-screens/

**Phase 2.5: API Architecture**
- `api-contract-architect` - API contracts from wireframes → docs/api-contract.md (single source of truth)

**Phase 3: Implementation**
- `ui-engineer` - All frontend (React, React Native, SwiftUI, Jetpack Compose) + integration with backend APIs. Also updates screens after ux-designer changes `styled-dsl.yaml`
- `api-engineer` - NestJS/PostgreSQL backends, MUST follow docs/api-contract.md exactly (zero tolerance)
- `qa-engineer` - Comprehensive testing (unit, integration, e2e) across all platforms. Runs AFTER feature agents complete
- `pm-maestro-reviewer` - Acceptance testing via Maestro. Runs AFTER qa-engineer, validates acceptance criteria from .crew/roadmap.yaml → docs/acceptance-reports/
- `ux-designer` - Design updates on specific screens. Updates `styled-dsl.yaml` file

**Phase 4: Quality & Optimization**
- `code-reviewer` - Code quality, security, best practices analysis + improvement reports
- `performance-optimizer` - Performance bottleneck identification and optimization
- `pm-maestro-reviewer` - Full acceptance regression suite across all implemented features

**Phase 5: Launch & Operations**
- `devops-engineer` - CI/CD pipelines, deployment infrastructure, app store preparation
- `post-launch-analyst` - Analytics implementation, user insights, performance monitoring

**Phase 6: Enhancement (On-Demand)**
- `i18n-engineer` - Internationalization for web/iOS/Android platforms

## 📌 Available Commands (Crew)
- `/crew` — Show available subcommands and current project status
- `/crew init` — Initialize Crew in a new project (creates `.crew/` state files, sets Phase 1)
- `/crew onboard` — Onboard existing codebase (interactive wizard: audit, import context, backfill artifacts, set phase)
- `/crew setup-mcp` — Configure an MCP server for external tools (Jira, Notion, Linear, GitHub, SuperDesign, etc.)
- `/crew feature` — Add a new feature to the roadmap and start the git development workflow

## 🌐 Project Types
The framework detects and adapts to project type: `fullstack`, `frontend_only`, `backend_only`, `mobile`.
- Stored in `.crew/current-phase.yaml` as `project_type`
- Phases, agents, and audit checks are filtered by project type
- `.crew/roadmap.yaml` structure is tailored to project type (backend = endpoints/services, frontend = pages/components)
- Set automatically by `/crew onboard` or can be set manually in `.crew/current-phase.yaml`

## 🔀 Git Workflow
All feature development follows `.crew/workflow.md` branching strategy:
- Feature branches from main
- Task branches from feature
- Subtask branches from task
- Merge only after explicit user approval
- Use `/crew feature` to create feature branches and track tasks in `.crew/current-feature.yaml`

## 🔄 Dynamic Phase Loading

**Where the reference files live:** `.crew/phases/*`, `.crew/schemas/*` and `.crew/workflow.md` below are read from the
project when it has its own copy, otherwise from the Crew plugin (`skills/crew/phases/`, `skills/crew/schemas/`,
`skills/crew/workflow.md`; see "Plugin files and project files" in the crew skill). Projects do not need copies.

**Current Phase Detection:**
```yaml
# Read .crew/current-phase.yaml to determine active phase
phase: 1  # Current phase number
phase_file: ".crew/phases/phase-1-strategy.md"  # Load this file for detailed instructions
```

**Phase Instruction Loading:**
```bash
# Check for existing phase tracker
if [[ -f ".crew/current-phase.yaml" ]]; then
  # Normal operation - use existing tracker
  Current Phase: .crew/current-phase.yaml → phase_file
  Detailed Instructions: .crew/phases/phase-{current}-{name}.md
else
  # Project setup needed - load setup system
  Setup Required: .crew/phases/phase-setup.md → detect and initialize phase
fi
```

## 📋 Universal Context Files (Always Required)
- `.crew/project-context.md` - Business goals, tech stack, architecture decisions
- `.crew/roadmap.yaml` - Feature roadmap and sprint planning
- `.crew/current-feature.yaml` - Active development scope and requirements
- `.crew/current-phase.yaml` - Phase state tracker (PROJECT-SCOPED, auto-created from template)

## 💡 Universal Critical Rules (Apply to ALL Phases)

### 🚨 API Contract Compliance (Phases 2.5-4)
- **API CONTRACT IS SACRED**: api-engineer AND ui-engineer MUST follow docs/api-contract.md exactly
- **ZERO TOLERANCE**: No deviations from contract specifications allowed
- **CONTRACT VERIFICATION**: Must confirm understanding before implementation
- **ui-engineer (real app only)**: When building the actual frontend app (`frontend/`), ui-engineer MUST read the API contract for every endpoint it integrates with. All TypeScript interfaces for API data MUST match the contract response schemas (field names, enum values, shapes). Pages MUST use real API hooks — no hardcoded mock data in page components. Mock data is only acceptable in HTML prototypes (`design-artifacts/`) and test files.
- **Prototype exception**: When building HTML prototypes/screens in `design-artifacts/`, static mock data is expected and correct.

### 🎨 SuperDesign MCP (Phase 2.25)
- **OPTIONAL INTEGRATION**: Phase 2.25 can use a SuperDesign MCP server if you have one. It is not shipped with Crew: install it from its own documentation and pin a version. Crew works without it
- **OPTIONAL PHASE**: If SuperDesign MCP is unavailable, Phase 2.25 can be skipped (Phase 2 → 2.5 directly)
- **VISUAL APPROVAL**: Hi-fi screens must be approved before API architecture begins

### ✅ Acceptance Testing (Phases 3-4)
- **ACCEPTANCE GATE**: After qa-engineer completes, launch `pm-maestro-reviewer` to validate acceptance criteria from `.crew/roadmap.yaml`
- **VERDICT REQUIRED**: Feature is not complete until pm-maestro-reviewer returns ACCEPTED verdict
- **REJECTION FLOW**: If REJECTED, fix blocking defects and re-run pm-maestro-reviewer — do not proceed
- **REPORTS**: Acceptance reports saved to `docs/acceptance-reports/{story-id}-review.md`

### ⚠️ Mandatory Approval Gates (ALL Phases)
- **USER APPROVAL REQUIRED**: Stop and wait for explicit user approval after EVERY phase
- **NO PHASE SKIPPING**: Complete every phase in exact sequence
- **DEMO REQUIRED**: Working features must be demonstrated before approval

### 🎯 Agent Selection Rules (ALL Phases)
- **SPECIALIZED AGENTS FIRST**: Always use sub-agents when possible, and prefer a specialised Crew agent. Use `general-purpose` only when no specialised Crew agent fits the task (for example the read-only analysis agents of `/crew onboard`)
- **AGENT NAMES**: In Claude Code, Crew's agents are named `crew:<agent>` (for example `crew:ui-engineer`); dispatch them by that name, or by the bare name if that is what the client lists
- **PHASE-APPROPRIATE AGENTS**: Only use agents listed for current phase
- **MANDATORY FILE NAMING**: Follow exact output naming conventions

### 🗺️ Codemap Navigation (optional — only if codemap is installed)
Codemap is an optional code-index tool; Crew does not ship it and works without it. Check with `command -v codemap`.
If it is not installed, skip this section and use normal search (grep/glob) with targeted reads.
- **CODEMAP FIRST**: If codemap is installed, use `codemap find` before reading full files or using grep/glob
- **TARGETED READS**: Use `codemap show` to get file structure, then read only the relevant line ranges
- **INIT ON SETUP**: If codemap is installed, run `codemap init .` when starting any new project, then `codemap watch . -q &`
- **VALIDATE BEFORE TRUSTING**: Run `codemap validate` before using cached line numbers after compaction

### 🔍 Subagent Codebase Navigation
- If codemap is installed, when launching **Explore** or **Plan** agents include this in the prompt: "Use codemap to navigate the codebase structurally. Avoid reading full files — use codemap indexes to find symbols, then read only the specific line ranges you need. At the end of your response, state how many files you read fully vs. how many you navigated via codemap line ranges (e.g. 'Codemap: 5 files via line ranges, 1 full read')."
- Without codemap, ask them to search first and read only the relevant line ranges.

### ⚡ Development Efficiency (ALL Phases)
- **AGENT TEAMS**: For Phase 3+ features, launch ui-engineer and api-engineer simultaneously when both have clear, independent scopes from the API contract
- **SEQUENTIAL DEPENDENCY**: qa-engineer runs AFTER feature agents complete, never in parallel. pm-maestro-reviewer runs AFTER qa-engineer
- **AGENT SCOPING**: Each agent works on ONE feature boundary. Never give an agent a cross-cutting concern
- **HANDOFF VIA FILES**: Agents communicate through files, not messages. api-engineer produces endpoints; ui-engineer consumes docs/api-contract.md and styled-dsl.yaml
- **CONFLICT PREVENTION**: Only ONE agent may modify a given file. If two agents need the same file, sequence them
- **TOKEN EFFICIENCY**: Search first (codemap find, if installed; else grep/glob) + targeted line reads instead of full file scans
- **ONE FEATURE AT A TIME**: Never batch features in Phase 3

## 🔄 Phase Navigation System

### Phase Transition Workflow
```yaml
Current Phase Complete:
  1. Validate all completion criteria met
  2. Present outputs to user
  3. Wait for explicit user approval
  4. Update .crew/current-phase.yaml to next phase
  5. Load .crew/phases/phase-{next}.md for next instructions

Phase Files Available:
  - .crew/phases/phase-onboarding.md    # For existing codebases (via /crew onboard)
  - .crew/phases/phase-1-strategy.md
  - .crew/phases/phase-2-design.md
  - .crew/phases/phase-2.25-hifi-design.md
  - .crew/phases/phase-2.5-api-architecture.md
  - .crew/phases/phase-3-implementation.md
  - .crew/phases/phase-4-quality.md
  - .crew/phases/phase-5-launch.md
  - .crew/phases/phase-6-enhancement.md
```

### Project Setup (When Needed)
For projects without `.crew/current-phase.yaml`:
- **Load Setup System**: `.crew/phases/phase-setup.md`
- **Phase Detection**: Automatic inference from project state
- **Initialization**: Create phase tracker and load instructions

## 🚀 Getting Started

**On Every New Session (only if codemap is installed):**
```bash
# Start codemap watch if codemap is installed and not already running
command -v codemap >/dev/null && { pgrep -f "codemap watch" > /dev/null || codemap watch . -q & }
```

**Normal Operation (.crew/current-phase.yaml exists):**
1. Start codemap watch (above, if installed)
2. Load current phase from `.crew/current-phase.yaml`
3. Load detailed instructions from `.crew/phases/phase-{current}.md`
4. Follow phase-specific execution steps
5. Complete approval gates before proceeding to next phase

**Project Setup (.crew/current-phase.yaml missing):**
1. Start codemap watch (above, if installed)
2. Load setup system from `.crew/phases/phase-setup.md`
3. Auto-detect phase from project state or start Phase 1
4. Create `.crew/current-phase.yaml` and continue with normal operation

**File Structure:**
- `.crew/current-phase.yaml` - Project phase state (auto-created if missing)
- `.crew/phases/phase-setup.md` - Setup system (loaded only when needed)
- `.crew/phases/phase-*.md` - Phase-specific instructions (loaded based on current phase)

---
**📍 Current Phase Instructions: Load .crew/current-phase.yaml → phase_file**
- You always commit ONLY the changes you did not all the files.
