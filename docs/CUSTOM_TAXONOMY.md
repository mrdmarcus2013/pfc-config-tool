# Box 81cc taxonomy

The editor offers None, Standard, and Custom. None suppresses billing-provider
taxonomy. Standard uses the provider lookup. Custom reports a fixed code and
requires exactly 10 ASCII letters or digits; trim surrounding whitespace and
normalize letters to uppercase. Format validation does not verify membership
in the NUCC code set or whether a code is appropriate for a provider.

The existing current/preview/apply endpoints support `PROVIDER_TAXONOMY_CUSTOM`
with `taxonomy_code`. On/Off option codes retain their existing behavior.
A code is required for Custom and rejected for every other option.
Current display and change responses include the custom code.

The Oracle option function builds Custom from Standard: enable the existing
PRV record, set only managed PRV03 HARD_CODED_DATA, and clear its STO_PROC_NAME.
The generic engine preserves the complete source and unmanaged fields, enforces
safety invariants, compares complete functional states, and hashes the desired
code. Apply remains atomic and requires a matching preview. Same-payor plan
inheritance and minimal overrides apply unchanged. Missing or ambiguous targets
and unsupported effective taxonomy values fail safely.

Switching Custom to Standard restores the provider lookup and clears the fixed
code. Switching to None also clears the fixed code using the existing Off
recipe. Previews and confirmations describe removal. Standard is an explicit
provider lookup request, not an inheritance/default request.

## Local upgrade

Run the preview, review it, then install against local synthetic Oracle:

```powershell
.venv/Scripts/python.exe database/run_poc.py install_taxonomy
.venv/Scripts/python.exe database/run_poc.py install_taxonomy --confirm-taxonomy
```

Restart the backend and refresh the frontend. This upgrade replaces routines
without reseeding or changing configuration rows. Fresh installation already
loads the updated function and procedures. Production harnesses have not been
extended for Custom; they remain governed by PRODUCTION_DATABASE_BOUNDARY.md.
