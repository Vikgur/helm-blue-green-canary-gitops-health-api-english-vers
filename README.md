# Table of Contents

* [About the Project](#about-the-project)
* [Helm/Helmfile Architecture](#helmhelmfile-architecture)
* [Adapting Manual Deploy to GitOps Deploy](#adapting-manual-deploy-to-gitops-deploy)  
  * [infra/](#infra)  
  * [Implementing ARGO Rollout](#implementing-argo-rollout)  
  * [Helmfile Changes for prod and dev](#helmfile-changes-for-prod-and-dev)  
    * [Prod (helmfile.prod.gotmpl)](#prod-helmfileprodgotmpl)  
    * [Dev (helmfile.dev.gotmpl)](#dev-helmfiledevgotmpl)  
* [Structure](#structure)  
  * [Bitnami_chart](#bitnami_chart)
  * [helm/](#helm)
    * [Manual/Fallback Option](#manualfallback-option)
  * [helm/helmfile.prod.gotmpl](#helmhelmfileprodgotmpl)
  * [helm/helmfile.dev.gotmpl](#helmhelmfiledevgotmpl)
  * [helm/values](#helmvalues)
    * [Using shared values for stage and prod](#using-shared-values-for-stage-and-prod)
* [Requirements Before Launch](#requirements-before-launch)
* [Launch Instructions (Makefile)](#launch-instructions-makefile)  
  * [Preparation](#preparation)  
  * [Main Commands](#main-commands)  
  * [Blue/Green (prod)](#bluegreen-prod)  
  * [Canary (prod)](#canary-prod)  
  * [Checks and Policy](#checks-and-policy)
* [Blue/Green and Canary Implementation](#bluegreen-and-canary-implementation)
  * [Deployment Strategies](#deployment-strategies)
  * [Deployment Instructions](#deployment-instructions)
    * [1. Blue/Green Deployment](#1-bluegreen-deployment)
    * [2. Verifying the New Release](#2-verifying-the-new-release)
    * [3. Switching Traffic](#3-switching-traffic)
    * [4. Canary Rollout](#4-canary-rollout)
    * [5. Rollback Scenarios](#5-rollback-scenarios)
* [Kubernetes Best Practices in Helm Charts](#kubernetes-best-practices-in-helm-charts)
* [Implemented DevSecOps Practices](#implemented-devsecops-practices)
  * [Security Architecture](#security-architecture)
  * [Coverage](#coverage)
    * [Basic Checks](#basic-checks)
    * [Linters and SAST](#linters-and-sast)
    * [Policy-as-Code](#policy-as-code)
    * [Configuration and Secret Security](#configuration-and-secret-security)
    * [CI/CD and Infrastructure](#cicd-and-infrastructure)
  * [Result](#result)
  * [Running Checks](#running-checks)
    * [OWASP Top-10 Mapping](#owasp-top-10-mapping)

---

# About the Project

This project is a working deployment infrastructure for the web application [`health-api`](https://github.com/vikgur/health-api-for-microservice-stack-english-vers) using **Helm**, **Helmfile**, and **Argo Rollouts**.  
The repository contains a full set of charts for the application services (backend, frontend, nginx, postgres, jaeger, swagger) and manages their rollout across **dev** and **prod** environments.

Main objectives:

* unified deployment structure for all services in the `helm/` directory;  
* use of Helmfile (`helmfile.dev.gotmpl`, `helmfile.prod.gotmpl`) for centralized release management;  
* convenient environment separation via values files (`values/values-dev/`, `values/blue/`, `values/green/`, `values/canary/`);  
* shared base values for all environments with Blue/Green/Canary overrides;  
* reproducible launch via Makefile and CI/CD;  
* advanced rollout strategy: **Blue/Green and Canary via Argo Rollouts**;  
* integration of DevSecOps practices (Trivy, Checkov, Conftest) for IaC and chart validation.  

Highlights:

* **Unified configuration for all environments** — base values are shared, differences are placed in separate directories (`values-dev/`, `blue/`, `green/`, `canary/`). The order of their inclusion is determined by the target environment.  
* **VERSION controls both the image tag and an environment variable**, ensuring a strict link between code and artifacts.  
* **Helm Monorepo pattern applied**: all charts and values are stored in a single repository, preventing version drift and simplifying reproducibility.  
* **Blue/Green and Canary strategies** via Argo Rollouts:  
  - Blue/Green — separate `blue` and `green` slots with `activeService` and `previewService`.  
  - Canary — gradual traffic shifting (10% → 30% → 60% → 100%).  

---

# Helm/Helmfile Architecture

The project is packaged into the `helm/` directory, where each service has its own chart (`backend`, `frontend`, `postgres`, `nginx`, `jaeger`, `swagger`, etc.), and release management is centralized via **Helmfile** (`helmfile.dev.gotmpl`, `helmfile.prod.gotmpl`).  

Values are stored in the `helm/values/` directory, which is divided by environments and strategies:  
- `values-dev/` — configuration for development, without Rollouts,  
- `blue/` and `green/` — configuration for Blue/Green deployment,  
- `canary/` — configuration for the Canary strategy,  
- shared base values are reused across environments.  

As a result:  
- **transparent structure** — each service has a separate chart,  
- **reproducible deployment** — environment logic is fully described in helmfile,  
- **flexibility ensured** — support for both `dev` and `prod` with advanced rollout strategies (**Blue/Green and Canary via Argo Rollouts**).  

---

# Adapting Manual Deploy to GitOps Deploy

## infra/

The `infra/` directory is kept as an artifact of the manual pattern.  
It is not used in GitOps, but allows a quick rollback of the project to manual if necessary.

## Implementing ARGO Rollout

**Step 1. Convert Deployment → Rollout**

- Rename `deployment.yaml` to `rollout.yaml` in **backend**, **frontend**, **nginx** services (best practice).  
- In the manifest, replace `kind: Deployment` with `kind: Rollout`.  
- Keep all container settings (`env`, `probes`, `resources`, `volumes`).  
- Add a universal strategy block at the end of the manifest:

```yaml
strategy:
{{- if eq .Values.rollout.strategy "blueGreen" }}
  blueGreen:
    activeService: {{ .Values.rollout.activeService }}
    previewService: {{ .Values.rollout.previewService }}
    autoPromotionEnabled: {{ .Values.rollout.autoPromotionEnabled | default false }}
{{- else if eq .Values.rollout.strategy "canary" }}
  canary:
    steps:
      {{- toYaml .Values.rollout.steps | nindent 6 }}
{{- end }}
```

**Step 2. Configure values for strategies**

- In `values/blue/*` and `values/green/*`, add a `rollout` block with the **blueGreen** strategy; the only difference is in `image.tag`.  
- In `values/canary/*`, add a `rollout` block with the **canary** strategy and `steps`.  
- Leave services without rollout strategies (postgres, jaeger, etc.) as `Deployment`.

## Helmfile Changes for prod and dev

### Prod (`helmfile.prod.gotmpl`)

- Kept **one release per service** (backend, frontend, nginx), instead of duplicates (-blue/-green).  
- Values connected via `values/{{ requiredEnv "ENV" }}` → allows switching blue/green/canary through the `ENV` variable.  
- **alias-service** removed (traffic switching is now handled by Argo Rollouts).  
- Dependency order set: `postgres → backend → frontend → nginx`.  
- Added `helmDefaults` (`wait: true`, `timeout: 600`, `verify: true`).  
- `init-db` kept but disabled (`installed: false`) as fallback/manual.  

### Dev (`helmfile.dev.gotmpl`)

- Values strictly connected from `values/dev/*`.  
- Kept **one release per service**, Rollouts are not used (regular Deployments).  
- **alias-service** disabled (`installed: false`) as irrelevant for dev.  
- `init-db` disabled (`installed: false`), left for manual execution, migrations will be configured via backend-job.  
- Dependency order set: `postgres → backend → frontend → nginx`.  
- Added `helmDefaults` (`wait: true`, `timeout: 600`, `verify: true`).  
- Added `environments.dev` section with `requiredEnv "VERSION"` for image version management.

---

# Structure

## Bitnami_charts/

The project uses the PostgreSQL chart from Bitnami.
Due to access restrictions without VPN, the chart is stored locally in the repository.
This ensures reproducible installation without external dependencies.

## helm/

- **backend/** — Helm chart for the main backend service.  
- **common/** — shared templates and configurations (labels, probes, resources) reused across other charts.  
- **frontend/** — Helm chart for the frontend application.  
- **init-db/** — chart for database initialization (schemas, seed data); disabled by default.  
- **jaeger/** — chart for the Jaeger tracing system.  
- **nginx/** — chart for the nginx proxy inside the project.  
- **postgres/** — chart for PostgreSQL (project database).  
- **swagger/** — chart for swagger-ui (API documentation UI).  
- **values/** — values files for all services (`dev/`, `blue/`, `green/`, `canary/`).  
- **helmfile.dev.gotmpl** — config for deploying the full stack in the dev environment.  
- **helmfile.prod.gotmpl** — config for the production environment (with Blue/Green and Canary strategies).  
- **rsync-exclude.txt** — list of excluded dev files for syncing prod files to the master node.  

### Manual/Fallback Option

- **alias-service/** — auxiliary service for manual slot switching (used in the manual approach, disabled in GitOps).  
- **infra/** — infrastructure charts for manual deployment (ingress-nginx, etc.); kept as fallback.  

## helm/helmfile.prod.gotmpl

This file is the single point of control and describes all releases of the production environment.  
It guarantees consistent and reproducible deployment and allows rolling out all chart services in one step: **backend, frontend, nginx, postgres, swagger, jaeger, init-db**.  

It includes:  
- paths to charts and values files (`values/blue/`, `values/green/`, `values/canary/`),  
- environment variables (`VERSION` for images, `ENV` for slot/strategy selection),  
- service dependencies (via `needs`),  
- rollout strategies implemented via **Argo Rollouts**:  
  - Blue/Green — a single Rollout per service with `activeService` and `previewService`,  
  - Canary — gradual traffic shifting via `strategy.canary.steps`.  

Additional services:  
- **jaeger** — request tracing service (observability), always installed.  
- **init-db** — auxiliary chart for database initialization; disabled by default (`installed: false`), used manually during initial setup.  

## helm/helmfile.dev.gotmpl

This file describes all releases of the dev environment and is a simplified counterpart of the production config.  
It is intended for development and debugging: allows spinning up the full application stack in the `health-api` namespace in one step.  

It includes:  
- values from the `values/dev/` directory,  
- deployed services: **backend, frontend, nginx, postgres, swagger, jaeger, init-db**,  
- service dependencies (e.g., nginx depends on backend and frontend),  
- the `VERSION` variable is taken from the environment and injected into backend, frontend, and nginx images.  

Highlights:  
- **Blue/Green and Canary are not used** — services are deployed as regular Deployments for simplified development.  
- **init-db** may be enabled for quick DB initialization in dev scenarios.  
- All services run in a single namespace and are available immediately after `helmfile apply`.  

## helm/values

- **blue/** — values for Blue slot releases (backend, frontend, nginx) serving the production domain.  
- **green/** — values for Green slot releases, where a new version is deployed for testing before switching.  
- **canary/** — values for canary rollouts; contain `canary.steps` strategy settings for Argo Rollouts.  
- **values-dev/** — simplified values for local development and the test environment.  

- **backend.yaml** — shared values for the backend service.  
- **frontend.yaml** — shared values for the frontend.  
- **nginx.yaml** — base config for the nginx proxy.  
- **postgres.yaml** — parameters for PostgreSQL.  
- **jaeger.yaml** — config for the tracing system.  
- **swagger.yaml** — config for swagger-ui.  

### Using shared values for stage and prod

The project uses a single values file for both environments.  
This simplifies configuration and follows the chosen pattern: stage and prod always run on the same tag.  

Consequence: the usual separation of "stage → testing → prod" is absent, and updates are applied simultaneously.  
In large-scale GitOps projects, it is recommended to use separate values for independent environment management.

---

# Requirements Before Launch

1. **Helm (v3)** — package manager for Kubernetes.  
   Installs charts into the cluster.  

2. **Helmfile** — manages a group of Helm releases.  
   Works with `helmfile.dev.gotmpl` and `helmfile.prod.gotmpl`.  

3. **Helm Diff Plugin** — shows differences between the current state and a new one (`helm plugin install https://github.com/databus23/helm-diff`).  
   Required for the `make diff` command.  

4. **kubectl** — CLI for working with Kubernetes.  
   Helm and Helmfile use kubeconfig to connect to the cluster.  

5. **Make** — used to run commands via `Makefile`.  

6. **Argo Rollouts CRD** — must be installed in the cluster (installed via [gitops-argocd-platform-health-api](https://github.com/vikgur/gitops-argocd-platform-health-api-english-vers)).  

7. **DevSecOps utilities** — for `make scan` and `make opa` you need `trivy`, `checkov`, `conftest`.  

8. **Access to the Kubernetes cluster** — a working kubeconfig so Helmfile can deploy releases.  

---

# Launch Instructions (Makefile)

## Preparation

Before running, set the image version:

```bash
export VERSION=1.0.0
```

By default, `ENV=dev` is used. For production specify `ENV=blue`, `ENV=green`, or `ENV=canary`.

## Main Commands

* `make apply ENV=dev` — deploy all releases in dev.
* `make apply ENV=blue VERSION=...` — deploy releases in prod (blue).
* `make apply ENV=green VERSION=...` — deploy releases in prod (green).
* `make apply ENV=canary VERSION=...` — deploy releases in prod (canary).
* `make diff ENV=dev` — show differences before applying.
* `make template ENV=dev` — render manifests without applying.

## Blue/Green (prod)

* `make deploy-blue VERSION=...` — deploy backend, frontend, and nginx in the blue slot.
* `make deploy-green VERSION=...` — deploy backend, frontend, and nginx in the green slot.

## Canary (prod)

* `make deploy-canary VERSION=...` — roll out a new backend/frontend/nginx release with gradual traffic shifting.

## Checks and Policy

* `make lint-all` — run helm lint on all charts.
* `make lint-svc` — run helm lint on backend/frontend/nginx.
* `make scan` — run Trivy and Checkov for static analysis.
* `make opa` — run Conftest (OPA) policy checks for helm charts.

---

# Blue/Green and Canary Implementation

* Each service (backend, frontend, nginx) uses **a single Rollout** (instead of two separate Deployments).  
* In Helmfile, one release per service is deployed, managed by Argo Rollouts.  
* With Blue/Green, the Rollout itself creates `activeService` and `previewService`.  
  - Production traffic goes to `activeService` (e.g., blue).  
  - The new release is deployed in `previewService` (e.g., green) and verified by QA.  
  - After verification, Argo Rollouts switches traffic to the new slot, while the old one remains as a rollback reserve.  
* With Canary, the `canary.steps` strategy is used:  
  - The Rollout creates several ReplicaSets and gradually shifts part of the traffic (10% → 30% → 60% → 100%).  
  - This allows testing the release under real production load before full switch-over.  

## Deployment Strategies

**Blue/Green**  
* Managed via **Argo Rollouts** (`kind: Rollout`).  
* The cluster maintains two slots: `blue` and `green`.  
* The production service (`*-active`) points only to one of the slots.  
* A new release is deployed in the second slot and goes through validation.  
* After validation, traffic is switched to the new slot, the old one remains as a rollback reserve and is updated afterward.  

**Canary**  
* Implemented via **Argo Rollouts** (`strategy.canary.steps`).  
* The Rollout creates several ReplicaSets and gradually shifts traffic (e.g., 10% → 30% → 60% → 100%).  
* This allows validating release stability under partial production load before full switch-over.  

## Deployment Instructions

## 1. Blue/Green Deployment

Launch a new version in a separate slot:

```bash
make deploy-blue VERSION=1.0.0
make deploy-green VERSION=1.0.1
```

Argo Rollouts starts the second version of the application (`blue` or `green`) in parallel with the current one.
The main service (`*-active`) points only to one slot.

## 2. New Release Verification

* QA or developer checks the pods of the new slot (`*-green` or `*-blue`) in the `health-api` namespace.
* User traffic still goes to the active slot.

## 3. Traffic Switching

When the new version has passed verification:

```bash
make apply ENV=green VERSION=1.0.1
```

Argo Rollouts switches the main service (`*-active`) to the new slot.
The old slot remains as a reserve for quick rollback.

## 4. Canary Rollout

For gradual traffic shifting, Argo Rollouts is used:

```bash
make deploy-canary VERSION=1.0.2
```

The Rollout creates several ReplicaSets and step by step routes a portion of traffic (e.g., 10% → 30% → 60% → 100%) to the new release.
This allows validating release stability under real production load before full switch-over.

## 5. Rollback Scenarios

If the new release is unstable:

* **Blue/Green:** switch traffic back to the stable slot (`make apply ENV=blue VERSION=...` or `make apply ENV=green VERSION=...`).  
* **Canary:** stop the rollout at the current step or roll back the version via Argo Rollouts.

If the current active slot has been updated with a failed version:

1. **Rollback the rollout via Argo Rollouts:**

```bash
kubectl argo rollouts undo backend -n health-api
kubectl argo rollouts undo frontend -n health-api
kubectl argo rollouts undo nginx -n health-api
```

2. **Or set a stable image tag and re-apply:**

```bash
export VERSION=v1.0.XX_stable
ENV=blue helmfile -f helmfile.prod.gotmpl apply
# or
ENV=green helmfile -f helmfile.prod.gotmpl apply
```

3. **If the second slot contains a stable version — switch to it:**

```bash
ENV=green VERSION=v1.0.XX_stable helmfile -f helmfile.prod.gotmpl apply
```

4. **If the second slot has been removed — redeploy it and switch:**

```bash
export VERSION=v1.0.XX_stable
ENV=green helmfile -f helmfile.prod.gotmpl apply
```

5. **After rollback:** update the inactive slot with the stable image to again maintain two environments for Blue/Green.

---

# Kubernetes Best Practices in Helm Charts

The project implements key best practices from production environments of top companies:

1. **Probes**  
   readinessProbe, livenessProbe, startupProbe — control of readiness, hangs, and initialization.

2. **Resources**  
   `resources.requests` and `resources.limits` are defined — ensures stability.

3. **HPA**  
   Automatic scaling by CPU and RAM; all parameters are in values and supported by Rollouts.

4. **SecurityContext**  
   `runAsNonRoot`, `runAsUser`, `readOnlyRootFilesystem` — run in non-privileged mode.

5. **ServiceAccount + RBAC**  
   Services run under dedicated serviceAccounts with restricted RBAC permissions.

6. **PriorityClass**  
   `priorityClassName` assigned to manage pod importance.

7. **Affinity & Spread**  
   Implemented affinity, nodeSelector, and topologySpreadConstraints for load balancing.

8. **Lifecycle Hooks**  
   `preStop`/`postStart` — proper shutdown/initialization.

9. **Graceful Shutdown**  
   `terminationGracePeriodSeconds` set for graceful termination.

10. **ImagePullPolicy**  
   `IfNotPresent` in prod for stability, `Always` only for dev/CI.

11. **InitContainers**  
   Used in dev to wait for services; DB migrations temporarily placed in a separate `init-db` chart.

12. **Volumes / PVC**  
   Volumes attached, persistent (PVC) when required.

13. **RollingUpdate Strategy**  
   Zero-downtime deployment: `maxSurge: 1`, `maxUnavailable: 0`.

14. **Annotations for rollout**  
   `checksum/config`, `checksum/secret` used — restart on change.

15. **Tolerations**  
   Taints supported where needed.

16. **Helm Helpers**  
   Templates in `_helpers.tpl` for DRY, name, and label standardization.

17. **Secrets (fine-grained access)**  
   `POSTGRES_PASSWORD` securely injected from Kubernetes Secret via `valueFrom.secretKeyRef`.

18. **Multienv Helmfile**  
   Using `helmfile.dev.gotmpl` and `helmfile.prod.gotmpl` with different sets of values (`values-dev/`, `blue/`, `green/`, `canary/`). All charts are shared, environments differ only by configuration.

---   

# Implemented DevSecOps Practices

The project is built around the secure Blue/Green + Canary pattern. DevSecOps practices are integrated as a mandatory layer of control and automated checks at the Helm/Helmfile level.

**Required tools for checks:** `helm`, `helmfile`, `helm-diff`, `trivy`, `checkov`, `conftest` (OPA), `gitleaks`, `make`, `pre-commit`

## Security Architecture

* **.gitleaks.toml** — rules for secret scanning, with exclusions for Helm templates.
* **.trivyignore** — list of false positives for the misconfiguration scanner.
* **policy/helm/security.rego** — OPA/Conftest policies (forbid privileged, require resources, etc.).
* **policy/helm/security_test.rego** — unit tests for policies.
* **.checkov.yaml** — Checkov config for static analysis of Kubernetes manifests.
* **Makefile** — `lint`, `scan`, `opa` targets to run checks with a single command.
* **.gitignore** — excludes temporary and sensitive artifacts: chart tarballs (`*.tgz`), local dev-values, scanner reports, IDE files, and encrypted values (`*.enc.yaml`, `*.sops.yaml`).

## Coverage

### Basic Checks

* **helm lint** — chart syntax and structure validation.
* **kubeconform** — validation against Kubernetes API.
  → Secure SDLC: early error detection.

### Linters and SAST

* **checkov**, **trivy config** — analyze Helm/manifests for insecure patterns.
* **kubesec** — check securityContext and capabilities.
  → Compliance with OWASP IaC Security and CIS Benchmarks.

### Policy-as-Code

* **OPA/Conftest** — strict rules: forbid privileged, enforce runAsNonRoot, require resources.
  → OWASP Top-10: A4 Insecure Design, A5 Security Misconfiguration.

### Configuration and Secret Security

* **helm-secrets / sops** — encryption of sensitive values.
* **gitleaks** — secret scanning in code and commits.
  → OWASP: A2 Cryptographic Failures, A3 Injection, A5 Security Misconfiguration.

### Pre-commit

* **.pre-commit-config.yaml** — defines hooks that run checks (`yamllint`, `gitleaks`, `helm lint`, `trivy`, `checkov`, `conftest`) on every commit.
* Ensures that errors and secrets are blocked from Git even before CI/CD.

### CI/CD and Infrastructure

* **Makefile** — single entry point for DevSecOps checks (`make lint`, `make scan`, `make opa`).
* **Helmfile diff** — dry-run before rollout.
  → OWASP A1 Broken Access Control: minimize manual actions and errors.

## Result

Key DevSecOps practices implemented: linters, SAST, Policy-as-Code, secret scanning, and secret management. Protection is ensured against major OWASP Top-10 categories (Security Misconfiguration, Insecure Design, Cryptographic Failures, Broken Access Control, Secrets Management). The configuration is reproducible and secure: no secrets or artifacts are committed to Git.

## Running Checks

All checks are combined into the following commands:

```bash
make lint-all     # helm lint for all charts
make lint-svc     # helm lint for backend/frontend/nginx
make scan         # Trivy + Checkov
make opa          # Conftest (OPA policies)
```

### OWASP Top-10 Compliance

A brief mapping of project practices to OWASP Top-10:

- **A1 Broken Access Control** → rollout strategies managed via Argo Rollouts; a single `activeService` eliminates manual switching and reduces access errors.  
- **A2 Cryptographic Failures** → secrets are not stored in values; leak detection with gitleaks; (optionally) helm-secrets/sops for encryption.  
- **A3 Injection** → no hardcoded credentials; linters and static analysis (helm lint, trivy config, checkov).  
- **A4 Insecure Design** → OPA/Conftest policies: deny privileged, enforce resource limits, runAsNonRoot.  
- **A5 Security Misconfiguration** → helm lint, kubeconform, checkov; deny by default for ingress and services.  
- **A6 Vulnerable and Outdated Components** → fixed versions of charts and images; scanning via trivy.  
- **A7 Identification and Authentication Failures** → GHCR registry secrets stored securely; Helm/Helmfile access managed via kubeconfig with cluster RBAC.  
- **A8 Software and Data Integrity Failures** → helmfile diff and CI/CD pipeline; image signing (cosign when using GHCR).  
- **A9 Security Logging and Monitoring Failures** → observability services (jaeger, prometheus) are included; centralized logging (e.g., Loki) is planned.  
- **A10 SSRF** → not applicable to Helm/Helmfile; controlled at the application and WAF level.  
