#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Crew User Profile Check  v0.1.0
# ─────────────────────────────────────────────────────────────
# Detects which technologies are in play for the current project
# (or the current feature) and reports which still need a
# knowledge-level answer from the user.
#
# Detection sources:
#   - .crew/current-phase.yaml#project_type
#   - package.json / requirements.txt / pyproject.toml / Gemfile /
#     Cargo.toml / go.mod / composer.json / pom.xml / build.gradle
#   - Optional --feature-description for keyword matches
#     (e.g. "build a fastapi service" → adds fastapi)
#
# Reads user-profile.technologies from .crew/profile.yaml if it
# exists, .crew/config.yaml otherwise. Writes nothing.
#
# Inputs (all optional):
#   --feature-description "..."  Hint text from the feature input
#                                  to enrich detection.
#
# Output (JSON to stdout):
#   {
#     "detected_techs":   ["python", "fastapi", "postgres"],
#     "new_techs":        ["fastapi"],            // not in profile
#     "cached_techs": {
#       "python":   {"level": "intermediate", "asked_at": "..."},
#       "postgres": {"level": "low",          "asked_at": "..."}
#     },
#     "has_low_or_none": true,            // any cached tech is low/none
#     "plain_english_required": true,
#     "learning_mode_recommended": "detailed"
#   }
#
# Exit codes:
#   0  detection complete (caller checks new_techs to decide if
#      asking is needed)
#   3  config / state error
# ─────────────────────────────────────────────────────────────
set -euo pipefail

FEATURE_DESC=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --feature-description) FEATURE_DESC="$2"; shift 2 ;;
    *) echo "❌  Unknown option: $1" >&2; exit 3 ;;
  esac
done

# ── Locate .crew root ─────────────────────────────────────────
CREW_ROOT=""
PROJECT_ROOT=""
DIR="$(pwd)"
while [[ "$DIR" != "/" ]]; do
  if [[ -d "$DIR/.crew" ]]; then
    CREW_ROOT="$DIR/.crew"
    PROJECT_ROOT="$DIR"
    break
  fi
  DIR="$(dirname "$DIR")"
done

if [[ -z "$CREW_ROOT" ]]; then
  echo '{"error":"no .crew root found; run /crew init or /crew onboard first"}'
  exit 3
fi

export CREW_ROOT PROJECT_ROOT FEATURE_DESC

python3 - <<'PYEOF'
import os, json, yaml, re

crew_root    = os.environ['CREW_ROOT']
project_root = os.environ['PROJECT_ROOT']
feature_desc = os.environ.get('FEATURE_DESC', '').lower()

profile_path  = os.path.join(crew_root, 'profile.yaml')
config_path   = os.path.join(crew_root, 'config.yaml')
phase_path    = os.path.join(crew_root, 'current-phase.yaml')

def load_yaml(path, default=None):
    if not os.path.exists(path):
        return default if default is not None else {}
    try:
        with open(path) as f:
            return yaml.safe_load(f) or (default if default is not None else {})
    except Exception:
        return default if default is not None else {}

# Profile lives in profile.yaml first, falls back to config.yaml#user_profile
profile = load_yaml(profile_path, {}).get('user_profile') or {}
if not profile:
    profile = (load_yaml(config_path, {}).get('user_profile') or {})

technologies = profile.get('technologies', {}) or {}

# ── Detect technologies from project + feature ───────────────
detected = set()

# 1. project_type signal
phase     = load_yaml(phase_path, {})
proj_type = phase.get('project_type', '')
type_techs = {
    'fullstack':      ['javascript', 'typescript'],
    'frontend_only':  ['javascript', 'typescript'],
    'backend_only':   [],   # determined by manifest below
    'mobile':         ['mobile'],
}
for t in type_techs.get(proj_type, []):
    detected.add(t)

# 2. Manifest files
def has(p):
    return os.path.exists(os.path.join(project_root, p))

if has('package.json'):
    detected.add('javascript')
    pkg = load_yaml(os.path.join(project_root, 'package.json'), {})
    deps = {**(pkg.get('dependencies') or {}), **(pkg.get('devDependencies') or {})}
    if 'typescript' in deps or has('tsconfig.json'): detected.add('typescript')
    if 'react' in deps: detected.add('react')
    if 'react-native' in deps: detected.add('react-native')
    if 'next' in deps: detected.add('nextjs')
    if 'vue' in deps: detected.add('vue')
    if '@nestjs/core' in deps: detected.add('nestjs')
    if 'express' in deps: detected.add('express')

if has('requirements.txt') or has('pyproject.toml') or has('Pipfile'):
    detected.add('python')
    # peek at deps for framework hints
    text = ''
    for f in ['requirements.txt', 'pyproject.toml', 'Pipfile']:
        full = os.path.join(project_root, f)
        if os.path.exists(full):
            try:
                with open(full) as fh: text += fh.read().lower()
            except Exception: pass
    if 'fastapi' in text: detected.add('fastapi')
    if 'django' in text:  detected.add('django')
    if 'flask' in text:   detected.add('flask')

if has('Gemfile'):     detected.add('ruby')
if has('Cargo.toml'):  detected.add('rust')
if has('go.mod'):      detected.add('go')
if has('composer.json'): detected.add('php')
if has('pom.xml') or has('build.gradle') or has('build.gradle.kts'):
    detected.add('java')
    if has('build.gradle.kts'): detected.add('kotlin')

# Database / infra hints
if any(has(f) for f in ['docker-compose.yml', 'docker-compose.yaml']):
    detected.add('docker')

# 3. Feature description keyword scan
KEYWORD_TECHS = {
    'fastapi': 'fastapi', 'django': 'django', 'flask': 'flask',
    'express': 'express', 'nestjs': 'nestjs', 'next.js': 'nextjs', 'nextjs': 'nextjs',
    'react native': 'react-native', 'react-native': 'react-native',
    'swift': 'swift', 'swiftui': 'swiftui',
    'kotlin': 'kotlin', 'jetpack compose': 'jetpack-compose',
    'postgres': 'postgres', 'postgresql': 'postgres', 'mysql': 'mysql',
    'mongodb': 'mongodb', 'redis': 'redis',
    'kubernetes': 'kubernetes', 'k8s': 'kubernetes',
    'graphql': 'graphql', 'rest': 'rest-api',
    'oauth': 'auth', 'jwt': 'auth',
}
for kw, tech in KEYWORD_TECHS.items():
    if kw in feature_desc:
        detected.add(tech)

detected = sorted(detected)

# ── Compute new vs cached ─────────────────────────────────────
new_techs    = [t for t in detected if t not in technologies]
cached_techs = {t: technologies[t] for t in detected if t in technologies}

# Are any cached at low/none?
has_low = any(
    (info.get('level') or '').lower() in ('low', 'none')
    for info in cached_techs.values()
)

result = {
    "detected_techs":             detected,
    "new_techs":                  new_techs,
    "cached_techs":               cached_techs,
    "has_low_or_none":            has_low,
    "plain_english_required":     has_low,
    "learning_mode_recommended":  "detailed" if has_low else None,
    "profile_path":               os.path.relpath(profile_path, start=os.path.dirname(crew_root)),
}

# Build prompts the caller will dispatch
prompts = []
for tech in new_techs:
    prompts.append({
        "tech":     tech,
        "header":   f"Knowledge: {tech}",
        "question": f"How would you describe your knowledge of {tech}?",
        "options": [
            {"label": "None",          "description": "Never used it; I want full plain-English explanations"},
            {"label": "Low",           "description": "Used it briefly; explain non-obvious choices in plain English"},
            {"label": "Intermediate", "description": "Use it regularly; default agent verbosity is fine"},
            {"label": "High",          "description": "Expert; agents can be terse and idiomatic"},
        ],
    })
result["prompts"] = prompts

print(json.dumps(result, indent=2))
PYEOF
