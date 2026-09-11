# Set up the PFC Configuration Tool on a new computer

This walkthrough installs the local viability demonstration from GitHub and
starts both the normal and Tier 2 views. It targets **Windows 11 on an Intel or
AMD 64-bit computer, using PowerShell**. macOS, Linux and Windows on ARM need
platform-specific installation steps and have not been verified by this guide.

The application runs on your computer with its own synthetic Oracle database.
Downloading the repository does not copy another person's saved demo settings,
database files or passwords. GitHub access is needed to obtain the repository;
the running application does not depend on the original developer's computer.

Use this only for the local synthetic demonstration. Do not point these setup
commands at MatrixCare or another existing database. Production work remains
outside this guide; see the [production boundary](PRODUCTION_DATABASE_BOUNDARY.md).

## What you will run

| Component | Address used in this guide | How it runs |
| --- | --- | --- |
| Normal end-user view | <http://127.0.0.1:5174/> | Frontend terminal; technical details disabled |
| Tier 2 view | <http://127.0.0.1:5173/> | Separate frontend terminal; collapsed technical details enabled |
| Backend API | <http://127.0.0.1:8000/api/health> | Python terminal shared by both views |
| Oracle | `localhost:1521`, service `FREEPDB1` | Docker container named `pfc-oracle` |

Both views use the same database. A change saved in one is visible to the other
after refreshing its configuration. Tier 2 is a local display setting, not an
authenticated permission role. The port assignments are explicit below; bare
`npm run dev` otherwise uses the Vite configuration's default port, 5173.

## 1. Install the prerequisites

Install these tools using their official Windows installers:

| Tool | Version or choice | Purpose |
| --- | --- | --- |
| [Git for Windows](https://git-scm.com/install/windows) | Current supported release, with its credential manager | Download and update the repository |
| [Python for Windows](https://www.python.org/downloads/windows/) | Python **3.13**, 64-bit, including the `py` launcher | Backend and database installer |
| [Node.js](https://nodejs.org/en/download) | Node **22.12 or later in the 22.x line**, or **24 LTS**, including npm | Frontend |
| [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/) | Windows installation using the WSL 2 backend and **Linux containers** | Local Oracle database |

Vite 7.1.3's committed dependency metadata requires Node `^20.19.0 || >=22.12.0`;
this guide's local verification used Node 22.17.1. Use Python 3.13 to match the
verified backend family. You do not need a separate Windows Oracle installation
or SQL*Plus installation: SQL*Plus is available inside the database container,
and the backend uses the Python Oracle driver's Thin mode.

Follow Docker's current [Windows system requirements](https://docs.docker.com/desktop/setup/install/windows-install/),
including WSL 2 and hardware virtualization. Microsoft's [WSL installation guide](https://learn.microsoft.com/en-us/windows/wsl/install)
explains the initial setup and restart. On a managed work computer, have IT enable
the required software and virtualization if your account cannot do so.

After installing, open Docker Desktop and wait for its engine to start. Open a
**new PowerShell window** and check:

```powershell
git --version
py -3.13 --version
node --version
npm.cmd --version
docker compose version
docker info --format '{{.OSType}}'
```

Each command should succeed; the final result should be `linux`. Internet access
is needed for GitHub, Python/npm packages and Oracle's container registry during
installation. Allow disk space for the Oracle image, persistent database and
project dependencies.

## 2. Download the repository

Accept the repository invitation first if access is restricted. These commands
use a folder under your Windows user profile so they do not require creating a
folder at the drive root:

```powershell
New-Item -ItemType Directory -Path "$env:USERPROFILE\source" -Force | Out-Null
Set-Location "$env:USERPROFILE\source"
git clone https://github.com/mrdmarcus2013/pfc-config-tool.git
Set-Location .\pfc-config-tool
git status --short --branch
```

Complete GitHub's sign-in prompt if requested. See [GitHub's cloning instructions](https://docs.github.com/en/repositories/creating-and-managing-repositories/cloning-a-repository)
for authentication help. Do not embed a token or password in the clone URL.

The rest of the guide assumes the repository is at
`$env:USERPROFILE\source\pfc-config-tool`. Substitute your chosen path if different.
Run each command block separately and resolve an error before continuing.

## 3. Create the Python environment and install the frontend

From the repository root:

```powershell
py -3.13 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m pip check
Set-Location .\frontend
npm.cmd ci
Set-Location ..
```

The Python check should report no broken requirements. `npm ci` installs the
versions in `frontend/package-lock.json`; it does not require changing the lock.
This guide uses explicit Python paths and `npm.cmd`, so virtual-environment
activation and PowerShell execution-policy changes are unnecessary.

## 4. Set local passwords and connection settings

Create the local environment file **once**. If it already exists, inspect your
existing setup rather than overwriting it:

```powershell
if (Test-Path -LiteralPath .env) { throw '.env already exists; review it before continuing.' }
Copy-Item -LiteralPath .env.example -Destination .env
notepad.exe .env
```

Fill all seven settings in the editor:

```dotenv
ORACLE_PWD=REPLACE_WITH_YOUR_LOCAL_ADMIN_PASSWORD
ORACLE_HOST=localhost
ORACLE_PORT=1521
ORACLE_SERVICE=FREEPDB1
ORACLE_SERVICE_NAME=FREEPDB1
ORACLE_USER=PFC_DEMO
ORACLE_PASSWORD=REPLACE_WITH_YOUR_LOCAL_APP_PASSWORD
```

Replace both password placeholders with your own passwords before saving.
For this walkthrough, use two different password-manager-generated passwords of
at least 20 letters and digits, with upper- and lower-case letters and a digit.
This avoids quoting/interpolation issues in the setup commands. Keep them locally.

- `ORACLE_PWD` initializes the container's administrator password, used for
  `SYSTEM` during first-time schema creation.
- `ORACLE_PASSWORD` is the separate password you will assign to `PFC_DEMO` in
  step 6. The backend uses this account.
- Keep **both** service settings: the backend prefers `ORACLE_SERVICE`; the
  database runner requires `ORACLE_SERVICE_NAME`.

Check that Git ignores the file:

```powershell
git check-ignore .env
```

Expected output: `.env`. Never commit or send this file with the project.
If this PowerShell session already has `ORACLE_*` environment variables from
another project, use a fresh session without those overrides: existing process
environment values take precedence over `.env`.

## 5. Start Oracle and wait for it to become ready

From the repository root:

```powershell
docker compose pull
docker compose up -d
docker compose ps
docker inspect --format '{{.State.Health.Status}}' pfc-oracle
```

The first download and initialization can take several minutes. Repeat the last
command until it reports `healthy`; `starting` means Oracle is still initializing.
If it becomes `unhealthy`, inspect `docker logs --tail 80 pfc-oracle` and resolve
the problem before continuing. Docker Desktop must remain running.

The named Docker volume stores the database across ordinary stops and restarts.
Changing `ORACLE_PWD` in `.env` after a database has already been initialized does
not change that database's existing administrator password.

## 6. Create a dedicated local application schema

Docker startup creates the Oracle instance, but **does not create `PFC_DEMO`**.
Open SQL*Plus inside the container from PowerShell:

```powershell
docker exec -it pfc-oracle sqlplus /nolog
```

At the **SQL> prompt**, connect and enter the administrator password from
`ORACLE_PWD` when prompted:

```sql
CONNECT SYSTEM@//localhost:1521/FREEPDB1
```

Enter the password before pasting the next commands:

```sql
SHOW CON_NAME
SELECT username FROM all_users WHERE username = 'PFC_DEMO';
SELECT tablespace_name FROM dba_tablespaces WHERE tablespace_name = 'PFC_DEMO_DATA';
SELECT file_name FROM dba_data_files WHERE tablespace_name = 'SYSTEM';
```

Confirm the container is `FREEPDB1` and both the user and tablespace checks return
**no rows**. The SYSTEM datafile should be in
`/opt/oracle/oradata/FREE/FREEPDB1/`. If that directory differs, stop and have the
local database administrator adapt the datafile path below. If the user or
tablespace already exists, this is no longer a fresh installation; do not drop
or overwrite it to continue the guide.

This Oracle Lite image does not provide a `USERS` tablespace. Review the following
creation step: it creates a dedicated 100 MB application tablespace, which can
grow to 500 MB, then a local schema with a 100 MB quota. The schema can connect
and create its own tables, PL/SQL routines and triggers; it receives no DBA role.
The new datafile is stored in the persistent Docker volume. No `REUSE` clause is
used, so an existing file will not be overwritten.

Still at the SQL> prompt, run:

```sql
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE TABLESPACE PFC_DEMO_DATA
  DATAFILE '/opt/oracle/oradata/FREE/FREEPDB1/pfc_demo_data01.dbf'
  SIZE 100M AUTOEXTEND ON NEXT 10M MAXSIZE 500M;
SET ECHO OFF
SET VERIFY OFF
ACCEPT pfc_app_password CHAR PROMPT 'Enter the application password from ORACLE_PASSWORD: ' HIDE
```

Enter exactly the `ORACLE_PASSWORD` value at that prompt. **After entering the
password**, run the remaining commands:

```sql
CREATE USER PFC_DEMO IDENTIFIED BY "&pfc_app_password"
  DEFAULT TABLESPACE PFC_DEMO_DATA TEMPORARY TABLESPACE TEMP
  QUOTA 100M ON PFC_DEMO_DATA;
UNDEFINE pfc_app_password
GRANT CREATE SESSION, CREATE TABLE, CREATE PROCEDURE, CREATE TRIGGER TO PFC_DEMO;
EXIT
```

The password is hidden and is not part of a PowerShell command. Return to
PowerShell for the next steps.

## 7. Verify the target, then install the schema and base demo

From the repository root, run this **read-only preflight**:

```powershell
@'
import os
from backend.app.database import create_connection, get_oracle_settings
settings = get_oracle_settings()
assert settings.host in {"localhost", "127.0.0.1"}, "Local database required"
assert settings.user.upper() == "PFC_DEMO", "Expected the dedicated PFC_DEMO account"
assert settings.port == 1521, "Expected the local database port 1521"
assert settings.service == os.environ.get("ORACLE_SERVICE_NAME") == "FREEPDB1", "Both service settings must be FREEPDB1"
with create_connection() as connection, connection.cursor() as cursor:
    cursor.execute("SELECT USER, SYS_CONTEXT('USERENV','CON_NAME') FROM dual")
    user, container = cursor.fetchone()
    cursor.execute("SELECT COUNT(*) FROM user_objects")
    count = cursor.fetchone()[0]
    print(f"Target: {user} in {container}; existing objects: {count}")
    assert container == "FREEPDB1" and count == 0, "Stop: target must be a fresh FREEPDB1 schema"
print("Preflight passed. Next step creates tool objects and synthetic data in this schema.")
'@ | .\.venv\Scripts\python.exe -
```

Only proceed after that check passes and you have reviewed the target. The next
command executes DDL and loads synthetic data; it is a **first-install command,
not a restart or upgrade command**:

```powershell
.\.venv\Scripts\python.exe database/run_poc.py install
```

Expected final message: `Oracle POC action 'install' completed successfully.`
If it fails, stop and retain the error for troubleshooting. Oracle DDL can persist
before a later error; do not blindly rerun installation against the partial schema.

The current fresh installer loads the latest package source files, including
plan ownership, Value Codes and Copy. The numbered upgrade wrappers described
in older change documents are for existing installations; do not run all of
them again just because their numbers are higher than `010`.

## 8. Load the plan and Copy demonstration examples

The base seed supplies the default UI payor and shared synthetic configurations.
Add the dedicated plan examples. Run the preview, review its description, and
then run the command with `--apply`:

```powershell
.\.venv\Scripts\python.exe -m database.maintenance.seed_payor_plans
.\.venv\Scripts\python.exe -m database.maintenance.seed_payor_plans --apply
```

This adds **Synthetic Plan Demo Home Health** and **Synthetic Plan Demo Hospice**,
with three named plans each and different settings for demonstration.

Next add the Copy examples, again reviewing the preview before applying:

```powershell
.\.venv\Scripts\python.exe -m database.maintenance.seed_payor_copy
.\.venv\Scripts\python.exe -m database.maintenance.seed_payor_copy --apply
```

This adds **Synthetic Copy Demo Source**, its **Working Source Plan**, and
**Synthetic Copy Demo Destination** with two destination plans. Both seeders
rehearse changes with rollback before saving them. They reject existing fixture
IDs to preserve later edits. Run them once, not every time you start the tool.

## 9. Start the backend

Open **PowerShell terminal A** and keep it open:

```powershell
Set-Location "$env:USERPROFILE\source\pfc-config-tool"
.\.venv\Scripts\python.exe -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8000
```

Wait for `Application startup complete`. In another PowerShell window:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/health
```

Expected values: `application = ok` and `oracle = connected`. This checks the
connection; it does not by itself prove the schema or sample data was installed.

## 10. Start the normal view and optional Tier 2 view

Open **PowerShell terminal B** for the normal view and keep it open:

```powershell
Set-Location "$env:USERPROFILE\source\pfc-config-tool\frontend"
$env:VITE_ENABLE_TECHNICAL_DETAILS = 'false'
npm.cmd run dev -- --host 127.0.0.1 --port 5174 --strictPort
```

Open **<http://127.0.0.1:5174/>** in your browser.

For Tier 2, open **a separate PowerShell terminal C** and keep it open:

```powershell
Set-Location "$env:USERPROFILE\source\pfc-config-tool\frontend"
$env:VITE_ENABLE_TECHNICAL_DETAILS = 'true'
npm.cmd run dev -- --host 127.0.0.1 --port 5173 --strictPort
```

Open **<http://127.0.0.1:5173/>**. This view adds collapsed Technical Details;
normal controls and operations are the same. The flag is read when Vite starts.
Restart that frontend if you change it. `--strictPort` makes a port conflict an
explicit error instead of silently changing the URL.

No separate Oracle client, IDE or coding assistant is required to use the tool
after these services are running.

## 11. Check that the demonstration is ready

First check the API through the normal frontend's proxy:

```powershell
Invoke-RestMethod http://127.0.0.1:5174/api/health
(Invoke-RestMethod http://127.0.0.1:5174/api/options).fields.Count
(Invoke-RestMethod http://127.0.0.1:5174/api/support/payor-contexts).contexts.Count
```

Health should still show Oracle connected; both counts should be greater than
zero. Then check these steps in the browser:

1. The payor dropdown loads and the page reports **Capabilities loaded**.
2. Select **Synthetic Plan Demo Home Health**. The Plan dropdown includes
   **All Plans** and the three named plans. Selecting another payor changes the
   available plans.
3. Open Value Codes. Current settings and editable CBSA/FIPS controls appear.
   Changing FIPS also respects the CBSA requirement.
4. Change a setting and choose **Preview**. Review the result, then Cancel if
   you want to leave the saved demonstration unchanged.
5. Select **Synthetic Copy Demo Source** and **Working Source Plan**. Open
   **COPY PAYOR SETTINGS**, select **Synthetic Copy Demo Destination**, and run
   Preview. Review the replacement and plan-reset information before Cancel or
   deliberate acceptance. Accept and Copy changes the saved destination setup.
6. Normal mode has no Technical Details sections. Tier 2 exposes them collapsed;
   template names and inheritance sources appear only when those details open.

**All Plans** edits shared payor settings. A named plan's own applicable settings
still take precedence. The [viability Q&A](VIABILITY_DEMO_QA.md) explains the
available workflows and their limits.

## 12. Stop and restart without reinstalling

Press **Ctrl+C** in each frontend/backend terminal to stop that service. To stop
Oracle, from the repository root run:

```powershell
docker compose stop
```

For the next session, start Docker Desktop, run `docker compose up -d`, wait for
Oracle to become healthy, and repeat steps 9 and 10. **Do not repeat schema
creation, installation or seed commands.** Your saved demo settings remain in
the Docker volume. Do not use `docker compose down -v` for an ordinary shutdown;
that deletes the database volume.

## 13. Get a newer GitHub version

Stop the frontend/backend terminals, then from the repository root:

```powershell
git status --short
git pull --ff-only
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Set-Location .\frontend
npm.cmd ci
Set-Location ..
```

Review any local changes before pulling. If Git refuses the fast-forward, do not
discard local work just to proceed. Read the update's database instructions:
pulling code does not install Oracle package updates. Use the specific documented
preview/confirmation upgrade for that release, then restart the services. Never
use fresh `install`, `reset` or reseeding as a routine update procedure.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| GitHub says repository not found or access denied | Accept the invitation and authenticate with the GitHub account that has access. |
| `py`, `node`, `npm.cmd` or `docker` is not found | Finish the corresponding installation and open a new PowerShell window. Confirm Python 3.13 with `py -3.13 --version`. |
| Docker cannot connect to its engine | Start Docker Desktop; confirm WSL 2/virtualization and Linux containers. Resolve installation restrictions with IT. |
| Oracle image pull fails | Check network/proxy access to `container-registry.oracle.com`; follow any registry authentication instructions returned. Do not disable certificate verification. |
| Port is already allocated / address already in use | Check for another Oracle or tool instance. Stop your duplicate process gracefully or use an explicitly chosen free frontend port. Backend port 8000 is the configured proxy target. |
| Oracle is still `starting` | Wait for initialization; inspect recent container logs if it does not become healthy. |
| ORA-01017 / invalid username-password | Match `ORACLE_USER` and `ORACLE_PASSWORD` to the app user created in FREEPDB1. `ORACLE_PWD` is a different, administrator password. Restart the backend after changing `.env`. |
| ORA-65096 during user creation | Confirm you connected to `FREEPDB1`, not the root container. |
| ORA-01950 / quota or ORA-01031 / privileges | Check the PFC_DEMO_DATA quota and four grants from step 6 for the dedicated app user. |
| ORA-00959 / tablespace does not exist | Complete the dedicated PFC_DEMO_DATA creation in step 6; this Lite image does not include USERS. |
| ORA-00955 during installation | Objects already exist or an earlier install partially completed. Stop and inspect that schema instead of rerunning or resetting it. |
| API is healthy but capabilities or payors do not load | Health only checks connectivity. Confirm installation and fixtures completed in the same schema configured for the backend. |
| "Fixtures already exist" | They are one-time examples. Continue with the existing fixtures; do not overwrite them to restart the application. |
| Tier 2 details appear in the normal view | Confirm the URL and start that frontend with `VITE_ENABLE_TECHNICAL_DETAILS='false'`; restart Vite after changing the flag. |
| Vite reports `spawn EPERM` | Run the frontend from ordinary PowerShell using the documented npm script, which already uses `--configLoader native`. Check that Windows or endpoint policy allows Node to start child processes. Do not hide the error overlay or disable security controls to mask the failure. |
| `npm ci` reports security advisories | This guide uses the committed dependency versions. Record the advisories for the developer; do not apply `npm audit fix --force` as part of setup. |

For setup help, share the failing command, its error, tool versions and Git commit
(`git rev-parse --short HEAD`). Do not include `.env` or passwords.

## Verification record and limits

Checked **September 11, 2026**, against application commit `b03434a`, using
Python 3.13.5, Node 22.17.1, npm 11.5.2 and Docker Engine 29.6.2 on Windows.

| Check | Result |
| --- | --- |
| Fresh Python virtual environment | `pip install -r requirements.txt`, dependency check and application imports passed; backend tests: **396 passed, 4 skipped** |
| Fresh frontend directory with committed lockfile | `npm ci` and build/typecheck passed |
| Dedicated new Oracle tablespace and empty application schema | SYSTEM administrator creation, the four grants and 100 MB quota worked; fresh `install` completed with **zero compilation errors or invalid objects** |
| Plan and Copy examples | Both preview/apply seed sequences passed their rollback rehearsals and committed only into the disposable schema |
| Final seeded data | **30 payors, 43 PFCs, 18 registered plans, 45 HERs and 180 HEFs** |
| API readiness against the fresh schema/dependencies | Oracle connected; **39 selector contexts**; all four field areas resolved in the default UI, both custom-plan LOB examples and the Copy source plan |
| Additional read/preview checks | Explicit Value Codes Off preview passed; Copy found **9 eligible destinations**, including the named demo destination; its preview covered **3 destination contexts** |
| Both frontend launch commands | Homepages and environment modules returned HTTP 200 with the expected false/true flags; the API health proxy worked |

The database rehearsal used temporary schema/tablespace names in an **existing
local Oracle container and FREEPDB1**, not a newly initialized Docker volume.
Temporary schemas, the added tablespace/datafile and credentials were removed
after verification; the existing demonstration's nine-table configuration
fingerprint was unchanged. Frontend launch checks used free ports 5184/5183 to
avoid interfering with the existing normal/Tier 2 servers; both temporary
process trees were stopped afterward. These are HTTP and API checks, not a new
mounted-browser acceptance test.

Windows installation, Docker Desktop/WSL provisioning and a brand-new Oracle
volume were not rehearsed. Follow the linked official prerequisite instructions
for those steps. Python requirements and the Compose image tag are unpinned,
so later downloads may differ from this verification. The committed frontend
lockfile installed successfully but npm reported **five high-severity
development-toolchain advisories** (Vite, Rollup, PostCSS, Picomatch and Nanoid).
This documentation change does not update dependencies; those need a separately
tested maintenance change. Keep the local launch bindings shown in this guide.
