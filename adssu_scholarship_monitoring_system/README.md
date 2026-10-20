# Student Scholarship Monitoring and Academic Compliance System (MVP)

A browser-based MVP for the Scholarship Office. Staff register scholars, verify grade
evidence, evaluate academic compliance against stored policy records, and record renewal
decisions. Scholars submit a semester grade summary and see only their own records.
**Synthetic data only.** The system never alters official grades and never releases payments.

## Contents

| Path | Deliverable |
|---|---|
| `index.html` | **A.** Single self-contained HTML/CSS/JS app (localStorage demo) with an in-app test runner |
| `docs/PART1_ANALYSIS.md` | **B.** Part I analysis: problem, causes, scope, tasks, risks, stakeholders, questions, FR/NFR/BR, use case diagram, detailed use cases, ERD, traceability |
| `supabase/schema.sql` | **C.** Schema, unique constraint, policy table, RLS policies, seed data |
| `README.md` | **D.** This file |

## Run the demo (no build step)

1. Download or clone the folder.
2. Open `index.html` directly in a modern browser (Chrome, Edge, Firefox, Safari).

That is the whole setup. There is no server and no dependency. Data persists in the
browser's `localStorage` under the keys `smsms.db.v1`, `smsms.session.v1`, `smsms.theme`.

To reset to the seed data, open the browser console and run:

```js
localStorage.clear(); location.reload();
```

## Using the app

- The app opens on a **Sign in** form. Enter a demo username and password (see the credentials
  table on the form, or click **use** to fill them).

  | Role | Username | Password |
  |---|---|---|
  | Scholarship Staff | `staff-01` | `staff123` |
  | Scholar | `A01` … `A12` | `scholar123` |

  Usernames are case-insensitive. Newly registered scholars also use `scholar123`.
- After sign-in the top bar shows the current account, a **Switch account** dropdown, and a
  **Sign out** button.
- **Staff tabs:** Dashboard, Verification queue, Compliance & renewal, Register scholar,
  History log, Tests.
- **Scholar tabs:** My records, Submit grades, History log, Tests.
- The **Tests** tab runs all ten scripts against a **fresh copy** of the seed data, so the
  working records are never modified.

### Seed scenario (AY 2026-2027, Semester 1)

| Scholar | Program | GWA | Units | Failed | Incomplete | Dropped | Submitted (Asia/Manila) | Verified |
|---|---|---|---|---|---|---|---|---|
| A01 | Merit | 1.75 | 18 | 0 | 0 | 0 | exact deadline | yes |
| A02 | Merit | 1.76 | 18 | 0 | 0 | 0 | 1 day before | yes |
| A03 | Community | 2.25 | 15 | 0 | 0 | 1 | 1 day before | yes |
| A04 | Community | 2.25 | 14 | 0 | 1 | 0 | 1 day before | yes |
| A05 | Merit | 1.50 | 18 | 1 | 0 | 0 | 1 minute late | yes |
| A06 | Community | 2.00 | 15 | 0 | 0 | 0 | 1 day before | **Pending** |
| A07–A12 | mixed | passing | OK | 0 | 0 | 0–2 | 1 day before | yes |

Expected results: A01 Compliant, A02 deficient (GWA), A03 Compliant, A04 deficient
(units + incomplete), A05 deficient (failed + late), A06 blocked (not verified).

## Environment variables (Supabase production path)

The demo needs none. When wiring the real backend, create a `.env.local` and never commit it:

```
NEXT_PUBLIC_SUPABASE_URL=https://<project-ref>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon-key>
# Server-only. Never expose to the browser.
SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
```

`NEXT_PUBLIC_*` values are visible to the browser by design; the anon key is safe because
every table is protected by row-level security. The service-role key bypasses RLS and must
stay server-side.

## Production setup (Supabase)

1. Create a Supabase project.
2. Run `supabase/schema.sql` in the SQL editor. It creates the enums, tables, constraints,
   policy table, guard triggers, RLS policies, and seed data.
3. Create auth users, then insert a matching `public.users` row per auth user with `role`
   `scholar` or `staff` and, for scholars, the `scholar_id` that links to `public.scholars`.
4. Sign in through Supabase Auth. RLS restricts each scholar to their own rows; staff have
   full access. The same rules in `index.html` are the reference behaviour these policies mirror.

## Key design decisions

- **Access control in the data layer.** All reads and writes go through one API object
  (`makeApi` in `index.html`), which checks role and ownership on every call. Hiding a button
  is never the only defence. `supabase/schema.sql` mirrors these checks as RLS.
- **Policy thresholds are data.** Evaluation reads limits and the deadline from the assigned
  `programs` row, never from constants in the UI.
- **Three separate facts.** Submission status, compliance result, and renewal decision are
  stored and shown independently.
- **Timezone.** Timestamps are stored with an explicit `+08:00` offset; the UI reads the
  stored wall clock so the Asia/Manila time never shifts with the viewer's timezone.
- **Auditability.** Verification, evaluation, and renewal each append a history entry with
  actor, timestamp, event, and notes.

## Known defects and limitations

1. **localStorage is not security.** The demo's role checks run in the same JavaScript the
   user can edit in devtools. It demonstrates the API-layer pattern, not a security boundary.
   Real protection is the Supabase RLS in `supabase/schema.sql`.
2. **No real authentication.** The login form checks demo passwords held in clear text in
   `localStorage`, and the **Switch account** dropdown lets anyone pick any account. This
   demonstrates the role-check pattern, not a security boundary. Production uses Supabase Auth.
3. **Demo user switch does not log out on refresh** beyond what is stored in
   `smsms.session.v1`; clearing localStorage is the manual reset.
4. **No file upload.** Evidence is a text reference (file name or Registrar document ID).
   Verification is manual by staff.
5. **Concurrency is unhandled in the demo.** Two staff editing the same record last-write-wins.
   The SQL uses unique constraints and a status-guarded resubmit policy to reduce the risk.
6. **`evaluations` and `decisions` guard triggers in SQL reference helper functions**
   (`program_code_for`, `current_role`) that assume the standard Supabase `auth.uid()` setup;
   run the file on a project with Auth enabled.
7. **Single-term UI focus.** The demo defaults to AY 2026-2027 Semester 1; other terms work but
   show no data unless submissions exist.
8. **No pagination.** The tables render all rows; fine for a small office, not for large data.

## Verification status

- `index.html` core and UI scripts pass a syntax check (Node `vm.Script`).
- All ten test cases TC01–TC10 pass against a fresh seed copy (run from the **Tests** tab).
- Seed evaluation results match the specification (see the seed table above).

## Test case reference

| TC | Expectation |
|---|---|
| TC01 | A01 Compliant |
| TC02 | A02 deficient for GWA only |
| TC03 | A03 Compliant |
| TC04 | A04 deficient for units + incomplete |
| TC05 | A05 deficient for failed + late |
| TC06 | A06 evaluation and approval blocked |
| TC07 | Duplicate, GWA 0.50, and negative count all rejected |
| TC08 | Scholar cannot read another record or verify |
| TC09 | Return, correct, resubmit stays Pending with history |
| TC10 | Staff approve compliant, hold deficient; scholar cannot decide |
