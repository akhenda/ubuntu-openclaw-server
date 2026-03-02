## Definition of Done: App is runnable in OpenClaw

An app task is DONE only if all items below are satisfied:

1. Project lives at:
   - `/opt/openclaw/workspace/projects/<app_slug>`

2. Dockerization exists:
   - `Dockerfile` + `.dockerignore`
   - Container listens on correct port and `0.0.0.0`

3. Global compose entry exists:
   - `/opt/openclaw/infra/global-compose/docker-compose.yml`
   - Service name: `app_<app_slug>`
   - Attached to network: `edge`
   - Includes Traefik labels for routing

4. App is running:
   - `docker compose up -d --build app_<app_slug>` succeeds
   - `docker ps` shows `app_<app_slug>` is up

5. URL works:
   - `https://<app_slug>.<base_domain>` responds (200/301/302 acceptable)
   - If bot-scoped enabled: `https://<app_slug>.<bot_name>.<base_domain>` responds

6. Health and logs captured:
   - Logs checked: `docker logs --tail=200 app_<app_slug>`
   - Any failing step includes last ~60 lines of logs in the report

7. Report posted back to Joseph:
   - Repo path
   - Preview URL(s)
   - Test commands + results
   - How to view logs
   - What changed (file list + compose diff summary)

If DNS is missing, the report must explicitly list the required DNS records.
