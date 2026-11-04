-- Open Rec Lite — Row Level Security
-- anon: no access. authenticated team members: read all + review actions.
-- The n8n pipeline writes with the service_role key (bypasses RLS, never exposed to the browser).
alter table app_setting enable row level security;   alter table pipeline_run enable row level security;
alter table company enable row level security;       alter table job_posting enable row level security;
alter table job_requirement enable row level security; alter table candidate enable row level security;
alter table lead enable row level security;          alter table outreach_draft enable row level security;

create policy "team can read settings"     on app_setting     for select to authenticated using (true);
create policy "team can read runs"         on pipeline_run    for select to authenticated using (true);
create policy "team can read companies"    on company         for select to authenticated using (true);
create policy "team can read jobs"         on job_posting     for select to authenticated using (true);
create policy "team can read requirements" on job_requirement for select to authenticated using (true);
create policy "team can read candidates"   on candidate       for select to authenticated using (true);
create policy "team can read leads"        on lead            for select to authenticated using (true);
create policy "team can read drafts"       on outreach_draft  for select to authenticated using (true);

create policy "team can review drafts"        on outreach_draft  for update to authenticated using (true) with check (true);
create policy "team can update lead status"   on lead            for update to authenticated using (true) with check (true);
create policy "team can correct requirements" on job_requirement for update to authenticated using (true) with check (true);
create policy "team can add contacts"         on company         for update to authenticated using (true) with check (true);
create policy "team can change settings"      on app_setting     for update to authenticated using (true) with check (true);
create policy "team can start a run"          on pipeline_run    for insert to authenticated with check (started_by = auth.uid());

revoke execute on function public.rls_auto_enable() from anon, authenticated, public;
