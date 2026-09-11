# Onfinity On-Premise

Self-hosted deployment of the Onfinity ERP/CRM: ASP.NET 4.8 on IIS (Windows container),
backed by PostgreSQL. Runs entirely on your own infrastructure with Docker — no Azure
account or cloud services required.

## Architecture: two dedicated hosts

The app **must** run as a Windows container (it's ASP.NET 4.8 / IIS); official
PostgreSQL images are Linux-only. A single Docker engine runs Windows containers *or*
Linux containers, never both at once — so this deploys across **two separate hosts**:

- **Windows host** — runs the app ([docker-compose.windows.yml](docker-compose.windows.yml))
- **Linux host or VM** — runs PostgreSQL ([docker-compose.linux.yml](docker-compose.linux.yml))

They talk to each other over the network on port 5432. Nothing here relies on
`host.docker.internal`, engine-switching, or any single-box workaround — two ordinary
Docker hosts, one service each.

## Prerequisites

**Windows host**
- Windows 10/11 Pro/Enterprise or Windows Server 2019+
- Docker Desktop or Docker Engine set to **Windows containers** mode
- ~10 GB free disk
- Port `8080` free (or a different one via `WEB_PORT`)
- Internet access to run [vendor/fetch-pg-client.ps1](vendor/fetch-pg-client.ps1) once (see below) — not required on the container itself

**Linux host**
- Any Docker host (physical, VM, or cloud instance)
- Port `5432` reachable from the Windows host (open it in the firewall/security group
  between the two)

## Quick Start

**On the Linux host:**

1. Copy `.env.example` to `.env` and set a real `POSTGRES_PASSWORD`. `.env` is
   gitignored — it holds real credentials and should never be committed.
2. Start the database:

   ```bash
   docker compose -f docker-compose.linux.yml up -d
   ```

3. Note this host's address (LAN IP or hostname) — you'll need it on the Windows host.

**On the Windows host:**

1. Fetch the PostgreSQL client tools used for the automatic database import (one-time,
   needs internet access on the machine doing the build — not on the container):

   ```powershell
   ./vendor/fetch-pg-client.ps1
   ```

2. Copy the *same* `.env` from the Linux host (credentials must match — don't
   generate a separate one from `.env.example`), and set `POSTGRES_HOST` to
   that host's address.
3. Build and start the app:

   ```powershell
   docker compose -f docker-compose.windows.yml up -d --build
   ```

4. Watch it come up (first start also imports the database over the network):

   ```powershell
   docker compose -f docker-compose.windows.yml logs -f web
   ```

5. Browse to `http://localhost:8080` (or whatever `WEB_PORT` you set).

To stop either side: `docker compose -f <file> down`. Postgres's data stays on disk
under `./data/postgres` on the Linux host (bind-mounted, not a named volume) — `down`
doesn't touch bind-mounted host directories.

## Configuration

Set once in `.env`, copied identically to **both** hosts so credentials stay in sync:

| Variable | Default | Used by | Purpose |
|---|---|---|---|
| `POSTGRES_HOST` | *(none — required)* | Windows host | The Linux host's address. Deliberately has no default; the compose file refuses to start without it rather than silently guessing wrong |
| `POSTGRES_USER` | `viennacrmuser` | both | DB user |
| `POSTGRES_PASSWORD` | `changeme` | both | DB password — **change this before going to production** |
| `POSTGRES_DB` | `onfinitydb` | both | Database name |
| `DB_PORT` | `5432` | both | DB port |
| `WEB_PORT` | `8080` | Windows host | Host port the app is published on |
| `ASPNETCORE_ENVIRONMENT` | `Production` | Windows host | ASP.NET environment |

The entrypoint script rewrites `web.config`'s connection string from these values on
every container start, so changing `.env` and re-running `up -d` on the Windows host is
enough to repoint the app at a different database.

## Backup & Restore

Run these on the Linux host, against the `onfinity-db` container:

```bash
# Backup
docker exec onfinity-db pg_dump -U viennacrmuser -d onfinitydb -Fc -f /tmp/backup.dump
docker cp onfinity-db:/tmp/backup.dump ./backup.dump

# Restore into a fresh database
docker cp ./backup.dump onfinity-db:/tmp/backup.dump
docker exec onfinity-db pg_restore -U viennacrmuser -d onfinitydb --no-owner --no-privileges -j 4 /tmp/backup.dump
```

The data directory is also bind-mounted to `./data/postgres` on the Linux host, so
ordinary file-based backups pick it up too — prefer the `pg_dump`/`pg_restore` pair
above for a guaranteed-consistent snapshot rather than copying files from a live
database.

## Updating the Application

On the Windows host, to pick up a new build (new files under [publish/](publish/)):

```powershell
docker compose -f docker-compose.windows.yml up -d --build
```

The database import only runs once (tracked via a `.db-imported` marker file inside the
container), so rebuilding/restarting the app container won't re-import or overwrite
existing data.

## HTTPS / Reverse Proxy

The app container serves plain HTTP on port 80 internally. For production use, put it
behind a reverse proxy that terminates TLS with your own certificate — IIS ARR, nginx,
Traefik, or whatever load balancer your environment already runs — and bind `WEB_PORT`
to an internal-only interface rather than exposing it directly.

## Troubleshooting

- **Windows host refuses to start with "Set POSTGRES_HOST in .env..."**: expected —
  there's no safe default for the Linux host's address. Set it in `.env`.
- **Container exits immediately / IIS won't start**: check
  `docker compose -f docker-compose.windows.yml logs web`; the entrypoint logs each
  setup step (permissions, DB wait, DB import, web.config update, IIS app pool config)
  as it runs.
- **Database import didn't run / "PostgreSQL was not reachable"**: confirm port 5432 is
  open between the two hosts (test with `Test-NetConnection <linux-host> -Port 5432`
  from the Windows host) and that `POSTGRES_HOST`/credentials in `.env` match on both
  sides.
- **Can't reach the app**: confirm Docker is in Windows-container mode
  (`docker info` should report `OSType: windows`) and that `WEB_PORT` isn't already in
  use on the host.

## License

Proprietary - © Vienna IT Solutions Pvt. Ltd. All rights reserved.
