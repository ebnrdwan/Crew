# /crew profile — User knowledge profile

Tracks the user's knowledge level for each technology in play, so Crew agents calibrate their output: terse and idiomatic for experts, plain-English with internals explained for beginners.

The profile is built **once per technology**, lazily — Crew asks about a tech only when it's first encountered in a project, then caches the answer in `.crew/profile.yaml`. The user can edit the file directly or use `/crew profile` to manage entries.

When **any** tech the current feature touches is at level `low` or `none`, Crew:

1. Sets `plain_english_required: true` in the profile flags
2. Appends a "Plain English mode" instruction to all agent dispatch prompts
3. Recommends `/learn detailed` for the global Claude Code learning mode (does not auto-set; respects the project/global boundary)

---

## Usage

```
/crew profile                    → Show current profile + run check on detected techs
/crew profile check              → Detect techs in this project, ask about new ones
/crew profile set <tech> <level> → Manually set/update a tech entry
/crew profile list               → Show all cached entries with levels
/crew profile clear <tech>       → Remove a tech entry (forces re-asking next time)
/crew profile reset              → Clear the entire profile (with confirmation)
```

`<level>` is one of: `none` · `low` · `intermediate` · `high`

---

## Subcommand: check (default)

This is what runs automatically inside `/crew drive` and `/crew feature` early steps. It can also be invoked directly when a user wants to refresh detection.

```bash
bash {plugin_root}/scripts/crew-profile-check.sh \
  [--feature-description "build a fastapi service"]
```

The script outputs JSON with:

- `detected_techs` — everything detected in the project + feature description
- `new_techs` — detected techs NOT yet in the profile (need asking)
- `cached_techs` — detected techs already in the profile (with their levels)
- `has_low_or_none` — whether any cached level is low/none
- `plain_english_required` — same as above (cached for clarity)
- `learning_mode_recommended` — `detailed` if low/none, else null
- `prompts[]` — pre-built `AskUserQuestion` payloads for each new tech

**For each prompt in `prompts[]`:**

1. Dispatch `AskUserQuestion` with the supplied header / question / options
2. Map the user's answer to a level (None / Low / Intermediate / High → lowercase)
3. Call `crew-profile-set.sh --tech {tech} --level {level} --context "{feature_id}"`

After all prompts are answered, the profile is fully populated for the current feature's tech set.

---

## Subcommand: set

```bash
bash {plugin_root}/scripts/crew-profile-set.sh \
  --tech python \
  --level intermediate \
  --context "feature: user-auth"
```

Writes the entry to `.crew/profile.yaml#user_profile.technologies.{tech}` and recomputes `flags.has_low_or_none` / `plain_english_required` / `learning_mode_recommended`.

---

## Subcommand: list

Read `.crew/profile.yaml#user_profile.technologies` and print each entry as:

```
react-native   intermediate   asked 2026-05-08  contexts: mobile-app
postgres       low            asked 2026-05-08  contexts: schema-design
typescript     high           asked 2026-05-07  contexts: feature-X, feature-Y
```

---

## Subcommand: clear / reset

`clear <tech>`: remove just one entry. Useful when the user has learned more and wants Crew to re-ask.

`reset`: blow away the whole profile after confirmation. Useful when team membership or skill-set changes substantially.

---

## How agents see the profile

Whenever an agent is dispatched, the model checks `.crew/profile.yaml#user_profile.flags`:

```yaml
user_profile:
  flags:
    has_low_or_none:           true
    plain_english_required:    true
    learning_mode_recommended: detailed
```

If `plain_english_required: true`, prepend this to the agent's system prompt:

```
PLAIN ENGLISH MODE — the user is a beginner with one or more of the
technologies in play. Calibrate your explanations:
  - Spell out acronyms on first use (e.g. "Cross-Origin Resource
    Sharing (CORS)" not "CORS").
  - When using framework-specific patterns (decorators, hooks, etc.),
    explain WHY the pattern is used in 1–2 sentences before showing it.
  - Avoid idiomatic shortcuts that experienced users prefer; favour
    the verbose-but-clear form.
  - When you make a non-obvious choice, narrate the reason briefly
    in a comment or summary line.
  - Never assume the user knows what a method does just because it's
    standard library — link to docs or summarise inline.

This mode is set per the user's profile in .crew/profile.yaml. The user
can change it with /crew profile set {tech} {level}.
```

Agents in plain-English mode trade brevity for clarity. They produce slightly longer output but are dramatically more useful when the user is learning the stack.

---

## Where the profile lives

```yaml
# .crew/profile.yaml
user_profile:
  technologies:
    python:
      level: low
      asked_at: 2026-05-08T15:30:00Z
      contexts: [service-auth]
    typescript:
      level: high
      asked_at: 2026-05-07T22:10:00Z
      contexts: [frontend, feature-cart]
    react-native:
      level: intermediate
      asked_at: 2026-05-08T16:45:00Z
      contexts: [mobile-app]
  flags:
    has_low_or_none:           true
    plain_english_required:    true
    learning_mode_recommended: detailed
    last_updated:              2026-05-08T16:45:00Z
```

The file is **project-scoped** — different projects can have different profiles for the same person (e.g., a developer might be high on TypeScript at work but low on Python in a side project where they're learning).

For team projects, commit `.crew/profile.yaml` if everyone has comparable skill levels; ignore it via `.gitignore` if profiles are per-developer.
