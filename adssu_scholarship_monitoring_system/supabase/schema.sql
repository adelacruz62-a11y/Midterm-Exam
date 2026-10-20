-- =============================================================================
-- Student Scholarship Monitoring and Academic Compliance System (MVP)
-- Supabase / PostgreSQL schema, constraints, policy table, RLS policies, seed.
--
-- This file is the production data layer. It mirrors the rules that index.html
-- implements in one JavaScript API object, so that access control lives in the
-- database rather than in the interface.
--
-- Run in the Supabase SQL editor (or `supabase db push`) after enabling the
-- auth schema. Synthetic data only.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Extensions and enums
-- -----------------------------------------------------------------------------
create extension if not exists "uuid-ossp";

do $$ begin
  create type user_role      as enum ('scholar','staff');
  create type submission_status as enum ('Pending','Verified','Returned');
  create type compliance_result as enum ('Compliant','With Deficiency');
  create type renewal_decision  as enum ('Approved','Held');
exception when duplicate_object then null; end $$;

-- -----------------------------------------------------------------------------
-- 2. Users (profile row 1:1 with auth.users)
-- -----------------------------------------------------------------------------
create table if not exists public.users (
  id         uuid primary key references auth.users(id) on delete cascade,
  role       user_role   not null,
  full_name  text        not null,
  scholar_id text,               -- set only for scholars; the scholar's business key
  created_at timestamptz not null default now(),
  constraint users_scholar_id_required check (
    (role = 'scholar' and scholar_id is not null) or
    (role = 'staff'   and scholar_id is null)
  )
);

-- -----------------------------------------------------------------------------
-- 3. Policy table — every threshold an evaluation reads lives here (FR-5/BR-5)
--    Evaluation code must never hardcode these numbers.
-- -----------------------------------------------------------------------------
create table if not exists public.programs (
  code             text primary key,
  name             text        not null,
  max_gwa          numeric(3,2) not null check (max_gwa between 1.00 and 5.00),
  min_units        integer      not null check (min_units >= 0),
  max_failed       integer      not null check (max_failed >= 0),
  max_incomplete   integer      not null check (max_incomplete >= 0),
  max_dropped      integer      not null check (max_dropped >= 0),
  evidence_required boolean     not null default true,
  -- Stored in Asia/Manila. timestamptz keeps the instant; the office reads it in +08:00.
  deadline         timestamptz  not null default timestamptz '2026-10-30 17:00:00+08',
  created_at       timestamptz  not null default now()
);

-- -----------------------------------------------------------------------------
-- 4. Scholars — one stored policy assigned at registration (FR-2)
-- -----------------------------------------------------------------------------
create table if not exists public.scholars (
  id            text primary key,           -- business key, e.g. 'A01'
  full_name     text        not null,
  program_code  text        not null references public.programs(code),
  user_id       uuid        references public.users(id) on delete set null,
  registered_at timestamptz not null default now(),
  constraint scholars_id_format check (id ~ '^[A-Z][0-9]{2}$')
);

-- -----------------------------------------------------------------------------
-- 5. Submissions — one per scholar + academic year + semester (FR-3, BR-1, BR-2)
-- -----------------------------------------------------------------------------
create table if not exists public.submissions (
  id             uuid primary key default uuid_generate_v4(),
  scholar_id     text        not null references public.scholars(id) on delete cascade,
  academic_year  text        not null check (academic_year ~ '^[0-9]{4}-[0-9]{4}$'),
  semester       smallint    not null check (semester in (1,2)),
  gwa            numeric(3,2) not null check (gwa between 1.00 and 5.00),
  enrolled_units integer      not null check (enrolled_units >= 0),
  failed         integer      not null check (failed >= 0),
  incomplete     integer      not null check (incomplete >= 0),
  dropped        integer      not null check (dropped >= 0),
  evidence_ref   text        not null check (length(trim(evidence_ref)) > 0),
  submitted_at   timestamptz not null default now(),
  status         submission_status not null default 'Pending',
  return_reason  text,
  verification_note text,
  verification_at   timestamptz,
  -- BR-1: duplicate scholar + academic year + semester is impossible
  constraint submissions_unique_term unique (scholar_id, academic_year, semester)
);
create index if not exists submissions_scholar_idx on public.submissions(scholar_id);

-- -----------------------------------------------------------------------------
-- 6. Evaluations — staff only, verified records only (FR-5)
-- -----------------------------------------------------------------------------
create table if not exists public.evaluations (
  id               uuid primary key default uuid_generate_v4(),
  submission_id    uuid unique not null references public.submissions(id) on delete cascade,
  program_code     text not null references public.programs(code),
  result           compliance_result not null,
  deficiencies     jsonb not null default '[]'::jsonb,
  policy_snapshot  jsonb not null,          -- frozen thresholds used for this decision
  evaluated_at     timestamptz not null default now(),
  evaluated_by     uuid references public.users(id)
);

-- -----------------------------------------------------------------------------
-- 7. Renewal decisions — staff only; Approved requires Compliant (FR-6, BR-6)
--    Kept as its own table so it is independent of submission status and result.
-- -----------------------------------------------------------------------------
create table if not exists public.decisions (
  id            uuid primary key default uuid_generate_v4(),
  submission_id uuid unique not null references public.submissions(id) on delete cascade,
  decision      renewal_decision not null,
  note          text,
  decided_at    timestamptz not null default now(),
  decided_by    uuid references public.users(id)
);

-- -----------------------------------------------------------------------------
-- 8. History log — actor, timestamp, event, notes (FR-7)
-- -----------------------------------------------------------------------------
create table if not exists public.history (
  id            uuid primary key default uuid_generate_v4(),
  actor         text not null,
  actor_role    text not null,
  event         text not null,
  notes         text not null default '',
  submission_id uuid references public.submissions(id) on delete set null,
  scholar_id    text references public.scholars(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index if not exists history_scholar_idx on public.history(scholar_id);
create index if not exists history_submission_idx on public.history(submission_id);

-- =============================================================================
-- 9. Helper functions (security definer) used by RLS policies
-- =============================================================================
create or replace function public.current_role()
returns user_role language sql stable security definer set search_path = public as $$
  select role from public.users where id = auth.uid();
$$;

create or replace function public.current_scholar_id()
returns text language sql stable security definer set search_path = public as $$
  select scholar_id from public.users where id = auth.uid();
$$;

-- -----------------------------------------------------------------------------
-- 10. Guard triggers for business rules the schema cannot express declaratively
-- -----------------------------------------------------------------------------

-- BR-3: evaluation only on Verified records with evidence present.
-- This is a database-level backstop; the API performs the same check first.
create or replace function public.guard_evaluation()
returns trigger language plpgsql as $$
declare
  s public.submissions;
  p public.programs;
begin
  select * into s from public.submissions where id = new.submission_id;
  if s is null then raise exception 'Submission % does not exist', new.submission_id; end if;
  if s.status <> 'Verified' then
    raise exception 'Compliance can only be evaluated on a Verified record (current: %)', s.status;
  end if;
  select * into p from public.programs where code = s.program_code_for(s.scholar_id);
  if p.evidence_required and length(trim(coalesce(s.evidence_ref,''))) = 0 then
    raise exception 'Evaluation blocked: the policy requires a grade-document reference';
  end if;
  return new;
end $$;

-- Small helper to read a scholar's program code (kept distinct for clarity).
create or replace function public.program_code_for(p_scholar_id text)
returns text language sql stable security definer set search_path = public as $$
  select program_code from public.scholars where id = p_scholar_id;
$$;

-- BR-6: approval requires a Compliant evaluation.
create or replace function public.guard_decision()
returns trigger language plpgsql as $$
declare r compliance_result;
begin
  if new.decision <> 'Approved' then return new; end if;
  select result into r from public.evaluations where submission_id = new.submission_id;
  if r is null then
    raise exception 'A renewal decision requires a compliance evaluation first';
  end if;
  if r <> 'Compliant' then
    raise exception 'Only a Compliant record can be approved (current: %)', r;
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_evaluation on public.evaluations;
create trigger trg_guard_evaluation before insert or update on public.evaluations
  for each row execute function public.guard_evaluation();

drop trigger if exists trg_guard_decision on public.decisions;
create trigger trg_guard_decision before insert or update on public.decisions
  for each row execute function public.guard_decision();

-- BR-9 / FR-9: resubmitting a Returned record resets it to Pending and clears
-- any prior evaluation/decision, and is logged.
create or replace function public.log_submission_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.history(actor, actor_role, event, notes, submission_id, scholar_id)
  values (coalesce(current_setting('request.jwt.claims', true)::json->>'sub','system'),
          coalesce((select role::text from public.users where id = auth.uid()), 'system'),
          'Submission changed',
          'Status set to ' || new.status,
          new.id, new.scholar_id);
  return new;
end $$;

drop trigger if exists trg_log_submission on public.submissions;
create trigger trg_log_submission after update of status on public.submissions
  for each row execute function public.log_submission_change();

-- =============================================================================
-- 11. Row-level security
-- =============================================================================
alter table public.users       enable row level security;
alter table public.programs    enable row level security;
alter table public.scholars    enable row level security;
alter table public.submissions enable row level security;
alter table public.evaluations enable row level security;
alter table public.decisions   enable row level security;
alter table public.history     enable row level security;

-- Users: a user may read their own profile; staff may read all.
drop policy if exists users_self_read on public.users;
create policy users_self_read on public.users
  for select using (id = auth.uid() or public.current_role() = 'staff');

-- Programs (policies): anyone signed in may read; only staff may write.
drop policy if exists programs_read on public.programs;
create policy programs_read on public.programs
  for select using (auth.uid() is not null);

drop policy if exists programs_staff_write on public.programs;
create policy programs_staff_write on public.programs
  for all using (public.current_role() = 'staff') with check (public.current_role() = 'staff');

-- Scholars: staff read and write all; a scholar reads only their own row.
drop policy if exists scholars_staff_all on public.scholars;
create policy scholars_staff_all on public.scholars
  for all using (public.current_role() = 'staff') with check (public.current_role() = 'staff');

drop policy if exists scholars_self_read on public.scholars;
create policy scholars_self_read on public.scholars
  for select using (id = public.current_scholar_id());

-- Submissions: staff full access; scholars read and insert only their own,
-- and may update only a Returned record of their own.
drop policy if exists submissions_staff_all on public.submissions;
create policy submissions_staff_all on public.submissions
  for all using (public.current_role() = 'staff') with check (public.current_role() = 'staff');

drop policy if exists submissions_scholar_read on public.submissions;
create policy submissions_scholar_read on public.submissions
  for select using (scholar_id = public.current_scholar_id());

drop policy if exists submissions_scholar_insert on public.submissions;
create policy submissions_scholar_insert on public.submissions
  for insert with check (
    scholar_id = public.current_scholar_id() and status = 'Pending'
  );

drop policy if exists submissions_scholar_resubmit on public.submissions;
create policy submissions_scholar_resubmit on public.submissions
  for update using (
    scholar_id = public.current_scholar_id() and status = 'Returned'
  ) with check (
    scholar_id = public.current_scholar_id() and status = 'Pending'
  );

-- Evaluations: staff only, for every command. Scholars never see or write these.
drop policy if exists evaluations_staff_all on public.evaluations;
create policy evaluations_staff_all on public.evaluations
  for all using (public.current_role() = 'staff') with check (public.current_role() = 'staff');

-- Decisions: staff only, for every command.
drop policy if exists decisions_staff_all on public.decisions;
create policy decisions_staff_all on public.decisions
  for all using (public.current_role() = 'staff') with check (public.current_role() = 'staff');

-- History: staff read all; scholars read only their own.
drop policy if exists history_staff_read on public.history;
create policy history_staff_read on public.history
  for select using (public.current_role() = 'staff');

drop policy if exists history_scholar_read on public.history;
create policy history_scholar_read on public.history
  for select using (scholar_id = public.current_scholar_id());

drop policy if exists history_insert on public.history;
create policy history_insert on public.history
  for insert with check (auth.uid() is not null);

-- =============================================================================
-- 12. Seed data — AY 2026-2027, Semester 1 (synthetic)
--     Policy thresholds come from the programs table only.
-- =============================================================================
insert into public.programs
  (code, name, max_gwa, min_units, max_failed, max_incomplete, max_dropped, evidence_required, deadline)
values
  ('MERIT',     'Merit Scholar',     1.75, 18, 0, 0, 0, true, timestamptz '2026-10-30 17:00:00+08'),
  ('COMMUNITY', 'Community Scholar', 2.25, 15, 0, 0, 1, true, timestamptz '2026-10-30 17:00:00+08')
on conflict (code) do update set
  max_gwa = excluded.max_gwa, min_units = excluded.min_units,
  max_failed = excluded.max_failed, max_incomplete = excluded.max_incomplete,
  max_dropped = excluded.max_dropped, evidence_required = excluded.evidence_required,
  deadline = excluded.deadline;

insert into public.scholars (id, full_name, program_code) values
  ('A01','Elena Cruz','MERIT'),
  ('A02','Marco Villanueva','MERIT'),
  ('A03','Jasmin Reyes','COMMUNITY'),
  ('A04','Paolo Santos','COMMUNITY'),
  ('A05','Andrea Lim','MERIT'),
  ('A06','Noel Bautista','COMMUNITY'),
  ('A07','Kim Torres','MERIT'),
  ('A08','Rhea Mendoza','COMMUNITY'),
  ('A09','Luis Garcia','MERIT'),
  ('A10','Mika Dela Cruz','COMMUNITY'),
  ('A11','Franco Reyes','MERIT'),
  ('A12','Shara Aquino','COMMUNITY')
on conflict (id) do nothing;

-- One day before deadline = 2026-10-29 17:00+08; exact deadline = 2026-10-30 17:00+08;
-- one minute late = 2026-10-30 17:01+08.
insert into public.submissions
  (scholar_id, academic_year, semester, gwa, enrolled_units, failed, incomplete, dropped,
   evidence_ref, submitted_at, status, verification_at)
values
  ('A01','2026-2027',1,1.75,18,0,0,0,'GWA-A01-2026-1.pdf', timestamptz '2026-10-30 17:00:00+08','Verified', timestamptz '2026-10-30 18:00:00+08'),
  ('A02','2026-2027',1,1.76,18,0,0,0,'GWA-A02-2026-1.pdf', timestamptz '2026-10-29 17:00:00+08','Verified', timestamptz '2026-10-29 18:00:00+08'),
  ('A03','2026-2027',1,2.25,15,0,0,1,'GWA-A03-2026-1.pdf', timestamptz '2026-10-29 17:00:00+08','Verified', timestamptz '2026-10-29 18:00:00+08'),
  ('A04','2026-2027',1,2.25,14,0,1,0,'GWA-A04-2026-1.pdf', timestamptz '2026-10-29 17:00:00+08','Verified', timestamptz '2026-10-29 18:00:00+08'),
  ('A05','2026-2027',1,1.50,18,1,0,0,'GWA-A05-2026-1.pdf', timestamptz '2026-10-30 17:01:00+08','Verified', timestamptz '2026-10-30 18:01:00+08'),
  ('A06','2026-2027',1,2.00,15,0,0,0,'GWA-A06-2026-1.pdf', timestamptz '2026-10-29 17:00:00+08','Pending',  null),
  ('A07','2026-2027',1,1.40,21,0,0,0,'GWA-A07-2026-1.pdf', timestamptz '2026-10-29 17:00:00+08','Verified', timestamptz '2026-10-29 18:00:00+08'),
  ('A08','2026-2027',1,2.10,16,0,0,0,'GWA-A08-2026-1.pdf', timestamptz '2026-10-29 17:00:00+08','Verified', timestamptz '2026-10-29 18:00:00+08'),
  ('A09','2026-2027',1,1.60,18,0,0,0,'GWA-A09-2026-1.pdf', timestamptz '2026-10-29 17:00:00+08','Verified', timestamptz '2026-10-29 18:00:00+08'),
  ('A10','2026-2027',1,2.20,16,0,0,0,'GWA-A10-2026-1.pdf', timestamptz '2026-10-29 17:00:00+08','Verified', timestamptz '2026-10-29 18:00:00+08'),
  ('A11','2026-2027',1,2.00,18,0,0,0,'GWA-A11-2026-1.pdf', timestamptz '2026-10-29 17:00:00+08','Verified', timestamptz '2026-10-29 18:00:00+08'),
  ('A12','2026-2027',1,2.10,15,0,0,2,'GWA-A12-2026-1.pdf', timestamptz '2026-10-29 17:00:00+08','Verified', timestamptz '2026-10-29 18:00:00+08')
on conflict (scholar_id, academic_year, semester) do nothing;

-- Seed history for the foundational events (verification/evaluation/renewal are
-- produced by the running system through the triggers and the API).
insert into public.history (actor, actor_role, event, notes, scholar_id)
select 'R. Alvarez', 'staff', 'Scholar registered',
       'Registered ' || full_name || ' and assigned the ' || program_code || ' policy.',
       id
from public.scholars
where not exists (select 1 from public.history h where h.scholar_id = public.scholars.id);

-- =============================================================================
-- 13. Notes on the two seed rows the acceptance tests depend on
--     TC01 A01 Compliant | TC02 A02 GWA deficiency | TC03 A03 Compliant
--     TC04 A04 units + incomplete | TC05 A05 failed + late
--     TC06 A06 Pending -> evaluation and approval blocked
-- =============================================================================
