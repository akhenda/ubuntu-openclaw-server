# Skill: App Builder + Preview Runner (OpenClaw)

You are an agent running inside an OpenClaw instance. Your job is to create or update apps and ensure they can be tested and previewed inside the OpenClaw host using Docker + Traefik.

## Core Principles

1. **Everything is a project folder under the workspace**
   - All projects MUST live at:
     - `/opt/openclaw/workspace/projects/<app_slug>`
   - `<app_slug>` must be lowercase, kebab-case.

2. **Every app MUST be runnable via the global docker-compose**
   - You will NOT create ad-hoc docker-compose files for production preview.
   - Instead, you will add a new service entry to:
     - `/opt/openclaw/infra/global-compose/docker-compose.yml`

3. **Every app MUST be reachable via a subdomain**
   - Primary convention:
     - `https://<app_slug>.<base_domain>`
   - If the user wants bot scoping:
     - `https://<app_slug>.<bot_name>.<base_domain>`
   - The service MUST include Traefik labels to route that hostname to the correct container port.

4. **You MUST provide a report with:**
   - Repo path
   - How to run locally inside the host
   - Preview URL(s)
   - Healthcheck result(s)
   - Test command(s) run + summary
   - Logs location / commands to view logs
   - What you changed in the global compose (diff summary)

## Inputs you MUST determine from the user request
If not explicitly provided, infer safely:
- `app_slug` (kebab-case)
- `app_type`: one of:
  - `nextjs`, `node-api`, `static`, `python-api`
- `app_port` inside the container:
  - Next.js: 3000
  - Node API: 3000 (unless specified)
  - Static: 80
  - Python API: 8000
- `base_domain` and optional `bot_name`
  - These usually exist in `/opt/openclaw/infra/global-compose/.env`
  - Read `.env` first before assuming.

## Standard Workflow (MANDATORY)

### Step 0 - Preflight
- Confirm required files exist:
  - `/opt/openclaw/infra/global-compose/docker-compose.yml`
  - `/opt/openclaw/infra/global-compose/.env`
- Verify Traefik is healthy:
  - `docker ps | grep traefik`
  - `curl -fsS http://127.0.0.1:8080/ping` (if enabled)
- Confirm DNS expectation:
  - Agent does NOT change registrar DNS unless explicitly configured.
  - If Cloudflare API automation exists in this repo, use it; otherwise, report the required DNS record.

### Step 1 - Create or Update Project
- Ensure project folder exists:
  - `/opt/openclaw/workspace/projects/<app_slug>`
- Scaffold based on `app_type`:
  - nextjs:
    - `pnpm create next-app@latest ...` OR existing repo conventions
  - node-api:
    - `pnpm init` + express/fastify (as requested)
  - static:
    - produce build artifacts into `/app` served by nginx
  - python-api:
    - use uvicorn/fastapi or as requested
- Install deps and run baseline tests/lint if available:
  - `pnpm install` + `pnpm test` / `pnpm lint`
  - For python: `uv pip install -r requirements.txt` + `pytest` if present

### Step 2 - Ensure Dockerization
Each app MUST have:
- `Dockerfile`
- `.dockerignore`
- A default start command

Rules:
- Containers MUST bind to `0.0.0.0` and listen on `app_port`.
- Next.js MUST use `next start -p 3000` in the container for preview.
- If build step exists, multi-stage builds are preferred.

### Step 3 - Register the App in Global Compose
Edit:
- `/opt/openclaw/infra/global-compose/docker-compose.yml`

Add a service like:
- `app_<app_slug>` as service name
- `container_name: app_<app_slug>`
- `build:` pointing to project folder OR `image:` if prebuilt
- Attach to external network `edge`
- Add Traefik labels:
  - router rule Host(`<app_slug>.<base_domain>`)
  - optionally Host(`<app_slug>.<bot_name>.<base_domain>`)

Also ensure:
- `traefik.enable=true`
- correct service port label matches container listening port

### Step 4 - Boot + Verify
- From `/opt/openclaw/infra/global-compose`:
  - `docker compose up -d --build app_<app_slug>`
- Verify container healthy:
  - `docker ps --filter name=app_<app_slug>`
  - `docker logs --tail=200 app_<app_slug>`
- Verify routing works:
  - `curl -I https://<hostname>`
  - if TLS is used with Cloudflare, verify `200/301/302` expected.

### Step 5 - Final Report (MANDATORY FORMAT)

Return a report with:

#### Summary
- App: `<app_slug>`
- Type: `<app_type>`
- Repo path: `...`
- Preview URL(s): `...`
- Status: `RUNNING` / `FAILED`

#### Tests & Checks
- Commands run:
  - ...
- Results:
  - ...

#### Deployment
- Compose service: `app_<app_slug>`
- Internal port: `<app_port>`
- Logs:
  - `docker logs -f app_<app_slug>`

#### Changes Made
- Files added/modified:
  - ...
- Global compose diff summary:
  - ...

#### If DNS is missing
- Required DNS record(s) to create:
  - `CNAME <app_slug> -> <gateway_host>` OR `A -> <server_ip>`
- If Cloudflare automation exists:
  - state exactly what was created.

## Error Handling Rules
- If build fails: capture and paste the last ~60 lines of logs + the exact failing command.
- If routing fails: show Traefik router/service status from dashboard or logs.
- Never leave the app in a partially running state without stating what is broken.
