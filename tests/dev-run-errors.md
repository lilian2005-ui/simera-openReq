# Development run errors (kept as testing evidence)

These errors were logged on runs 2 and 3 during development. They were removed from the live run log
on 4 Nov 2026 so the Settings → Run log shows production runs only. Each one led to a fix.

| When (UTC) | Stage | Count | Error | Cause | Fix |
|---|---|---|---|---|---|
| 2 Nov 18:18–18:29 | ai_call | 2 | `Service unavailable` (503) | `gemini-flash-latest` = Gemini 3 Flash, free limit 5 requests/min, overloaded | Switched model (setting `llm_model`), 5 s pause between jobs, 3 retries |
| 2 Nov 18:43–18:48 | ai_call | 18 | `The resource you are requesting could not be found` (404) | Model ID `gemini-2.5-flash-lite` not available for this API key | Switched to `gemini-3.1-flash-lite` (15 requests/min free) — 20/20 jobs scored, 0 errors |
| 3 Nov 06:35–06:37 | outreach_draft | 2 | `draft does not name any of the open roles` | "One Item Per Lead" node passed an empty item to the AI | Node now keeps only items with a `lead_id`; the validator correctly refused the empty draft |
| 3 Nov 19:04 | outreach_draft | 2 | `body has 76 / 80 words (allowed 120-180)` | Prompt v2 was too restrictive | Prompt v2.1 (paragraph plan + approved company description) — 154 and 158 words |
| 3 Nov 20:00 | human_review | 4 | Fit 95 and 85 given to jobs with no required skills (gig posting, empty template) | Fit prompt scored from title/seniority alone | Evidence rule in the prompt + code cap at 30 → re-scored 20 and 30 |

Raw log (JSON) as it was in `pipeline_run.errors`:

```json
[
  {
    "run_id": 2,
    "status_before_cleanup": "partial",
    "errors": [
      {
        "at": "2026-11-02T18:18:51Z",
        "stage": "ai_call",
        "job_id": 1,
        "detail": "Service unavailable - try again later or consider setting this node to retry automatically (in the node settings)"
      },
      {
        "at": "2026-11-02T18:29:20Z",
        "stage": "ai_call",
        "job_id": 3,
        "detail": "Service unavailable - try again later or consider setting this node to retry automatically (in the node settings)"
      },
      {
        "at": "2026-11-02T18:43:44Z",
        "stage": "ai_call",
        "job_id": 1,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:44:00Z",
        "stage": "ai_call",
        "job_id": 4,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:44:16Z",
        "stage": "ai_call",
        "job_id": 5,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:44:32Z",
        "stage": "ai_call",
        "job_id": 6,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:44:48Z",
        "stage": "ai_call",
        "job_id": 7,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:45:04Z",
        "stage": "ai_call",
        "job_id": 8,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:45:20Z",
        "stage": "ai_call",
        "job_id": 9,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:45:35Z",
        "stage": "ai_call",
        "job_id": 10,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:45:51Z",
        "stage": "ai_call",
        "job_id": 11,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:46:07Z",
        "stage": "ai_call",
        "job_id": 12,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:46:23Z",
        "stage": "ai_call",
        "job_id": 13,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:46:38Z",
        "stage": "ai_call",
        "job_id": 14,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:46:54Z",
        "stage": "ai_call",
        "job_id": 15,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:47:10Z",
        "stage": "ai_call",
        "job_id": 16,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:47:26Z",
        "stage": "ai_call",
        "job_id": 17,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:47:41Z",
        "stage": "ai_call",
        "job_id": 18,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:47:57Z",
        "stage": "ai_call",
        "job_id": 19,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-02T18:48:13Z",
        "stage": "ai_call",
        "job_id": 20,
        "detail": "The resource you are requesting could not be found"
      },
      {
        "at": "2026-11-03T06:35:56Z",
        "stage": "outreach_draft",
        "detail": "draft does not name any of the open roles"
      },
      {
        "at": "2026-11-03T06:37:26Z",
        "stage": "outreach_draft",
        "detail": "draft does not name any of the open roles"
      },
      {
        "at": "2026-11-03T19:04:15Z",
        "stage": "outreach_draft",
        "lead_id": 5,
        "detail": "body has 76 words (allowed 120-180)"
      },
      {
        "at": "2026-11-03T19:04:23Z",
        "stage": "outreach_draft",
        "lead_id": 16,
        "detail": "body has 80 words (allowed 120-180)"
      }
    ]
  },
  {
    "run_id": 3,
    "status_before_cleanup": "completed",
    "errors": [
      {
        "at": "2026-11-03T20:00:10Z",
        "stage": "human_review",
        "job_id": 17,
        "detail": "Before fix: fit 20 for \"Director, Product Design\" (Samsara) with no required skills. Re-queued after evidence rule."
      },
      {
        "at": "2026-11-03T20:00:10Z",
        "stage": "human_review",
        "job_id": 26,
        "detail": "Before fix: fit 95 for \"Software Engineer, AI Coding Tasks (Contract)\" (Askable) with no required skills. Re-queued after evidence rule."
      },
      {
        "at": "2026-11-03T20:00:10Z",
        "stage": "human_review",
        "job_id": 6,
        "detail": "Before fix: fit 0 for \"Video Annotation\" (micro1) with no required skills. Re-queued after evidence rule."
      },
      {
        "at": "2026-11-03T20:00:10Z",
        "stage": "human_review",
        "job_id": 34,
        "detail": "Before fix: fit 85 for \"Principal Software Enginner\" (SubBase) with no required skills. Re-queued after evidence rule."
      }
    ]
  }
]
```
