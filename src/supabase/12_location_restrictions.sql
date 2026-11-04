-- 12: Location restrictions (rule, not AI)
-- Himalayas sends locationRestrictions per job. We store them in job_posting.source_meta and,
-- when a job can only hire in countries outside Simera's talent regions, the job goes to human review
-- and never counts for a lead.

insert into app_setting (key, value) values
  ('talent_regions', 'worldwide,anywhere,global,mena,middle east,north africa,emea,algeria,bahrain,egypt,iraq,jordan,kuwait,lebanon,libya,morocco,oman,palestine,qatar,saudi arabia,sudan,syria,tunisia,united arab emirates,uae,yemen,turkey,türkiye')
on conflict (key) do nothing;

-- Returns a human-readable reason when the job is restricted to countries outside the talent regions, else null.
create or replace function public.location_flag(p_meta jsonb)
returns text language plpgsql stable set search_path to 'public' as $$
declare
  v_list text[]; v_regions text[]; v_ok boolean := false; x text; r text;
begin
  select coalesce(array(select lower(btrim(e)) from jsonb_array_elements_text(p_meta->'location_restrictions') e where btrim(e) <> ''), '{}')
    into v_list;
  if coalesce(array_length(v_list, 1), 0) = 0 then return null; end if;          -- no restriction = open
  v_regions := string_to_array((select value from app_setting where key = 'talent_regions'), ',');
  foreach x in array v_list loop
    foreach r in array v_regions loop
      if x ~* ('\m' || btrim(r) || '\M') then v_ok := true; end if;
    end loop;
  end loop;
  if v_ok then return null; end if;
  return 'hiring limited to: ' || array_to_string(array(select jsonb_array_elements_text(p_meta->'location_restrictions')), ', ')
         || ' (outside Simera talent regions)';
end $$;

-- ingest_jobs: also store source_meta (location restrictions) on insert, update and unchanged rows.
create or replace function public.ingest_jobs(p_run_id bigint, p_jobs jsonb, p_source text default 'himalayas')
returns jsonb language plpgsql set search_path to 'public' as $function$
declare
  j jsonb; v_company_id bigint; v_norm text; v_hash text; v_existing record; v_meta jsonb;
  v_max_age int := coalesce((select value::int from app_setting where key = 'max_job_age_days'), 7);
  n_new int := 0; n_updated int := 0; n_same int := 0; n_skipped int := 0; n_old int := 0;
begin
  for j in select * from jsonb_array_elements(p_jobs) loop
    if coalesce(j->>'external_id','') = '' or coalesce(j->>'title','') = '' or coalesce(j->>'company_name','') = '' then
      n_skipped := n_skipped + 1; continue;
    end if;
    if (j->>'posted_at') is not null and (j->>'posted_at')::timestamptz < now() - make_interval(days => v_max_age) then
      n_old := n_old + 1; continue;
    end if;
    v_meta := jsonb_build_object('location_restrictions', coalesce(j->'location_restrictions', '[]'::jsonb));

    v_norm := lower(regexp_replace(btrim(j->>'company_name'), '\s+', ' ', 'g'));
    insert into company (name, normalized_name) values (btrim(j->>'company_name'), v_norm)
      on conflict (normalized_name) do update set name = company.name
      returning company_id into v_company_id;

    v_hash := encode(sha256(convert_to(btrim(j->>'title') || E'\n' || coalesce(j->>'description_text',''), 'UTF8')), 'hex');
    select job_id, content_hash, status into v_existing from job_posting where source = p_source and external_id = j->>'external_id';

    if not found then
      insert into job_posting (company_id, run_id, source, external_id, url, title, description_raw, description_text,
                               content_hash, posted_at, expires_at, status, source_meta)
      values (v_company_id, p_run_id, p_source, j->>'external_id', j->>'url', btrim(j->>'title'), j->>'description_raw',
              j->>'description_text', v_hash, (j->>'posted_at')::timestamptz, (j->>'expires_at')::timestamptz, 'discovered', v_meta);
      n_new := n_new + 1;
    elsif v_existing.content_hash <> v_hash and v_existing.status <> 'dismissed' then
      update job_posting set company_id = v_company_id, run_id = p_run_id, url = j->>'url', title = btrim(j->>'title'),
             description_raw = j->>'description_raw', description_text = j->>'description_text', content_hash = v_hash,
             posted_at = (j->>'posted_at')::timestamptz, expires_at = (j->>'expires_at')::timestamptz,
             status = 'discovered', updated_at = now(), source_meta = v_meta
       where job_id = v_existing.job_id;
      n_updated := n_updated + 1;
    else
      update job_posting set expires_at = (j->>'expires_at')::timestamptz, source_meta = v_meta where job_id = v_existing.job_id;
      n_same := n_same + 1;
    end if;
  end loop;

  update pipeline_run set jobs_fetched = jobs_fetched + jsonb_array_length(p_jobs),
         jobs_new = jobs_new + n_new, jobs_updated = jobs_updated + n_updated
   where run_id = p_run_id;
  return jsonb_build_object('fetched', jsonb_array_length(p_jobs), 'new', n_new, 'updated', n_updated,
                            'unchanged', n_same, 'too_old', n_old, 'skipped', n_skipped, 'max_age_days', v_max_age);
end $function$;

-- save_requirements: a location restriction outside the talent regions always sends the job to human review.
create or replace function public.save_requirements(p_run_id bigint, p_job_id bigint, p_source_hash text, p_req jsonb,
       p_extraction_status text default 'ok', p_flag_reason text default null)
returns jsonb language plpgsql set search_path to 'public' as $function$
declare v_hash text; v_meta jsonb; v_loc text; v_status text := p_extraction_status; v_flag text := p_flag_reason;
begin
  select content_hash, source_meta into v_hash, v_meta from job_posting where job_id = p_job_id;
  if v_hash is null then return jsonb_build_object('ok', false, 'reason', 'job not found'); end if;
  if v_hash <> p_source_hash then return jsonb_build_object('ok', false, 'reason', 'posting changed since it was read'); end if;

  v_loc := location_flag(v_meta);
  if v_loc is not null then
    v_status := 'needs_review';
    v_flag := concat_ws('; ', v_flag, v_loc);
  end if;

  insert into job_requirement as r (job_id, source_hash, title, seniority, min_years_experience, required_skills,
      preferred_skills, timezone_offsets, employment_type, remote_policy, salary_min, salary_max, salary_currency,
      salary_period, extraction_status, flag_reason, fit_score, fit_reason, parsed_at, scored_at)
  values (p_job_id, p_source_hash, p_req->>'title',
      (p_req->>'seniority')::seniority_level,
      (p_req->>'min_years_experience')::smallint,
      coalesce(array(select jsonb_array_elements_text(p_req->'required_skills')), '{}'),
      coalesce(array(select jsonb_array_elements_text(p_req->'preferred_skills')), '{}'),
      coalesce(array(select x::smallint from jsonb_array_elements_text(p_req->'timezone_offsets') x), '{}'),
      (p_req->>'employment_type')::employment_type,
      (p_req->>'remote_policy')::remote_policy,
      (p_req->>'salary_min')::numeric, (p_req->>'salary_max')::numeric,
      p_req->>'salary_currency', (p_req->>'salary_period')::salary_period,
      v_status::extraction_status, v_flag, null, null, now(), null)
  on conflict (job_id) do update set
      source_hash = excluded.source_hash, title = excluded.title, seniority = excluded.seniority,
      min_years_experience = excluded.min_years_experience, required_skills = excluded.required_skills,
      preferred_skills = excluded.preferred_skills, timezone_offsets = excluded.timezone_offsets,
      employment_type = excluded.employment_type, remote_policy = excluded.remote_policy,
      salary_min = excluded.salary_min, salary_max = excluded.salary_max, salary_currency = excluded.salary_currency,
      salary_period = excluded.salary_period, extraction_status = excluded.extraction_status,
      flag_reason = excluded.flag_reason, fit_score = null, fit_reason = null, parsed_at = now(), scored_at = null;

  update job_posting set status = case when v_status = 'ok' then 'parsed'::job_status else 'needs_review'::job_status end
   where job_id = p_job_id;
  return jsonb_build_object('ok', true, 'job_id', p_job_id, 'extraction_status', v_status);
end $function$;

revoke all on function public.location_flag(jsonb) from public, anon, authenticated;
