# LinkedIn Professional Networking & Jobs Database: DBMS Project

**Course:** Database Management Systems · **Year:** B.Tech 2nd year · **Team size:** 4
**Database:** PostgreSQL 15 or newer · **Final submission:** Mon 23 Nov 2026
**Topics used:** Data types & constraints · Keys & relationships · Normalization · Query execution plans · Indexing · Query optimization · VACUUM/ANALYZE · Partitioning & sharding

## Files in this folder

| Path | What it is |
|------|------------|
| `README.md` | This project brief |
| `seed_data.zip` | 12 CSV files (149,984 job applications): the only input for Phase 2. Unzip it to get `seed_data/` |
| `queries/workload_30.sql` | The 30 queries for Phase 3 (do not edit) |
| `benchmarks/run_benchmark.sh` | Timing script: 3 runs per query, average, raw plans saved |
| `CHECKPOINTS.md` | Checkpoint dates and the files each one needs (DE and AP repos) |

**Getting started:** **clone this repository and push it into your team's DE repo** (the DE repo you submitted in the form); the steps are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Keep the structure shown in [Repository structure](#repository-structure-submit-exactly-this). Unzip `seed_data.zip` inside your project folder, but don't commit the CSV files. Deadlines are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Then begin with Phase 1.

---

## Team details (fill in before you start)

| Role | Name | Enrollment No. | GitHub Username |
|------|------|----------------|-----------------|
| Group Lead | Parth Saarthi Chhikara | 2501010325 | parth-access |
| Member 2 | Tanishq Tyagi | 2501010474 | tanishqt25 |
| Member 3 | Dhruv Maan | 2501010142 | dhruvm25142-end |
| Member 4 | Aarabdh Sharma | 2501010611 | aarabdh-ICA |

**Team No.:** ____ · **Section:** ____ · **Repository URL:** https://github.com/parth-access/DE_Project_2026

---

## How this project works

| Phase | What you do | You submit | Counts toward | Marks |
|-------|-------------|------------|---------------|------:|
| 1 | Understand the problem statements | `docs/01_problem_understanding.md` | Query Execution | 2 |
| 2 | Work out the database schema **from the seed data** and load it | `sql/01_schema.sql`, `sql/02_load_data.sql`, `docs/02_schema_design.md` | Query Execution | 5 |
| 3 | Run the **30 given SQL queries** and record their execution time | `docs/03_baseline_timings.md`, `benchmarks/results/baseline/` | Query Execution | 3 |
| 4 | Optimize the queries and record the new times | `sql/05_indexes.sql`, `sql/06_optimized_queries.sql`, `docs/04_optimization_report.md`, `benchmarks/results/optimized/` | Code Optimization | 16 |
| 5 | Scalability test on the **large dataset** (given later by faculty) and final report | `docs/05_scalability_report.md`, `benchmarks/results/large/` | Code Optimization | 14 |
| | **Total** | | | **40** |

---

## Phase 1: Problem statements

LinkedIn is a **professional network** and a **job marketplace**. Members list their career history (**positions** at companies, the current one has no end date) and **skills** that others endorse. Members send **invitations**; once accepted they become **connections** (a two-way relationship stored once). Companies post **jobs** that require skills; members **apply**, and recruiters move applications through a pipeline (viewed → shortlisted → interview → offer → hired). Members can see **who viewed their profile**—unless the viewer browsed in private mode. You have joined the LinkedIn India data team.

The current database was put together quickly by an earlier team. It has **no documented schema** (only data exports survive), and the product teams are complaining:

| # | Problem reported | Team | Related queries |
|---|------------------|------|-----------------|
| P1 | "**Profiles and the network page** (experience, connections, mutual connections) are slow for well-connected members." | Member experience | R01, R02, R03, R04 |
| P2 | "**People You May Know** and invitations take too long to compute." | Growth / Network | R05, R10, W02, W03 |
| P3 | "**Job search and "Jobs for you"** recommendations lag; applying must be instant." | Jobs | R06, R07, R09, W01 |
| P4 | "**Recruiters** need pipeline views, candidate search and bulk clean-ups quickly." | Recruiters | R08, R18, W05 |
| P5 | "**Who viewed your profile**: the re-engagement list of members who never view profiles is always **empty**." | Engagement | R11, R13 |
| P6 | "**Talent insights** (company tenure, time to hire, skill demand, salaries, talent flow, career breaks) time out." | Talent insights | R12, R14, R15, R16, R17, R25 |
| P7 | "Platform reports and jobs maintenance are slow, and activity will grow **20×**." | Platform | R19, R20, R21, R22, R23, R24, W04 |

**Your job:**
1. Rebuild a correct, well-constrained schema from the data exports (Phase 2).
2. Measure how the 30 most important queries perform today (Phase 3).
3. Make them fast **without changing their results** (Phase 4).
4. Prove the database will survive next year's growth (Phase 5).

**Deliverable for Phase 1** (`docs/01_problem_understanding.md`, at most 1 page):
- For each problem P1–P7, write in your own words what the business needs and which **stakeholder** is affected (member/job seeker, recruiter, company page admin, growth team, talent-insights team, trust & safety).
- Classify each problem as **customer-facing / real-time** or **reporting / analytics**. This decides your performance targets later.
- List any assumptions you make.

---

## Phase 2: Work out the schema from the seed data

You receive **`seed_data.zip`**. Unzip it to get a folder **`seed_data/`** with 12 CSV files, a real export of the production data:

| File | Rows | What it contains |
|------|-----:|------------------|
| `cities.csv` | 10 | Cities |
| `members.csv` | 40,000 | LinkedIn members |
| `companies.csv` | 2,000 | Companies |
| `positions.csv` | 99,940 | Work history of members (current position has no end date) |
| `skills.csv` | 72 | Skills |
| `member_skills.csv` | 212,417 | Skills of each member with endorsement counts |
| `connections.csv` | 219,966 | Connections between members (each pair stored once) |
| `invitations.csv` | 60,000 | Connection invitations |
| `jobs.csv` | 15,000 | Job postings |
| `job_skills.csv` | 65,719 | Skills required by each job |
| `applications.csv` | 149,984 | Every job application from 1 Jan 2025 to 30 Jun 2026 |
| `profile_views.csv` | 199,996 | Profile views (viewer hidden in private mode) |

The first line of every file is the header (column names). Here are the headers and the first rows of each file:

**cities.csv**
```
city_id,city_name,state
1,Bengaluru,Karnataka
2,Mumbai,Maharashtra
```

**members.csv**
```
member_id,first_name,last_name,headline,email,city_id,industry,is_premium,open_to_work,created_at
1,Vivaan,Sharma,Chartered Accountant at a bank,vivaan.sharma1@Gmail.com,2,EdTech,f,f,2021-07-08 18:21:16+05:30
2,Aditya,Sharma,Student at a bank,aditya.sharma2@Gmail.com,4,IT Services,f,f,2013-05-08 09:08:36+05:30
```

**companies.csv**
```
company_id,company_name,industry,company_size,hq_city_id,founded_year,website
1,Infosys,Fintech,10001+,4,1987,https://www.company1.com
2,TCS,Telecom,10001+,1,2024,https://www.company2.com
```

**positions.csv**
```
position_id,member_id,company_id,title,employment_type,start_date,end_date
1,1,133,Product Manager,FULL_TIME,2012-06-14,2013-08-29
2,1,1044,Accountant,FULL_TIME,2013-10-28,
```

**skills.csv**
```
skill_id,skill_name
1,SQL
2,Python
```

**member_skills.csv**
```
member_id,skill_id,endorsements
1,17,0
1,22,0
```

**connections.csv**
```
member_a,member_b,connected_at
1,767,2023-09-12 05:06:31+05:30
1,776,2024-12-30 13:36:14+05:30
```

**invitations.csv**
```
invitation_id,sender_id,recipient_id,note,sent_at,status,responded_at
1,15157,30098,,2025-01-01 00:00:00+05:30,ACCEPTED,2025-01-05 15:00:00+05:30
2,27800,1814,"Hi, I would like to add you to my professional network.",2025-01-01 00:13:06+05:30,IGNORED,2025-01-10 10:13:06+05:30
```

**jobs.csv**
```
job_id,company_id,title,city_id,workplace_type,employment_type,min_experience,min_salary_lpa,max_salary_lpa,posted_at,closes_at,status
1,554,Backend Engineer,2,ONSITE,FULL_TIME,2,17.5,,2025-01-01 00:00:00+05:30,2025-02-06 00:00:00+05:30,CLOSED
2,143,Product Manager,4,ONSITE,FULL_TIME,6,,,2025-01-01 00:52:24+05:30,2025-02-03 00:52:24+05:30,CLOSED
```

**job_skills.csv**
```
job_id,skill_id
1,14
1,32
```

**applications.csv**
```
application_id,job_id,member_id,applied_at,easy_apply,status,status_updated_at
1,1,17724,2025-01-01 00:00:00+05:30,t,OFFER,2025-01-20 00:00:00+05:30
2,1,37298,2025-01-01 00:05:14+05:30,t,APPLIED,2025-01-01 00:05:14+05:30
```

**profile_views.csv**
```
view_id,viewer_id,viewed_id,viewed_at
1,30469,2725,2025-01-01 00:00:00+05:30
2,23933,20409,2025-01-01 00:03:55+05:30
```

Open the files yourself (a spreadsheet, `head`, or `SELECT` after a quick load into a scratch table) and study the data carefully. **Nobody will give you the CREATE TABLE statements.** Working them out *is* the task.

### 2.1 What you must identify (for every table)
1. **Table name and column names.** Use exactly the file names and CSV headers. The 30 queries depend on them.
2. **Data type** of every column. Choose the *right* type, not just `TEXT` everywhere. Think about money, timestamps with a time-zone offset, yes/no columns, small whole numbers, decimals and short codes.
3. **Primary key.** Is it one column, or a combination? (Look closely at `connections`—how is a two-way relationship stored exactly once? Also `member_skills`, `job_skills`, and what stops someone applying twice to the same job.)
4. **Foreign keys.** Which column points to which table? What should happen **ON DELETE** (CASCADE, RESTRICT or SET NULL), and why?
5. **NOT NULL vs NULL.** Some columns are empty in some rows. Find out **when** and **why**, and decide which columns must never be empty. Why do some profile views have no `viewer_id`, and some jobs no `city_id`? When are `end_date`, `responded_at`, `max_salary_lpa`, `headline` and `website` empty?
6. **UNIQUE** columns (natural candidate keys such as emails, phone numbers, codes and handles).
7. **CHECK constraints.** Write at least **12** that the data obeys and the business needs. Look for allowed values (company sizes, employment and workplace types, statuses), rules between columns (end after start, remote ⇔ no city, max salary ≥ min salary, no self-invitations or self-views, pending ⇔ not responded), and the ordering rule in `connections`.
8. **Relationships and cardinalities** (1:1, 1:N, M:N). Draw the **ER diagram** (image + Mermaid code).
9. **Normal form.** Show that each table is in 3NF/BCNF (list its functional dependencies). Point out any column that is *derived or redundant* (hint: can a member's current company be derived from `positions`? Is `members.headline` redundant with the current position?) and say whether keeping it is justified.

### 2.2 Rules for your schema
- Create every table in a schema named **`linkedin`**: `CREATE SCHEMA linkedin;` and `SET search_path TO linkedin;`
- In this phase create **only constraints**: PK, FK, UNIQUE, NOT NULL, CHECK. **Do not create any other index yet.** (PostgreSQL automatically indexes PRIMARY KEY and UNIQUE columns; that's allowed. Note which indexes exist.) Your baseline in Phase 3 must reflect a database *without* tuning.
- Your constraints must accept **all** rows of the seed data. If a load fails, either your constraint is wrong or you found a data problem. Explain which in your design doc.

### 2.3 Load the data
Write `sql/02_load_data.sql` using `\copy`, loading tables in the right order (parents before children):

```sql
SET search_path TO linkedin;
\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true)
-- ... the other tables, in an order that satisfies your foreign keys
ANALYZE;
```

Then verify the row counts match the table above, and run at least **3 integrity checks** of your own (e.g. "no member has two positions that overlap in time", "every accepted invitation has a matching connection", "nobody applied to a job after it closed"). Paste the results into `docs/02_schema_design.md`.

### Phase 2 deliverables
- `sql/01_schema.sql`: runs top-to-bottom on an empty database without errors
- `sql/02_load_data.sql`: loads all 12 files without errors
- `docs/02_schema_design.md`: data dictionary (table · column · type · constraint · *why*), ER diagram, FDs and normal form per table, integrity-check results, and every data problem you found

---

## Phase 3: Run the 30 queries and record the time

The file **`queries/workload_30.sql`** contains **30 queries**: 25 reads (`R01`–`R25`) and 5 writes (`W01`–`W05`). They're also listed in the [Appendix](#appendix-the-30-queries). **Do not modify them.** If a query fails, your schema doesn't match the seed data; fix the schema, not the query.

### 3.1 How to measure (everyone must use the same method)
- Run each query with `EXPLAIN (ANALYZE, BUFFERS)` and read the **`Execution Time`** at the bottom.
- Run each query **3 times** and record the **average** of the three `Execution Time` values. Keep all three runs in the raw plan file.
- Write queries (`W01`–`W05`) must be measured inside `BEGIN; … ROLLBACK;` so the data does not change.
- Close other heavy applications while measuring, and use the **same laptop** for Phase 3 and Phase 4.

The helper script does all of this for you:
```bash
./benchmarks/run_benchmark.sh <your_database> baseline
# → benchmarks/results/baseline/summary.csv   (avg, median, min, max, scan types)
# → benchmarks/results/baseline/R01.txt …     (full plans of all 3 runs)
```
> ⚠️ One of the 30 queries takes **noticeably longer** than the others on the seed data. That's intentional. Let it finish, and don't skip it.

### 3.2 Deliverable: the timing table
In `docs/03_baseline_timings.md`, fill this table for **all 30** queries:

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Profile header: member 1023 with their current position and company | READ | | | | |
| R02: Experience section: member 1023's positions, latest first | READ | | | | |
| R03: "My Network": everyone connected to member 1023 | READ | | | | |
| R04: Profile page: mutual connections of member 1023 and member 356 | READ | | | | |
| R05: "People you may know": 2nd-degree connections of member 1023 ranked by mutual connections | READ | | | | |
| R06: Job search: open "data analyst" jobs in Bengaluru or remote, posted in the last 30 days of June 2026 | READ | | | | |
| R07: "Jobs for you": open jobs that need at least 2 of member 1023's skills | READ | | | | |
| R08: Recruiter: applicants of job 14075 by pipeline stage | READ | | | | |
| R09: "My Jobs": member 1023's applications with their status | READ | | | | |
| R10: Invitations tab: pending invitations received by member 1023 | READ | | | | |
| R11: "Who viewed your profile": viewers of member 217 since April 2026 (private-mode viewers counted separately) | READ | | | | |
| R12: Company page: current employees of Flipkart and their average tenure in years | READ | | | | |
| R13: Engagement: members who have never viewed anyone's profile (for a re-engagement nudge) | READ | | | | |
| R14: Talent insights: average days from application to hire, per company (2026 hires) | READ | | | | |
| R15: Skill demand: skills most requested by jobs posted in 2026 | READ | | | | |
| R16: Salary insights: average advertised salary range per job title and city (2026 postings with salaries) | READ | | | | |
| R17: Talent flow: companies people joined right after leaving TCS | READ | | | | |
| R18: Recruiter search: open-to-work Bengaluru members with SQL skill, most endorsed first | READ | | | | |
| R19: Employer report: open jobs and June 2026 applications of every IT Services company | READ | | | | |
| R20: Platform analytics: applications per day and running total, June 2026 | READ | | | | |
| R21: Skills pages: the most-endorsed member for each skill | READ | | | | |
| R22: Trust & safety console: all applications, newest first, page 4,001 (25 per page) | READ | | | | |
| R23: Sign-in: find the member by email, ignoring case | READ | | | | |
| R24: Growth: invitation acceptance rate of Premium vs free senders (2026) | READ | | | | |
| R25: Career insights: members with a career break of more than 6 months between two positions | READ | | | | |
| W01: "Easy Apply": member 1023 applies to job 14075 | WRITE | | | | |
| W02: Member 1023 accepts their oldest pending invitation | WRITE | | | | |
| W03: …and the new connection is stored once, smaller member id first | WRITE | | | | |
| W04: Nightly job: close every job whose closing date has passed | WRITE | | | | |
| W05: Recruiter clean-up: reject applications to TCS jobs still unreviewed after 60 days | WRITE | | | | |
| **Total (sum of all 30)** | | | | | |

Below the table, add for each query the **scan type** from the plan (Seq Scan, Index Scan, …) and one line on **why** it is slow or fast.

---

## Phase 4: Optimize the queries

Make the queries faster. **The results must stay the same** (same rows; order matters only where the query has an `ORDER BY`).

### 4.1 Techniques you may use
| Technique | Example |
|-----------|---------|
| B-tree index (single / composite) | the right column **order** matters: equality columns first, then range/sort |
| Partial index | index only the rows a query needs (e.g. a rare status) |
| Covering index | `INCLUDE (...)` so the table is never visited (Index Only Scan) |
| Expression index | index the exact expression used in `WHERE` |
| GIN index | for `ILIKE '%text%'` (extension `pg_trgm`), arrays or full-text search |
| BRIN index | for huge tables stored in time order |
| Query rewrite | sargable date ranges instead of functions on columns; `NOT EXISTS` instead of `NOT IN`; joins instead of correlated subqueries; keyset instead of `OFFSET` pagination; `UNION ALL` instead of `OR` across columns |
| VACUUM / ANALYZE | fresh statistics and visibility maps |
| Summary table / materialized view | for heavy reports that don't need live data (state how it's refreshed) |

**Not allowed:** changing the data, deleting rows, changing PostgreSQL server settings to hide the problem (e.g. huge `work_mem`, `enable_seqscan = off`), or caching results outside the database.

### 4.2 How to work
1. Put every index in `sql/05_indexes.sql`, each with a comment: **which queries it serves and why this type and column order**.
2. Put rewritten queries in `sql/06_optimized_queries.sql`. Copy `queries/workload_30.sql` and change **only** the queries you rewrite, keeping the `-- @R01` markers.
3. **Prove the results are unchanged** for every rewritten query (compare row counts, plus a checksum or an `EXCEPT` query). Put the proof in your report.
4. Benchmark again with the same method:
```bash
./benchmarks/run_benchmark.sh <your_database> optimized 5 sql/06_optimized_queries.sql
```
> 🔎 **Read the results, not just the timings.** At least one of the 30 original queries returns a **wrong answer** because of a subtle SQL rule about NULLs. Find it, explain it, and fix it. This is worth marks.

### 4.3 Deliverable: the optimization table
In `docs/04_optimization_report.md`:

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R03 | | e.g. Seq Scan on 220k connections (OR across two columns) | e.g. `UNION ALL` of two indexed lookups on `member_a` and `member_b` | | e.g. 99% (150×) | ✅ |
| … all 30 … | | | | | | |
| **Total** | | | | | | |

Improvement % = (before − after) / before × 100

Also include:
- **Before/after `EXPLAIN` plans** for your 5 biggest improvements
- **Write overhead:** which write queries got **slower** because of your indexes, by how much, and whether that's acceptable
- **Index storage:** the size of each index you created (`pg_relation_size`) compared with its table
- **Queries you could not speed up**, and why (an honest "this query must read most of the table" earns marks)

---

## Phase 5: Scalability report (large dataset round)

Your optimizations worked on 149,984 job applications. Next year the business expects **20× the volume**.

By **Thu 19 Nov 2026**, faculty will release **`large_data.zip`**: the same 12 CSV files with about **20× the rows** (≈ 3,000,000 applications, ≈ 4,000,000 profile views, ≈ 4,399,000 connections, ≈ 1,999,000 positions, ≈ 800,000 members). Until then, work on the design part of the report.

### 5.1 What to do with the large dataset
1. Create a new database. Run **your** `01_schema.sql`, load `large_data/` with your load script (change the folder name only), then run **your** `05_indexes.sql` and `ANALYZE`.
2. Run your **optimized** queries (`sql/06_optimized_queries.sql`). **Do not run the original 30 on the large data.** Some of them could run for a very long time.
   - R22 pages with `OFFSET`; if you replaced it with keyset pagination, explain how the "last seen" value is chosen for the large data.
3. Record the times and compare with your Phase 4 results on the seed data.

| Query | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Meets target? | If not, what you changed |
|-------|------------------------:|------------------------:|----------------------:|:-------------:|--------------------------|
| R01 | | | | | |
| … all 30 … | | | | | |

### 5.2 Performance targets on the large dataset
| Query group | Queries | Target (average of 3 runs) |
|-------------|---------|----------------:|
| Real-time / member-facing | R01, R02, R03, R04, R08, R09, R10, R11, R23, W01, W02, W03 | **under 5 ms** |
| Interactive search and recommendations | R05, R06, R07, R12, R13, R18, R22, W05 | **under 250 ms** |
| Reports and analytics | R14, R15, R16, R17, R19, R20, R21, R24, R25 | **under 5,000 ms** |
| Batch jobs | W04 | **under 1,000 ms** |

If a query misses its target, **find out why from the plan and fix it.** A query that was fast on the seed data can become slow on large data for reasons that only appear at scale. Show the before/after plans for every fix.

### 5.3 Deliverable: `docs/05_scalability_report.md`
1. **Results table** (above), with every target met or explained.
2. **Growth analysis.** Group your queries by how their time grew when the data grew 20×:
   - *stayed about the same* (why? e.g. index lookups grow with log n)
   - *grew about 20×* (why? e.g. they read a fixed *share* of the table)
   - *grew more than 20×* (why, and what you did about it)
3. **What broke at scale** and how you fixed it (plans before/after).
4. **Storage:** total database size, table vs index size, on seed and large data.
5. **Architecture for 100×:** explain with numbers from your own measurements:
   - **Partitioning:** which table, by which column (RANGE / LIST / HASH), and why. Write the DDL for `applications`, show partition pruning with `EXPLAIN`, and note the primary-key rule for partitioned tables.
   - **Sharding:** Would you shard by member? A connection links two members who may sit on different shards—how would R03 and R05 work then? Which queries become cross-shard, and how would you handle them?
   - **Read replicas and caching:** which of the 30 queries you would send to a replica or cache, and which must hit the primary.
   - **Maintenance:** VACUUM/autovacuum settings for `applications`, archiving old data, refreshing summary tables.
6. **Conclusion:** is your database ready for next year? What are the remaining risks?

---

## Repository structure (submit exactly this)

```
linkedin-dbms-<team-no>/
├── README.md                          # team table, how to run, headline numbers
├── team.json                          # group lead, members, enrollment numbers
├── docs/
│   ├── 01_problem_understanding.md
│   ├── 02_schema_design.md
│   ├── 03_baseline_timings.md
│   ├── 04_optimization_report.md
│   └── 05_scalability_report.md
├── diagrams/
│   └── er_diagram.png
├── sql/
│   ├── 01_schema.sql
│   ├── 02_load_data.sql
│   ├── 05_indexes.sql
│   ├── 06_optimized_queries.sql
│   └── 08_partitioning.sql
├── queries/
│   └── workload_30.sql                # given; do not edit
└── benchmarks/
    ├── run_benchmark.sh               # given
    └── results/
        ├── baseline/                  # Phase 3: summary.csv + raw plans
        ├── optimized/                 # Phase 4
        └── large/                     # Phase 5
```

`team.json`:
```json
{
  "team_number": "",
  "group_lead": { "name": "", "enrollment_no": "", "github": "" },
  "members": [
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" }
  ],
  "postgres_version": "",
  "laptop_used_for_benchmarks": ""
}
```

**Do not commit the CSV files** (`seed_data/`, `large_data/`); add them to `.gitignore`. They are too large and we already have them.

---

## Timeline

| Due | Work | Checkpoint |
|-----|------|------------|
| Tue 3 Nov 2026 | Clone this repo into your team's DE repo, add members, commit `team.json` | **CP0** Setup |
| Mon 16 Nov 2026 | Phase 1 + Phase 2 (schema, load, ER, data dictionary) | **CP1** Schema loads all seed data with no errors |
| Tue 17 Nov 2026 | Phase 3 (baseline, 3 runs, average) + start Phase 4 | **CP2** Baseline table for all 30 queries committed |
| Thu 19 Nov 2026 | Phase 4 (indexes, rewrites, wrong-result query) | **CP3** Optimization table committed |
| Mon 23 Nov 2026 | Phase 5 on the large dataset + final report | **CP4 Final submission:** last commit on the default branch |
| Wed 25 – Thu 26 Nov 2026 | Individual analysis, in class time | **CP5** Individual analysis |

Full list of files per checkpoint, including the AP repo: [`CHECKPOINTS.md`](CHECKPOINTS.md).

---

## Evaluation (40 marks)

These 40 marks are the DE part of the project: **Query Execution (10)** and **Code Optimization (30)**.
The AP project (20) and your Individual analysis (40) make up the rest of the 100.

| Phase | Criteria | Marks |
|-------|----------|------:|
| | **Query Execution** | **10** |
| 1 | Problems understood, stakeholders and query groups correctly identified | 2 |
| 2 | Correct data types (1), keys and foreign keys with justified delete rules (1), ≥12 meaningful CHECK / NOT NULL / UNIQUE constraints (1), ER diagram + normal-form analysis (1), data loads cleanly + integrity checks (1) | 5 |
| 3 | All 30 queries measured with the required method: 3 runs, average (1), raw plans committed (1), scan type and reason for each query (1) | 3 |
| | **Code Optimization** | **30** |
| 4 | Speed-up achieved with appropriate techniques (6), every index justified (3), results proven unchanged (2), wrong-result query found and explained (2), write overhead and index storage reported (3) | 16 |
| 5 | Large-dataset results with all targets met or explained (4), growth analysis (3), scale-only problems found and fixed (3), partitioning DDL + sharding/replica design backed by your numbers (4) | 14 |
| | **Total** | **40** |

**Integrity rules**
- Every number in your reports must match the raw plan files in `benchmarks/results/`. Copied or invented timings make the whole phase score 0.
- Every member must have commits; the commit history is checked.
- You may use AI tools to learn, but you must be able to explain every index and rewrite in your individual analysis.

---

## Appendix: the 30 queries

These are identical to `queries/workload_30.sql`. Use the file, not copy-paste from this page.

**R01: Profile header: member 1023 with their current position and company**
```sql
SELECT m.member_id, m.first_name, m.last_name, m.headline, p.title, c.company_name
FROM members m
LEFT JOIN positions p ON p.member_id = m.member_id AND p.end_date IS NULL
LEFT JOIN companies c ON c.company_id = p.company_id
WHERE m.member_id = 1023;
```

**R02: Experience section: member 1023's positions, latest first**
```sql
SELECT p.title, c.company_name, p.employment_type, p.start_date, p.end_date
FROM positions p
JOIN companies c ON c.company_id = p.company_id
WHERE p.member_id = 1023
ORDER BY p.start_date DESC;
```

**R03: "My Network": everyone connected to member 1023**
```sql
SELECT CASE WHEN c.member_a = 1023 THEN c.member_b ELSE c.member_a END AS connection_id, c.connected_at
FROM connections c
WHERE c.member_a = 1023 OR c.member_b = 1023
ORDER BY c.connected_at DESC;
```

**R04: Profile page: mutual connections of member 1023 and member 356**
```sql
SELECT x.friend
FROM (SELECT CASE WHEN member_a = 1023 THEN member_b ELSE member_a END AS friend
      FROM connections WHERE member_a = 1023 OR member_b = 1023) x
JOIN (SELECT CASE WHEN member_a = 356 THEN member_b ELSE member_a END AS friend
      FROM connections WHERE member_a = 356 OR member_b = 356) y ON y.friend = x.friend;
```

**R05: "People you may know": 2nd-degree connections of member 1023 ranked by mutual connections**
```sql
WITH my_conn AS (
    SELECT CASE WHEN member_a = 1023 THEN member_b ELSE member_a END AS f
    FROM connections WHERE member_a = 1023 OR member_b = 1023
)
SELECT CASE WHEN c.member_a = mc.f THEN c.member_b ELSE c.member_a END AS suggestion, count(*) AS mutuals
FROM my_conn mc
JOIN connections c ON c.member_a = mc.f OR c.member_b = mc.f
WHERE CASE WHEN c.member_a = mc.f THEN c.member_b ELSE c.member_a END <> 1023
  AND CASE WHEN c.member_a = mc.f THEN c.member_b ELSE c.member_a END NOT IN (SELECT f FROM my_conn)
GROUP BY 1
ORDER BY mutuals DESC, suggestion
LIMIT 20;
```

**R06: Job search: open "data analyst" jobs in Bengaluru or remote, posted in the last 30 days of June 2026**
```sql
SELECT j.job_id, j.title, c.company_name, j.workplace_type, j.min_salary_lpa, j.max_salary_lpa, j.posted_at
FROM jobs j
JOIN companies c ON c.company_id = j.company_id
WHERE j.status = 'OPEN'
  AND j.title ILIKE '%data analyst%'
  AND (j.city_id = 1 OR j.workplace_type = 'REMOTE')
  AND j.posted_at >= '2026-06-01'
ORDER BY j.posted_at DESC;
```

**R07: "Jobs for you": open jobs that need at least 2 of member 1023's skills**
```sql
SELECT js.job_id, count(*) AS matching_skills
FROM job_skills js
JOIN member_skills ms ON ms.skill_id = js.skill_id AND ms.member_id = 1023
JOIN jobs j           ON j.job_id = js.job_id AND j.status = 'OPEN'
GROUP BY js.job_id
HAVING count(*) >= 2
ORDER BY matching_skills DESC, js.job_id DESC
LIMIT 25;
```

**R08: Recruiter: applicants of job 14075 by pipeline stage**
```sql
SELECT a.status, count(*) AS applicants
FROM applications a
WHERE a.job_id = 14075
GROUP BY a.status
ORDER BY applicants DESC;
```

**R09: "My Jobs": member 1023's applications with their status**
```sql
SELECT a.application_id, j.title, c.company_name, a.status, a.applied_at
FROM applications a
JOIN jobs j      ON j.job_id = a.job_id
JOIN companies c ON c.company_id = j.company_id
WHERE a.member_id = 1023
ORDER BY a.applied_at DESC;
```

**R10: Invitations tab: pending invitations received by member 1023**
```sql
SELECT i.invitation_id, i.sender_id, m.first_name, m.last_name, i.note, i.sent_at
FROM invitations i
JOIN members m ON m.member_id = i.sender_id
WHERE i.recipient_id = 1023 AND i.status = 'PENDING'
ORDER BY i.sent_at DESC;
```

**R11: "Who viewed your profile": viewers of member 217 since April 2026 (private-mode viewers counted separately)**
```sql
SELECT coalesce(v.viewer_id::text, 'Someone in private mode') AS viewer, count(*) AS views, max(v.viewed_at) AS last_view
FROM profile_views v
WHERE v.viewed_id = 217
  AND v.viewed_at >= '2026-04-01'
GROUP BY 1
ORDER BY last_view DESC;
```

**R12: Company page: current employees of Flipkart and their average tenure in years**
```sql
SELECT c.company_name, count(*) AS current_employees,
       round(avg((DATE '2026-07-01' - p.start_date) / 365.25), 1) AS avg_tenure_years
FROM positions p
JOIN companies c ON c.company_id = p.company_id
WHERE c.company_name = 'Flipkart' AND p.end_date IS NULL
GROUP BY c.company_name;
```

**R13: Engagement: members who have never viewed anyone's profile (for a re-engagement nudge)**
```sql
SELECT m.member_id, m.first_name, m.last_name
FROM members m
WHERE m.member_id NOT IN (SELECT v.viewer_id FROM profile_views v);
```

**R14: Talent insights: average days from application to hire, per company (2026 hires)**
```sql
SELECT c.company_name, count(*) AS hires,
       round(avg(EXTRACT(EPOCH FROM (a.status_updated_at - a.applied_at)) / 86400), 1) AS avg_days_to_hire
FROM applications a
JOIN jobs j      ON j.job_id = a.job_id
JOIN companies c ON c.company_id = j.company_id
WHERE a.status = 'HIRED'
  AND a.status_updated_at >= '2026-01-01'
GROUP BY c.company_name
HAVING count(*) >= 3
ORDER BY avg_days_to_hire;
```

**R15: Skill demand: skills most requested by jobs posted in 2026**
```sql
SELECT s.skill_name, count(*) AS jobs
FROM job_skills js
JOIN skills s ON s.skill_id = js.skill_id
JOIN jobs j   ON j.job_id = js.job_id
WHERE EXTRACT(YEAR FROM j.posted_at) = 2026
GROUP BY s.skill_name
ORDER BY jobs DESC
LIMIT 20;
```

**R16: Salary insights: average advertised salary range per job title and city (2026 postings with salaries)**
```sql
SELECT j.title, coalesce(ct.city_name, 'Remote') AS city, count(*) AS postings,
       round(avg(j.min_salary_lpa), 1) AS avg_min_lpa, round(avg(j.max_salary_lpa), 1) AS avg_max_lpa
FROM jobs j
LEFT JOIN cities ct ON ct.city_id = j.city_id
WHERE j.min_salary_lpa IS NOT NULL AND j.posted_at >= '2026-01-01'
GROUP BY j.title, coalesce(ct.city_name, 'Remote')
ORDER BY j.title, avg_max_lpa DESC NULLS LAST;
```

**R17: Talent flow: companies people joined right after leaving TCS**
```sql
SELECT nxt.company_name, count(*) AS moved
FROM (
    SELECT p.member_id, p.company_id,
           lead(p.company_id) OVER (PARTITION BY p.member_id ORDER BY p.start_date) AS next_company_id
    FROM positions p
) t
JOIN companies cur ON cur.company_id = t.company_id AND cur.company_name = 'TCS'
JOIN companies nxt ON nxt.company_id = t.next_company_id
WHERE t.next_company_id <> t.company_id
GROUP BY nxt.company_name
ORDER BY moved DESC
LIMIT 15;
```

**R18: Recruiter search: open-to-work Bengaluru members with SQL skill, most endorsed first**
```sql
SELECT m.member_id, m.first_name, m.last_name, m.headline, ms.endorsements
FROM members m
JOIN member_skills ms ON ms.member_id = m.member_id
JOIN skills s         ON s.skill_id = ms.skill_id AND s.skill_name = 'SQL'
WHERE m.open_to_work AND m.city_id = 1
ORDER BY ms.endorsements DESC
LIMIT 50;
```

**R19: Employer report: open jobs and June 2026 applications of every IT Services company**
```sql
SELECT c.company_id, c.company_name,
       (SELECT count(*) FROM jobs j WHERE j.company_id = c.company_id AND j.status = 'OPEN') AS open_jobs,
       (SELECT count(*) FROM applications a JOIN jobs j ON j.job_id = a.job_id
         WHERE j.company_id = c.company_id AND a.applied_at >= '2026-06-01') AS june_applications
FROM companies c
WHERE c.industry = 'IT Services'
ORDER BY june_applications DESC;
```

**R20: Platform analytics: applications per day and running total, June 2026**
```sql
SELECT day, apps, sum(apps) OVER (ORDER BY day) AS running_total
FROM (
    SELECT applied_at::date AS day, count(*) AS apps
    FROM applications
    WHERE applied_at::date BETWEEN '2026-06-01' AND '2026-06-30'
    GROUP BY 1
) d
ORDER BY day;
```

**R21: Skills pages: the most-endorsed member for each skill**
```sql
SELECT skill_name, member_id, endorsements
FROM (
    SELECT s.skill_name, ms.member_id, ms.endorsements,
           ROW_NUMBER() OVER (PARTITION BY ms.skill_id ORDER BY ms.endorsements DESC, ms.member_id) AS rn
    FROM member_skills ms
    JOIN skills s ON s.skill_id = ms.skill_id
) t
WHERE rn = 1
ORDER BY endorsements DESC;
```

**R22: Trust & safety console: all applications, newest first, page 4,001 (25 per page)**
```sql
SELECT application_id, job_id, member_id, status, applied_at
FROM applications
ORDER BY applied_at DESC
OFFSET 100000
LIMIT 25;
```

**R23: Sign-in: find the member by email, ignoring case**
```sql
SELECT member_id, first_name, last_name, is_premium
FROM members
WHERE lower(email) = 'yash.sharma1023@gmail.com';
```

**R24: Growth: invitation acceptance rate of Premium vs free senders (2026)**
```sql
SELECT m.is_premium, count(*) AS invitations,
       round(100.0 * count(*) FILTER (WHERE i.status = 'ACCEPTED') / count(*), 1) AS accept_pct
FROM invitations i
JOIN members m ON m.member_id = i.sender_id
WHERE i.sent_at >= '2026-01-01'
GROUP BY m.is_premium;
```

**R25: Career insights: members with a career break of more than 6 months between two positions**
```sql
SELECT member_id, prev_end, start_date, start_date - prev_end AS gap_days
FROM (
    SELECT member_id, start_date,
           lag(end_date) OVER (PARTITION BY member_id ORDER BY start_date) AS prev_end
    FROM positions
) t
WHERE start_date - prev_end > 182
ORDER BY gap_days DESC, member_id
LIMIT 100;
```

**W01: "Easy Apply": member 1023 applies to job 14075**
```sql
INSERT INTO applications (application_id, job_id, member_id, applied_at, easy_apply, status, status_updated_at)
VALUES (90000001, 14075, 1023, '2026-07-01 09:00:00+05:30', TRUE, 'APPLIED', '2026-07-01 09:00:00+05:30')
ON CONFLICT (job_id, member_id) DO NOTHING;
```

**W02: Member 1023 accepts their oldest pending invitation**
```sql
UPDATE invitations
SET status = 'ACCEPTED', responded_at = '2026-07-01 09:10:00+05:30'
WHERE invitation_id = (SELECT min(invitation_id) FROM invitations WHERE recipient_id = 1023 AND status = 'PENDING');
```

**W03: …and the new connection is stored once, smaller member id first**
```sql
INSERT INTO connections (member_a, member_b, connected_at)
SELECT least(sender_id, recipient_id), greatest(sender_id, recipient_id), '2026-07-01 09:10:00+05:30'
FROM invitations
WHERE invitation_id = (SELECT min(invitation_id) FROM invitations WHERE recipient_id = 1023 AND status = 'PENDING')
ON CONFLICT DO NOTHING;
```

**W04: Nightly job: close every job whose closing date has passed**
```sql
UPDATE jobs
SET status = 'CLOSED'
WHERE status = 'OPEN' AND closes_at < '2026-07-01 00:00:00+05:30';
```

**W05: Recruiter clean-up: reject applications to TCS jobs still unreviewed after 60 days**
```sql
UPDATE applications a
SET status = 'REJECTED', status_updated_at = '2026-07-01 10:00:00+05:30'
FROM jobs j
JOIN companies c ON c.company_id = j.company_id
WHERE a.job_id = j.job_id
  AND c.company_name = 'TCS'
  AND a.status = 'APPLIED'
  AND a.applied_at < TIMESTAMPTZ '2026-07-01 00:00:00+05:30' - interval '60 days';
```
