-- =====================================================================
-- sql/08_partitioning.sql   LinkedIn Professional Network database
-- Team T0016 · Section E · Phase 5: partitioning `applications` for 100× data
--
-- Run AFTER 01_schema.sql, the data load and 05_indexes.sql:
--     psql -d <db> -f sql/08_partitioning.sql
--
-- It builds `applications_p`, a partitioned copy of `applications`, next to the
-- original (the original is not touched, so every other script keeps working),
-- copies the rows, and ends with EXPLAIN plans that show partition pruning.
-- The swap that would make it the real table is at the bottom, commented out.
--
-- WHICH TABLE: applications. It is the biggest and fastest-growing table
-- (≈150k rows on seed, ≈3M on the large data, ≈15M at 100×), every row has a
-- time (applied_at), and the heavy reports (R14, R15, R16, R17, R24) and the
-- batch job W04 all ask for a window of time ("June 2026", "older than 60 days").
--
-- WHICH COLUMN AND METHOD: RANGE on applied_at, one partition per month.
--   * Time-window queries read only the months they ask for (pruning).
--   * Old months can be archived by DETACH PARTITION: instant, no huge DELETE,
--     no table-wide VACUUM afterwards.
--   * New rows always land in the newest partition, so its pages stay hot in cache.
--   * Month size: seed ≈ 8,300 rows, large ≈ 170,000, 100× ≈ 830,000. That keeps
--     each partition's indexes small enough to stay in memory.
--   Not HASH(member_id): it spreads one member's rows evenly but gives no pruning
--   for the date reports and no cheap archiving, which is what this table needs.
--
-- THE PRIMARY-KEY RULE: on a partitioned table every PRIMARY KEY or UNIQUE
-- constraint must include the partition key column. So:
--   * PRIMARY KEY (application_id)        becomes PRIMARY KEY (application_id, applied_at)
--   * UNIQUE (job_id, member_id)          cannot be enforced across partitions any more.
-- That second one matters: W01 relies on ON CONFLICT (job_id, member_id) to stop a
-- member applying twice to the same job. We keep that guarantee with a small
-- non-partitioned table `application_keys (job_id, member_id)` that owns the
-- uniqueness; W01 claims the key there first (see the W01 version below).
-- =====================================================================

SET search_path TO linkedin;
\timing on

-- ---------------------------------------------------------------------
-- 1. The partitioned table (same columns and checks as `applications`)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS applications_p CASCADE;
DROP TABLE IF EXISTS application_keys;

CREATE TABLE applications_p (
    application_id    INTEGER     NOT NULL,
    job_id            INTEGER     NOT NULL,
    member_id         INTEGER     NOT NULL,
    applied_at        TIMESTAMPTZ NOT NULL,
    easy_apply        BOOLEAN     NOT NULL DEFAULT FALSE,
    status            VARCHAR(12) NOT NULL DEFAULT 'APPLIED',
    status_updated_at TIMESTAMPTZ NOT NULL,
    -- the partition key (applied_at) must be part of the primary key
    CONSTRAINT pk_applications_p PRIMARY KEY (application_id, applied_at),
    CONSTRAINT fk_applications_p_job    FOREIGN KEY (job_id)    REFERENCES jobs (job_id)       ON DELETE CASCADE,
    CONSTRAINT fk_applications_p_member FOREIGN KEY (member_id) REFERENCES members (member_id) ON DELETE CASCADE,
    CONSTRAINT chk_applications_p_status CHECK (status IN ('APPLIED','VIEWED','SHORTLISTED','INTERVIEW',
                                                           'OFFER','HIRED','REJECTED','WITHDRAWN')),
    CONSTRAINT chk_applications_p_dates  CHECK (status_updated_at >= applied_at)
) PARTITION BY RANGE (applied_at);

-- One partition per month, from the oldest application to 3 months ahead,
-- so new applications (W01 uses now()) always have a home.
-- Boundaries are in UTC: a month runs from 00:00 UTC on the 1st to 00:00 UTC
-- on the 1st of the next month (lower bound included, upper bound excluded).
DO $$
DECLARE
    first_month date := date_trunc('month', (SELECT min(applied_at) FROM applications) AT TIME ZONE 'UTC');
    last_month  date := date_trunc('month', greatest((SELECT max(applied_at) FROM applications), now()) AT TIME ZONE 'UTC')
                        + interval '3 months';
    m date := first_month;
BEGIN
    WHILE m <= last_month LOOP
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF applications_p
               FOR VALUES FROM (%L) TO (%L)',
            'applications_' || to_char(m, 'YYYY_MM'),
            (m::timestamp AT TIME ZONE 'UTC'),
            ((m + interval '1 month')::timestamp AT TIME ZONE 'UTC'));
        m := m + interval '1 month';
    END LOOP;
END $$;

-- Safety net: a row outside every month (a bad clock, a far-future date) still
-- inserts instead of failing. A monthly job should create partitions ahead of
-- time so this stays empty; a non-empty default partition is the alert.
CREATE TABLE applications_default PARTITION OF applications_p DEFAULT;

-- ---------------------------------------------------------------------
-- 2. Uniqueness of (job_id, member_id) across all partitions
-- ---------------------------------------------------------------------
CREATE TABLE application_keys (
    job_id    INTEGER NOT NULL,
    member_id INTEGER NOT NULL,
    CONSTRAINT pk_application_keys PRIMARY KEY (job_id, member_id)
);

-- ---------------------------------------------------------------------
-- 3. Copy the data
-- ---------------------------------------------------------------------
INSERT INTO applications_p
SELECT application_id, job_id, member_id, applied_at, easy_apply, status, status_updated_at
FROM applications;

INSERT INTO application_keys (job_id, member_id)
SELECT job_id, member_id FROM applications;

-- ---------------------------------------------------------------------
-- 4. Indexes. Created on the parent, PostgreSQL creates them on every
--    partition (and on every partition added later). Same as 05_indexes.sql.
-- ---------------------------------------------------------------------
CREATE INDEX ix_applications_p_member     ON applications_p (member_id, applied_at DESC);
CREATE INDEX ix_applications_p_job        ON applications_p (job_id);
CREATE INDEX ix_applications_p_applied_at ON applications_p (applied_at);
CREATE INDEX ix_applications_p_hired      ON applications_p (job_id) WHERE status = 'HIRED';

ANALYZE applications_p;
ANALYZE application_keys;

-- How the rows spread over the partitions
SELECT tableoid::regclass AS partition, count(*) AS rows
FROM applications_p
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------
-- 5. Partition pruning
-- ---------------------------------------------------------------------

-- 5a. June 2026 report (the filter R14/R15 use). The plan scans ONLY
--     applications_2026_06; every other month is never opened.
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT count(*)
FROM applications_p
WHERE applied_at >= '2026-06-01 00:00+05:30'
  AND applied_at <  '2026-07-01 00:00+05:30';
-- India time: 1 June 00:00 IST is 31 May 18:30 UTC, so this window touches the
-- last hours of the May partition as well. Two partitions, not nineteen.

-- 5b. The same report in UTC months lines up with exactly one partition.
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT count(*)
FROM applications_p
WHERE applied_at >= '2026-06-01 00:00+00'
  AND applied_at <  '2026-07-01 00:00+00';

-- 5c. W04-style batch filter ("applied more than 60 days ago"): prunes the
--     newest months, which are the busiest ones.
EXPLAIN (COSTS OFF)
SELECT count(*)
FROM applications_p
WHERE applied_at < now() - interval '60 days'
  AND status = 'APPLIED';

-- 5d. No time filter, so NO pruning: "My Jobs" for one member (R-style lookup)
--     has to look in every partition. It stays fast because each partition's
--     member index is small, but it is the cost of partitioning by time: lookups
--     by member, job or id now touch every month. That is why we would not
--     go to daily partitions: more partitions = more index probes here.
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT application_id, job_id, status
FROM applications_p
WHERE member_id = 1023
ORDER BY applied_at DESC;

-- ---------------------------------------------------------------------
-- 6. W01 (apply to a job) on the partitioned table
--    The key is claimed in application_keys first; only if that worked is the
--    application inserted. Both in one transaction, so a failure leaves neither.
-- ---------------------------------------------------------------------
BEGIN;
WITH claimed AS (
    INSERT INTO application_keys (job_id, member_id)
    VALUES (512, 1023)
    ON CONFLICT DO NOTHING
    RETURNING job_id, member_id
)
INSERT INTO applications_p (application_id, job_id, member_id, applied_at, easy_apply, status, status_updated_at)
SELECT (SELECT max(application_id) + 1 FROM applications_p), job_id, member_id, now(), true, 'APPLIED', now()
FROM claimed
RETURNING application_id, tableoid::regclass AS landed_in;
ROLLBACK;  -- demo only

-- ---------------------------------------------------------------------
-- 7. Archiving a month (runs in milliseconds, no DELETE, no VACUUM):
--      ALTER TABLE applications_p DETACH PARTITION applications_2025_01 CONCURRENTLY;
--      -- then dump it to cold storage and DROP TABLE applications_2025_01;
--    and its keys: DELETE FROM application_keys k USING applications_2025_01 a
--                  WHERE k.job_id = a.job_id AND k.member_id = a.member_id;
--
-- 8. Making it the real table (in a maintenance window):
--      BEGIN;
--      ALTER TABLE applications   RENAME TO applications_old;
--      ALTER TABLE applications_p RENAME TO applications;
--      COMMIT;
--    then point W01 at the version in step 6, and add next month's partition
--    every month (a cron job, or the pg_partman extension).
-- ---------------------------------------------------------------------
