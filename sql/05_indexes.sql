-- =====================================================================
-- sql/05_indexes.sql  (Phase 4, CP3): indexes added after the baseline
-- Owner: Dhruv Maan
--
-- The schema (sql/01_schema.sql) only has the indexes PostgreSQL builds for
-- PRIMARY KEY and UNIQUE constraints. The baseline (docs/03_baseline_timings.md)
-- showed full-table Seq Scans in the slow queries. Each index below names the
-- query it is for and the reason. Every index also slows writes a little
-- (W01-W05), so we only keep indexes that the plans actually use.
--
-- Run after 01_schema.sql and 02_load_data.sql:
--   psql -d <db> -f sql/05_indexes.sql
-- Safe to re-run (IF NOT EXISTS).
-- =====================================================================

SET search_path TO linkedin;

-- ---------------------------------------------------------------------
-- connections
-- ---------------------------------------------------------------------
-- R03, R04, R05: "connections of member X" is
--   WHERE member_a = X OR member_b = X.
-- The primary key (member_a, member_b) serves only the member_a half;
-- the member_b half was a Seq Scan. This index serves the other half,
-- so the planner can combine two index scans (BitmapOr).
CREATE INDEX IF NOT EXISTS ix_connections_member_b
    ON connections (member_b, member_a);

-- ---------------------------------------------------------------------
-- positions
-- ---------------------------------------------------------------------
-- R01, R02: one member's positions (Seq Scan on positions in the baseline).
-- R17, R25: window functions PARTITION BY member_id ORDER BY start_date.
-- Leading with member_id finds a member's rows; start_date gives the order
-- the window needs, so no separate sort.
CREATE INDEX IF NOT EXISTS ix_positions_member_start
    ON positions (member_id, start_date);

-- R12: current employees of one company (end_date IS NULL).
-- Partial index: only current positions are stored, so it is small.
CREATE INDEX IF NOT EXISTS ix_positions_current_company
    ON positions (company_id)
    WHERE end_date IS NULL;

-- ---------------------------------------------------------------------
-- companies
-- ---------------------------------------------------------------------
-- R12 ('Flipkart'), R17 ('TCS'): company looked up by name.
CREATE INDEX IF NOT EXISTS ix_companies_name
    ON companies (company_name);

-- R19: all companies of one industry ('IT Services').
CREATE INDEX IF NOT EXISTS ix_companies_industry
    ON companies (industry);

-- ---------------------------------------------------------------------
-- jobs
-- ---------------------------------------------------------------------
-- R19 (slowest query, about 220 ms): for every IT Services company it
-- counts open jobs and joins its jobs to applications. Both subqueries
-- look up jobs by company_id, which was a Seq Scan on jobs per company.
-- R14 also joins jobs to companies on company_id.
CREATE INDEX IF NOT EXISTS ix_jobs_company_status
    ON jobs (company_id, status);

-- ---------------------------------------------------------------------
-- applications
-- ---------------------------------------------------------------------
-- R09: one member's applications. The UNIQUE (job_id, member_id) index
-- leads with job_id, so it cannot find rows by member_id.
CREATE INDEX IF NOT EXISTS ix_applications_member
    ON applications (member_id, applied_at DESC);

-- R22: newest applications first (ORDER BY applied_at DESC ... LIMIT).
-- R19, R20: applications in a date range (R20 after the rewrite in
-- 06_optimized_queries.sql, which compares applied_at to a plain range
-- instead of applied_at::date, so this index can be used).
CREATE INDEX IF NOT EXISTS ix_applications_applied_at
    ON applications (applied_at);

-- R14: only HIRED applications, filtered by status_updated_at.
-- Partial index: hires are a small share of all applications.
CREATE INDEX IF NOT EXISTS ix_applications_hired
    ON applications (status_updated_at)
    WHERE status = 'HIRED';

-- ---------------------------------------------------------------------
-- member_skills
-- ---------------------------------------------------------------------
-- R21 (about 85 ms): top-endorsed member per skill,
--   ROW_NUMBER() OVER (PARTITION BY skill_id ORDER BY endorsements DESC, member_id).
-- The index stores rows in exactly that order, so the window needs no sort.
-- R18: members with one skill ('SQL'), ordered by endorsements DESC.
-- The primary key (member_id, skill_id) leads with member_id, so it
-- cannot find rows by skill.
CREATE INDEX IF NOT EXISTS ix_member_skills_skill_endorse
    ON member_skills (skill_id, endorsements DESC, member_id);

-- ---------------------------------------------------------------------
-- profile_views
-- ---------------------------------------------------------------------
-- R13: members who never viewed a profile. Used by the NOT EXISTS
-- rewrite in 06_optimized_queries.sql (anti-join on viewer_id).
CREATE INDEX IF NOT EXISTS ix_profile_views_viewer
    ON profile_views (viewer_id);

-- R11: views of one member since a date.
CREATE INDEX IF NOT EXISTS ix_profile_views_viewed_at
    ON profile_views (viewed_id, viewed_at);

-- ---------------------------------------------------------------------
-- invitations
-- ---------------------------------------------------------------------
-- R10: pending invitations received by one member, newest first.
-- Partial: only PENDING rows are ever shown in that tab.
CREATE INDEX IF NOT EXISTS ix_invitations_pending_recipient
    ON invitations (recipient_id, sent_at DESC)
    WHERE status = 'PENDING';

-- R24: invitations sent in 2026 (sent_at >= '2026-01-01').
CREATE INDEX IF NOT EXISTS ix_invitations_sent_at
    ON invitations (sent_at);

-- ---------------------------------------------------------------------
-- members
-- ---------------------------------------------------------------------
-- R23: sign-in by email ignoring case: WHERE lower(email) = '...'.
-- The UNIQUE (email) index cannot be used because the query compares
-- lower(email), not email. An expression index on lower(email) can.
CREATE INDEX IF NOT EXISTS ix_members_lower_email
    ON members (lower(email));

-- Refresh planner statistics so the new indexes are considered.
ANALYZE;
