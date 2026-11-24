# 05 · Scalability report (Phase 5, large dataset)

Team T0016 · Section E

Next year the business expects **20× the volume**. This report checks whether our optimized database (Phase 4: `sql/05_indexes.sql` + `sql/06_optimized_queries.sql`) still meets its targets at that size, explains how each query's time grows, and designs the next step to **100×**: partitioning (`sql/08_partitioning.sql`, written and tested), sharding, replicas, caching and maintenance.

> **Numbers marked ⟪TANISHQ⟫ come from the large-data run** (`benchmarks/results/large/summary.csv`, 3 runs per query) and are filled in from that file. Everything else in this report was measured on the seed data with the commands in [§8](#8-how-to-reproduce).

---

## 1. Results on the large dataset

How the large run is done (README §5.1): new database → `sql/01_schema.sql` → `sql/02_load_data.sql` with `seed_data/` changed to `large_data/` → `sql/05_indexes.sql` → `ANALYZE` → `./benchmarks/run_benchmark.sh <db> large 3 sql/06_optimized_queries.sql`. The original 30 queries are **not** run on the large data.

"Expected growth" is our prediction from each query's **seed plan**, made before the large run (see §2 for the reasoning). The large column then shows whether the prediction held.

| Query | Group (target) | Seed (ms) | Large (ms) | Growth (large ÷ seed) | Expected growth (from the seed plan) | Meets target? | If not, what we changed |
|-------|----------------|----------:|-----------:|----------------------:|--------------------------------------|:-------------:|-------------------------|
| R01 | Real-time (< 5 ms) | 0.037 | ⟪TANISHQ⟫ | | ≈ same: index scans | | |
| R02 | Real-time (< 5 ms) | 0.030 | ⟪TANISHQ⟫ | | ≈ same: index scan | | |
| R03 | Real-time (< 5 ms) | 0.043 | ⟪TANISHQ⟫ | | ≈ same: index scan | | |
| R04 | Real-time (< 5 ms) | 0.064 | ⟪TANISHQ⟫ | | ≈ same: index-only scan | | |
| R05 | Search (< 250 ms) | 0.248 | ⟪TANISHQ⟫ | | ≈ same to a few ×: index-only, grows with one member's network | | |
| R06 | Search (< 250 ms) | 0.562 | ⟪TANISHQ⟫ | | a few ×: bitmap scan, grows with matching rows | | |
| R07 | Search (< 250 ms) | 4.647 | ⟪TANISHQ⟫ | | ≈ 20×: has a Seq Scan (≈ 93 ms projected, inside target) | | |
| R08 | Real-time (< 5 ms) | 0.063 | ⟪TANISHQ⟫ | | ≈ same: index scan | | |
| R09 | Real-time (< 5 ms) | 0.070 | ⟪TANISHQ⟫ | | a few ×: bitmap scan | | |
| R10 | Real-time (< 5 ms) | 0.031 | ⟪TANISHQ⟫ | | ≈ same: index scan | | |
| R11 | Real-time (< 5 ms) | 0.055 | ⟪TANISHQ⟫ | | ≈ same: index scan | | |
| R12 | Search (< 250 ms) | 0.196 | ⟪TANISHQ⟫ | | a few ×: bitmap scan | | |
| R13 | Search (< 250 ms) | 17.640 | ⟪TANISHQ⟫ | | **≈ 20×: Seq Scan of all profile_views → ≈ 350 ms projected, AT RISK** | | see §3 |
| R14 | Report (< 5 s) | 3.186 | ⟪TANISHQ⟫ | | ≈ 20×: Seq Scan | | |
| R15 | Report (< 5 s) | 7.676 | ⟪TANISHQ⟫ | | ≈ 20×: Seq Scan | | |
| R16 | Report (< 5 s) | 1.506 | ⟪TANISHQ⟫ | | ≈ 20×: Seq Scan | | |
| R17 | Report (< 5 s) | 7.424 | ⟪TANISHQ⟫ | | ≈ 20×: Seq Scan | | |
| R18 | Search (< 250 ms) | 2.867 | ⟪TANISHQ⟫ | | up to 20×: has a Seq Scan (≈ 57 ms projected) | | |
| R19 | Report (< 5 s) | 2.650 | ⟪TANISHQ⟫ | | up to 20× | | |
| R20 | Report (< 5 s) | 1.273 | ⟪TANISHQ⟫ | | ≈ 20×: full index-only scan | | |
| R21 | Report (< 5 s) | 31.345 | ⟪TANISHQ⟫ | | ≥ 20×: Seq Scan + big aggregate (≈ 630 ms projected; watch for sort spilling to disk) | | |
| R22 | Search (< 250 ms) | 0.027 | ⟪TANISHQ⟫ | | ≈ same: keyset pagination (see §1.1) | | |
| R23 | Real-time (< 5 ms) | 0.025 | ⟪TANISHQ⟫ | | ≈ same: index scan | | |
| R24 | Report (< 5 s) | 7.155 | ⟪TANISHQ⟫ | | ≈ 20×: Seq Scan | | |
| R25 | Report (< 5 s) | 23.555 | ⟪TANISHQ⟫ | | ≈ 20×: walks a whole index (≈ 470 ms projected) | | |
| W01 | Real-time (< 5 ms) | 0.469 | ⟪TANISHQ⟫ | | ≈ same: one insert, a few index updates (log n) | | |
| W02 | Real-time (< 5 ms) | 0.144 | ⟪TANISHQ⟫ | | ≈ same | | |
| W03 | Real-time (< 5 ms) | 0.333 | ⟪TANISHQ⟫ | | ≈ same | | |
| W04 | Batch (< 1 s) | 2.520 | ⟪TANISHQ⟫ | | ≈ 20×: Seq Scan (≈ 50 ms projected) | | |
| W05 | Search (< 250 ms) | 2.030 | ⟪TANISHQ⟫ | | a few ×: bitmap scan | | |

Seed times are the Phase 4 averages from `benchmarks/results/optimized/summary.csv`.

### 1.1 R22 on the large data

R22 is page 4,001 of "all applications, newest first". Phase 4 replaced `OFFSET 100000` with **keyset pagination**: the page starts right after the last `applied_at` the previous page showed (`WHERE applied_at < :last_seen ORDER BY applied_at DESC LIMIT 25`), which is one index lookup on `ix_applications_applied_at` instead of reading and throwing away 100,000 rows. For the benchmark the "last seen" value is the `applied_at` of the 100,000th newest application, read once from the large data, so the test returns the same 25 rows the `OFFSET` version would. In the app, the value comes from the last row of the page the user is looking at. Its time does not depend on how many pages came before, so it stays flat on any table size.

---

## 2. Growth analysis

When the data grows 20×, a query's time grows with **how much of the data it has to touch**, which the seed plan already shows:

### 2.1 Stays about the same: index lookups (R01–R04, R08, R10, R11, R22, R23, W01–W03)

These plans go straight to a few rows through a B-tree index. A B-tree's height grows with **log n**. We measured it on the seed data with `bt_metap()`: `members_pkey` has 2 levels, while `applications_pkey` and `ix_applications_applied_at` have 3. A B-tree page holds a few hundred keys, so 20× the rows adds at most one level, and each lookup still costs about the same 3–4 page reads. They return a fixed small number of rows (one member, one job, one page of 25), and that number does not grow with the table. **Expect growth ≈ 1×.** These are exactly the real-time, member-facing queries, which is why they have the strictest target (5 ms) and why that target is safe.

⟪TANISHQ⟫ confirm from the large column: all of these should still be well under 1 ms.

### 2.2 Grows a few times: lookups whose result grows (R05, R06, R09, R12, W05)

Still index-driven, but the number of rows they return grows with the data: one member's network (R05), the jobs matching a search (R06, R12), a company's applications (W05). At 20× there are more members and more rows per member, but not 20× more per member, so **expect 1–5×**.

### 2.3 Grows about 20×: queries that read a fixed share of a table (R07, R13–R21, R24, R25, W04)

These read every row (Seq Scan) or a fixed fraction of the table, such as "applications in June 2026" or "every company's totals". 20× the rows means 20× the pages, so **expect ≈ 20×**. On seed they take 1.3–31 ms, so 20× still fits the 5 s report target with a wide margin. The one exception is **R13**, which is in the 250 ms "search" group (§3).

### 2.4 Grows more than 20×: anything that stops fitting in memory

A plan whose sort or hash table fits in `work_mem` on seed data can spill to disk at 20×, and then it gets disproportionately slower. In `EXPLAIN (ANALYZE)` this shows as `Sort Method: external merge  Disk: …` or a hash with `Batches: > 1`. The candidates are the big aggregates **R21** and **R25**.

⟪TANISHQ⟫ check `benchmarks/results/large/R21.txt` and `R25.txt` for "external merge" or "Batches". If present, the fix is to raise `work_mem` for that report session (`SET work_mem = '64MB'`) or pre-compute it (§5.3).

---

## 3. What broke at scale (and the fix)

### R13: members who have never viewed a profile (target < 250 ms)

**Plan on seed (17.6 ms):** `Hash Right Anti Join`: a **Seq Scan of all 199,996 `profile_views`**, hashed against all 40,000 members. On the large data that is ≈ 4,000,000 views and ≈ 800,000 members, so ≈ 20× → **≈ 350 ms**, over the 250 ms target.

⟪TANISHQ⟫ the measured value. If it is under 250 ms, mark R13 as met and keep this section as "close to the limit".

The problem is the shape of the question: "who has *never* done X" has to rule out every row of X. Options, cheapest first:
1. **Index on `profile_views (viewer_id)`** so the anti join can read the index only (`Index Only Scan`, much narrower than the table) or run as a `Merge Anti Join` on two sorted inputs. Smaller pages to read, same answer.
2. **Keep the answer instead of recomputing it**: a `has_viewed_profile` flag on `members`, set by the view insert. R13 becomes `WHERE NOT has_viewed_profile`, an index scan that stays flat at any size. The cost is one extra update the first time a member views a profile.

Owner of the fix and before/after plans: ⟪DHRUV / AARABDH: add here if R13 misses on the large data⟫.

### Other queries over their target

⟪TANISHQ⟫ list any other query from §1 marked "no", with the plan line that explains it.

---

## 4. Storage

Measured with `pg_database_size`, `pg_table_size` and `pg_indexes_size` (commands in §8):

| | Seed data | Large data |
|---|---:|---:|
| Whole database | 134 MB | ⟪TANISHQ⟫ |
| All tables (heap) | 61.7 MB | ⟪TANISHQ⟫ |
| All indexes | 62.6 MB | ⟪TANISHQ⟫ |
| Index ÷ table | 1.01 | ⟪TANISHQ⟫ |
| `applications` (table + indexes) | 26 MB | ⟪TANISHQ⟫ |

On seed data **the indexes are as big as the tables**: Phase 4 added 16 indexes, and they are the price of the fast reads. At 20× both should grow about 20× (≈ 2.7 GB in total). That still fits in memory on a normal server, which is why the index lookups in §2.1 stay fast. At 100× (≈ 13 GB) the indexes of the biggest tables no longer fit comfortably, and that is the main argument for partitioning (§5.1).

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

**Is the database ready for next year (20×)?** Based on the seed plans, yes for almost everything:
- The member-facing queries are index lookups whose cost grows with log n, so they stay far under 5 ms.
- The reports grow about 20× and still land well inside 5 s.
- The real risk is **R13**, projected at ≈ 350 ms against a 250 ms target, and the fix is in §3.

⟪TANISHQ⟫ confirm with the large-data table in §1.

**Remaining risks:**
1. **Memory:** at 20× the indexes are ≈ 1.4 GB. If the server has less RAM than that, index lookups start reading from disk and the 5 ms queries are the first to feel it.
2. **Reports and writes share one server.** Until reports move to a replica (§5.3), a heavy report can slow the real-time queries.
3. **Write cost of our indexes:** 16 extra indexes mean every W01 updates more structures. Phase 4 measured this as small, but it grows with the number of indexes, not the data, so we should not keep adding them.
4. **Partitioning moves the uniqueness of (job, member) into a second table** that W01 must always use. Any code that inserts applications directly would bypass it.
5. **Second-degree network (R05)** is the one feature that gets much harder if we ever shard.

---

## 7. Files

| File | What it is |
|---|---|
| `sql/08_partitioning.sql` | Partitioned `applications` (monthly RANGE), the `application_keys` table, pruning plans, W01 on the partitioned table, archiving steps |
| `benchmarks/results/large/` | Plans and `summary.csv` of the optimized queries on the large data ⟪TANISHQ⟫ |
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
