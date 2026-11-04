# Open Rec Lite — Lovable Prompts

Paste each prompt into Lovable as one message. Attach the Simera logo (PNG or SVG) to Prompt 1.

---

## Prompt 1 — Full app (attach the Simera logo to this message)

```
Build "Open Rec", an internal web app for Simera's business development team.
Simera places pre-vetted remote technical talent with hiring companies. Open Rec shows which companies are hiring
roles that Simera's talent can fill, explains why, and lets a team member review an AI-written first outreach email.
A separate n8n pipeline fills the database every day. This app only reads the data and records human review decisions.
Nothing is ever sent from this app: there is no send button anywhere.

== BACKEND (very important) ==
Connect to my EXISTING Supabase project "open-rec-lite". The tables, enums and Row Level Security already exist.
Do NOT create, rename, drop or alter any table, column, enum, function or policy. Do NOT create migrations.
Use supabase-js only, with Supabase Auth (email + password) for login and sign-up.
Every page except login/sign-up requires a logged-in user.

Existing tables (public schema):
- company: company_id, name, website, location, contact_name, contact_title, contact_email, created_at
- job_posting: job_id, company_id -> company, run_id, source ('himalayas'), external_id, url, title, description_text,
  posted_at, expires_at, discovered_at, status enum (discovered | parsed | needs_review | scored | failed)
- job_requirement (one row per job, job_id -> job_posting): title, seniority (entry|mid|senior|lead), min_years_experience,
  required_skills text[], preferred_skills text[], timezone_offsets smallint[], employment_type, remote_policy,
  salary_min, salary_max, salary_currency, salary_period, extraction_status (ok|needs_review|failed), flag_reason,
  fit_score (0-100), fit_reason, parsed_at, scored_at
- candidate: mock talent pool (read only) — candidate_id, headline, seniority, years_experience, skills, timezone_offsets
- lead (one per company, company_id -> company): lead_id, lead_score (0-100), best_job_score, qualifying_jobs,
  status enum (qualified | not_qualified | draft_ready | approved | rejected), reason, evidence jsonb {"job_ids":[...]}, scored_at
- outreach_draft (lead_id -> lead): draft_id, subject, body, word_count, status enum (pending_review | approved | edited | rejected),
  reviewed_by uuid, reviewed_at, review_comment, created_at
- pipeline_run: run_id, trigger_type (manual|scheduled), status (running|completed|partial|failed), started_at, finished_at,
  jobs_fetched, jobs_new, jobs_updated, errors jsonb array of {at, stage, job_id?, lead_id?, detail}
- app_setting: key, value (text). Keys: lead_threshold, search_query, fetch_limit, process_limit, llm_model, run_mode, max_retries

Logged-in users may SELECT all tables and UPDATE: outreach_draft, lead, job_requirement, company, app_setting.

== PAGES ==
Left sidebar navigation: Dashboard, Jobs, Leads, Settings. User email + Log out at the bottom of the sidebar.
Top of every page: page title and a short one-line description.

1. Login / Sign up
   Centered card with the Simera logo, "Open Rec" title, tagline "From job posts to qualified leads".
   Email + password. Wrong credentials show one generic error. Link to switch between Log in and Sign up.

2. Dashboard (home)
   - 4 KPI cards: Jobs discovered, Jobs scored, Qualified leads, Drafts waiting for review.
   - "Last pipeline run" card: run id, manual/scheduled, status badge, started, duration, new/updated jobs, error count.
   - "Top leads" list: the 5 highest lead scores with company, score ring, status, and an Open button.
   - Small pipeline strip showing the 6 stages: Discovery → Understanding → Fit scoring → Lead scoring → Draft → Human review.

3. Jobs (feed)
   - Search by title or company. Filter by status. Sort by newest.
   - Table: Title, Company, Fit score (pill, empty if not scored), Status badge, Posted (relative time "2h ago").
   - Pagination (20 per page). Clicking a row opens Job detail.

4. Job detail
   - Breadcrumb Jobs › {title} · {company}, status badge on the right.
   - Left: original job description text in a scrollable card, with "View original on Himalayas ↗" link (job_posting.url, opens new tab).
   - Right: "Extracted requirements" card: title, seniority, min years, timezone (show offsets as "UTC-5, UTC-4"),
     employment type, remote policy, salary range + period. Any empty value shows a muted "Not stated" (never guess).
     Required skills and Nice-to-have skills as chips.
   - Fit card: big fit score (0-100) with colored ring and the fit_reason text.
   - If extraction_status is needs_review: a warning banner with flag_reason ("Flagged for human review").
   - "Edit fields" toggles the requirement fields into inputs; "Save" updates job_requirement.

5. Leads
   - Note at top: "Lead score = best suitable job + 5 per extra suitable job (max 100). A job is suitable when its fit score ≥ {lead_threshold}."
   - Search by company, filter by lead status, sort by lead score (default, high to low).
   - Each lead is a card: rank number, company name, "{qualifying_jobs} qualifying jobs · best job {best_job_score}",
     the reason line ("Why: …"), large lead score, status badge, Open button.
   - not_qualified leads are shown greyed out at the bottom, with their reason, under a collapsible "Not qualified" section.

6. Lead review (open from a lead)
   Two columns, everything on one screen.
   Left column:
   - "Why this lead" card: lead.reason.
   - "Suitable jobs (evidence)": jobs from lead.evidence.job_ids, each with title, fit score pill, fit_reason, link to Job detail.
   - "Contact (optional)": shows company contact or "None yet — add manually"; inline form to save contact_name, contact_title,
     contact_email on company. Never auto-fill.
   - "Review checklist": two checkboxes — "Facts match the jobs" and "Tone approved" (Approve stays disabled until both are ticked).
   Right column:
   - Latest outreach_draft for this lead: Subject and Message, with a live word counter showing "x words (120–180)",
     red when outside the range.
   - Buttons: Reject (asks for an optional comment), Edit (makes subject/body editable, then "Save edits"), Approve.
     Approve: outreach_draft.status = 'approved' (or 'edited' if the text was changed), reviewed_by = current user id,
     reviewed_at = now(), and lead.status = 'approved'. Reject: draft status 'rejected', lead.status = 'rejected'.
   - Under the buttons, muted text: "Approving marks the draft ready to send manually. Nothing is sent from Open Rec."
   - After a decision show who reviewed it and when.
   - If there is no draft yet: an empty state "No draft yet — it is created in the next pipeline run."

7. Settings
   - "Pipeline settings" card with editable fields saved to app_setting: Search keyword (search_query, e.g. "software engineer"),
     Lead threshold (0-100), Jobs per run (fetch_limit), Run mode (manual/scheduled, read-only label for now).
     Show "Saved ✓" toast after saving.
   - "Run log" card: last 10 pipeline_run rows (run id, trigger, status badge, started, duration, new jobs, errors).
     Clicking a run expands its errors list (time, stage, detail).
   - "Data source" note: "Jobs from Himalayas public API" with a link to https://himalayas.app.

== DESIGN ==
Premium, calm and modern internal SaaS look — clean, spacious and very well aligned (think Linear / Vercel dashboards).
- Use the attached Simera logo in the sidebar and on the login card. Take the brand colors from the logo:
  primary color = the logo's main color, accent = its secondary color. Build a full palette (primary, primary-hover,
  soft background tint, borders) from them as CSS variables / Tailwind theme tokens.
- Light mode by default + a dark mode toggle in the sidebar. Both must look polished.
- Font: Inter. Clear hierarchy: page title 24px semibold, card titles 16px semibold, body 14px.
- Cards with 12px radius, subtle 1px border, very soft shadow. Generous padding. Consistent 8px spacing grid.
- Status badges with consistent colors everywhere: scored/qualified/approved = green, parsed/draft_ready = brand primary,
  needs_review/pending_review = amber, failed/rejected = red, discovered/not_qualified = grey.
- Score display: 80-100 green, 60-79 brand primary, 30-59 amber, 0-29 grey. Use a circular ring for big scores and pills in tables.
- Skeleton loaders while loading, friendly empty states, toast notifications for saves and errors.
- Fully responsive (sidebar collapses to a top menu on mobile).
- Use lucide-react icons. No emojis in the UI.
```

---

## Prompt 2 — Polish and check (send after reviewing Prompt 1)

```
Review the whole app and fix:
1. Every query uses the existing Supabase tables only — no new tables, no migrations, no mock data.
2. Every status badge and score color uses the same shared component and palette on every page.
3. Empty values in Job detail always show "Not stated" — never invented values.
4. There is no send/email button anywhere. Only Approve, Edit, Reject.
5. Approve is disabled until both checklist boxes are ticked and the word count is 120-180.
6. Check alignment, spacing and dark mode on every page; make the Dashboard and Lead review look premium.
Tell me what you changed.
```

---

## Prompt 3 — "Run pipeline" button (later, after the n8n webhook is ready)

```
Add a "Run pipeline now" button to the Dashboard and Settings pages.
On click, send POST to {N8N_WEBHOOK_URL} with body {"trigger":"manual","user_id": current user id}.
Disable the button while the latest pipeline_run has status "running", and show a spinner with "Pipeline running…".
Refresh the dashboard every 10 seconds while a run is active. Show a toast when the run finishes.
```

---

## Prompt 4 — Dismiss flagged jobs + freshness setting (one message)

```
Small update. Do NOT create or alter any table, enum, function or policy — they already exist. No migrations.

1) Job detail page — human decision on flagged jobs
- When the job status is "needs_review", show a "Dismiss job" button (outline, red text) next to the status badge.
- Clicking it opens a dialog: "Dismiss this job? It will not count for any lead." with a required reason:
  a select with "Empty or template posting", "Per-task gig, not a hiring role", "Not a technical role",
  "Duplicate posting", "Other" — plus an optional note field. Confirm button disabled until a reason is chosen.
- On confirm call: supabase.rpc('dismiss_job', { p_job_id: <job id>, p_note: "<reason> — <note>" }).
  Show a toast "Job dismissed" and refresh the page.
- job_posting now has reviewed_at and review_note. When status is "dismissed", replace the yellow review banner
  with a grey banner: "Dismissed on {reviewed_at, local date and time} — {review_note}".

2) Status "dismissed" everywhere
- Add "dismissed" to the shared status badge component: grey, label "Dismissed".
- Jobs page: add "Dismissed" to the status filter. By default hide dismissed jobs (filter "All except dismissed").
- Dashboard: add a small card "Needs review" with the count of jobs in status needs_review, linking to Jobs filtered by that status.

3) Settings page
- Add a field "Max job age (days)" saved to app_setting key "max_job_age_days" (number, 1-60),
  helper text: "Postings older than this are skipped before any AI step."
- Run mode: show as read-only text "Scheduled — runs daily at 07:00 (n8n)" when app_setting run_mode = "scheduled".
```
