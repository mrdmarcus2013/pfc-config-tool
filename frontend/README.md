# PFC Configuration Tool frontend

This is the standalone React and TypeScript vertical slice for **Customize
Claim Fields**. Vite provides the local development server and production
bundle. The UI is intentionally dependency-light and uses ordinary CSS.

## Run locally

From the repository root, start the FastAPI backend:

```powershell
.\.venv\Scripts\python.exe -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8000 --reload
```

In a second terminal:

```powershell
cd frontend
npm install
npm run dev
```

Open `http://127.0.0.1:5173/`. Vite proxies `/api` to the local backend at
`http://127.0.0.1:8000`; the frontend contains no production endpoint.

The local page automatically uses the synthetic `Synthetic UI Demo Payor`
launch context. GUIDs are not editable and are shown only in the collapsed
Technical Details area when support/developer mode is enabled. The `audit_user`
is supplied by the development launch context and remains internal, never shown
or editable. Oracle continues to resolve the PFC using `payor_guid` and nullable
`plan_guid`; the display-context `pfc_guid` is never sent as a target.

The UI Demo Payor starts with Line of Business undefined. Home Health or
Hospice must be saved before Fields 77 and 81 can be opened. A later Line of
Business change uses a warning, read-only reset preview, and final confirmation.
Successful reset closes the field editor and clears cached field state so the
next opening performs a fresh Oracle read.

MatrixCare host integration is future work. A host launch is expected to supply
`payor_guid`, nullable `plan_guid`, `pfc_guid`, and the authenticated audit-user
context. The MatrixCare Template-button entry point is not implemented in this
standalone checkpoint.

## Support/developer diagnostics

Technical Details are hidden from the normal support experience. Developers or
Tier 2 support can enable the collapsed diagnostic sections for a local Vite
session with the environment value `VITE_ENABLE_TECHNICAL_DETAILS=true`:

```powershell
cd frontend
$env:VITE_ENABLE_TECHNICAL_DETAILS = "true"
npm run dev
```

For a production bundle, set the same value before `npm run build`; Vite embeds
the setting at build time. Unset the environment value or set it to `false` for
the normal customer-facing mode. No visible developer-mode control is rendered.

## Catalog and capabilities

The static 159-entry catalog covers every numbered CMS-1450/UB-04 locator and
its recognizable lettered subfields. Labels and locator structure are derived
from the **Form CMS-1450 Layout Summary** in the CMS *Medicare Claims Processing
Manual, Chapter 25*. The application presents them in the approved eight-section
workflow:

- Billing Details
- Patient
- Admissions & Occurrences
- Services
- Insurance
- Diagnosis & Procedure Codes
- Providers
- Other

Reference: <https://www.cms.gov/manuals/downloads/clm104c25.pdf>

The catalog owns standard labels, order, sections, and neutral capability keys.
`GET /api/options` owns runtime availability. A supported field is enabled only
when the API supplies its complete expected public option set. All other fields
stay visible and disabled as **Not configurable yet**.

- **77 — Operating Provider** opens Service Facility reporting settings.
- **80 — Remarks** opens Default/Custom remark settings.
- **81 — cc** opens Provider Taxonomy reporting.

No Oracle record types, stored procedures, target selectors, or HER/HEF logic
exist in the catalog or user-facing controls.

Field 80 defaults to the complete inherited source configuration. Selecting
Custom exposes a text editor for the actual claim remark; the trimmed text is
sent through Preview/Apply and stored by Oracle as NTE02 hard-coded data.
Recognized current Custom text is returned and repopulates that editor. Blank
or whitespace-only remarks are blocked because they can cause claim rejection.
The displayed maximum is the temporary configured limit exported as
`REMARKS_CUSTOM_REMARK_MAX_LENGTH` from `src/app/remarks.ts`; it is not a
confirmed MatrixCare production limit. Future managed NTE fields can extend the
structured overlay without exposing stored procedures or technical recipes in
the normal UI.

## Preview and apply

Each supported editor lazily calls `POST /api/config/current` once for its
payor/plan/field context. The Oracle-resolved effective configuration is shown
as **Current configuration**, and the controls initialize from it. Changes are
shown separately as **Proposed configuration** before the editor follows
Preview → Apply. Service Facility remains one request even though Oracle owns
multiple atomic targets. A preview hash is retained only while the option and
launch context are unchanged. `NO_CHANGE` and blocked previews cannot be
applied. Apply requires confirmation and forwards the exact preview hash.

Current state is cached by payor, plan, and field for the launch-context
lifetime. Stale previews clear the retained hash, refresh the authoritative
current state while preserving the proposal, and return the editor to the
normal **Preview** workflow.
Successful Apply invalidates that field's cache and performs one fresh current
read; it does not perform an unnecessary preview. A synchronous single-flight
gate prevents simultaneous duplicate preview or apply requests. API errors are
translated to safe user messages; raw Oracle details are not rendered.
After that fresh read confirms the requested state, the completion footer shows
only **Close**; dismissing it performs no API or database action.

## Checks

```powershell
cd frontend
npm test
npm run build
```

Vite serves `src/main.tsx` directly and owns the browser TypeScript, JSX, and
React dependency transformation. Node unit tests compile their imports into the
separate ignored `.test-build` directory; those artifacts are never browser
entry points. The production build is emitted to the ignored `dist` directory.
