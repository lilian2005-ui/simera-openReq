-- 04–11: Pipeline functions (final state after migrations 04–11).
-- All functions are called by n8n with the service_role key, except dismiss_job (logged-in team members).
-- ingest_jobs and save_requirements are defined in 12_location_restrictions.sql (latest version).

-- ---------- 10: dismiss support + freshness rule ----------
alter type job_status add value if not exists 'dismissed';
alter table job_posting
  add column if not exists reviewed_by uuid references auth.users(id),
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_note text;
insert into app_setting (key, value) values ('max_job_age_days', '7') on conflict (key) do nothing;
insert into app_setting (key, value) values ('llm_model', 'gemini-3.1-flash-lite'), ('process_limit', '20') on conflict (key) do nothing;

-- ---------- 04: start / finish a run (only one active run at a time) ----------
create or replace function public.start_pipeline_run(p_trigger text default 'manual', p_started_by uuid default null)
returns jsonb language plpgsql set search_path = public as $$
declare v_run_id bigint;
begin
  update pipeline_run set status = 'failed', finished_at = now(),
         errors = errors || jsonb_build_array(jsonb_build_object('stage','run','error','closed as stale after 30 minutes'))
   where status = 'running' and started_at < now() - interval '30 minutes';
  begin
    insert into pipeline_run (trigger_type, started_by) values (p_trigger::trigger_type, p_started_by)
    returning run_id into v_run_id;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'message', 'A pipeline run is already active');
  end;
  return jsonb_build_object('ok', true, 'run_id', v_run_id);
end $$;

create or replace function public.finish_pipeline_run(p_run_id bigint, p_status text, p_errors jsonb default '[]'::jsonb)
returns jsonb language plpgsql set search_path = public as $$
begin
  update pipeline_run set status = p_status::run_status, finished_at = now(),
         errors = errors || coalesce(p_errors, '[]'::jsonb)
   where run_id = p_run_id;
  return jsonb_build_object('ok', true, 'run_id', p_run_id, 'status', p_status);
end $$;

-- ---------- 06: fit score + per-job error ----------
-- Flagged postings keep NEEDS REVIEW and never count for leads.
create or replace function public.save_fit(p_run_id bigint, p_job_id bigint, p_fit_score int, p_fit_reason text)
returns jsonb language plpgsql set search_path = public as $$
declare v_flag extraction_status;
begin
  if p_fit_score is null or p_fit_score < 0 or p_fit_score > 100 then raise exception 'fit_score must be between 0 and 100'; end if;
  if coalesce(btrim(p_fit_reason), '') = '' then raise exception 'fit_reason must not be empty'; end if;
  update job_requirement set fit_score = p_fit_score, fit_reason = left(btrim(p_fit_reason), 300), scored_at = now()
   where job_id = p_job_id returning extraction_status into v_flag;
  if v_flag is null then return jsonb_build_object('ok', false, 'reason', 'requirements not found'); end if;
  update job_posting set status = case when v_flag = 'ok' then 'scored'::job_status else 'needs_review'::job_status end
   where job_id = p_job_id;
  return jsonb_build_object('ok', true, 'job_id', p_job_id, 'fit_score', p_fit_score, 'counts_for_leads', v_flag = 'ok');
end $$;

create or replace function public.record_job_error(p_run_id bigint, p_job_id bigint, p_stage text, p_detail text)
returns jsonb language plpgsql set search_path = public as $$
begin
  update job_posting set status = 'failed' where job_id = p_job_id;
  update pipeline_run set errors = errors || jsonb_build_array(jsonb_build_object(
           'at', now(), 'stage', p_stage, 'job_id', p_job_id, 'detail', left(coalesce(p_detail, 'unknown error'), 500)))
   where run_id = p_run_id;
  return jsonb_build_object('ok', true, 'job_id', p_job_id, 'stage', p_stage);
end $$;

-- ---------- 07: lead scoring (pure rules) + drafts ----------
-- lead_score = best qualifying fit + 5 per extra qualifying job (max 100).
-- A job qualifies when status = scored, fit_score >= lead_threshold and it has not expired.
create or replace function public.score_leads(p_run_id bigint)
returns jsonb language plpgsql set search_path = public as $$
declare
  v_threshold int := coalesce((select value::int from app_setting where key = 'lead_threshold'), 60);
  c record; v_score int; v_status lead_status; v_old record; v_reason text;
  n_q int := 0; n_nq int := 0; n_kept int := 0;
begin
  for c in
    select co.company_id, co.name,
           max(r.fit_score) filter (where q) as best,
           count(*) filter (where q) as n_qual,
           coalesce(jsonb_agg(j.job_id order by r.fit_score desc) filter (where q), '[]'::jsonb) as job_ids,
           max(r.fit_score) as best_any
      from company co
      join job_posting j on j.company_id = co.company_id
      join job_requirement r on r.job_id = j.job_id
      cross join lateral (select j.status = 'scored' and r.fit_score >= v_threshold
                                 and (j.expires_at is null or j.expires_at > now()) as q) qq
     where r.fit_score is not null
     group by co.company_id, co.name
  loop
    v_score  := case when c.n_qual > 0 then least(100, c.best + 5 * (c.n_qual - 1)) else 0 end;
    v_status := case when c.n_qual > 0 then 'qualified' else 'not_qualified' end;
    v_reason := case when c.n_qual > 0
                  then format('%s qualifying job(s); best fit %s/100.', c.n_qual, c.best)
                  else format('No job reaches the %s threshold (best fit %s/100).', v_threshold, coalesce(c.best_any, 0)) end;
    select lead_id, lead_score, evidence, status into v_old from lead where company_id = c.company_id;
    if found and v_old.lead_score = v_score and v_old.evidence->'job_ids' = c.job_ids then
      n_kept := n_kept + 1;   -- same evidence: keep the review status
    elsif found then
      update lead set run_id = p_run_id, lead_score = v_score, best_job_score = coalesce(c.best, 0),
             qualifying_jobs = c.n_qual, status = v_status, reason = v_reason,
             evidence = jsonb_build_object('job_ids', c.job_ids), scored_at = now()
       where lead_id = v_old.lead_id;
    else
      insert into lead (company_id, run_id, lead_score, best_job_score, qualifying_jobs, status, reason, evidence)
      values (c.company_id, p_run_id, v_score, coalesce(c.best, 0), c.n_qual, v_status, v_reason,
              jsonb_build_object('job_ids', c.job_ids));
    end if;
    if v_status = 'qualified' then n_q := n_q + 1; else n_nq := n_nq + 1; end if;
  end loop;
  return jsonb_build_object('threshold', v_threshold, 'qualified', n_q, 'not_qualified', n_nq, 'unchanged', n_kept);
end $$;

-- Qualified leads that still need a draft, with the evidence the AI may use.
create or replace function public.get_leads_for_drafts(p_limit int default 10)
returns jsonb language sql set search_path = public as $$
  select coalesce(jsonb_agg(x order by x.lead_score desc), '[]'::jsonb) from (
    select l.lead_id, l.lead_score, l.qualifying_jobs, co.name as company_name,
           (select jsonb_agg(jsonb_build_object(
                     'title', j.title, 'fit_score', r.fit_score, 'fit_reason', r.fit_reason,
                     'required_skills', r.required_skills, 'seniority', r.seniority,
                     'timezone_offsets', r.timezone_offsets, 'url', j.url) order by r.fit_score desc)
              from jsonb_array_elements_text(l.evidence->'job_ids') e(id)
              join job_posting j on j.job_id = e.id::bigint
              join job_requirement r on r.job_id = j.job_id) as jobs
      from lead l join company co using (company_id)
     where l.status = 'qualified'
       and not exists (select 1 from outreach_draft d where d.lead_id = l.lead_id and d.status = 'pending_review')
     order by l.lead_score desc
     limit p_limit) x;
$$;

-- Save the AI lead reason + draft (pending human review). Never sends anything.
create or replace function public.save_lead_draft(p_run_id bigint, p_lead_id bigint, p_reason text, p_subject text, p_body text)
returns jsonb language plpgsql set search_path = public as $$
declare v_words int; v_draft bigint;
begin
  if coalesce(btrim(p_reason), '') = '' or coalesce(btrim(p_subject), '') = '' or coalesce(btrim(p_body), '') = '' then
    raise exception 'reason, subject and body are required';
  end if;
  v_words := array_length(regexp_split_to_array(btrim(p_body), '\s+'), 1);
  if v_words < 100 or v_words > 200 then raise exception 'draft body has % words (allowed 100-200)', v_words; end if;
  update lead set reason = left(btrim(p_reason), 500), status = 'draft_ready' where lead_id = p_lead_id and status = 'qualified';
  if not found then return jsonb_build_object('ok', false, 'reason', 'lead is not in qualified status'); end if;
  insert into outreach_draft (lead_id, subject, body, word_count)
  values (p_lead_id, left(btrim(p_subject), 150), btrim(p_body), v_words) returning draft_id into v_draft;
  return jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'draft_id', v_draft, 'word_count', v_words);
end $$;

-- ---------- 08: log a lead-level error ----------
create or replace function public.log_run_error(p_run_id bigint, p_stage text, p_detail text, p_lead_id bigint default null)
returns jsonb language plpgsql set search_path = public as $$
begin
  update pipeline_run set errors = errors || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
           'at', now(), 'stage', p_stage, 'lead_id', p_lead_id, 'detail', left(coalesce(p_detail, 'unknown error'), 500))))
   where run_id = p_run_id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- 09: close the whole run (all three workflows) ----------
create or replace function public.close_run(p_run_id bigint, p_since timestamptz default null)
returns jsonb language plpgsql set search_path = public as $$
declare v_errs int;
begin
  select coalesce(jsonb_array_length(errors), 0) into v_errs from pipeline_run where run_id = p_run_id;
  update pipeline_run set status = case when v_errs > 0 then 'partial'::run_status else 'completed'::run_status end,
         finished_at = now() where run_id = p_run_id;
  return jsonb_build_object('run_id', p_run_id, 'status', case when v_errs > 0 then 'partial' else 'completed' end, 'errors', v_errs);
end $$;

-- ---------- 11: human decision on flagged jobs (called from the web app) ----------
create or replace function public.dismiss_job(p_job_id bigint, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_status job_status;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  if coalesce(btrim(p_note), '') = '' then raise exception 'a reason is required'; end if;
  select status into v_status from job_posting where job_id = p_job_id;
  if v_status is null then raise exception 'job not found'; end if;
  if v_status = 'dismissed' then return jsonb_build_object('ok', true, 'already', true); end if;
  update job_posting set status = 'dismissed', reviewed_by = auth.uid(), reviewed_at = now(), review_note = left(btrim(p_note), 300)
   where job_id = p_job_id;
  return jsonb_build_object('ok', true, 'job_id', p_job_id, 'status', 'dismissed');
end $$;

-- ---------- permissions ----------
do $$ declare f text; begin
  foreach f in array array['start_pipeline_run(text,uuid)','finish_pipeline_run(bigint,text,jsonb)',
    'save_fit(bigint,bigint,int,text)','record_job_error(bigint,bigint,text,text)','score_leads(bigint)',
    'get_leads_for_drafts(int)','save_lead_draft(bigint,bigint,text,text,text)',
    'log_run_error(bigint,text,text,bigint)','close_run(bigint,timestamptz)'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end $$;
revoke execute on function public.dismiss_job(bigint, text) from public, anon;
grant  execute on function public.dismiss_job(bigint, text) to authenticated;
