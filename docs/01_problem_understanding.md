# Phase 1: Problem understanding (Team T0016, Section E)

LinkedIn India is a **professional network** (profiles, connections, invitations) and a **job marketplace**
(jobs, applications, recruiters). The database has no documented schema and seven teams report slow or wrong results.

| # | What the business needs | Stakeholder | Type | Queries |
|---|---|---|---|---|
| P1 | Profile page and "My Network" open instantly, even for members with thousands of connections. | Member / job seeker | **Customer-facing, real-time** | R01 R02 R03 R04 |
| P2 | "People You May Know" and the invitations tab are quick; accepting an invitation creates the connection at once. | Member; growth team | **Customer-facing, real-time** (R05 is a heavier list) | R05 R10 W02 W03 |
| P3 | Job search and "Jobs for you" do not lag; Easy Apply is instant. | Member / job seeker | **Customer-facing, real-time** | R06 R07 R09 W01 |
| P4 | Recruiters get a job's pipeline, a candidate search and a bulk clean-up of stale applications, fast. | Recruiter | **Customer-facing, real-time**; R18 interactive; W05 bulk write | R08 R18 W05 |
| P5 | "Who viewed your profile" works, with private viewers shown as one anonymous group. The re-engagement list is always **empty** and must return the real members (private-mode views have a NULL `viewer_id`, and `NOT IN` against a NULL never matches). | Member (R11); growth team (R13); privacy | R11 **real-time**; R13 **campaign report** | R11 R13 |
| P6 | Talent insights (tenure, time to hire, skill demand, salaries, talent flow, career breaks) stop timing out. | Talent-insights team; company page admins | **Reporting / analytics** | R12 R14 R15 R16 R17 R25 |
| P7 | Platform reports and maintenance are fast enough, and still fast at **20 times** the activity. | Platform team; employers; trust and safety; growth | **Reporting / analytics**, plus one **batch job** (W04) | R19 R20 R21 R22 R23 R24 W04 |

The type sets our Phase 4 targets (brief, section 5.2): real-time member-facing queries need index lookups
(under 5 ms at 20 times the data), interactive ones under 250 ms, reports under 5 s, the batch job under 1 s.

## Assumptions
1. "Today" is **1 July 2026**: the data ends on 30 June 2026 and the workload uses that date.
2. The seed data is the truth: we never change rows; rule breaks are recorded in `docs/02_schema_design.md`.
3. A member's **current position** has no `end_date`. A connection is stored **once**, smaller member id first.
4. A NULL `viewer_id` means private mode (viewer never shown); a NULL job `city_id` means remote; a NULL `responded_at` means the invitation is pending.
5. Member-facing queries dominate real traffic, so latency matters most there; W04 and W05 are rare batch writes.
6. Data grows about 20 times next year, so a query that reads a fixed share of a growing table is a risk.
