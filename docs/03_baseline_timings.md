# Baseline Benchmark Timings

**Run date:** 11 November 2026

**Environment:** PostgreSQL 18.6 on a MacBook Pro (Apple M4, 16 GB RAM); `PGTZ=Asia/Kolkata`.

**Dataset:** seed dataset; all 12 loaded row counts matched the expected counts.
**Method:** each query ran three times with `EXPLAIN (ANALYZE, BUFFERS)`. Write queries ran inside `BEGIN`/`ROLLBACK`. Values below are PostgreSQL execution times in milliseconds from the three raw plans; averages are arithmetic means. The schema had its 16 primary-key/unique indexes and no added tuning indexes.

| SQL query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Profile header: member 1023 with current position and company | READ | 5.063 | 4.247 | 3.876 | 4.395 |
| R02: Experience section: member 1023's positions, latest first | READ | 2.829 | 2.872 | 2.820 | 2.840 |
| R03: My Network: everyone connected to member 1023 | READ | 2.222 | 2.145 | 2.436 | 2.268 |
| R04: Profile page: mutual connections of members 1023 and 356 | READ | 8.090 | 8.076 | 7.763 | 7.976 |
| R05: People you may know: second-degree connections ranked by mutual connections | READ | 27.133 | 32.387 | 26.181 | 28.567 |
| R06: Job search: open data analyst jobs in Bengaluru or remote, posted in June 2026 | READ | 2.268 | 2.220 | 2.222 | 2.237 |
| R07: Jobs for you: open jobs requiring at least two of member 1023’s skills | READ | 4.860 | 4.861 | 4.895 | 4.872 |
| R08: Recruiter: applicants of job 14075 by pipeline stage | READ | 0.063 | 0.056 | 0.059 | 0.059 |
| R09: My Jobs: member 1023’s applications with status | READ | 1.849 | 1.687 | 1.706 | 1.747 |
| R10: Invitations tab: pending invitations received by member 1023 | READ | 2.335 | 2.380 | 2.214 | 2.310 |
| R11: Who viewed your profile: viewers of member 217 since April 2026 | READ | 4.196 | 4.087 | 4.202 | 4.162 |
| R12: Company page: current employees of Flipkart and average tenure | READ | 4.992 | 5.053 | 4.984 | 5.010 |
| R13: Engagement: members who have never viewed anyone’s profile | READ | 20.201 | 20.632 | 20.757 | 20.530 |
| R14: Talent insights: average days from application to hire, by company in 2026 | READ | 8.793 | 8.480 | 8.580 | 8.618 |
| R15: Skill demand: most requested skills in jobs posted in 2026 | READ | 8.903 | 9.099 | 8.866 | 8.956 |
| R16: Salary insights: average advertised salary range by title and city | READ | 1.560 | 1.502 | 1.552 | 1.538 |
| R17: Talent flow: companies people joined after leaving TCS | READ | 34.335 | 34.847 | 34.599 | 34.594 |
| R18: Recruiter search: open-to-work Bengaluru members with SQL skill | READ | 8.079 | 8.031 | 8.193 | 8.101 |
| R19: Employer report: open jobs and June applications of IT Services companies | READ | 220.607 | 221.548 | 221.359 | 221.171 |
| R20: Platform analytics: applications per day and running total in June 2026 | READ | 6.078 | 5.955 | 5.985 | 6.006 |
| R21: Skills pages: most-endorsed member for each skill | READ | 84.276 | 83.921 | 85.902 | 84.700 |
| R22: Trust and safety: applications, page 4,001 at 25 rows per page | READ | 27.297 | 27.915 | 27.218 | 27.477 |
| R23: Sign-in: find member by email, ignoring case | READ | 4.042 | 3.651 | 3.794 | 3.829 |
| R24: Growth: 2026 invitation acceptance rate, Premium vs free senders | READ | 9.257 | 9.029 | 9.436 | 9.241 |
| R25: Career insights: members with a gap over six months between positions | READ | 33.239 | 33.786 | 35.447 | 34.157 |
| W01: Easy Apply: member 1023 applies to job 14075 | WRITE | 0.394 | 0.339 | 0.318 | 0.350 |
| W02: Accept member 1023’s oldest pending invitation | WRITE | 2.497 | 2.409 | 2.380 | 2.429 |
| W03: Store the resulting connection with the smaller member id first | WRITE | 2.490 | 2.551 | 2.421 | 2.487 |
| W04: Nightly job: close jobs whose closing date has passed | WRITE | 1.907 | 1.992 | 2.112 | 2.004 |
| W05: Recruiter clean-up: reject unreviewed TCS applications older than 60 days | WRITE | 2.697 | 2.663 | 2.530 | 2.630 |
| **Total (sum of all 30)** | | | | | **545.261** |

## Plan notes

| Query | Scan nodes in the last run | Timing explanation |
|---|---|---|
| R01 | Index Scan using members_pkey on members; Seq Scan on positions; Index Scan using companies_pkey on companies | Primary-key lookup finds one member; positions are scanned before the company lookup. |
| R02 | Seq Scan on positions; Index Scan using companies_pkey on companies | Positions are scanned to find one member’s history; company lookups use the primary key. |
| R03 | Bitmap Heap Scan on connections; Bitmap Index Scan on pk_connections | The composite connection key starts with member_a, so the requested adjacency lookup uses it. |
| R04 | Seq Scan on connections | The baseline has no index for the reverse connection direction, so connections are scanned. |
| R05 | Bitmap Heap Scan on connections; Bitmap Index Scan on pk_connections | The member_a index narrows adjacency lookups, but second-degree expansion and ranking add work. |
| R06 | Seq Scan on jobs; Index Scan using companies_pkey on companies | Jobs are scanned for status, title, location and date; the seed table is only 15,000 rows. |
| R07 | Seq Scan on job_skills; Seq Scan on jobs; Index Only Scan using pk_member_skills on member_skills | Jobs and job_skills are scanned to count skill matches; only the existing composite key helps member skills. |
| R08 | Index Scan using uq_applications_job_member on applications | The existing (job_id, member_id) unique index supports this selective job lookup. |
| R09 | Index Scan using uq_applications_job_member on applications; Index Scan using jobs_pkey on jobs; Index Scan using companies_pkey on companies | The applications composite index supports the member/job lookup; related rows use primary keys. |
| R10 | Seq Scan on invitations; Index Scan using members_pkey on members | Invitations are scanned for recipient and status; member details use the primary key. |
| R11 | Seq Scan on profile_views | Profile views are scanned for viewed member and date because those columns lack a baseline index. |
| R12 | Seq Scan on positions; Seq Scan on companies | Positions and companies are scanned for the company-page aggregation. |
| R13 | Seq Scan on members; Seq Scan on profile_views | Both tables are scanned. The original NOT IN returns zero rows because viewer_id contains NULLs; NOT EXISTS is needed for the correct 6,513-member result. |
| R14 | Seq Scan on applications; Seq Scan on jobs; Seq Scan on companies | Applications, jobs and companies are scanned/joined for the 2026 hired-application aggregation. |
| R15 | Seq Scan on jobs; Index Only Scan using pk_job_skills on job_skills; Seq Scan on skills | Jobs are scanned, job_skills uses its composite key for job lookup, and skills are scanned for aggregation. |
| R16 | Seq Scan on jobs; Seq Scan on cities | The jobs and cities tables are scanned; both are small in this seed dataset. |
| R17 | Seq Scan on positions; Seq Scan on companies; Index Scan using companies_pkey on companies | Positions and companies are scanned for the TCS-to-next-company self-join. |
| R18 | Seq Scan on member_skills; Seq Scan on skills; Index Scan using members_pkey on members | Member skills and skills are scanned for the SQL skill; matching members use their primary key. |
| R19 | Seq Scan on companies; Seq Scan on jobs; Index Scan using uq_applications_job_member on applications | This is the slowest read (221.171 ms): company/jobs filtering and application aggregation touch broad portions of the data. |
| R20 | Seq Scan on applications | Applications are scanned for the June date range and running-total window. |
| R21 | Seq Scan on member_skills; Seq Scan on skills | All member-skill endorsements are scanned and grouped by skill. |
| R22 | Seq Scan on applications | Applications are scanned and sorted for a deep OFFSET page. |
| R23 | Seq Scan on members | Members are scanned because lower(email) does not match the case-sensitive email unique index. |
| R24 | Seq Scan on invitations; Seq Scan on members | Invitations are scanned and joined to members before grouping acceptance rates. |
| R25 | Seq Scan on positions | Positions are scanned for the self-join and date-gap calculation. |
| W01 | (no scan) | No scan node appears in the plan; the transactional insert is very small. |
| W02 | Seq Scan on invitations; Index Scan using invitations_pkey on invitations | Invitations are scanned to select the oldest pending row; the update addresses it by primary key. |
| W03 | Seq Scan on invitations; Index Scan using invitations_pkey on invitations | Same selection/update pattern as W02; connection insertion is rolled back after measurement. |
| W04 | Seq Scan on jobs | The update scans the 15,000-row jobs table for expired open jobs. |
| W05 | Seq Scan on jobs; Seq Scan on companies; Index Scan using uq_applications_job_member on applications | Jobs, companies and matching applications are scanned/joined for the cleanup update. |

## Artifacts and interpretation

The raw plans for all three runs are in `benchmarks/results/baseline/`. The slowest read was R19 at 221.171 ms on average, followed by R21 at 84.700 ms. Most point lookups were below 10 ms. The total is the sum of the 30 query averages, not a single end-to-end application latency. The R23 plan replaces its email literals with `[redacted email]`; its measured timing and plan operators are unchanged.

R13’s baseline result is incorrect by design: its `NOT IN` subquery sees NULL `viewer_id` values and returns no members. The schema design report records the correct result as 6,513 members when rewritten with `NOT EXISTS`; query rewrites are part of CP3.
