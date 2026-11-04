-- Open Rec Lite — core schema (applied to Supabase project open-rec-lite)
-- Enums
create type job_status        as enum ('discovered','parsed','needs_review','scored','failed');
create type lead_status       as enum ('qualified','not_qualified','draft_ready','approved','rejected');
create type draft_status      as enum ('pending_review','approved','edited','rejected');
create type run_status        as enum ('running','completed','partial','failed');
create type trigger_type      as enum ('manual','scheduled');
create type seniority_level   as enum ('entry','mid','senior','lead');
create type employment_type   as enum ('full_time','part_time','contractor','other');
create type remote_policy     as enum ('remote','hybrid','onsite');
create type salary_period     as enum ('hourly','weekly','fortnightly','monthly','annual');
create type extraction_status as enum ('ok','needs_review','failed');

create table app_setting (key text primary key, value text not null, updated_by uuid references auth.users(id), updated_at timestamptz not null default now());

create table pipeline_run (
  run_id bigint generated always as identity primary key,
  started_by uuid references auth.users(id),
  trigger_type trigger_type not null default 'manual',
  status run_status not null default 'running',
  started_at timestamptz not null default now(), finished_at timestamptz,
  jobs_fetched integer not null default 0, jobs_new integer not null default 0, jobs_updated integer not null default 0,
  errors jsonb not null default '[]'::jsonb);
create unique index one_running_pipeline on pipeline_run ((true)) where status = 'running';

create table company (
  company_id bigint generated always as identity primary key,
  name text not null, normalized_name text not null unique,
  website text, location text, contact_name text, contact_title text, contact_email text,
  created_at timestamptz not null default now());

create table job_posting (
  job_id bigint generated always as identity primary key,
  company_id bigint not null references company(company_id) on delete cascade,
  run_id bigint references pipeline_run(run_id),
  source text not null default 'himalayas', external_id text not null, url text not null, title text not null,
  description_raw text, description_text text, content_hash char(64) not null,
  posted_at timestamptz, expires_at timestamptz,
  discovered_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  status job_status not null default 'discovered',
  unique (source, external_id));
create index job_posting_company_idx on job_posting(company_id);
create index job_posting_status_idx  on job_posting(status);

create table job_requirement (
  req_id bigint generated always as identity primary key,
  job_id bigint not null unique references job_posting(job_id) on delete cascade,
  source_hash char(64) not null, title text, seniority seniority_level, min_years_experience smallint,
  required_skills text[] not null default '{}', preferred_skills text[] not null default '{}',
  timezone_offsets smallint[] not null default '{}',
  employment_type employment_type, remote_policy remote_policy,
  salary_min numeric(12,2), salary_max numeric(12,2), salary_currency char(3), salary_period salary_period,
  extraction_status extraction_status not null default 'ok', flag_reason text,
  fit_score smallint check (fit_score between 0 and 100), fit_reason text,
  parsed_at timestamptz not null default now(), scored_at timestamptz);

create table candidate (
  candidate_id bigint primary key, display_name text not null, headline text,
  years_experience numeric(3,1), seniority seniority_level,
  skills text[] not null default '{}', timezone_offsets smallint[] not null default '{}',
  availability text, summary text);

create table lead (
  lead_id bigint generated always as identity primary key,
  company_id bigint not null unique references company(company_id) on delete cascade,
  run_id bigint references pipeline_run(run_id),
  lead_score smallint not null check (lead_score between 0 and 100),
  best_job_score smallint not null default 0, qualifying_jobs smallint not null default 0,
  status lead_status not null, reason text not null,
  evidence jsonb not null default '{"job_ids": []}'::jsonb,
  scored_at timestamptz not null default now());

create table outreach_draft (
  draft_id bigint generated always as identity primary key,
  lead_id bigint not null references lead(lead_id) on delete cascade,
  reviewed_by uuid references auth.users(id),
  subject text not null, body text not null, word_count smallint not null,
  status draft_status not null default 'pending_review',
  reviewed_at timestamptz, review_comment text, created_at timestamptz not null default now());
create index outreach_draft_lead_idx on outreach_draft(lead_id);

insert into app_setting (key, value) values ('lead_threshold','60'),('fetch_limit','20'),('run_mode','manual'),('max_retries','3');
