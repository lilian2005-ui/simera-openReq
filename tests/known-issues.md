# Known Issues & Fixes

| # | Issue | Fix | Status |
|---|---|---|---|
| 1 | No scheduled run: workflows were not published. | Workflow 1 timezone = Asia/Gaza; publish workflows 1–3. | In progress (manual step in n8n) |
| 2 | Dashboard "Qualified leads" showed 0 while 2 leads were draft_ready. | Lovable: count qualified + draft_ready + approved. | Prompt sent to Lovable |
| 3 | Run duration showed 2–3 s. | Old runs were stage-1 only. The Close Run node (end of Workflow 1) now closes the run after all stages. | Verify on next full run |
| 4 | "Sign up" link visible on the login page. | Hide link + disable sign-ups in Supabase. | Postponed |
| 5 | Online Doctor AG scored 85 although it only hires people living in Germany or Switzerland. | **Rule (database):** store Himalayas `locationRestrictions`; `location_flag()` + `save_requirements` send jobs restricted outside Simera talent regions to *Needs review* (setting `talent_regions`). **AI backup:** Gemini extracts `hiring_countries` from the posting text; *Validate Requirements* flags it. | Code deployed; job 5 reset to `discovered` for re-reading |
| 6 | knowmad mood lead reason named skills (microservices, hexagonal architecture) the fit evidence said were missing. | Draft prompt v2.2: lead reason and body may only name skills the fit evidence confirms. | Prompt deployed; old draft marked *rejected* (superseded) and lead reset to `qualified` for a new draft |
| 7 | Dismiss reason "Not a technical role" contradicts Simera's technical + business talent. | Lovable: rename to "Outside Simera talent scope". | Prompt sent to Lovable |

## Changes by component

**Supabase — migration `supabase/12_location_restrictions.sql`**
- `app_setting.talent_regions`: worldwide, MENA countries, EMEA, Türkiye.
- `location_flag(source_meta)`: returns "hiring limited to: …" when every allowed country is outside the talent regions (whole-word match, e.g. "Romania" ≠ "Oman").
- `ingest_jobs`: saves `source_meta.location_restrictions`.
- `save_requirements`: applies `location_flag` before saving; restricted jobs → `needs_review`, never counted for leads.

**n8n — Code nodes**
- Workflow 1 · *Normalise Jobs* (`n8n/js/normalise_jobs.js`): passes `location_restrictions`.
- Workflow 2 · *Build Prompts* (`n8n/js/prepare_prompts.js`): new `hiring_countries` field + `talent_regions` from settings.
- Workflow 2 · *Validate Requirements* (`n8n/js/validate_requirements.js`): flags hiring countries outside the talent regions.
- Workflow 3 · *Build Draft Prompt* (`n8n/js/build_draft_prompt.js`): prompt v2.2 (previous: `build_draft_prompt.v2.1.js`).

**Data changes (approved)**
- Job 5 (Online Doctor AG) → `discovered` to be re-read with the new rules.
- knowmad mood: pending draft → `rejected` with comment "Superseded…"; lead → `qualified` so a v2.2 draft is written.
