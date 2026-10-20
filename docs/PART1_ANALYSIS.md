# Part I — Systems Analysis

**Project:** Student Scholarship Monitoring and Academic Compliance System (MVP)
**Client:** Scholarship Office, a state university
**Scope of this document:** analysis only. Implementation is in `index.html` (demo) and
`supabase/schema.sql` (production data layer). Data is synthetic.

ID conventions used consistently across analysis, code, and tests:

| Prefix | Meaning | Example |
|---|---|---|
| `FR` | Functional requirement | FR-3 grade submission |
| `BR` | Business rule | BR-2 duplicate block |
| `UC` | Use case | UC-02 Verify Evidence |
| `TC` | Test case | TC-05 deficient + late |

---

## 1. Problem statement

The Scholarship Office administers two grant programs, **Merit Scholar** and **Community
Scholar**, using spreadsheets, emailed attachments, and paper forms. Records are duplicated
across staff so the same scholar can appear twice with different values; grades arrive as
unverified attachments; deadlines pass unnoticed; and renewal decisions vary between staff
because no single set of rules is applied. The Registrar remains the official source of
grades, so the office needs a system that records and verifies evidence and decisions without
becoming a grade authority or a payment system. The MVP must give each role exactly the access
it needs, read every policy threshold from a stored program record, keep submission status,
compliance result and renewal decision as three separate facts, and leave a defensible history.

## 2. Cause–effect analysis (4 entries)

| # | Cause | Mechanism | Effect | Addressed by |
|---|---|---|---|---|
| C1 | Each staff member keeps a private spreadsheet | The same scholar is keyed twice with divergent values | Duplicate entries; conflicting renewals | FR-2, BR-1 |
| C2 | Grades arrive as email attachments with no verification step | Nothing links the claimed GWA to checked evidence | Unverified or fabricated grades drive decisions | FR-3, FR-4, BR-3 |
| C3 | Deadlines live in memos and inboxes | No per-record timestamp against a stored deadline | Late submissions judged inconsistently or missed | FR-3, BR-4 |
| C4 | Renewal rules are applied from memory and vary by staff | Thresholds differ between people and semesters | Inconsistent, hard-to-audit renewal decisions | FR-5, BR-5, FR-7 |

## 3. Scope

**In scope (MVP)**
- Role-based access for Scholar and Scholarship Staff, enforced in the data/API layer.
- Registering scholars and assigning one stored policy record.
- Semester grade submission with evidence reference and Asia/Manila timestamp.
- Staff verification (Verified / Returned with reason) and scholar correction/resubmission.
- Compliance evaluation against stored thresholds; renewal decision (Approved / Held).
- Dashboard, search, filters, persistence, and a history log.

**Out of scope**
- Altering official grades (Registrar owns them).
- Releasing, computing, or approving payments.
- Registrar/CAS integration, SSO, and real file storage.
- Applicant intake before registration, and appeal workflows.

## 4. Work breakdown / tasks

| Task | Deliverable |
|---|---|
| T1 Requirements | This document (FR, BR, UC, TC, ERD, traceability) |
| T2 Data layer (demo) | `index.html` API object with role + ownership checks |
| T3 Data layer (production) | `supabase/schema.sql`: tables, constraints, RLS, seed |
| T4 Grade submission | Validation, duplicate block, Manila timestamp |
| T5 Verification | Verified/Returned, reason required, resubmission resets to Pending |
| T6 Evaluation & renewal | Policy-driven checks, deficiencies, approve/hold guard |
| T7 Dashboard & search | Counts, search by ID/name, filters by program and compliance |
| T8 History & persistence | Actor/timestamp/event/notes log; localStorage persistence |
| T9 Tests | 10 in-app test cases (TC01–TC10) with a results table |

## 5. Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | localStorage has no real security | High (demo) | High if shipped as-is | Production moves rules to Supabase RLS (deliverable C) |
| R2 | Registrar grade file format differs from the evidence reference | Medium | Medium | Evidence is a reference only; verification is manual by staff |
| R3 | Deadline or policy changes mid-semester | Medium | Medium | Thresholds and deadline stored in the policy table, not in code |
| R4 | Browser clock or timezone differs from Manila | Medium | Medium | Timestamps stored with explicit `+08:00`; display reads stored wall clock |
| R5 | Two staff evaluate the same record concurrently | Low (small office) | Medium | Unique constraint + last-write-wins in MVP; audit log records each action |
| R6 | Staff treat "Returned" as a final decision | Medium | Medium | UI and BR-6 separate submission status from renewal decision |

## 6. Stakeholders (4)

| Stakeholder | Interest | Influence | Key concern |
|---|---|---|---|
| Scholarship Staff (primary user) | Fast, consistent processing | High | Fewer manual checks; defensible decisions |
| Scholar (primary user) | Clarity on status and next steps | Medium | Knows exactly what is missing and by when |
| Scholarship Office Head (sponsor) | Policy compliance and auditability | High | Every decision traceable to a stored rule |
| Registrar (external dependency) | Grade integrity | High | System never alters or overrides official grades |

*(A fifth, the Internal Audit / IT Security office, is consulted for RLS review but not a primary stakeholder.)*

## 7. Elicitation questions (6)

1. When a scholar submits grades, is a scanned/exported document mandatory for both programs, and who stores the original?
2. If a scholar is late, does the office want an automatic deficiency, or discretion with a note?
3. How are "incomplete" grades handled if they are resolved after the deadline but within the semester?
4. When staff return a record, how long may a scholar correct and resubmit before it counts as not submitted?
5. Is one renewal decision final for the semester, or can it be revised, and who may revise it?
6. What identifier does the Registrar use on a grade document so staff can verify it reliably?

## 8. Functional requirements (10)

| ID | Requirement |
|---|---|
| FR-1 | The system shall authenticate a user and resolve exactly one role (Scholar or Staff). |
| FR-2 | Staff shall register a scholar with a unique ID and assign exactly one stored policy record. |
| FR-3 | A scholar shall submit one grade summary per scholar + academic year + semester: GWA, enrolled units, failed, incomplete, dropped, evidence reference, and a Manila timestamp. |
| FR-4 | Staff shall mark a pending record Verified or Returned; a return shall require a reason. |
| FR-5 | The system shall evaluate only Verified records against the assigned policy record and shall list every check and every deficiency reason. |
| FR-6 | Staff shall record a renewal decision of Approved or Held; a decision of Approved shall require a Compliant result. |
| FR-7 | The system shall record history entries (actor, timestamp, event, notes) for verification, evaluation, and renewal. |
| FR-8 | The system shall show a dashboard of assigned, pending, compliant, and deficient counts for the selected semester. |
| FR-9 | The system shall let a scholar correct and resubmit a Returned record, which resets it to Pending. |
| FR-10 | The system shall search by scholar ID or name and filter by program and compliance result. |

## 9. Non-functional requirements (4)

| ID | Requirement |
|---|---|
| NFR-1 | Access control shall be enforced in the data/API layer, not by hiding controls, and mirrored in Supabase RLS. |
| NFR-2 | Every relevant timestamp shall be recorded and displayed in Asia/Manila (`+08:00`). |
| NFR-3 | The interface shall be responsive, support dark mode, and keep keyboard focus visible. |
| NFR-4 | Validation errors shall be plain-language and name the field, the accepted range, and an example. |

## 10. Business rules (6)

| ID | Rule |
|---|---|
| BR-1 | One record per scholar + academic year + semester; duplicates are rejected. |
| BR-2 | GWA must be between 1.00 and 5.00; counts must be nonnegative whole numbers. |
| BR-3 | Evaluation requires a Verified record and, when the policy requires it, a non-empty evidence reference. |
| BR-4 | A submission is late when its Manila timestamp is strictly after the deadline; exactly on the deadline is on time. |
| BR-5 | All checks passing = Compliant; otherwise With Deficiency with the specific failing reasons. |
| BR-6 | Approval requires Compliant. Submission status, compliance result, and renewal decision are three separate fields. |

### Policy table (thresholds read from the program record)

| Policy | Max GWA | Min units | Failed | Incomplete | Dropped | Evidence | Deadline (Asia/Manila) |
|---|---|---|---|---|---|---|---|
| Merit Scholar | 1.75 | 18 | 0 | 0 | 0 | Required | 2026-10-30 17:00 |
| Community Scholar | 2.25 | 15 | 0 | 0 | 1 | Required | 2026-10-30 17:00 |

## 11. UML Use Case Diagram

```
                          Student Scholarship Monitoring & Compliance System
   Actor                       Use Cases                                         Actor
   +-------+                                                        +-----------+
   |Scholar|--->( UC-01 Submit Grades )<..include..( UC-01a Authenticate )
   +-------+          |                                             | Staff     |
       |              +--<extend>--( UC-01b Correct & Resubmit )     +-----------+
       |              |
       |---->( UC-07 View Own Records & Status )                     |
                                                                     |
   +-------+                                                         |
   |Staff  |--->( UC-02 Register Scholar & Assign Policy )<..include..( UC-01a Authenticate )
   +-------+--->( UC-03 Verify Evidence )
              |        |
              |        +--<include>--( UC-03a Record Return Reason )   [only when Returned]
              |
              +--->( UC-04 Evaluate Compliance )<..include..( UC-03 )   [verified required]
              |
              +--->( UC-05 Record Renewal Decision )<..include..( UC-04 ) [compliance required]
              |
              +--->( UC-06 View Dashboard, Search & Filter )
              |
              +--->( UC-08 View History Log )
```

**Includes (2) — always executed as part of the base use case**

1. **UC-04 → UC-03 (Verify Evidence).** Evaluation can only run on a Verified record. Verification is not optional here; it is a guaranteed sub-step, so it is an include, not an extend (BR-3).
2. **UC-05 → UC-04 (Evaluate Compliance).** A renewal decision cannot exist without a compliance result, because Approve requires Compliant and Held is a response to a result. Always executed → include (BR-6).

**Extend (1) — conditional, optional behaviour**

- **UC-01b (Correct & Resubmit) extends UC-01 (Submit Grades).** Correction only happens when a record is Returned, and only the scholar chooses to do it. It is conditional, so it is an extend. It is *not* an include because a normal first submission never runs it.

*Justification summary:* a step that always runs is an include (UC-04, UC-05); a step that runs only under a condition and that a user can decline is an extend (UC-01b).

## 12. Detailed Use Cases

### UC-01 / UC-01b — Submit Grades (with Correct & Resubmit)

| Field | Detail |
|---|---|
| ID / Name | UC-01 Submit Grades (extends: UC-01b Correct & Resubmit) |
| Primary actor | Scholar |
| Stakeholders | Scholar, Scholarship Staff, Registrar (evidence source) |
| Trigger | Semester grades are released and the scholar opens **Submit grades** |
| Preconditions | Scholar is authenticated; a policy record is assigned; no existing record for the target scholar + academic year + semester |
| Guarantees | On success the record exists with status `Pending` and a history entry; no official grade is modified |
| Main success scenario | 1. Scholar selects academic year and semester of type `YYYY-YYYY` / `1 or 2`. 2. Enters GWA, enrolled units, failed, incomplete and dropped counts, and an evidence reference. 3. System validates each value. 4. System rejects a duplicate scholar + year + semester. 5. System stores the record with status `Pending` and a Manila `+08:00` timestamp. 6. System writes a "Grades submitted" history entry. |
| Alternate A1 | A value fails validation → system names the field, the range, and an example; nothing is stored. |
| Alternate A2 | A duplicate exists → system blocks and points the scholar to the existing record. |
| Alternate A3 (UC-01b) | The existing record is `Returned` → scholar corrects values, resubmits; status returns to `Pending`; the prior evaluation/decision, if any, is discarded; a "Submission resubmitted" history entry is written. |
| Postconditions | Exactly one record for the term; status `Pending`; history appended. |

### UC-04 — Evaluate Compliance

| Field | Detail |
|---|---|
| ID / Name | UC-04 Evaluate Compliance |
| Primary actor | Scholarship Staff |
| Stakeholders | Scholarship Office Head, Scholar, Registrar |
| Trigger | Staff opens **Compliance & renewal** for a semester |
| Preconditions | Submission exists; actor is Staff |
| Guarantees | Evaluation is derived entirely from the stored policy record; submission status, compliance result and renewal decision are stored separately |
| Includes | UC-03 Verify Evidence (the record must be Verified) |
| Main success scenario | 1. Staff opens a record. 2. System shows the record facts (GWA, units, failed, incomplete, dropped, evidence, timestamp) beside the assigned policy thresholds. 3. System confirms the record is `Verified` and evidence is present. 4. System runs each check: verified, evidence, GWA, units, failed, incomplete, dropped, on-time. 5. System lists every check with Pass/Fail and each deficiency reason. 6. If no check fails, result is `Compliant`; else `With Deficiency`. 7. System stores the evaluation, the policy snapshot, and a history entry. |
| Alternate A1 | Record is not `Verified` (Pending/Returned) → system blocks evaluation with a plain-language message. |
| Alternate A2 | Policy requires evidence and none is recorded → system blocks evaluation. |
| Postconditions | One evaluation per record: `Compliant` or `With Deficiency` with reasons. |

## 13. Entity–Relationship Diagram

```
 users (id PK, role, name)                     programs (code PK, name, max_gwa, min_units,
   |                                                     max_failed, max_incomplete, max_dropped,
   | 1..*                                                evidence_required, deadline)
   |                                                              | 1..*
   | (staff evaluates/decides; scholar submits)                   | assigned to
   |                                                              |
   v                                                              v
 scholars (id PK, name, program_code FK -> programs.code, registered_at)
   | 1..*                                                   
   | has                                                     
   v                                                         
 submissions (id PK, scholar_id FK -> scholars.id, academic_year, semester,
              gwa, enrolled_units, failed, incomplete, dropped, evidence_ref,
              submitted_at, status, return_reason, verification_note, verification_at)
   |                     UNIQUE (scholar_id, academic_year, semester)   <-- BR-1
   | 1..1                                                       1..1
   | evaluated as                                               decided as
   v                                                            v
 evaluations (id PK, submission_id FK UNIQUE -> submissions.id, program_code FK,
              result, deficiencies, policy_snapshot, evaluated_at, evaluated_by FK -> users.id)
                                                              
 decisions (id PK, submission_id FK UNIQUE -> submissions.id, decision,
            decided_at, decided_by FK -> users.id, note)

 history (id PK, actor, actor_role, event, notes, submission_id FK (nullable),
          scholar_id FK (nullable), created_at)
```

**Keys and cardinalities**
- `scholars.id` PK; `programs.code` PK; `users.id` PK.
- `scholars.program_code → programs.code` (many scholars : one program).
- `submissions.scholar_id → scholars.id` (many submissions : one scholar).
- `UNIQUE (submissions.scholar_id, academic_year, semester)` enforces BR-1.
- `evaluations.submission_id` and `decisions.submission_id` are UNIQUE → one evaluation and one decision per submission (1:1).
- `evaluations.evaluated_by` and `decisions.decided_by → users.id` (many rows : one staff user).
- `history.submission_id` and `history.scholar_id` are nullable FKs so registration events (scholar only) and verification/evaluation/renewal events (both) are all representable.

## 14. Traceability Matrix (4 FRs)

| FR | Business rule | Use case | Test case(s) | Implementation |
|---|---|---|---|---|
| FR-3 Submit grades | BR-1, BR-2, BR-4 | UC-01 | TC01, TC02, TC03, TC05, TC07 | `submitGrades`, `validateSubmissionPayload`, `computeChecks` (deadline) |
| FR-4 Verify evidence | BR-3 | UC-03 | TC06, TC08, TC09 | `verify`, `resubmit`, `submissions.status` |
| FR-5 Evaluate compliance | BR-3, BR-5 | UC-04 | TC01–TC05, TC06 | `evaluate`, `computeChecks` (reads `programs`) |
| FR-6 Renewal decision | BR-6 | UC-05 | TC06, TC10 | `decide` (Approve requires Compliant) |

## 15. Test case overview (TC01–TC10)

| TC | Scenario | Seed actor | Expected |
|---|---|---|---|
| TC01 | A01 exactly on threshold and exact deadline | A01 (Merit) | Compliant |
| TC02 | A02 GWA 1.76 > 1.75 | A02 (Merit) | With Deficiency: GWA only |
| TC03 | A03 exactly on Community thresholds incl. 1 dropped | A03 (Community) | Compliant |
| TC04 | A04 units 14 < 15 and incomplete 1 > 0 | A04 (Community) | With Deficiency: units + incomplete |
| TC05 | A05 failed 1 and 1 minute late | A05 (Merit) | With Deficiency: failed + late |
| TC06 | A06 still Pending | A06 (Community) | Evaluation and approval both blocked |
| TC07 | Duplicate, GWA 0.50, negative count | A01 | All three rejected |
| TC08 | A01 reads A02 record; A01 verifies | A01 | Both blocked by API |
| TC09 | Return A06, correct, resubmit | Staff then A06 | Pending with both history events |
| TC10 | Approve compliant / hold deficient / scholar decides | Staff, A01 | Approved / blocked / Held / blocked |
