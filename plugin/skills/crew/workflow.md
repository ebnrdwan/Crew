# Feature Development Workflow

A generalized workflow for managing feature development with tasks and subtasks.

## Branch Structure

```
[feature-branch] (feature branch)
└── [feature]/[task-name] (task branch)
    ├── [feature]/[task-number]-[subtask-name] (subtask branch)
    ├── [feature]/[task-number]-[subtask-name] (subtask branch)
    └── ...
```

**Example:**
```
user-auth (feature branch)
└── auth/login-flow (task branch)
    ├── auth/1.1-email-validation (subtask branch)
    ├── auth/1.2-password-strength (subtask branch)
    └── auth/1.3-remember-me (subtask branch)
└── auth/registration (task branch)
    └── ...
```

---

## Git safety (applies to every step below)

- **Ask before every push, merge into `main`/`develop`, or branch deletion** — ask the user first (AskUserQuestion in Claude Code, a plain question in GitHub Copilot), name the exact
  branch and remote, and wait for a yes. One yes covers one action, not the rest of the feature.
- **Prefer a pull request over pushing to `main`**: when a feature is done, offer to open a PR
  (`gh pr create --base main --head [feature-branch]`) instead of merging and pushing `main` yourself.
- **Stage exact paths** (`git add path/to/file ...`), never `git add .` or `git add -A`: the working tree may hold files
  that are not part of the change.
- Deleting branches is optional housekeeping: only offer it after the merge or PR is done, and never delete a remote
  branch without a yes.

---

## Starting a New Feature

```bash
# 1. Create feature branch from main/develop
git checkout main  # or develop
git pull origin main
git checkout -b [feature-branch]
git push -u origin [feature-branch]   # only after the user says yes to publishing the branch
```

---

## Starting a New Task (within a Feature)

```bash
# 1. Create task branch from feature branch
git checkout [feature-branch]
git pull origin [feature-branch]
git checkout -b [feature]/[task-name]
git push -u origin [feature]/[task-name]   # only after the user says yes
```

---

## For Each Subtask

### Step 1: Create subtask branch from task branch
```bash
git checkout [feature]/[task-name]
git pull origin [feature]/[task-name]
git checkout -b [feature]/[task-number]-[subtask-name]
```

### Step 2: Implement changes
- Make code changes as specified in the subtask requirements
- Follow existing code patterns and styling conventions

### Step 3: Build and test locally
```bash
# Run your project's build/test commands
yarn build && yarn start
# or
npm run build && npm run dev
```

- Test the feature to verify requirements
- Check responsiveness if applicable
- Verify dark mode/themes work correctly

### Step 4: Commit, then ask before pushing
```bash
git add path/to/changed-file another/changed-file   # exact paths of the files this subtask changed
git commit -m "feat: [description of changes]"
# Ask the user before pushing; push only after a yes:
git push -u origin [feature]/[task-number]-[subtask-name]
```

### Step 5: Wait for EXPLICIT user approval
- **CRITICAL**: Do NOT merge until user EXPLICITLY approves
- Push subtask branch and wait for user to test
- User will test the changes
- Address any feedback before proceeding
- **Never auto-merge** - user must confirm the task is done

### Step 6: After EXPLICIT approval, merge subtask to task branch
```bash
git checkout [feature]/[task-name]
git pull origin [feature]/[task-name]
git merge [feature]/[task-number]-[subtask-name]
# Ask before pushing the task branch; push only after a yes:
git push origin [feature]/[task-name]
```

### Step 7: Clean up subtask branch (optional - ask first)
Ask the user whether to delete the subtask branch. Only on a yes:
```bash
git branch -d [feature]/[task-number]-[subtask-name]
git push origin --delete [feature]/[task-number]-[subtask-name]   # separate yes for the remote branch
```

### Step 8: Update tracking documentation

After completing a subtask, update BOTH tracking files:

#### 8.1 Update roadmap.yaml
Find your story → subtasks array → your subtask:
```yaml
subtasks:
  - text: "Your subtask description"
    completed: true    # ← Change from false to true
```

#### 8.2 Update current-feature.yaml
Find your task → update progress:
```yaml
tasks:
  - id: "1"
    name: "Your task"
    status: "in_progress"  # or "complete" if ALL subtasks done
    completed_subtasks: 5   # ← increment
    total_subtasks: 7
```

#### 8.3 Commit the tracking update
```bash
git add .crew/roadmap.yaml .crew/current-feature.yaml
git commit -m "docs: mark subtask complete - [subtask description]"
```

IMPORTANT: Do this AFTER each subtask, not at the end of the story.

---

## Completing a Task

After ALL subtasks in a task are complete and approved:

```bash
# Merge task branch to feature branch
git checkout [feature-branch]
git pull origin [feature-branch]
git merge [feature]/[task-name]
# Ask before pushing; push only after a yes:
git push origin [feature-branch]

# Clean up task branch - optional, only after the user says yes:
git branch -d [feature]/[task-name]
git push origin --delete [feature]/[task-name]
```

Then:
1. Update tracking docs with next task
2. Update status tracker
3. Start next task if applicable

---

## Completing a Feature

After ALL tasks in a feature are complete and approved, ask the user how to land it (AskUserQuestion in Claude Code,
a plain question in GitHub Copilot):

1. **Open a pull request (recommended)** - push the feature branch (after a yes) and open a PR into `main`/`develop`:
   ```bash
   git push -u origin [feature-branch]
   gh pr create --base main --head [feature-branch] --title "feat: [feature]" --body "[summary, test plan]"
   ```
2. **Merge locally into `main`** - only when the user explicitly picks it:
   ```bash
   git checkout main  # or develop
   git pull origin main
   git merge [feature-branch]
   # Pushing main is a separate question; push only after a yes:
   git push origin main
   ```
3. **Leave it** - keep the feature branch as it is.

Cleaning up the feature branch is optional (it may be kept for reference) and needs its own yes:
```bash
git branch -d [feature-branch]
git push origin --delete [feature-branch]
```

---

## Testing Checklist

Before requesting user review:
- [ ] Build succeeds without errors
- [ ] App runs correctly
- [ ] Feature works as specified in requirements
- [ ] Responsive design verified (if applicable)
- [ ] Dark mode/themes work correctly (if applicable)
- [ ] No console errors
- [ ] Accessibility considerations addressed
- [ ] Unit/integration tests pass (if applicable)

---

## Branch Naming Conventions

| Level | Pattern | Example |
|-------|---------|---------|
| Feature | `[feature-name]` | `user-auth`, `payment-flow` |
| Task | `[feature]/[task-name]` | `auth/login-flow`, `payment/checkout` |
| Subtask | `[feature]/[number]-[name]` | `auth/1.1-validation`, `payment/2.3-stripe` |

---

## Commit Message Conventions

```bash
# Feature commits
feat: add user authentication flow

# Bug fixes
fix: resolve login redirect issue

# Refactoring
refactor: extract validation logic to utils

# Documentation
docs: update API documentation

# Styling
style: improve button hover states

# Tests
test: add unit tests for auth service
```

---

## Quick Reference

### Create Subtask Branch
```bash
git checkout [feature]/[task-name] && \
git pull origin [feature]/[task-name] && \
git checkout -b [feature]/[subtask]
```

### Merge Subtask (after approval)
```bash
git checkout [feature]/[task-name] && \
git merge [feature]/[subtask]
# Then, each only after its own yes from the user:
#   git push origin [feature]/[task-name]
#   git branch -d [feature]/[subtask]
#   git push origin --delete [feature]/[subtask]
```

### Merge Task (after all subtasks complete)
```bash
git checkout [feature-branch] && \
git merge [feature]/[task-name]
# Then, each only after its own yes from the user:
#   git push origin [feature-branch]
#   git branch -d [feature]/[task-name]
#   git push origin --delete [feature]/[task-name]
```

---

## Template Variables

Replace these placeholders with your actual values:

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `[feature-branch]` | Main feature branch name | `user-auth` |
| `[feature]` | Feature prefix for branches | `auth` |
| `[task-name]` | Name of the current task | `login-flow` |
| `[task-number]` | Task number (1, 2, 3...) | `1` |
| `[subtask-name]` | Name of the subtask | `email-validation` |
| `[subtask]` | Full subtask identifier | `1.1-email-validation` |

---

*Reference this file when starting new features, tasks, or subtasks*
