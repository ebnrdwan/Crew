# Changelog

All notable changes to Crew will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/).

---

## [0.5.0] — 2026-05-08

Substantial expansion past the initial fork. Adds GitHub Projects integration with live status sync and hierarchy mapping, usage-aware checkpointing with auto-resume, per-tech user knowledge profiling, two new commands for diagnose-and-fix lifecycle, and a structured impact reporting system.

### Added — GitHub Projects v2 integration
- **`/crew push`** — creates one live draft card per feature on configured project boards. Status field updates as the feature advances through phases (Planned / Building / In Review / Shipped). Identity is `feature_id`; the cache file `.crew/github-cards.yaml` prevents duplicates across all entry points (`/crew feature`, `/crew drive`, `/crew gang-import`, `/crew gaps`, phase auto-triggers, manual `/crew push`).
- **Hierarchy mapping** — Epic / Sprint / Story / Task all on one board without duplicate cards. Stories ARE the cards; epics + sprints become custom fields; tasks become checklist items inside the card body. Smart field detection auto-routes Single-select / Iteration / Text fields. Full design rationale in `references/hierarchy-mapping.md`.
- **5 card-type skeletons** — feature / enhancement / bug / infra / spike. Each with its own required / live / manual field markers. Documented in `references/card-skeletons.md`.
- **Scripts** — `plugin/scripts/github-project-fields.sh` (one-time discovery of Status field + option IDs with fuzzy matching), `plugin/scripts/github-project-sync.sh` (two modes: create-with-initial-status, update-status; supports `--epic`, `--sprint`, `--story-points`, `--source`, `--parent-story`).

### Added — Usage-aware checkpointing & auto-resume
- **`/crew resume [id]`** — resumes a feature build paused by the budget gate. Idempotent (lock file + consumed-checkpoint archival). Subcommands: `--list`, `--discard {id}`.
- **`crew-budget-check.sh`** — pre-dispatch gate that estimates the next operation against `max_tokens_per_session`. Exits 0 (ok), 1 (warn ≥ 90%), or 2 (stop ≥ 98%, configurable). On stop: writes a checkpoint, computes `scheduled_resume_at = session_start + 5h + 10min`, emits MCP scheduled-task instructions for the model to invoke.
- **`crew-budget-log.sh`** — post-dispatch logger; updates running session total in `.crew/usage-state.yaml`.
- **Defaults tuned for Anthropic Max plan** — 5M tokens / 5h reset window / 10min resume buffer. All configurable in `.crew/config.yaml#usage`.
- Full design doc: `references/usage-budget.md`.

### Added — Per-tech user knowledge profile + Plain-English Mode
- **`/crew profile [check|set|list|clear|reset]`** — manages per-technology knowledge level (none / low / intermediate / high). Asked once per tech when first encountered; cached forever in `.crew/profile.yaml`.
- **Plain-English Mode** — when any tech in play is none/low, all subsequent agent dispatches get a `PLAIN ENGLISH MODE` prefix: spell out acronyms, explain framework patterns, narrate the *why*. Trades brevity for clarity.
- **Tech detection** — covers `project_type`, manifest files (package.json, requirements.txt, pyproject.toml, Pipfile, Gemfile, Cargo.toml, go.mod, composer.json, pom.xml, build.gradle, build.gradle.kts), and keyword scan of feature descriptions.
- Profile is project-scoped — different projects can have different levels for the same tech.

### Added — Diagnose & Fix lifecycle
- **`/crew investigate [topic]`** — hypothesis-driven, time-boxed investigation. Read-only agent dispatch — no code changes. Creates a `spike` card. Four investigation types (`bug`, `perf`, `integration`, `architecture`) route to the right read-only agents. **Always ends with a calibrated recommendation** marked ★ as the first option: HIGH confidence → next command (`/crew fix` or `/crew feature`) with context pre-filled; MEDIUM → continue investigating or add observability; LOW → re-run with different `--type` or escalate to `/gang`.
- **`/crew fix [issue]`** — reproduce → locate → fix → verify a known bug. Skips Phase 1 (Strategy) and Phase 2 (Design); known bugs don't need scoping. The Reproduce step writes a failing regression test that the fix MUST satisfy — the test is the spec; engineers fix the code, never the test.
- **Project-aware pattern propagation** — Locate (Step 4) scans the whole codebase for the same bug pattern, classifying matches as EXACT / FUZZY / LOOSE. Step 4.5 confirms scope (fix-all / review-each / primary-only / EXACT-only); sites NOT included auto-spawn a `SPK-{date}-{bug_id}-adjacent` follow-up spike pushed as a Planned card.
- **Cross-layer dispatch decision** — when a bug spans UI + API, the user picks sequential vs parallel vs single-layer dispatch (avoids the "two agents fighting over related files" failure mode).
- **Structured IMPACT.md report** — written to `.crew/fixes/{bug_id}/IMPACT.md` after verify passes. 9 sections: Files modified, Public interfaces changed (BREAKING / ADDITIVE / INTERNAL), Blast radius, Behavior changes, Risk areas (deferred sites + adjacent drift), Production monitoring metrics to watch, Rollback plan, Test coverage delta, Sign-off checklist.

### Added — Drive command Gang detection + minimal-mode check-ins
- **`/crew drive` Step 1.5** — auto-detects `.gang/features/{slug}/go-package/brd.md`. If found with verdict GO/CONDITIONAL-GO, offers to import (skipping drive's Phase 1 + 2). If found with verdict NO-GO, asks: build anyway (override) / abandon / escalate to `/crew gang-escalate`. If not found, asks how to plan: Phase 1 dispatch / minimal-mode with check-ins / pause for `/gang`.
- **Minimal-mode check-ins** — when planning_mode is `minimal_with_checkins`, drive injects short `AskUserQuestion` calls before every heavy dispatch (Phase 5 ui, Phase 5 api, Phase 6 qa, Phase 7 audit, pre-ship) to keep scope tight without an upfront formal plan.
- **Gang ↔ Crew overlap contract** — `references/overlap-handoff-contract.md` codifies which Crew agents skip when gang-bridge has populated their output (BRD imported / architecture seeded / API contract imported / etc.) per Gang verdict × card type.

### Added — Tooling & UX
- **Trusty / institutional palette** — bronze (Strategy) → copper (Design) → forest (Contract) → deep teal (Build) → deep ocean (Quality) → deep indigo (Launch). 600/700 weights chosen to feel grounded; reads as the second half of Gang's flow (Stage 1 STRATEGY echoes Gang's DELIVER orange).
- **Documentation site** — `docs/index.html` with 11 sections covering pipeline, Gang integration, agents, features, commands, GitHub Projects (status + hierarchy), Diagnose & Fix, Project-Wide Fixes & IMPACT.md, Usage-Aware Checkpointing, Plain-English Mode, Install. Trusty palette + WebGL fluid background.
- **Presentation deck** — `docs/present/index.html`, 14 slides covering everything above with class-toggle slide engine, keyboard nav (arrows / space / 1-9 / Home / End / P for print), touch swipe, hash-based deep links, and print stylesheet for PDF export.
- **Bidirectional handoff with Gang docs** — Gang's `docs/index.html` now has a "Continue with Crew" footer button + handoff section; Crew's docs link back to Gang. Same orange (#F97316) on both sides reinforces the visual continuity.
- **Marketplace renamed** — `crew` → `crew-marketplace` to match Gang's marketplace/plugin naming convention. Update command: `claude plugin marketplace update crew-marketplace`.

### Changed
- `marketplace.json` and `plugin.json` versions: `0.1.0` → `0.5.0`.
- README focused and shortened from 385 → ~210 lines. Marketplace install/update commands match Gang's pattern.
- Docs landing page redesigned with trusty palette; replaces the original Tailwind-style page.

### Compatibility
- **Gang plugin** — still requires v1.3.0 or newer. Same artifacts as 0.1.0 expected.
- **Anthropic Max plan** — usage budget defaults tuned for 5M tokens / 5h reset. For Pro plan, set `max_tokens_per_session: 1_000_000` in `.crew/config.yaml#usage`.
- **GitHub Projects v2** — `gh` CLI must be authenticated with `project` and `repo` scopes (`gh auth login --scopes project,repo`).

---

## [0.1.0] — 2026-05-07

Initial fork of [archflow v1.2.3](https://github.com/azidan/archflow) with Gang plugin integration and additional workflow commands.

### Added — Gang integration
- **`/crew gang-import <slug>`** — read a Gang evaluation's GO Package and seed `roadmap.yaml` with a feature entry. Preserves CONDITIONAL-GO conditions verbatim as `phase-3` gates.
- **`/crew gang-escalate <feature-id>`** — package the current Crew state as escalation context for `/gang reinit` so Gang can re-score a stalled or invalidated feature.
- **`gang-bridge` agent** — handles all state translation between `.gang/` and `.crew/` directories. Imports GO Packages, builds escalation briefs, writes back `crew_import` blocks to Gang state, maintains audit logs.
- **`plugin/skills/crew/references/gang-integration.md`** — full lifecycle documentation showing when to use Gang vs Crew vs both.

### Added — Workflow commands (originally added to the user's archflow runtime, brought into the Crew fork)
- **`/crew drive [name]`** — end-to-end product-led feature development: pm-architect → implementation → QA → gap audit.
- **`/crew deploy [flags]`** — pre-deployment checklist with auto-remediation. Verifies env, runs health checks, dispatches fix agents.
- **`/crew gaps [url]`** — gap-finder audit and fix pipeline. Audits a URL, analyses gaps, creates fixes, verifies.
- **`/crew features [filters]`** — feature dashboard showing all roadmap features with status, pages, navigation flow, and acceptance progress.
- **`gap-finder` agent** — runs UI gap audits referenced by `/crew gaps`.
- **`pm-architect` agent** — drives product analysis at the start of `/crew drive`.

### Changed — fork-wide rebranding
- All 17 upstream archflow agents copied unchanged except for text rebranding (`archflow → crew`, `Archflow → Crew`, `ARCHFLOW → CREW`, `.archflow/ → .crew/`, `/archflow → /crew`).
- Plugin manifest (`plugin/.claude-plugin/plugin.json`):
  - `name: archflow` → `name: crew`
  - `version: 1.2.3` → `version: 0.1.0` (reset for the fork)
  - Added `upstream` block tracking fork point
  - Added `keywords` to surface the gang integration
- Project state directory renamed `.archflow/` → `.crew/` so a project can have both `.gang/` and `.crew/` side by side without ambiguity.
- Slash command renamed `/archflow` → `/crew`.

### Removed
- archflow-specific marketing assets in `docs/` (landing page, LinkedIn launch post, archflow overview SVG) — Crew will produce its own when ready.

### Preserved (intentional)
- All URLs pointing to `https://github.com/azidan/archflow` are unchanged so the upstream attribution stays intact.
- LICENSE file is unchanged (MIT, original copyright on AZidan).
- Phase definitions in `plugin/.crew/phases/` and `plugin/skills/crew/phases/` are byte-identical to upstream apart from `archflow → crew` text replacement.

### Compatibility
- **Gang plugin**: requires v1.3.0 or newer (the version that introduced GO Package generation, `github_push` state, and `default_card_type` in config).
- **archflow upstream**: not currently merged-back. Future archflow releases can be merged into Crew via `git merge upstream/main` followed by re-running the rebrand script. The fork is small and the agent files match exactly.
