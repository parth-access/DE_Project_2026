-- =====================================================================
-- sql/07_scale_fixes.sql   LinkedIn Professional Network database
-- Team T0016 · Section E · Phase 5: fixes for queries that missed their target
-- on the large dataset (see docs/05_scalability_report.md §3)
--
-- Run AFTER 05_indexes.sql:   psql -d <db> -f sql/07_scale_fixes.sql
-- =====================================================================

SET search_path TO linkedin;

-- ---------------------------------------------------------------------
-- R13: members who have never viewed anyone's profile (target < 250 ms)
--
-- Seed: 17.6 ms. Large: 918 ms (MISS). The plan reads ALL 4,000,000 profile views
-- (Parallel Seq Scan) and hashes them against all 800,000 members, spilling to
-- disk (Batches: 8). "Never did X" has to rule out every row of X, so this grows
-- with the whole profile_views table, which is the fastest-growing table.
--
-- Tried first:
--   * more work_mem (64MB): no spill any more, but still ≈ 900 ms. The cost is
--     reading 4M rows, not the hash.
--   * Merge Anti Join on members_pkey + ix_profile_views_viewer: 339 ms. Still
--     over the target, and it walks a 3M-entry index on every call.
--
-- Fix: keep the answer instead of recomputing it. A has_viewed_profile flag on
-- members, set the first time a member views a profile (trigger below), so R13
-- reads members only: ≈ 100 ms on the large data, and it no longer depends on
-- the size of profile_views at all. Same rows as before (130,313 members).
-- Cost: one extra UPDATE of members on a member's FIRST profile view only
-- (the trigger skips members whose flag is already true).
-- ---------------------------------------------------------------------

ALTER TABLE members ADD COLUMN IF NOT EXISTS has_viewed_profile BOOLEAN NOT NULL DEFAULT FALSE;

-- One-time fill from the views that already exist.
UPDATE members m
SET has_viewed_profile = TRUE
WHERE NOT m.has_viewed_profile
  AND EXISTS (SELECT 1 FROM profile_views v WHERE v.viewer_id = m.member_id);

-- Keep it true from now on. Private-mode views (viewer_id IS NULL) change nothing.
CREATE OR REPLACE FUNCTION mark_member_has_viewed() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.viewer_id IS NOT NULL THEN
        UPDATE members
        SET has_viewed_profile = TRUE
        WHERE member_id = NEW.viewer_id
          AND NOT has_viewed_profile;   -- only the first view writes
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_profile_views_mark_viewer ON profile_views;
CREATE TRIGGER trg_profile_views_mark_viewer
AFTER INSERT ON profile_views
FOR EACH ROW EXECUTE FUNCTION mark_member_has_viewed();

ANALYZE members;

-- R13, rewritten to read the flag:
--   SELECT member_id, first_name, last_name
--   FROM members
--   WHERE NOT has_viewed_profile;
--
-- No index on the flag on purpose: on the large data 130,313 of 800,000 members
-- (16 %) have never viewed anyone, so reading the table once (Seq Scan) is
-- cheaper than 130,000 index lookups. If that share drops below a few percent,
-- a partial index  CREATE INDEX ON members (member_id) WHERE NOT has_viewed_profile
-- becomes the better plan.
