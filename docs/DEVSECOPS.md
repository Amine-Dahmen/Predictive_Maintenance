# DevOps / DevSecOps loop

Every change goes around the same loop. Security checks run at every stage, not as a final gate.

```
   ┌──────────── plan ◄──────────────────────────────────────────────┐
   │  backlog (PrediMaint_Product_Backlog_Roadmap.xlsx), branch per   │
   ▼  feature                                                         │
 code ──► commit ──► CI ──► security ──► images ──► deploy ──► monitor ┘
  │     pre-commit   tests  SAST / SCA   SBOM +      docker      health checks,
  │     gitleaks     5 parts secrets     provenance  compose     logs, Dependabot,
  │                         Trivy        Trivy scan              code scanning alerts
```

| Stage | What runs | Where | Blocks on |
|---|---|---|---|
| Commit | gitleaks (project rules), large files, private keys, merge markers | `.pre-commit-config.yaml` (local, `pre-commit install`) | any finding |
| CI | backend unit + **integration tests on a real PostgreSQL**, web build + tests, Flutter analyze + tests, firmware logic tests, ML tests | `.github/workflows/ci.yml`, on every push and pull request | failing test, Flutter warning |
| Secrets | gitleaks over the **whole history**, default rules + a rule for the firmware's Wi-Fi / MQTT passwords | `security.yml` | any finding |
| SAST | **Semgrep** (JavaScript, TypeScript, Python, Node.js, Dockerfile rules) on every run; CodeQL `security-extended` as well once the repository is public | `security.yml` | Semgrep ERROR finding |
| SCA | `npm audit --omit=dev` (backend, web), `pip-audit` (ML), dependency review on pull requests | `security.yml` | high or critical |
| Config | Trivy 0.76 filesystem scan: fixable vulnerabilities, misconfigurations (Dockerfiles, compose), secrets | `security.yml` | HIGH or CRITICAL |
| Weekly | the whole security workflow, every Monday, to catch vulnerabilities published since the last push | `security.yml` (cron) | — |
| Images | build backend, web, ML images; Trivy image scan; on `main` or a `v*` tag, push to GHCR with **SBOM and provenance attestation** | `images.yml` | fixable critical CVE |
| Updates | Dependabot pull requests for npm, pip, pub, Docker base images and the actions themselves, tested by the CI before merge | `.github/dependabot.yml` | — |
| Deploy | `docker compose up -d` from the published images, or built locally | `docker-compose.yml` | health checks |
| Monitor | container health checks (`/api/health`, ML `/health`), backend logs (alerts, failed logins, refresh-token reuse, OTA results), weekly scans | — | — |

## Security measures already in the application

Kept from the team's Release 1 work and extended in Release 3:

- JWT access tokens (15 min) with rotating, hashed refresh tokens. Reuse of a refresh token revokes every
  session. Password policy and bcrypt (12 rounds). Login rate limiting and constant-time answers for
  unknown e-mails. The user is reloaded on every request, so a deactivated or reset account is blocked
  immediately, and its open real-time stream is closed (US-35, US-36).
- RBAC on every route and zod validation of every input (unknown fields removed). Parameterised SQL only.
  helmet headers, CORS allow-list, 100 kB body limit.
- MQTT: no anonymous access and a per-machine ACL. A board can only publish under its own topics and
  only read its own thresholds and OTA orders.
- Photos (US-25): type checked on the bytes (JPEG/PNG), 5 MB, server-generated names, served only to
  users who can see the intervention, `nosniff`.
- Reports (US-17): HTML escaped and served with a strict CSP; CSV cells protected against formula
  injection.
- OTA (US-46): orders only through the ACL-protected topic. Files are downloaded with a random,
  hashed, 30-minute token that is invalidated at the end, and their SHA-256 is checked **before**
  anything is replaced. `credentials.py` and `boot.py` are never sent. The board rolls back after 3
  failed boots.
- ML service: optional API key (`X-API-Key`, constant-time comparison), input sizes and values
  validated, batch size limited. Dataset files verified against pinned hashes.
- Containers: non-root users (`node`, `ml`, nginx-unprivileged), health checks, no secrets in images.
  Every secret of the compose stack is mandatory in `.env` (git-ignored) and compose refuses to start
  without it.

## Private repository

The repository is private. Without GitHub Advanced Security, *Code scanning* (CodeQL, SARIF uploads) is
not available, which is why CodeQL and the first Trivy job failed on the first push. The blocking checks
now run as plain command-line tools (Semgrep, Trivy) whose findings fail the job and appear in its log.
CodeQL runs automatically if the repository becomes public. Trivy downloads its vulnerability database
from the AWS mirror first, to avoid GitHub registry rate limits.

## First run on GitHub

1. Push the branches (`main`, `feature/*`). The CI runs on every push.
2. *Settings › Code security*: enable Dependabot alerts and security updates (free for private repositories).
3. *Settings › Actions › General*: allow GitHub Actions to create packages (GHCR) for `images.yml`.
4. *Settings › Branches*: protect `main` and require the `CI` jobs and the `secrets` job before merge.
5. Optional hardening: pin each action to a commit SHA (Dependabot keeps them up to date), sign images
   with cosign, and run the compose stack behind a reverse proxy with HTTPS (needed anyway for web
   push notifications).

## Known findings to act on

- `partie_embarque/src/credentials_example.py` in the working copy (not committed) contains a real
  Wi-Fi password. Put real values only in `credentials.py`, which git ignores, and restore the example
  (`git checkout partie_embarque/src/credentials_example.py`). The project gitleaks rule would block that
  commit.
- The development default `SEED_DIRECTEUR_PASSWORD` in `backend/src/config/env.js` is only acceptable
  because the first login forces a password change. The compose stack requires a value in `.env`.
