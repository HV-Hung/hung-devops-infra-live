# GitHub Actions Workflows Documentation

This document describes the CI/CD workflows for the `hung-devops-infra-live` Terragrunt monorepo.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Workflow Summary](#workflow-summary)
- [Change Detection](#change-detection)
- [PR Plan Workflows](#pr-plan-workflows)
- [Apply Workflows (Dev / QA)](#apply-workflows-dev--qa)
- [Apply Workflow (Prod — with Approval)](#apply-workflow-prod--with-approval)
- [Manual: Unlock State](#manual-unlock-state)
- [Manual: Plan/Apply Dispatch](#manual-planapply-dispatch)
- [Adding a New Terragrunt Module](#adding-a-new-terragrunt-module)
- [Secrets & Authentication](#secrets--authentication)
- [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
Pull Request to main ──┬── Plan: Dev  ── detect-changes → matrix plan → PR comments
                       ├── Plan: QA   ── detect-changes → matrix plan → PR comments
                       └── Plan: Prod ── detect-changes → matrix plan → PR comments

Merge to main ─────────┬── Apply: Dev  ── detect-changes → matrix apply (auto)
                       ├── Apply: QA   ── detect-changes → matrix apply (auto)
                       └── Apply: Prod ── detect-changes → plan → approve (1h) → apply

Manual (workflow_dispatch) ── Unlock State
                           ── Manual: Plan/Apply (select env + path + action)
```

**Key design principles:**
- **Separate workflow per environment** — enables proper `paths:` filtering and clear PR status checks
- **`dorny/paths-filter`** — detects which Terragrunt paths changed using per-env filter files
- **`max-parallel: 1`** — ensures sequential execution in dependency order within each environment
- **`fail-fast: true` on apply** — stops if a dependency fails; `fail-fast: false` on plan to show all results
- **Prod approval gate** — uses GitHub Environment `production` with required reviewers and 1-hour timeout

---

## Prerequisites

1. **Azure resources** created by [`setup/bootstrap.sh`](../setup/bootstrap.sh):
   - Storage Account for Terraform state
   - Managed Identity with OIDC federated credentials

2. **GitHub repository secrets** (set by bootstrap.sh):
   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`

3. **GitHub Environment** named `production` with required reviewers:
   - Go to: **Settings → Environments → New environment → `production`**
   - Add at least one required reviewer

4. **OIDC Federated Credentials** (3 total, created by bootstrap.sh):
   - `github-actions-main` — for `refs/heads/main` (push/apply workflows)
   - `github-actions-pr` — for `pull_request` (plan workflows)
   - `github-actions-prod-env` — for `environment:production` (prod approval gate)

---

## Workflow Summary

| Workflow | Trigger | Environment | File |
|----------|---------|-------------|------|
| **Plan: Dev** | PR to main | dev | `terragrunt-plan-dev.yml` |
| **Plan: QA** | PR to main | qa | `terragrunt-plan-qa.yml` |
| **Plan: Prod** | PR to main | prod | `terragrunt-plan-prod.yml` |
| **Apply: Dev** | Push to main | dev | `terragrunt-apply-dev.yml` |
| **Apply: QA** | Push to main | qa | `terragrunt-apply-qa.yml` |
| **Apply: Prod** | Push to main | prod | `terragrunt-apply-prod.yml` |
| **Unlock State** | Manual dispatch | any | `terragrunt-unlock.yml` |
| **Manual: Plan/Apply** | Manual dispatch | any | `terragrunt-dispatch.yml` |

---

## Change Detection

Change detection uses [`dorny/paths-filter@v3`](https://github.com/dorny/paths-filter) with per-environment filter files.

### Filter Files

Located in `.github/filters/`:

```
.github/filters/
├── dev.yaml    # Dev environment path filters
├── qa.yaml     # QA environment path filters
└── prod.yaml   # Prod environment path filters
```

### How It Works

1. Each filter file defines named entries (e.g., `resource-group`, `network`)
2. Each entry lists file patterns that trigger it (including shared files like `_envcommon/`, `modules/`, `root.hcl`)
3. `dorny/paths-filter` outputs a JSON array of matched entry names in **definition order**
4. The matrix strategy with `max-parallel: 1` executes them **sequentially in that order**

### Example Filter File

```yaml
# .github/filters/dev.yaml
# Order matters! Executed top-to-bottom.

resource-group:         # Runs 1st
  - 'dev/resource-group/**'
  - 'dev/env.hcl'
  - '_envcommon/resource-group.hcl'
  - 'modules/resource-group/**'
  - 'root.hcl'

network:                # Runs 2nd (may depend on resource-group)
  - 'dev/network/**'
  - '_envcommon/network.hcl'
  - 'modules/network/**'
  - 'root.hcl'
```

### Convention

**Filter name = subdirectory name.** The filter name `resource-group` maps to `{env}/resource-group/`. The workflow constructs the working directory as `{env}/{filter_name}`.

---

## PR Plan Workflows

**Files:** `terragrunt-plan-dev.yml`, `terragrunt-plan-qa.yml`, `terragrunt-plan-prod.yml`

### Trigger

```yaml
on:
  pull_request:
    branches: [main]
    paths:
      - '{env}/**'
      - '_envcommon/**'
      - 'modules/**'
      - 'root.hcl'
```

### Jobs

1. **`detect-changes`** — Uses `dorny/paths-filter` to find which paths changed
2. **`plan`** — Matrix job: runs `terragrunt plan` for each changed path, posts a **separate PR comment** per path with collapsible plan output

### PR Comment Format

Each path gets its own comment:

```
### ✅ Plan: `dev/resource-group`
<details><summary>Show Plan Output</summary>
...terraform plan output...
</details>
```

---

## Apply Workflows (Dev / QA)

**Files:** `terragrunt-apply-dev.yml`, `terragrunt-apply-qa.yml`

### Trigger

```yaml
on:
  push:
    branches: [main]
    paths: ['{env}/**', '_envcommon/**', 'modules/**', 'root.hcl']
```

### Jobs

1. **`detect-changes`** — Same as plan workflow
2. **`apply`** — Matrix job: runs `terragrunt apply -auto-approve` for each changed path

### Concurrency

```yaml
concurrency:
  group: terragrunt-apply-{env}
  cancel-in-progress: false
```

This prevents concurrent applies to the same environment. If a second merge happens while apply is running, it queues instead of cancelling.

### Behavior

- `max-parallel: 1` — Apply sequentially in dependency order
- `fail-fast: true` — Stop on first failure (later resources may depend on this one)

---

## Apply Workflow (Prod — with Approval)

**File:** `terragrunt-apply-prod.yml`

### Flow

```
detect-changes → plan (save artifact) → approve (1h timeout) → apply (from saved plan)
```

### Jobs

1. **`detect-changes`** — Find changed paths
2. **`plan`** — Run `terragrunt plan -out=tfplan`, upload plan binary as GitHub artifact
3. **`approve`** — GitHub Environment `production` gate. Reviewers have **1 hour** to approve before timeout
4. **`apply`** — Download the saved plan artifact and apply it

### Why Save the Plan?

The plan is saved as a GitHub Actions artifact so the **exact plan that was reviewed is applied**. Without this, a re-plan after approval might produce different results if someone pushed new changes to main.

### Approval Process

1. After the plan job completes, the workflow pauses at the `approve` job
2. Required reviewers receive a notification from GitHub
3. Reviewers go to the workflow run in GitHub UI and click **"Review deployments"**
4. After approval, the `apply` job downloads the saved plan and applies it
5. If no one approves within 1 hour, the workflow fails

---

## Manual: Unlock State

**File:** `terragrunt-unlock.yml`

Use this when a Terraform state gets locked from a cancelled CI run.

### Inputs

| Input | Type | Description | Example |
|-------|------|-------------|---------|
| `environment` | choice | dev, qa, or prod | `dev` |
| `path` | string | Terragrunt path relative to env | `resource-group` |
| `lock_id` | string | The lock ID from the error message | `abc-123-def` |

### How to Use

1. Go to **Actions → Unlock State → Run workflow**
2. Select environment, enter path and lock ID
3. Click **Run workflow**

### Finding the Lock ID

The lock ID is shown in the error message when a plan or apply fails due to a locked state:

```
Error: Error locking state: Error acquiring the state lock: ...
Lock Info:
  ID:        abc-123-def-456
  ...
```

---

## Manual: Plan/Apply Dispatch

**File:** `terragrunt-dispatch.yml`

For ad-hoc plan or apply on a specific environment + path combination.

### Inputs

| Input | Type | Description | Example |
|-------|------|-------------|---------|
| `environment` | choice | dev, qa, or prod | `prod` |
| `path` | string | Terragrunt path relative to env | `resource-group` |
| `action` | choice | plan or apply | `plan` |

### How to Use

1. Go to **Actions → Manual: Plan/Apply → Run workflow**
2. Select environment, enter path, choose action
3. Click **Run workflow**

### Notes

- **Prod applies** require approval via the `production` GitHub Environment (same as automated applies)
- The workflow validates that `{env}/{path}/terragrunt.hcl` exists before running
- Useful for debugging, targeted re-applies, or testing new modules

---

## Adding a New Terragrunt Module

When you add a new Terragrunt module (e.g., `dev/network/`), you must also update the filter files:

### Step 1: Create the module

```
dev/network/terragrunt.hcl
qa/network/terragrunt.hcl
prod/network/terragrunt.hcl
_envcommon/network.hcl
modules/network/
```

### Step 2: Update filter files

Add the new entry to each environment's filter file **in dependency order**:

```yaml
# .github/filters/dev.yaml

resource-group:           # ← Runs first (no dependencies)
  - 'dev/resource-group/**'
  - 'dev/env.hcl'
  - '_envcommon/resource-group.hcl'
  - 'modules/resource-group/**'
  - 'root.hcl'

network:                  # ← Runs second (depends on resource-group)
  - 'dev/network/**'
  - 'dev/env.hcl'
  - '_envcommon/network.hcl'
  - 'modules/network/**'
  - 'root.hcl'
```

Do the same for `qa.yaml` and `prod.yaml`.

### Step 3: No workflow changes needed

The workflows automatically pick up new entries from the filter files.

---

## Secrets & Authentication

### GitHub Secrets

| Secret | Description | Set by |
|--------|-------------|--------|
| `AZURE_CLIENT_ID` | Managed Identity Client ID | `bootstrap.sh` |
| `AZURE_TENANT_ID` | Azure AD Tenant ID | `bootstrap.sh` |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID | `bootstrap.sh` |

### OIDC Authentication Flow

1. GitHub Actions requests an OIDC token from GitHub's token endpoint
2. The token includes claims about the workflow (repo, branch, event type, environment)
3. `azure/login@v2` exchanges this token with Azure AD using the federated credential
4. Azure AD validates the token's subject claim matches a registered federated credential
5. If valid, Azure AD returns an access token for the Managed Identity

### Federated Credentials

| Name | Subject Claim | Used By |
|------|---------------|---------|
| `github-actions-main` | `repo:HV-Hung/hung-devops-infra-live:ref:refs/heads/main` | Apply workflows (push to main) |
| `github-actions-pr` | `repo:HV-Hung/hung-devops-infra-live:pull_request` | Plan workflows (PRs) |
| `github-actions-prod-env` | `repo:HV-Hung/hung-devops-infra-live:environment:production` | Prod apply (after approval) |

---

## Troubleshooting

### OIDC Authentication Failure

**Error:** `AADSTS70021: No matching federated identity record found`

**Cause:** The OIDC token's subject claim doesn't match any federated credential.

**Fix:** Ensure all 3 federated credentials exist. Run:
```bash
az identity federated-credential list \
  --identity-name id-github-actions-iac \
  --resource-group rg-hung-devops-tfstate \
  -o table
```

### State Lock Error

**Error:** `Error acquiring the state lock`

**Fix:** Use the **Unlock State** workflow with the lock ID from the error message.

### No Changes Detected

**Symptom:** Workflow triggers but the plan/apply job is skipped.

**Cause:** `dorny/paths-filter` didn't match any entries in the filter file.

**Check:**
1. Verify the changed files match patterns in the filter file
2. Ensure the filter file includes shared paths (`_envcommon/`, `modules/`, `root.hcl`) if applicable
3. Verify the new module is registered in the filter file

### Workflow Not Triggering

**Symptom:** You changed files but the workflow didn't run.

**Check:**
1. Verify the changed files match the `paths:` filter in the workflow's `on:` trigger
2. The `paths:` filter in the workflow YAML must include the env directory and shared directories
3. For PRs, the target branch must be `main`

### Prod Apply Timed Out

**Symptom:** The prod apply workflow failed with a timeout.

**Cause:** No reviewer approved within 1 hour.

**Fix:** Re-run the workflow or trigger a new merge. The plan will be regenerated.
