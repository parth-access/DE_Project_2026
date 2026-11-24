# 05 · Scalability report (Phase 5, large dataset)

Team T0016 · Section E

Next year the business expects **20× the volume**. This report checks whether our optimized database (Phase 4: `sql/05_indexes.sql` + `sql/06_optimized_queries.sql`) still meets its targets at that size, explains how each query's time grows, and designs the next step to **100×**: partitioning (`sql/08_partitioning.sql`, written and tested), sharding, replicas, caching and maintenance.

**Result: 29 of 30 queries met their target on the large data as they were. The one that missed, R13 (918 ms against 250 ms), is fixed: it now takes 115 ms** (`sql/07_scale_fixes.sql`, §3).

How it was measured: Sir's `large_data.zip` (release `large-data`, ≈1 GB of CSVs) loaded with our own scripts, then `./benchmarks/run_benchmark.sh linkedin_large large 3 sql/06_optimized_queries.sql`. To make the growth numbers fair, the seed column below was measured **on the same machine and the same day** as the large column (PostgreSQL 16, 2 CPUs, 7 GB RAM, default settings: `work_mem` 4 MB, `shared_buffers` 128 MB). Phase 4's seed times were measured on a different machine, so they are not used for the ratios.

---

## 1. Results on the large dataset

How the large run is done (README §5.1): new database → `sql/01_schema.sql` → `sql/02_load_data.sql` with `seed_data/` changed to `large_data/` → `sql/05_indexes.sql` → `ANALYZE` → `./benchmarks/run_benchmark.sh <db> large 3 sql/06_optimized_queries.sql`. The original 30 queries are **not** run on the large data.

Seed and large: average of 3 runs, from `benchmarks/results/large/summary.csv` and the same script on the seed data.

| Query | Group (target) | Seed (ms) | Large (ms) | Growth | What it grew like | Met? | Notes |
|-------|----------------|----------:|-----------:|-------:|-------------------|:----:|-------|
| R01 | Real-time (< 5 ms) | 0.084 | 0.133 | 2× | ≈ same (index lookup) | ✅ |  |
| R02 | Real-time (< 5 ms) | 0.062 | 0.092 | 1× | ≈ same (index lookup) | ✅ |  |
| R03 | Real-time (< 5 ms) | 0.078 | 0.126 | 2× | ≈ same (index lookup) | ✅ |  |
| R04 | Real-time (< 5 ms) | 0.109 | 0.196 | 2× | ≈ same (index lookup) | ✅ |  |
| R05 | Search (< 250 ms) | 0.367 | 1.813 | 5× | a few × (result grows) | ✅ |  |
| R06 | Search (< 250 ms) | 1.405 | 79.385 | 57× | more than 20× | ✅ | `ILIKE '%…%'` cannot use a B-tree, so it scans all 300k jobs (§2.4) |
| R07 | Search (< 250 ms) | 11.031 | 150.234 | 14× | ≈ 20× (reads a share of a table) | ✅ |  |
| R08 | Real-time (< 5 ms) | 0.121 | 0.135 | 1× | ≈ same (index lookup) | ✅ |  |
| R09 | Real-time (< 5 ms) | 0.163 | 0.167 | 1× | ≈ same (index lookup) | ✅ |  |
| R10 | Real-time (< 5 ms) | 0.058 | 0.061 | 1× | ≈ same (index lookup) | ✅ |  |
| R11 | Real-time (< 5 ms) | 0.121 | 0.193 | 2× | ≈ same (index lookup) | ✅ |  |
| R12 | Search (< 250 ms) | 0.324 | 2.202 | 7× | a few × (result grows) | ✅ |  |
| R13 | Search (< 250 ms) | 23.671 | 917.660 | 39× | more than 20× | ❌ → fixed | **fixed: 918 → 115 ms** (§3) |
| R14 | Report (< 5 s) | 8.340 | 209.403 | 25× | ≈ 20× (reads a share of a table) | ✅ |  |
| R15 | Report (< 5 s) | 17.019 | 217.953 | 13× | ≈ 20× (reads a share of a table) | ✅ |  |
| R16 | Report (< 5 s) | 2.987 | 35.174 | 12× | ≈ 20× (reads a share of a table) | ✅ |  |
| R17 | Report (< 5 s) | 18.754 | 322.585 | 17× | ≈ 20× (reads a share of a table) | ✅ |  |
| R18 | Search (< 250 ms) | 4.792 | 74.409 | 16× | ≈ 20× (reads a share of a table) | ✅ |  |
| R19 | Report (< 5 s) | 6.064 | 437.803 | 72× | more than 20× | ✅ | cold disk reads + small hash spill (§2.4) |
| R20 | Report (< 5 s) | 2.347 | 48.459 | 21× | ≈ 20× (reads a share of a table) | ✅ |  |
| R21 | Report (< 5 s) | 26.510 | 664.451 | 25× | ≈ 20× (reads a share of a table) | ✅ |  |
| R22 | Search (< 250 ms) | 0.235 | 0.083 | 0.4× | ≈ same (index lookup) | ✅ |  |
| R23 | Real-time (< 5 ms) | 0.053 | 0.122 | 2× | ≈ same (index lookup) | ✅ |  |
| R24 | Report (< 5 s) | 20.294 | 369.052 | 18× | ≈ 20× (reads a share of a table) | ✅ |  |
| R25 | Report (< 5 s) | 54.923 | 1133.258 | 21× | ≈ 20× (reads a share of a table) | ✅ |  |
| W01 | Real-time (< 5 ms) | 1.038 | 1.041 | 1× | ≈ same (index lookup) | ✅ |  |
| W02 | Real-time (< 5 ms) | 0.251 | 0.381 | 2× | ≈ same (index lookup) | ✅ |  |
| W03 | Real-time (< 5 ms) | 0.595 | 0.667 | 1× | ≈ same (index lookup) | ✅ |  |
| W04 | Batch (< 1 s) | 5.850 | 146.253 | 25× | ≈ 20× (reads a share of a table) | ✅ |  |
| W05 | Search (< 250 ms) | 4.544 | 36.555 | 8× | a few × (result grows) | ✅ |  |

Raw plans of every run: `benchmarks/results/large/<ID>.txt`.

### 1.1 R22 on the large data

R22 is "page 4,001 of all applications, newest first". Phase 4 replaced `OFFSET 100000` with **keyset pagination**: the page starts right after the `applied_at` the previous page ended on (`WHERE applied_at < :last_seen ORDER BY applied_at DESC LIMIT 25`). That is one lookup on `ix_applications_applied_at` instead of reading and throwing away 100,000 rows. The value in `06_optimized_queries.sql` is the `applied_at` of row 100,000 **in the seed data**. On the large data the same value is a page much deeper into the 3 million rows, and it still takes **0.08 ms**, because keyset pagination costs the same however deep the page is. With `OFFSET` the cost grows with the page number. In the app, the value comes from the last row of the page the user is looking at.

---

## 2. Growth analysis

The data grew 20× (40,000 → 800,000 members; 150,000 → 3,000,000 applications; 200,000 → 4,000,000 profile views). A query's time grew with **how much of the data it has to touch**, and the seed plans predicted every group correctly:

### 2.1 Stayed about the same (≈ 1–2×): index lookups
**R01–R04, R08–R11, R22, R23, W01–W03.** All still **under 0.7 ms** on the large data.

These plans go straight to a few rows through a B-tree index, and a B-tree's height grows with **log n**. We measured it with `bt_metap()`: `members_pkey` went from 2 levels on seed to 3 on large, and `applications_pkey`, `ix_applications_applied_at` and `ix_profile_views_viewer` stay at 3 levels. 20× the rows added at most one level, so a lookup still costs about 3 page reads. These queries return a fixed small number of rows (one member, one job, one page of 25), and that does not grow with the tables. This is why the strict 5 ms target for member-facing queries is safe. R22 (keyset pagination, §1.1) is a good example: page 4,001 takes 0.08 ms on 3 million applications.

### 2.2 Grew a few times (5–8×): lookups whose result grows
**R05 (5×), R12 (7×), W05 (8×).**

Still index-driven, but the number of rows they return grows with the data: one member's second-degree network (R05), a member's applications (R12), a company's applications (W05). There are more rows per member and per company at 20×, but not 20× more. All finish in under 40 ms.

### 2.3 Grew about as much as the data (12–25×): reading a share of a table
**R07, R14–R18, R20, R21, R24, R25, W04.**

These read every row (Seq Scan) or a fixed share of a table, such as all hires, all June applications or every company's totals. 20× the rows means about 20× the pages to read. The slowest is **R25 at 1.13 s**, still well inside the 5 s report target, and the batch job **W04 takes 146 ms** against 1 s. None of them spilled to disk: R21 and R25, which we expected to be at risk, sort in memory (`Sort Method: quicksort` / `top-N heapsort`).

### 2.4 Grew faster than the data (39–72×)
**R06 (57×), R13 (39×), R19 (72×).** Three different reasons:
- **R06: job search with `title ILIKE '%data analyst%'` (79 ms, target 250 ms).** On seed the matching jobs were few enough to find quickly. On large the plan is a `Parallel Seq Scan on jobs` over all 300,000 jobs, because a pattern that **starts with `%`** cannot use a B-tree index. It is still inside the target. If job search grows further, the fix is a trigram index (`CREATE EXTENSION pg_trgm; CREATE INDEX … USING gin (title gin_trgm_ops)`), which can serve `ILIKE '%…%'`.
- **R13: never viewed a profile (918 ms, target 250 ms). The one miss.** Its hash of 800,000 members no longer fits in `work_mem` and spills to disk (`Batches: 8`, `temp written`). Fixed in §3.
- **R19: IT-services employer report (438 ms, target 5 s).** Part of the time is cold disk reads (the first read of `companies` alone took 234 ms) and a small hash spill (`temp read=521 written=521`). It is well inside its target.

**The clearest "breaks at scale" example is not in our optimized set at all.** The load script `sql/02_load_data.sql` ends with a check that still runs the **original R13 (`NOT IN`)**. On the seed data it finishes in milliseconds. On the large data it was still running after **15 minutes**, and we cancelled it. With 4 million viewer ids, `NOT IN` cannot keep them in a hash table, so PostgreSQL compares every member against the whole list. This is why the README says not to run the original 30 queries on the large data, and why the Phase 4 rewrite to `NOT EXISTS` mattered for speed as well as for the wrong answer.

---

## 3. What broke at scale (and the fix)

### R13: members who have never viewed a profile (target < 250 ms): **918 ms → 115 ms**

**Before** (`benchmarks/results/large/R13.txt`, run 3: 936 ms). The anti join reads all 4 million profile views and hashes all 800,000 members, spilling to disk:
```
Gather (actual time=596.601..915.449 rows=130313 loops=1)
  Workers Launched: 2
  Buffers: shared hit=11717 read=25199, temp read=11908 written=11972
  ->  Parallel Hash Right Anti Join (actual rows=43438 loops=3)
        Hash Cond: (v.viewer_id = m.member_id)
        ->  Parallel Seq Scan on profile_views v (actual rows=1333331 loops=3)
        ->  Parallel Hash (actual rows=266667 loops=3)
              Buckets: 262144  Batches: 8  Memory Usage: 7072kB
              ->  Parallel Seq Scan on members m (actual rows=266667 loops=3)
Execution Time: 935.813 ms
```

"Who has *never* done X" has to rule out every row of X, so this grows with `profile_views`, the fastest-growing table. What we tried, measured on the large data:

| Attempt | Plan | Time | Met? |
|---|---|---:|:---:|
| As written (`NOT EXISTS`) | Parallel Hash Anti Join, spills (`Batches: 8`) | 773–936 ms | ❌ |
| `SET work_mem = '64MB'` | same plan, no spill (`Batches: 1`) | 909–929 ms | ❌ |
| Merge Anti Join on `members_pkey` + `ix_profile_views_viewer` (after `VACUUM`) | walks a 3M-entry index | 339 ms | ❌ |
| **Stored flag** `members.has_viewed_profile` | Seq Scan on `members` only | **110–122 ms** | ✅ |

More memory removes the spill but not the cost, which is reading 4 million rows. The fix is to **keep the answer instead of recomputing it**: a `has_viewed_profile` column on `members`, filled once, and kept true by a trigger on `profile_views` that runs on a member's **first** view only. Private-mode views have `viewer_id IS NULL` and change nothing. The full fix is in `sql/07_scale_fixes.sql`. R13 becomes:
```sql
SELECT member_id, first_name, last_name FROM members WHERE NOT has_viewed_profile;
```

**After** (large data, after `VACUUM (ANALYZE) members`; 3 runs: 122.2, 110.4, 113.4 ms):
```
Seq Scan on members (actual time=0.020..117.043 rows=130313 loops=1)
  Filter: (NOT has_viewed_profile)
  Rows Removed by Filter: 669687
  Buffers: shared hit=11101 read=22886
Execution Time: 122.223 ms
```

**Same answer:** the flag gives 130,313 members, the same count as the `NOT EXISTS` query. **Trigger checked:** inserting a view by a member who had never viewed anyone flips their flag to true (inside a transaction that was rolled back). R13 no longer depends on the size of `profile_views` at all.

We did not index the flag. 16 % of members have never viewed anyone, so reading `members` once is cheaper than 130,000 index lookups. If that share drops below a few percent, a partial index (`WHERE NOT has_viewed_profile`) becomes the better plan.

### Other queries over their target
None. The other 29 met their targets as they were (§1).

---

## 4. Storage

Measured with `pg_database_size`, `pg_table_size` and `pg_indexes_size` (commands in §8):

| | Seed data | Large data | Growth |
|---|---:|---:|---:|
| Whole database | 134 MB | 2,454 MB | 18× |
| All tables (heap) | 61.9 MB | 1,202.9 MB | 19× |
| All indexes | 62.6 MB | 1,243.1 MB | 20× |
| Index ÷ table | 1.01 | 1.03 | |
| `applications` (table + indexes) | 26.1 MB | 520.8 MB | 20× |

**The indexes are as big as the tables**, on both datasets. That is the price of the fast reads from Phase 4's 15 indexes, and it grew exactly with the data. The large database (2.4 GB) still fits in a normal server's memory, which is why the index lookups in §2.1 stayed fast even on a 7 GB machine. At 100× it would be ≈ 12 GB, of which ≈ 6 GB is indexes, and the biggest tables' indexes no longer fit comfortably. That is the main argument for partitioning (§5.1): each month's index is small and only recent months need to stay in memory.

---

## 5. Architecture for 100×

At 100× the platform has ≈ 15,000,000 applications, ≈ 20,000,000 profile views and ≈ 4,000,000 members.

### 5.1 Partitioning: `applications`, by RANGE on `applied_at`, one partition per month

Written and tested in **`sql/08_partitioning.sql`** (it builds `applications_p` next to the real table, copies the rows and shows the plans below).

**Why this table:** it is the largest and fastest-growing table, every row has a time, and the heavy queries ask for a time window: the June 2026 reports (R14–R17, R24) and the "older than 60 days" batch job (W04).

**Why RANGE by month:**
- **Pruning:** a June report opens one month instead of the whole table.
- **Archiving:** removing an old month is `DETACH PARTITION`, which is instant, instead of a multi-million-row `DELETE` followed by a long `VACUUM`.
- **Hot data stays small:** new applications always go into the newest partition.
- **Partition size:** a month is ≈ 8,300 rows on seed, ≈ 170,000 at 20× and ≈ 830,000 at 100×. Each partition's indexes stay small enough for memory.

We did not choose HASH(`member_id`): it spreads rows evenly but gives no pruning for date reports and no cheap archiving, which is what this table needs most. We also did not choose daily partitions, because queries without a date filter must probe every partition (see the last plan below), so more partitions would make them slower.

**The primary-key rule.** On a partitioned table every PRIMARY KEY and UNIQUE constraint **must include the partition key**. So:
- `PRIMARY KEY (application_id)` becomes `PRIMARY KEY (application_id, applied_at)`.
- `UNIQUE (job_id, member_id)` cannot be enforced across partitions any more. W01 depends on it, through `ON CONFLICT (job_id, member_id)`, to stop a member applying twice to the same job. We keep the guarantee with a small non-partitioned table, `application_keys (job_id, member_id) PRIMARY KEY`. W01 first claims the pair there with `ON CONFLICT DO NOTHING`, and only inserts the application if the claim succeeded, all in one statement (step 6 of the script).

**Partition pruning, measured on the seed data** (from running `sql/08_partitioning.sql`). There are 28 partitions: 19 months with data, the next months ahead, and a DEFAULT partition.

June 2026 in UTC months: **1 of 28 partitions read**.
```
Aggregate (actual rows=1 loops=1)
  ->  Seq Scan on applications_2026_06 applications_p (actual rows=8178 loops=1)
        Filter: ((applied_at >= '2026-06-01 00:00:00+00') AND (applied_at < '2026-07-01 00:00:00+00'))
```

June 2026 in India time (what our reports use): **2 partitions**. 1 June 00:00 IST is 31 May 18:30 UTC, so the last 5½ hours of May are included.
```
Aggregate (actual rows=1 loops=1)
  ->  Append (actual rows=8241 loops=1)
        ->  Index Only Scan using applications_2026_05_applied_at_idx on applications_2026_05 (actual rows=63 loops=1)
        ->  Seq Scan on applications_2026_06 (actual rows=8178 loops=1)
```

W04-style batch filter (`applied_at < now() - interval '60 days'`): `now()` is only known when the query runs, so pruning happens **at execution time**. The plan reports `Subplans Removed: 5`, which are the newest months.

No date filter ("My Jobs" for one member): **no pruning**. The plan probes the member index of every partition. Each probe is cheap, but this is the cost of partitioning by time, and why we keep partitions monthly rather than daily.

**Running it:** a monthly job creates the next months' partitions in advance (or the `pg_partman` extension does it). The DEFAULT partition catches any row with an unexpected date, and a non-empty default partition is the alert that the job did not run.

### 5.2 Sharding: by member? What happens to connections?

Sharding by `member_id` puts each member's profile, positions, skills, applications and the views they made on one shard. Member-facing queries (R01–R04, R08–R11, W01–W03) then hit **one shard**, which is what the strict 5 ms target needs.

**The problem is connections.** A connection links two members who may live on different shards.
- **R03 (a member's connections):** we would store each connection **twice**, once under each member (`(a, b)` on a's shard and `(b, a)` on b's shard). R03 then reads one shard. The cost is double storage for connections and writing two shards when people connect. That write is rare, and the read happens on every profile visit.
- **R05 (second-degree network, people you may know):** this needs a member's connections and then *their* connections, which are spread over many shards. It becomes a **scatter-gather** query: ask every shard that holds a first-degree connection, then merge. That makes it the slowest member-facing query. We would precompute "people you may know" in a background job and serve it from a cache, rather than run it live.

**Cross-shard queries:** the platform-wide reports (R14–R21, R24, R25) read everything by nature. We would not run them on the shards: they belong on a **separate analytics copy** (a read replica of each shard, or a nightly load into a warehouse) where a few seconds is fine. The same goes for anything that joins jobs from all companies to applicants from all shards.

**Our conclusion:** at 100× we do **not** need sharding yet. ≈ 15 GB with partitioning, replicas and caching fits one primary server. Sharding adds the cross-shard costs above for every feature, so it should come only when one machine can no longer take the **write** load.

### 5.3 Read replicas and caching

| Send to | Queries | Why |
|---|---|---|
| **Primary** (must be up to date) | W01–W05; R10, R11 and any read right after a write (the member's own "My Jobs" after applying) | Writes must go to the primary. A member who just applied must see the application immediately, and a replica can be a moment behind. |
| **Read replica** | R01–R09, R12, R13, R18, R22, R23 | Profile pages, search and lists. A delay of a second or two is invisible to the user, and this is most of the read traffic. |
| **Replica + cache / summary tables** | R14–R17, R19–R21, R24, R25 | Reports and analytics. Run them on a replica so a 1–5 s report never slows a member's request on the primary. Their answers change slowly, so we would keep them in **summary tables refreshed every few minutes** (a materialized view, `REFRESH MATERIALIZED VIEW CONCURRENTLY`) and serve them from the cache. |
| **Precomputed** | R05 (people you may know), R13 (members who never viewed a profile) | Expensive to compute live (§3, §5.2), cheap to recompute in the background. |

### 5.4 Maintenance

- **Autovacuum on `applications`:** status changes (W04 updates thousands of rows at once) leave dead rows behind. The default trigger (20 % of the table changed) means waiting for ≈ 3,000,000 dead rows at 100× before cleaning. Per table we would set:
  `ALTER TABLE applications SET (autovacuum_vacuum_scale_factor = 0.02, autovacuum_analyze_scale_factor = 0.01);`
  so cleaning and fresh statistics start at 2 % / 1 %. With monthly partitions this applies to each partition separately, so only the busy recent months get vacuumed, not the whole history.
- **Statistics:** run `ANALYZE` after every bulk load. Most bad plans on new data come from missing statistics, not missing indexes.
- **Archiving:** keep 18–24 months online. Older months are **detached** (`DETACH PARTITION … CONCURRENTLY`), dumped to cold storage and dropped, and their `application_keys` rows are removed with them.
- **Summary tables:** refresh the report views (§5.3) every few minutes with `REFRESH MATERIALIZED VIEW CONCURRENTLY`, so readers are never blocked.
- **Watching:** `pg_stat_statements` for queries that start to slow down, and an alert on a non-empty DEFAULT partition.

---

## 6. Conclusion

**Is the database ready for next year (20×)? Yes, with one fix.** We loaded the real large dataset (20× the seed) and ran all 30 optimized queries 3 times each:
- **29 of 30 met their targets as written.** Every member-facing query is still under 0.7 ms (target 5 ms), the slowest report takes 1.1 s (target 5 s), and the batch job takes 146 ms (target 1 s).
- **R13 missed** (918 ms against 250 ms), as the seed plan had warned. It is fixed with a stored flag and a trigger, and now takes **115 ms**.
- The growth matched what the seed plans predicted: index lookups stayed flat (log n), table reads grew about 20×, and the three queries that grew faster did so for reasons we can see in their plans (§2.4).

**Remaining risks:**
1. **Memory:** at 20× the indexes are 1.24 GB (measured). If the server has less RAM than that, index lookups start reading from disk and the 5 ms queries are the first to feel it.
2. **Reports and writes share one server.** Until reports move to a replica (§5.3), a heavy report can slow the real-time queries.
3. **Write cost of our indexes:** 15 extra indexes, plus the R13 trigger, mean every W01 updates more structures. Phase 4 measured this as small, but it grows with the number of indexes, not the data, so we should not keep adding them.
4. **Partitioning moves the uniqueness of (job, member) into a second table** that W01 must always use. Any code that inserts applications directly would bypass it.
5. **Second-degree network (R05)** is the one feature that gets much harder if we ever shard.

---

## 7. Files

| File | What it is |
|---|---|
| `sql/08_partitioning.sql` | Partitioned `applications` (monthly RANGE), the `application_keys` table, pruning plans, W01 on the partitioned table, archiving steps |
| `sql/07_scale_fixes.sql` | The R13 fix: `has_viewed_profile` flag, one-time fill and trigger |
| `benchmarks/results/large/` | Plans and `summary.csv` of the optimized queries on the large data (3 runs each) |
| this file | Results, growth analysis, fixes, storage, architecture |

## 8. How to reproduce

```bash
# large data (README §5.1)
createdb linkedin_large
psql -d linkedin_large -f sql/01_schema.sql
sed 's#seed_data/#large_data/#g' sql/02_load_data.sql > /tmp/load_large.sql
psql -d linkedin_large -f /tmp/load_large.sql
psql -d linkedin_large -f sql/05_indexes.sql
psql -d linkedin_large -c "ANALYZE;"
./benchmarks/run_benchmark.sh linkedin_large large 3 sql/06_optimized_queries.sql

# R13 fix (then VACUUM, because the one-time fill rewrites most of members)
psql -d linkedin_large -f sql/07_scale_fixes.sql
psql -d linkedin_large -c "VACUUM (ANALYZE) linkedin.members;"

# partitioning (on seed or large)
psql -d <db> -f sql/08_partitioning.sql

# storage numbers
psql -d <db> -c "SELECT pg_size_pretty(pg_database_size(current_database()));"
psql -d <db> -c "SELECT relname, pg_size_pretty(pg_table_size(oid)) AS table_size,
                        pg_size_pretty(pg_indexes_size(oid)) AS index_size
                 FROM pg_class
                 WHERE relkind = 'r' AND relnamespace = 'linkedin'::regnamespace
                 ORDER BY pg_total_relation_size(oid) DESC;"
```
