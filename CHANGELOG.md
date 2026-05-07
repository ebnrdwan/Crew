# Changelog

All notable changes to Crew will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/).

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
