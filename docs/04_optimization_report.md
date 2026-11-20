# Optimization Report (CP3)

**Run date:** 20 November 2026

**Environment:** PostgreSQL 18.6 on a MacBook Pro (Apple M4, 16 GB RAM); default server settings (`shared_buffers` 128 MB, `work_mem` 4 MB); `PGTZ=Asia/Kolkata`.

**Dataset:** the seed dataset (all 12 loaded row counts matched the expected counts). Nothing in the data was changed.

**Method:** the same as the baseline. Each query ran three times with `EXPLAIN (ANALYZE, BUFFERS)`, write queries inside `BEGIN`/`ROLLBACK`, and the table shows the average of the three Execution Times in milliseconds. The command was `./benchmarks/run_benchmark.sh capstone optimized 3 sql/06_optimized_queries.sql`, run after `sql/05_indexes.sql`. The raw plans and `summary.csv` are in `benchmarks/results/optimized/`.

**"Before" column:** the averages in `benchmarks/results/baseline/summary.csv` (see `docs/03_baseline_timings.md`). To check that a fresh run on the same server gives about the same numbers, the baseline was run again before adding the indexes; its total was 519.966 ms against 545.261 ms (4.6% lower) and every query used the same scan types. Individual queries moved by up to about 13% (W01), which is normal run-to-run noise for timings this small.

## Summary

- The sum of all 30 averages went from **545.261 ms to 117.871 ms: 78.4% less, 4.6× faster**.
- The 25 reads together went from 535.361 ms to 112.375 ms. 24 of the 25 reads are faster, and 12 of them are at least 90% faster.
- We added **15 indexes** (`sql/05_indexes.sql`) and rewrote **11 queries** (R03, R04, R05, R13, R15, R17, R19, R20, R21, R22, R24; R24 only makes its date literal explicit). All other queries are unchanged and are sped up by the indexes alone.
- One query, **R13, returned a wrong answer** in the baseline. The rewrite fixes it (section 3).
- The write queries got faster in total (9.900 ms to 5.496 ms), but W01 and W04 are slightly slower because of the new indexes (section 5).

## 1. Optimization table

Improvement % = (before − after) / before × 100.

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R01 | 4.395 | Seq Scan on positions to find one member's positions | New index `ix_positions_member_start` (member_id, start_date); query unchanged | 0.037 | 99% (119×) | ✅ |
| R02 | 2.840 | Seq Scan on positions | Same index `ix_positions_member_start`; query unchanged | 0.030 | 99% (95×) | ✅ |
| R03 | 2.268 | `OR` on member_a / member_b: the primary key starts with member_a, so only one side can use an index | New index `ix_connections_member_b`; `OR` rewritten as `UNION ALL` of two index lookups | 0.043 | 98% (53×) | ✅ |
| R04 | 7.976 | Seq Scan on connections (nothing indexed the member_b side) | `ix_connections_member_b`; each friend list built with `UNION ALL` of two lookups, then intersected (Index Only Scans) | 0.064 | 99% (125×) | ✅ |
| R05 | 28.567 | Second-degree step joins on `member_a = f OR member_b = f`; only one side indexed; `NOT IN` | `ix_connections_member_b`; `UNION ALL` lookups; `NOT IN` changed to `NOT EXISTS` | 0.248 | 99% (115×) | ✅ |
| R06 | 2.237 | Seq Scan on jobs (15,000 rows) | No rewrite; the planner now reads jobs through `ix_jobs_company_status` | 0.562 | 75% (4×) | ✅ |
| R07 | 4.872 | Seq Scan on jobs and job_skills to count skill matches | None (see section 7) | 4.647 | 5% | ✅ |
| R08 | 0.059 | Already an Index Scan on `uq_applications_job_member` | None needed | 0.063 | -7% (slower) | ✅ |
| R09 | 1.747 | Applications found through the (job_id, member_id) index although the query filters by member | New index `ix_applications_member` (member_id, applied_at DESC) | 0.070 | 96% (25×) | ✅ |
| R10 | 2.310 | Seq Scan on invitations | Partial index `ix_invitations_pending_recipient` (only PENDING rows) | 0.031 | 99% (75×) | ✅ |
| R11 | 4.162 | Seq Scan on profile_views | New index `ix_profile_views_viewed_at` (viewed_id, viewed_at) | 0.055 | 99% (76×) | ✅ |
| R12 | 5.010 | Seq Scan on positions and companies | `ix_companies_name` and partial index `ix_positions_current_company` (end_date IS NULL) | 0.196 | 96% (26×) | ✅ |
| R13 | 20.530 | **Wrong answer:** `NOT IN` meets NULL viewer_id values and returns 0 rows (section 3) | `NOT EXISTS` (anti-join) using `ix_profile_views_viewer` | 17.640 | 14% | ❌→✅ fixed: 0 rows became the correct 6,513 |
| R14 | 8.618 | Seq Scan on applications, jobs and companies | Partial index `ix_applications_hired` (status = 'HIRED'); query unchanged | 3.186 | 63% (3×) | ✅ |
| R15 | 8.956 | `EXTRACT(YEAR FROM posted_at) = 2026` hides the column from the planner | Plain range on `posted_at` (sargable); no index needed | 7.676 | 14% | ✅ |
| R16 | 1.538 | Seq Scan on small jobs and cities tables | None (see section 7) | 1.506 | 2% | ✅ |
| R17 | 34.594 | `lead()` window ran over every position of every member, then almost all was thrown away | Only members who ever worked at TCS go through the window; `ix_companies_name`, `ix_positions_member_start` | 7.424 | 79% (5×) | ✅ |
| R18 | 8.101 | Seq Scan on member_skills and skills | New index `ix_member_skills_skill_endorse` (skill_id, endorsements DESC, member_id) | 2.867 | 65% (3×) | ✅ |
| R19 | 221.171 | Two correlated subqueries ran once per IT Services company (Seq Scan on jobs and applications each time) | Two grouped joins computed once; `ix_companies_industry`, `ix_applications_applied_at`, `ix_jobs_company_status` | 2.650 | 99% (83×) | ✅ (same rows; order differs only between ties) |
| R20 | 6.006 | `applied_at::date BETWEEN` hides the column from the index; Seq Scan on applications | Half-open range on `applied_at`; `ix_applications_applied_at` gives an Index Only Scan | 1.273 | 79% (5×) | ✅ |
| R21 | 84.700 | `ROW_NUMBER()` numbered every member_skills row after a sort | `DISTINCT ON (skill_id)` reading `ix_member_skills_skill_endorse` in order | 31.345 | 63% (3×) | ✅ |
| R22 | 27.477 | `OFFSET 100000` reads and throws away 100,000 rows to show 25 | Keyset pagination on `applied_at` using `ix_applications_applied_at` | 0.027 | 100% (1018×) | ✅ |
| R23 | 3.829 | `lower(email)` cannot use the case-sensitive unique index; Seq Scan on 40,000 members | Expression index `ix_members_lower_email` | 0.025 | 99% (153×) | ✅ |
| R24 | 9.241 | Seq Scan on invitations, joined to members | `ix_invitations_sent_at`; date literal made an explicit India-time timestamp | 7.155 | 23% | ✅ |
| R25 | 34.157 | Seq Scan on positions for the career-gap self-join | `ix_positions_member_start`; query unchanged | 23.555 | 31% | ✅ |
| W01 | 0.350 | No scan (single-row insert) | None; the insert now also maintains 3 new `applications` indexes | 0.469 | -34% (slower) | ✅ |
| W02 | 2.429 | Seq Scan on invitations to find the oldest pending row | Partial index `ix_invitations_pending_recipient` | 0.144 | 94% (17×) | ✅ |
| W03 | 2.487 | Seq Scan on invitations (same pattern as W02) | Partial index `ix_invitations_pending_recipient` | 0.333 | 87% (7×) | ✅ |
| W04 | 2.004 | Seq Scan on jobs (15,000 rows) | None; the update must keep `ix_jobs_company_status` current | 2.520 | -26% (slower) | ✅ |
| W05 | 2.630 | Seq Scan on jobs and companies | `ix_companies_name`, `ix_jobs_company_status` | 2.030 | 23% | ✅ |
| **Total** | **545.261** | | | **117.871** | **78.4% (4.6×)** | |

R08 (−7%) is the same plan before and after (an Index Scan on `uq_applications_job_member`); 0.004 ms is noise.

R22 uses keyset pagination. The `applied_at` value in the rewritten query is the one from row 100,000 of this dataset, so it returns exactly the same 25 rows as the `OFFSET` version (no two applications share an `applied_at`). In an application, that value comes from the last row of the previous page.

## 2. Proof that the results are unchanged

For every query, the original text from `queries/workload_30.sql` and the optimized text from `sql/06_optimized_queries.sql` were run on the same database (with the indexes in place). Each result was saved with `psql -At`, and the two outputs were compared with an MD5 checksum of the whole output (so row order counts), and again after sorting the lines.

- **23 of the 25 reads give exactly the same rows in the same order.** R01 to R12, R14 to R18, R20 to R25.
- **R19** returns the same 200 rows. The order differs only between companies with the same `june_applications` value, because the query orders by that one column and ties have no defined order. The `june_applications` column is in the identical sequence in both outputs.
- **R13** is the one query that changes on purpose: 0 rows before, 6,513 after (section 3).
- **All 5 write queries** do the same thing: same row counts for the `INSERT`/`UPDATE` (W01 inserts 1 row, W02 updates 1, W03 inserts 1, W04 updates 552, W05 updates 119), checked inside `BEGIN`/`ROLLBACK`.

## 3. The query with a wrong answer: R13

R13 asks for members who have never viewed anyone's profile. The original used

```sql
WHERE member_id NOT IN (SELECT viewer_id FROM profile_views)
```

but `viewer_id` is NULL for the 50,173 views made in private mode. In SQL, `x NOT IN (…, NULL, …)` is never TRUE: comparing `x` with the NULL gives "unknown", and "unknown" does not pass a `WHERE`. So the query returned **0 rows**, which looks like a normal answer but is wrong.

The fix is `NOT EXISTS`, which ignores the NULL rows: it returns the **6,513** members who really never viewed anyone. As a bonus it is a little faster (20.530 ms to 17.640 ms), because it becomes an anti-join that can use `ix_profile_views_viewer`. The two times are not an exact like-for-like comparison, since the new query returns the correct, much larger result.

## 4. Before and after plans for the 5 biggest improvements

These are the five queries that saved the most time (R19, R21, R05, R22, R17). Plans are run 3 of each query, with the `Buffers` lines left out to keep them short; the full plans are in `benchmarks/results/baseline/` and `benchmarks/results/optimized/`.

### R19: 221.171 ms → 2.650 ms

**Before** (baseline plan, run 3)
```
Sort  (cost=226814.92..226815.42 rows=200 width=39) (actual time=221.320..221.325 rows=200.00 loops=1)
  Sort Key: ((SubPlan 2)) DESC
  Sort Method: quicksort  Memory: 36kB
  ->  Seq Scan on companies c  (cost=0.00..226807.28 rows=200 width=39) (actual time=1.688..221.290 rows=200.00 loops=1)
        Filter: ((industry)::text = 'IT Services'::text)
        Rows Removed by Filter: 1800
        SubPlan 1
          ->  Aggregate  (cost=489.00..489.01 rows=1 width=8) (actual time=0.677..0.677 rows=1.00 loops=200)
                ->  Seq Scan on jobs j  (cost=0.00..489.00 rows=1 width=0) (actual time=0.589..0.676 rows=0.82 loops=200)
                      Filter: ((company_id = c.company_id) AND ((status)::text = 'OPEN'::text))
                      Rows Removed by Filter: 14999
        SubPlan 2
          ->  Aggregate  (cost=644.65..644.66 rows=1 width=8) (actual time=0.428..0.428 rows=1.00 loops=200)
                ->  Nested Loop  (cost=0.42..644.64 rows=4 width=0) (actual time=0.406..0.428 rows=3.96 loops=200)
                      ->  Seq Scan on jobs j_1  (cost=0.00..451.50 rows=8 width=4) (actual time=0.068..0.397 rows=6.97 loops=200)
                            Filter: (company_id = c.company_id)
                            Rows Removed by Filter: 14993
                      ->  Index Scan using uq_applications_job_member on applications a  (cost=0.42..24.13 rows=1 width=4) (actual time=0.004..0.004 rows=0.57 loops=1394)
                            Index Cond: (job_id = j_1.job_id)
                            Filter: (applied_at >= '2026-06-01 00:00:00+05:30'::timestamp with time zone)
                            Rows Removed by Filter: 9
Execution Time: 221.359 ms
```
**After** (optimized plan, run 3)
```
Sort  (cost=1449.40..1449.90 rows=200 width=238) (actual time=2.607..2.612 rows=200.00 loops=1)
  Sort Key: (COALESCE((count(*)), '0'::bigint)) DESC
  Sort Method: quicksort  Memory: 36kB
  CTE it
    ->  Bitmap Heap Scan on companies  (cost=5.83..56.33 rows=200 width=23) (actual time=0.010..0.036 rows=200.00 loops=1)
          Recheck Cond: ((industry)::text = 'IT Services'::text)
          Heap Blocks: exact=25
          ->  Bitmap Index Scan on ix_companies_industry  (cost=0.00..5.78 rows=200 width=0) (actual time=0.005..0.005 rows=200.00 loops=1)
                Index Cond: ((industry)::text = 'IT Services'::text)
  ->  Hash Left Join  (cost=1362.73..1385.43 rows=200 width=238) (actual time=2.560..2.589 rows=200.00 loops=1)
        Hash Cond: (it.company_id = o.company_id)
        ->  Hash Right Join  (cost=889.56..911.72 rows=200 width=230) (actual time=1.733..1.751 rows=200.00 loops=1)
              Hash Cond: (j.company_id = it.company_id)
              ->  HashAggregate  (cost=883.06..891.55 rows=849 width=12) (actual time=1.671..1.677 rows=109.00 loops=1)
                    Group Key: j.company_id
                    Batches: 1  Memory Usage: 49kB
                    ->  Hash Join  (cost=511.17..878.81 rows=849 width=4) (actual time=0.968..1.629 rows=791.00 loops=1)
                          Hash Cond: (a.job_id = j.job_id)
                          ->  Index Scan using ix_applications_applied_at on applications a  (cost=0.42..327.95 rows=8432 width=4) (actual time=0.008..0.394 rows=8241.00 loops=1)
                                Index Cond: (applied_at >= '2026-06-01 00:00:00+05:30'::timestamp with time zone)
                          ->  Hash  (cost=491.86..491.86 rows=1511 width=8) (actual time=0.958..0.958 rows=1394.00 loops=1)
                                Buckets: 2048  Batches: 1  Memory Usage: 71kB
                                ->  Hash Join  (cost=6.50..491.86 rows=1511 width=8) (actual time=0.019..0.904 rows=1394.00 loops=1)
                                      Hash Cond: (j.company_id = it_1.company_id)
                                      ->  Seq Scan on jobs j  (cost=0.00..414.00 rows=15000 width=8) (actual time=0.001..0.481 rows=15000.00 loops=1)
                                      ->  Hash  (cost=4.00..4.00 rows=200 width=4) (actual time=0.013..0.014 rows=200.00 loops=1)
                                            Buckets: 1024  Batches: 1  Memory Usage: 16kB
                                            ->  CTE Scan on it it_1  (cost=0.00..4.00 rows=200 width=4) (actual time=0.000..0.006 rows=200.00 loops=1)
                                                  Storage: Memory  Maximum Storage: 27kB
              ->  Hash  (cost=4.00..4.00 rows=200 width=222) (actual time=0.058..0.058 rows=200.00 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 20kB
                    ->  CTE Scan on it  (cost=0.00..4.00 rows=200 width=222) (actual time=0.011..0.051 rows=200.00 loops=1)
                          Storage: Memory  Maximum Storage: 27kB
        ->  Hash  (cost=470.93..470.93 rows=179 width=12) (actual time=0.817..0.817 rows=101.00 loops=1)
              Buckets: 1024  Batches: 1  Memory Usage: 13kB
              ->  Subquery Scan on o  (cost=467.35..470.93 rows=179 width=12) (actual time=0.806..0.813 rows=101.00 loops=1)
                    ->  HashAggregate  (cost=467.35..469.14 rows=179 width=12) (actual time=0.805..0.809 rows=101.00 loops=1)
                          Group Key: j_1.company_id
                          Batches: 1  Memory Usage: 32kB
                          ->  Hash Join  (cost=6.50..466.46 rows=179 width=4) (actual time=0.035..0.794 rows=165.00 loops=1)
                                Hash Cond: (j_1.company_id = it_2.company_id)
                                ->  Seq Scan on jobs j_1  (cost=0.00..451.50 rows=1778 width=4) (actual time=0.004..0.717 rows=1778.00 loops=1)
                                      Filter: ((status)::text = 'OPEN'::text)
                                      Rows Removed by Filter: 13222
                                ->  Hash  (cost=4.00..4.00 rows=200 width=4) (actual time=0.018..0.018 rows=200.00 loops=1)
                                      Buckets: 1024  Batches: 1  Memory Usage: 16kB
                                      ->  CTE Scan on it it_2  (cost=0.00..4.00 rows=200 width=4) (actual time=0.000..0.009 rows=200.00 loops=1)
                                            Storage: Memory  Maximum Storage: 27kB
Execution Time: 2.660 ms
```

### R21: 84.700 ms → 31.345 ms

**Before** (baseline plan, run 3)
```
Sort  (cost=34541.91..34544.56 rows=1062 width=17) (actual time=84.744..84.746 rows=72.00 loops=1)
  Sort Key: t.endorsements DESC
  Sort Method: quicksort  Memory: 27kB
  ->  Subquery Scan on t  (cost=27053.96..34488.53 rows=1062 width=17) (actual time=70.391..84.735 rows=72.00 loops=1)
        Filter: (t.rn = 1)
        ->  WindowAgg  (cost=27053.96..31833.32 rows=212417 width=27) (actual time=70.391..84.730 rows=72.00 loops=1)
              Window: w1 AS (PARTITION BY ms.skill_id ORDER BY ms.endorsements, ms.member_id ROWS UNBOUNDED PRECEDING)
              Run Condition: (row_number() OVER w1 <= 1)
              Storage: Memory  Maximum Storage: 17kB
              ->  Sort  (cost=27053.93..27584.98 rows=212417 width=19) (actual time=70.383..79.852 rows=212417.00 loops=1)
                    Sort Key: ms.skill_id, ms.endorsements DESC, ms.member_id
                    Sort Method: external merge  Disk: 6128kB
                    ->  Hash Join  (cost=2.62..3901.20 rows=212417 width=19) (actual time=0.014..21.074 rows=212417.00 loops=1)
                          Hash Cond: (ms.skill_id = s.skill_id)
                          ->  Seq Scan on member_skills ms  (cost=0.00..3308.17 rows=212417 width=10) (actual time=0.003..5.475 rows=212417.00 loops=1)
                          ->  Hash  (cost=1.72..1.72 rows=72 width=11) (actual time=0.008..0.009 rows=72.00 loops=1)
                                Buckets: 1024  Batches: 1  Memory Usage: 12kB
                                ->  Seq Scan on skills s  (cost=0.00..1.72 rows=72 width=11) (actual time=0.001..0.003 rows=72.00 loops=1)
Execution Time: 85.902 ms
```
**After** (optimized plan, run 3)
```
Sort  (cost=11813.65..11813.83 rows=72 width=17) (actual time=30.358..30.359 rows=72.00 loops=1)
  Sort Key: ms.endorsements DESC
  Sort Method: quicksort  Memory: 27kB
  ->  Nested Loop  (cost=0.42..11811.43 rows=72 width=17) (actual time=0.016..30.349 rows=72.00 loops=1)
        Join Filter: (s.skill_id = ms.skill_id)
        Rows Removed by Join Filter: 2556
        ->  Unique  (cost=0.42..11732.10 rows=72 width=10) (actual time=0.010..30.187 rows=72.00 loops=1)
              ->  Index Only Scan using ix_member_skills_skill_endorse on member_skills ms  (cost=0.42..11201.05 rows=212417 width=10) (actual time=0.010..26.062 rows=212417.00 loops=1)
                    Heap Fetches: 212417
        ->  Materialize  (cost=0.00..2.08 rows=72 width=11) (actual time=0.000..0.001 rows=36.50 loops=72)
              Storage: Memory  Maximum Storage: 19kB
              ->  Seq Scan on skills s  (cost=0.00..1.72 rows=72 width=11) (actual time=0.003..0.009 rows=72.00 loops=1)
Execution Time: 30.383 ms
```

### R05: 28.567 ms → 0.248 ms

**Before** (baseline plan, run 3)
```
Limit  (cost=32218.06..32218.11 rows=20 width=12) (actual time=26.144..26.146 rows=20.00 loops=1)
  CTE my_conn
    ->  Bitmap Heap Scan on connections  (cost=4074.65..4129.98 rows=15 width=4) (actual time=2.127..2.128 rows=14.00 loops=1)
          Recheck Cond: ((member_a = 1023) OR (member_b = 1023))
          Heap Blocks: exact=1
          ->  BitmapOr  (cost=4074.65..4074.65 rows=15 width=0) (actual time=2.123..2.124 rows=0.00 loops=1)
                ->  Bitmap Index Scan on pk_connections  (cost=0.00..4.48 rows=8 width=0) (actual time=0.009..0.009 rows=14.00 loops=1)
                      Index Cond: (member_a = 1023)
                ->  Bitmap Index Scan on pk_connections  (cost=0.00..4070.16 rows=7 width=0) (actual time=2.115..2.115 rows=0.00 loops=1)
                      Index Cond: (member_b = 1023)
  ->  Sort  (cost=28088.08..28088.37 rows=116 width=12) (actual time=26.143..26.144 rows=20.00 loops=1)
        Sort Key: (count(*)) DESC, (CASE WHEN (c.member_a = mc.f) THEN c.member_b ELSE c.member_a END)
        Sort Method: top-N heapsort  Memory: 25kB
        ->  GroupAggregate  (cost=28082.68..28085.00 rows=116 width=12) (actual time=26.115..26.130 rows=127.00 loops=1)
              Group Key: (CASE WHEN (c.member_a = mc.f) THEN c.member_b ELSE c.member_a END)
              ->  Sort  (cost=28082.68..28082.97 rows=116 width=4) (actual time=26.112..26.115 rows=127.00 loops=1)
                    Sort Key: (CASE WHEN (c.member_a = mc.f) THEN c.member_b ELSE c.member_a END)
                    Sort Method: quicksort  Memory: 25kB
                    ->  Nested Loop  (cost=1816.33..28078.70 rows=116 width=4) (actual time=3.899..26.103 rows=127.00 loops=1)
                          ->  CTE Scan on my_conn mc  (cost=0.00..0.30 rows=15 width=4) (actual time=2.128..2.128 rows=14.00 loops=1)
                                Storage: Memory  Maximum Storage: 17kB
                          ->  Bitmap Heap Scan on connections c  (cost=1816.33..1871.79 rows=8 width=8) (actual time=1.707..1.711 rows=9.07 loops=14)
                                Recheck Cond: ((member_a = mc.f) OR (member_b = mc.f))
                                Filter: ((CASE WHEN (member_a = mc.f) THEN member_b ELSE member_a END <> 1023) AND (NOT (ANY (CASE WHEN (member_a = mc.f) THEN member_b ELSE member_a END = (hashed SubPlan 2).col1))))
                                Rows Removed by Filter: 1
                                Heap Blocks: exact=90
                                ->  BitmapOr  (cost=1815.99..1815.99 rows=16 width=0) (actual time=1.704..1.704 rows=0.00 loops=14)
                                      ->  Bitmap Index Scan on pk_connections  (cost=0.00..4.49 rows=9 width=0) (actual time=0.001..0.001 rows=4.64 loops=14)
                                            Index Cond: (member_a = mc.f)
                                      ->  Bitmap Index Scan on pk_connections  (cost=0.00..1811.50 rows=7 width=0) (actual time=1.703..1.703 rows=5.43 loops=14)
                                            Index Cond: (member_b = mc.f)
                                SubPlan 2
                                  ->  CTE Scan on my_conn  (cost=0.00..0.30 rows=15 width=4) (actual time=0.000..0.002 rows=14.00 loops=1)
                                        Storage: Memory  Maximum Storage: 17kB
Execution Time: 26.181 ms
```
**After** (optimized plan, run 3)
```
Limit  (cost=830.35..830.40 rows=20 width=12) (actual time=0.207..0.209 rows=20.00 loops=1)
  CTE my_conn
    ->  Append  (cost=0.42..50.83 rows=15 width=4) (actual time=0.014..0.021 rows=14.00 loops=1)
          ->  Index Only Scan using pk_connections on connections  (cost=0.42..20.81 rows=8 width=4) (actual time=0.014..0.015 rows=14.00 loops=1)
                Index Cond: (member_a = 1023)
                Heap Fetches: 14
          ->  Index Only Scan using ix_connections_member_b on connections connections_1  (cost=0.42..29.95 rows=7 width=4) (actual time=0.005..0.005 rows=0.00 loops=1)
                Index Cond: (member_b = 1023)
                Heap Fetches: 0
  ->  Sort  (cost=779.52..780.02 rows=200 width=12) (actual time=0.207..0.208 rows=20.00 loops=1)
        Sort Key: (count(*)) DESC, c.member_b
        Sort Method: top-N heapsort  Memory: 26kB
        ->  HashAggregate  (cost=772.20..774.20 rows=200 width=12) (actual time=0.189..0.194 rows=127.00 loops=1)
              Group Key: c.member_b
              Batches: 1  Memory Usage: 32kB
              ->  Hash Anti Join  (cost=0.91..771.12 rows=216 width=4) (actual time=0.034..0.179 rows=127.00 loops=1)
                    Hash Cond: (c.member_b = m.f)
                    ->  Append  (cost=0.42..767.84 rows=233 width=4) (actual time=0.023..0.164 rows=127.00 loops=1)
                          ->  Nested Loop  (cost=0.42..330.15 rows=129 width=4) (actual time=0.023..0.071 rows=65.00 loops=1)
                                ->  CTE Scan on my_conn mc  (cost=0.00..0.30 rows=15 width=4) (actual time=0.015..0.015 rows=14.00 loops=1)
                                      Storage: Memory  Maximum Storage: 17kB
                                ->  Index Only Scan using pk_connections on connections c  (cost=0.42..21.90 rows=9 width=8) (actual time=0.003..0.004 rows=4.64 loops=14)
                                      Index Cond: (member_a = mc.f)
                                      Filter: (member_b <> 1023)
                                      Heap Fetches: 65
                          ->  Nested Loop  (cost=0.42..436.52 rows=104 width=4) (actual time=0.011..0.088 rows=62.00 loops=1)
                                ->  CTE Scan on my_conn mc_1  (cost=0.00..0.30 rows=15 width=4) (actual time=0.000..0.000 rows=14.00 loops=1)
                                      Storage: Memory  Maximum Storage: 17kB
                                ->  Index Only Scan using ix_connections_member_b on connections c_1  (cost=0.42..29.01 rows=7 width=8) (actual time=0.003..0.006 rows=4.43 loops=14)
                                      Index Cond: (member_b = mc_1.f)
                                      Filter: (member_a <> 1023)
                                      Rows Removed by Filter: 1
                                      Heap Fetches: 76
                    ->  Hash  (cost=0.30..0.30 rows=15 width=4) (actual time=0.009..0.009 rows=14.00 loops=1)
                          Buckets: 1024  Batches: 1  Memory Usage: 9kB
                          ->  CTE Scan on my_conn m  (cost=0.00..0.30 rows=15 width=4) (actual time=0.000..0.007 rows=14.00 loops=1)
                                Storage: Memory  Maximum Storage: 17kB
Execution Time: 0.249 ms
```

### R22: 27.477 ms → 0.027 ms

**Before** (baseline plan, run 3)
```
Limit  (cost=19643.30..19643.36 rows=25 width=28) (actual time=26.609..26.611 rows=25.00 loops=1)
  ->  Sort  (cost=19393.30..19768.26 rows=149984 width=28) (actual time=21.909..24.870 rows=100025.00 loops=1)
        Sort Key: applied_at DESC
        Sort Method: external merge  Disk: 6176kB
        ->  Seq Scan on applications  (cost=0.00..2907.84 rows=149984 width=28) (actual time=0.004..6.863 rows=149984.00 loops=1)
Execution Time: 27.218 ms
```
**After** (optimized plan, run 3)
```
Limit  (cost=0.42..1.37 rows=25 width=28) (actual time=0.011..0.013 rows=25.00 loops=1)
  ->  Index Scan Backward using ix_applications_applied_at on applications  (cost=0.42..1900.99 rows=49981 width=28) (actual time=0.010..0.012 rows=25.00 loops=1)
        Index Cond: (applied_at < '2025-07-01 23:07:35+05:30'::timestamp with time zone)
Execution Time: 0.021 ms
```

### R17: 34.594 ms → 7.424 ms

**Before** (baseline plan, run 3)
```
Limit  (cost=13875.83..13875.87 rows=15 width=27) (actual time=34.122..34.124 rows=15.00 loops=1)
  ->  Sort  (cost=13875.83..13875.95 rows=50 width=27) (actual time=34.121..34.123 rows=15.00 loops=1)
        Sort Key: (count(*)) DESC
        Sort Method: quicksort  Memory: 26kB
        ->  GroupAggregate  (cost=13873.73..13874.60 rows=50 width=27) (actual time=34.091..34.116 rows=19.00 loops=1)
              Group Key: nxt.company_name
              ->  Sort  (cost=13873.73..13873.85 rows=50 width=19) (actual time=34.084..34.097 rows=558.00 loops=1)
                    Sort Key: nxt.company_name
                    Sort Method: quicksort  Memory: 25kB
                    ->  Nested Loop  (cost=10348.11..13872.32 rows=50 width=19) (actual time=13.378..34.037 rows=558.00 loops=1)
                          ->  Hash Join  (cost=10347.84..13857.45 rows=50 width=4) (actual time=13.373..33.798 rows=558.00 loops=1)
                                Hash Cond: (t.company_id = cur.company_id)
                                ->  Subquery Scan on t  (cost=10274.82..13522.85 rows=99440 width=8) (actual time=13.253..32.141 rows=59940.00 loops=1)
                                      Filter: (t.next_company_id <> t.company_id)
                                      Rows Removed by Filter: 40000
                                      ->  WindowAgg  (cost=10274.82..12273.60 rows=99940 width=16) (actual time=13.253..29.116 rows=99940.00 loops=1)
                                            Window: w1 AS (PARTITION BY p.member_id ORDER BY p.start_date)
                                            Storage: Memory  Maximum Storage: 17kB
                                            ->  Sort  (cost=10274.80..10524.65 rows=99940 width=12) (actual time=13.245..16.004 rows=99940.00 loops=1)
                                                  Sort Key: p.member_id, p.start_date
                                                  Sort Method: external merge  Disk: 2160kB
                                                  ->  Seq Scan on positions p  (cost=0.00..1975.40 rows=99940 width=12) (actual time=0.003..5.229 rows=99940.00 loops=1)
                                ->  Hash  (cost=73.00..73.00 rows=1 width=4) (actual time=0.076..0.076 rows=1.00 loops=1)
                                      Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                      ->  Seq Scan on companies cur  (cost=0.00..73.00 rows=1 width=4) (actual time=0.003..0.074 rows=1.00 loops=1)
                                            Filter: ((company_name)::text = 'TCS'::text)
                                            Rows Removed by Filter: 1999
                          ->  Index Scan using companies_pkey on companies nxt  (cost=0.28..0.30 rows=1 width=23) (actual time=0.000..0.000 rows=1.00 loops=558)
                                Index Cond: (company_id = t.next_company_id)
Execution Time: 34.599 ms
```
**After** (optimized plan, run 3)
```
Limit  (cost=2399.02..2399.02 rows=1 width=27) (actual time=7.143..7.144 rows=15.00 loops=1)
  CTE tcs
    ->  Index Scan using ix_companies_name on companies  (cost=0.28..8.29 rows=1 width=4) (actual time=0.004..0.004 rows=1.00 loops=1)
          Index Cond: ((company_name)::text = 'TCS'::text)
  ->  Sort  (cost=2390.72..2390.73 rows=1 width=27) (actual time=7.142..7.143 rows=15.00 loops=1)
        Sort Key: (count(*)) DESC
        Sort Method: quicksort  Memory: 26kB
        ->  GroupAggregate  (cost=2390.69..2390.71 rows=1 width=27) (actual time=7.115..7.138 rows=19.00 loops=1)
              Group Key: nxt.company_name
              ->  Sort  (cost=2390.69..2390.70 rows=1 width=19) (actual time=7.111..7.121 rows=558.00 loops=1)
                    Sort Key: nxt.company_name
                    Sort Method: quicksort  Memory: 25kB
                    ->  Nested Loop  (cost=2382.64..2390.68 rows=1 width=19) (actual time=6.385..7.073 rows=558.00 loops=1)
                          ->  Nested Loop  (cost=2382.37..2388.81 rows=1 width=4) (actual time=6.380..6.881 rows=558.00 loops=1)
                                Join Filter: (t.company_id = tcs.company_id)
                                Rows Removed by Join Filter: 1294
                                ->  CTE Scan on tcs  (cost=0.00..0.02 rows=1 width=4) (actual time=0.005..0.005 rows=1.00 loops=1)
                                      Storage: Memory  Maximum Storage: 17kB
                                ->  Subquery Scan on t  (cost=2382.37..2387.01 rows=142 width=8) (actual time=6.374..6.831 rows=1852.00 loops=1)
                                      Filter: (t.next_company_id <> t.company_id)
                                      Rows Removed by Filter: 928
                                      ->  WindowAgg  (cost=2382.37..2385.23 rows=143 width=16) (actual time=6.374..6.753 rows=2780.00 loops=1)
                                            Window: w1 AS (PARTITION BY p.member_id ORDER BY p.start_date)
                                            Storage: Memory  Maximum Storage: 17kB
                                            ->  Sort  (cost=2382.37..2382.72 rows=143 width=12) (actual time=6.370..6.416 rows=2780.00 loops=1)
                                                  Sort Key: p.member_id, p.start_date
                                                  Sort Method: quicksort  Memory: 183kB
                                                  ->  Nested Loop  (cost=2351.12..2377.25 rows=143 width=12) (actual time=5.031..6.147 rows=2780.00 loops=1)
                                                        ->  HashAggregate  (cost=2350.83..2351.33 rows=50 width=4) (actual time=5.027..5.060 rows=928.00 loops=1)
                                                              Group Key: p2.member_id
                                                              Batches: 1  Memory Usage: 113kB
                                                              ->  Hash Join  (cost=0.03..2350.71 rows=50 width=4) (actual time=0.017..4.926 rows=928.00 loops=1)
                                                                    Hash Cond: (p2.company_id = tcs_1.company_id)
                                                                    ->  Seq Scan on positions p2  (cost=0.00..1975.40 rows=99940 width=8) (actual time=0.003..2.682 rows=99940.00 loops=1)
                                                                    ->  Hash  (cost=0.02..0.02 rows=1 width=4) (actual time=0.002..0.002 rows=1.00 loops=1)
                                                                          Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                                                          ->  CTE Scan on tcs tcs_1  (cost=0.00..0.02 rows=1 width=4) (actual time=0.000..0.000 rows=1.00 loops=1)
                                                                                Storage: Memory  Maximum Storage: 17kB
                                                        ->  Index Scan using ix_positions_member_start on positions p  (cost=0.29..0.49 rows=3 width=12) (actual time=0.001..0.001 rows=3.00 loops=928)
                                                              Index Cond: (member_id = p2.member_id)
                          ->  Index Scan using companies_pkey on companies nxt  (cost=0.28..1.87 rows=1 width=23) (actual time=0.000..0.000 rows=1.00 loops=558)
                                Index Cond: (company_id = t.next_company_id)
Execution Time: 7.185 ms
```

## 5. Write overhead

Every index has to be updated when a row is written, so indexes can make writes slower. Three runs of a 0.4 ms query are noisy, so the table also shows the baseline re-run on the same server (before the indexes were added).

| Query | Baseline (ms) | Baseline re-run (ms) | After (ms) | Change vs re-run |
|-------|-------------:|--------------------:|-----------:|-----------------:|
| W01 Easy Apply (insert) | 0.350 | 0.396 | 0.469 | +0.073 ms (+18%), slower |
| W02 Accept invitation | 2.429 | 2.236 | 0.144 | much faster |
| W03 Store the connection | 2.487 | 2.329 | 0.333 | much faster |
| W04 Close expired jobs | 2.004 | 1.997 | 2.520 | +0.523 ms (+26%), slower |
| W05 Reject old applications | 2.630 | 2.561 | 2.030 | faster |

- **W01** inserts one application, and now also has to add an entry to the new `applications` indexes (`ix_applications_member`, `ix_applications_applied_at`). The cost is 0.07 ms per insert.
- **W04** updates 552 jobs and changes their `status`, which is a column of `ix_jobs_company_status`, so those 552 index entries have to be updated too. The cost is about 0.5 ms per nightly run.
- **Is it acceptable?** Yes. Both are well under a millisecond. W01 happens once per application and W04 once a night, while the reads these indexes speed up (R09, R19, R22 and others) are run far more often. The other three writes got faster because their `SELECT` part now finds rows through an index.

## 6. Index storage

Sizes from `pg_relation_size` after loading the seed data (MB).

| New index | On table | Index (MB) | Table (MB) |
|-----------|----------|-----------:|-----------:|
| ix_applications_applied_at | applications | 3.23 | 11.00 |
| ix_applications_hired (partial) | applications | 0.17 | 11.00 |
| ix_applications_member | applications | 4.53 | 11.00 |
| ix_companies_industry | companies | 0.03 | 0.38 |
| ix_companies_name | companies | 0.09 | 0.38 |
| ix_connections_member_b | connections | 4.73 | 9.75 |
| ix_invitations_pending_recipient (partial) | invitations | 0.11 | 5.50 |
| ix_invitations_sent_at | invitations | 1.30 | 5.50 |
| ix_jobs_company_status | jobs | 0.26 | 2.14 |
| ix_member_skills_skill_endorse | member_skills | 6.41 | 9.25 |
| ix_members_lower_email | members | 1.91 | 5.13 |
| ix_positions_current_company (partial) | positions | 0.29 | 7.63 |
| ix_positions_member_start | positions | 2.16 | 7.63 |
| ix_profile_views_viewed_at | profile_views | 6.04 | 9.88 |
| ix_profile_views_viewer | profile_views | 2.11 | 9.88 |
| **Total new indexes** | | **33.4** | |

For comparison, all 12 tables together are 63.3 MB and the 16 primary-key and unique indexes that already existed are 29.3 MB. The new indexes add about 53% of the table size. The partial indexes (`ix_applications_hired`, `ix_invitations_pending_recipient`, `ix_positions_current_company`) are tiny because they only store the few rows the queries need.

## 7. Queries we could not speed up, and why

| Query | Before → after (ms) | Why |
|-------|--------------------|-----|
| R07 | 4.872 → 4.647 (5%) | It counts, for every open job (1,778 of them), how many of the member's skills the job needs, so it has to read the skill rows of all open jobs (65,719 rows in `job_skills`). The plan still uses Seq Scans, and we found no index that the planner chose. At under 5 ms it is already fast. |
| R16 | 1.538 → 1.506 (2%) | It averages salaries over jobs posted in 2026, which is about a third of `jobs` (4,972 of 15,000). Reading the whole small table once takes only about 1.5 ms, and the query needs about a third of its rows anyway. |
| R15 | 8.956 → 7.676 (14%) | The rewrite removed `EXTRACT(YEAR …)` so the date filter is now a plain range, but the same third of `jobs` still has to be read and its skills counted. |
| R13 | 20.530 → 17.640 (14%) | It has to look at every member and every one of the 199,996 profile views to find who is missing. The real gain here is the correct answer (section 3). |
| R24 | 9.241 → 7.155 (23%) | About a third of the invitations were sent in 2026 (19,890 of 60,000) and each one is joined to its sender, so a lot of the work is needed whatever the index. |
| R25 | 34.157 → 23.555 (31%) | It compares every pair of consecutive positions of every member to find gaps, so it must read most of `positions`; the index mainly saves the sort. |
| R08 | 0.059 → 0.063 | Already an Index Scan on a unique index before any change. |

## 8. How to reproduce

```bash
createdb capstone
psql -d capstone -f sql/01_schema.sql
psql -d capstone -f sql/02_load_data.sql      # run from the folder that contains seed_data/
psql -d capstone -f sql/05_indexes.sql
./benchmarks/run_benchmark.sh capstone optimized 3 sql/06_optimized_queries.sql
```
