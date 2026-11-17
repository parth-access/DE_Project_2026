-- =====================================================================
-- sql/06_optimized_queries.sql  (Phase 4, CP3): optimized versions of the workload
-- Owner: Aarabdh Sharma
--
-- Same 30 queries as queries/workload_30.sql, same "-- @R01" markers, so it runs
-- through the same benchmark script:
--   ./benchmarks/run_benchmark.sh <db> optimized 3 sql/06_optimized_queries.sql
-- Run it AFTER sql/05_indexes.sql (Dhruv) is applied: several rewrites exist so
-- that those indexes can be used.
--
-- Queries marked "CHANGE" were rewritten; each says what changed and why.
-- Every rewrite was checked to return the same rows, in the same order, as the
-- original on the seed data, except R13, where the original was WRONG (0 rows,
-- NOT IN with NULLs) and the rewrite returns the correct 6,513 members.
-- Queries marked "UNCHANGED" are copied as they are: the indexes alone fix
-- them, or they were already fast.
-- =====================================================================
SET search_path TO linkedin;
BEGIN;

-- @R01
-- Profile header: member 1023 with their current position and company
-- UNCHANGED.
SELECT m.member_id, m.first_name, m.last_name, m.headline, p.title, c.company_name
FROM members m
LEFT JOIN positions p ON p.member_id = m.member_id AND p.end_date IS NULL
LEFT JOIN companies c ON c.company_id = p.company_id
WHERE m.member_id = 1023;

-- @R02
-- Experience section: member 1023's positions, latest first
-- UNCHANGED.
SELECT p.title, c.company_name, p.employment_type, p.start_date, p.end_date
FROM positions p
JOIN companies c ON c.company_id = p.company_id
WHERE p.member_id = 1023
ORDER BY p.start_date DESC;

-- @R03
-- "My Network": everyone connected to member 1023
-- CHANGE: the OR on two different columns becomes UNION ALL of two lookups.
-- WHY: "member_a = 1023" uses the primary key, "member_b = 1023" uses
-- ix_connections_member_b (05_indexes.sql); each branch is a plain index scan.
-- A pair is stored once (member_a < member_b), so the two branches never overlap
-- and UNION ALL (no duplicate removal) is safe.
SELECT member_b AS connection_id, connected_at FROM connections WHERE member_a = 1023
UNION ALL
SELECT member_a AS connection_id, connected_at FROM connections WHERE member_b = 1023
ORDER BY connected_at DESC;

-- @R04
-- Profile page: mutual connections of member 1023 and member 356
-- CHANGE: each member's friend list is built with UNION ALL of two index lookups
-- (as in R03) instead of OR + CASE, then intersected.
-- WHY: the original OR forced a Seq Scan on connections; each branch now uses an index.
WITH a AS (
    SELECT member_b AS friend FROM connections WHERE member_a = 1023
    UNION ALL
    SELECT member_a FROM connections WHERE member_b = 1023
), b AS (
    SELECT member_b AS friend FROM connections WHERE member_a = 356
    UNION ALL
    SELECT member_a FROM connections WHERE member_b = 356
)
SELECT a.friend FROM a JOIN b ON b.friend = a.friend;

-- @R05
-- "People you may know": 2nd-degree connections of member 1023 ranked by mutual connections
-- CHANGE: (1) my friends are found with UNION ALL of two index lookups;
-- (2) their friends are found the same way, instead of joining on
--     "c.member_a = f OR c.member_b = f" (which cannot use one index);
-- (3) "NOT IN (SELECT f FROM my_conn)" becomes NOT EXISTS.
-- WHY: every step is now an index lookup; NOT EXISTS is a plain anti-join and
-- is also safe if a NULL ever appears (NOT IN returns nothing in that case).
WITH my_conn AS (
    SELECT member_b AS f FROM connections WHERE member_a = 1023
    UNION ALL
    SELECT member_a FROM connections WHERE member_b = 1023
), second AS (
    SELECT c.member_b AS suggestion FROM my_conn mc JOIN connections c ON c.member_a = mc.f
    UNION ALL
    SELECT c.member_a FROM my_conn mc JOIN connections c ON c.member_b = mc.f
)
SELECT s.suggestion, count(*) AS mutuals
FROM second s
WHERE s.suggestion <> 1023
  AND NOT EXISTS (SELECT 1 FROM my_conn m WHERE m.f = s.suggestion)
GROUP BY s.suggestion
ORDER BY mutuals DESC, s.suggestion
LIMIT 20;

-- @R06
-- Job search: open "data analyst" jobs in Bengaluru or remote, posted in the last 30 days of June 2026
-- UNCHANGED.
SELECT j.job_id, j.title, c.company_name, j.workplace_type, j.min_salary_lpa, j.max_salary_lpa, j.posted_at
FROM jobs j
JOIN companies c ON c.company_id = j.company_id
WHERE j.status = 'OPEN'
  AND j.title ILIKE '%data analyst%'
  AND (j.city_id = 1 OR j.workplace_type = 'REMOTE')
  AND j.posted_at >= '2026-06-01'
ORDER BY j.posted_at DESC;

-- @R07
-- "Jobs for you": open jobs that need at least 2 of member 1023's skills
-- UNCHANGED.
SELECT js.job_id, count(*) AS matching_skills
FROM job_skills js
JOIN member_skills ms ON ms.skill_id = js.skill_id AND ms.member_id = 1023
JOIN jobs j           ON j.job_id = js.job_id AND j.status = 'OPEN'
GROUP BY js.job_id
HAVING count(*) >= 2
ORDER BY matching_skills DESC, js.job_id DESC
LIMIT 25;

-- @R08
-- Recruiter: applicants of job 14075 by pipeline stage
-- UNCHANGED.
SELECT a.status, count(*) AS applicants
FROM applications a
WHERE a.job_id = 14075
GROUP BY a.status
ORDER BY applicants DESC;

-- @R09
-- "My Jobs": member 1023's applications with their status
-- UNCHANGED.
SELECT a.application_id, j.title, c.company_name, a.status, a.applied_at
FROM applications a
JOIN jobs j      ON j.job_id = a.job_id
JOIN companies c ON c.company_id = j.company_id
WHERE a.member_id = 1023
ORDER BY a.applied_at DESC;

-- @R10
-- Invitations tab: pending invitations received by member 1023
-- UNCHANGED.
SELECT i.invitation_id, i.sender_id, m.first_name, m.last_name, i.note, i.sent_at
FROM invitations i
JOIN members m ON m.member_id = i.sender_id
WHERE i.recipient_id = 1023 AND i.status = 'PENDING'
ORDER BY i.sent_at DESC;

-- @R11
-- "Who viewed your profile": viewers of member 217 since April 2026 (private-mode viewers counted separately)
-- UNCHANGED.
SELECT coalesce(v.viewer_id::text, 'Someone in private mode') AS viewer, count(*) AS views, max(v.viewed_at) AS last_view
FROM profile_views v
WHERE v.viewed_id = 217
  AND v.viewed_at >= '2026-04-01'
GROUP BY 1
ORDER BY last_view DESC;

-- @R12
-- Company page: current employees of Flipkart and their average tenure in years
-- UNCHANGED.
SELECT c.company_name, count(*) AS current_employees,
       round(avg((DATE '2026-07-01' - p.start_date) / 365.25), 1) AS avg_tenure_years
FROM positions p
JOIN companies c ON c.company_id = p.company_id
WHERE c.company_name = 'Flipkart' AND p.end_date IS NULL
GROUP BY c.company_name;

-- @R13
-- Engagement: members who have never viewed anyone's profile (for a re-engagement nudge)
-- CHANGE: NOT IN (subquery) becomes NOT EXISTS.
-- WHY (correctness first): profile_views.viewer_id is NULL for private-mode views.
-- "x NOT IN (..., NULL, ...)" is never TRUE in SQL, so the original query returned
-- 0 rows. NOT EXISTS ignores NULLs and returns the members who really never viewed
-- anyone. It is also faster: an anti-join that can use ix_profile_views_viewer.
SELECT m.member_id, m.first_name, m.last_name
FROM members m
WHERE NOT EXISTS (SELECT 1 FROM profile_views v WHERE v.viewer_id = m.member_id);

-- @R14
-- Talent insights: average days from application to hire, per company (2026 hires)
-- UNCHANGED.
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

-- @R15
-- Skill demand: skills most requested by jobs posted in 2026
-- CHANGE: EXTRACT(YEAR FROM posted_at) = 2026 becomes a plain range on posted_at.
-- WHY: a function around the column hides it from any index and from the
-- planner's statistics; a range is "sargable" and estimated correctly.
-- Same rows: posted_at in [2026-01-01, 2027-01-01) in India time.
SELECT s.skill_name, count(*) AS jobs
FROM job_skills js
JOIN skills s ON s.skill_id = js.skill_id
JOIN jobs j   ON j.job_id = js.job_id
WHERE j.posted_at >= TIMESTAMPTZ '2026-01-01 00:00:00+05:30'
  AND j.posted_at <  TIMESTAMPTZ '2027-01-01 00:00:00+05:30'
GROUP BY s.skill_name
ORDER BY jobs DESC
LIMIT 20;

-- @R16
-- Salary insights: average advertised salary range per job title and city (2026 postings with salaries)
-- UNCHANGED.
SELECT j.title, coalesce(ct.city_name, 'Remote') AS city, count(*) AS postings,
       round(avg(j.min_salary_lpa), 1) AS avg_min_lpa, round(avg(j.max_salary_lpa), 1) AS avg_max_lpa
FROM jobs j
LEFT JOIN cities ct ON ct.city_id = j.city_id
WHERE j.min_salary_lpa IS NOT NULL AND j.posted_at >= '2026-01-01'
GROUP BY j.title, coalesce(ct.city_name, 'Remote')
ORDER BY j.title, avg_max_lpa DESC NULLS LAST;

-- @R17
-- Talent flow: companies people joined right after leaving TCS
-- CHANGE: only members who ever worked at TCS go through the window function.
-- WHY: the original ran lead() over every position of every member, then threw
-- almost all of it away. Filtering members first (EXISTS on a TCS position)
-- means the window only sorts a small set of rows, read in order from
-- ix_positions_member_start.
WITH tcs AS (SELECT company_id FROM companies WHERE company_name = 'TCS'),
t AS (
    SELECT p.member_id, p.company_id,
           lead(p.company_id) OVER (PARTITION BY p.member_id ORDER BY p.start_date) AS next_company_id
    FROM positions p
    WHERE EXISTS (SELECT 1 FROM positions p2 JOIN tcs ON tcs.company_id = p2.company_id
                  WHERE p2.member_id = p.member_id)
)
SELECT nxt.company_name, count(*) AS moved
FROM t
JOIN tcs ON tcs.company_id = t.company_id
JOIN companies nxt ON nxt.company_id = t.next_company_id
WHERE t.next_company_id <> t.company_id
GROUP BY nxt.company_name
ORDER BY moved DESC
LIMIT 15;

-- @R18
-- Recruiter search: open-to-work Bengaluru members with SQL skill, most endorsed first
-- UNCHANGED.
SELECT m.member_id, m.first_name, m.last_name, m.headline, ms.endorsements
FROM members m
JOIN member_skills ms ON ms.member_id = m.member_id
JOIN skills s         ON s.skill_id = ms.skill_id AND s.skill_name = 'SQL'
WHERE m.open_to_work AND m.city_id = 1
ORDER BY ms.endorsements DESC
LIMIT 50;

-- @R19
-- Employer report: open jobs and June 2026 applications of every IT Services company
-- CHANGE: the two correlated subqueries (run once per company) become two
-- grouped joins computed once, then joined to the companies.
-- WHY: the original re-scanned jobs and applications for every IT Services
-- company (the slowest query in the baseline). Now each table is read once,
-- and the June filter on applied_at can use ix_applications_applied_at.
WITH it AS (
    SELECT company_id, company_name FROM companies WHERE industry = 'IT Services'
), open_jobs AS (
    SELECT j.company_id, count(*) AS n
    FROM jobs j JOIN it ON it.company_id = j.company_id
    WHERE j.status = 'OPEN'
    GROUP BY j.company_id
), june_apps AS (
    SELECT j.company_id, count(*) AS n
    FROM applications a
    JOIN jobs j ON j.job_id = a.job_id
    JOIN it ON it.company_id = j.company_id
    WHERE a.applied_at >= '2026-06-01'
    GROUP BY j.company_id
)
SELECT it.company_id, it.company_name,
       coalesce(o.n, 0) AS open_jobs,
       coalesce(ja.n, 0) AS june_applications
FROM it
LEFT JOIN open_jobs o  ON o.company_id = it.company_id
LEFT JOIN june_apps ja ON ja.company_id = it.company_id
ORDER BY june_applications DESC;

-- @R20
-- Platform analytics: applications per day and running total, June 2026
-- CHANGE: "applied_at::date BETWEEN '2026-06-01' AND '2026-06-30'" becomes a
-- half-open range on applied_at itself.
-- WHY: casting the column to date hides it from ix_applications_applied_at.
-- Same rows: in India time, June 1 00:00 up to (not including) July 1 00:00.
SELECT day, apps, sum(apps) OVER (ORDER BY day) AS running_total
FROM (
    SELECT applied_at::date AS day, count(*) AS apps
    FROM applications
    WHERE applied_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
      AND applied_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
    GROUP BY 1
) d
ORDER BY day;

-- @R21
-- Skills pages: the most-endorsed member for each skill
-- CHANGE: ROW_NUMBER() ... WHERE rn = 1 becomes DISTINCT ON (skill_id).
-- WHY: DISTINCT ON keeps the first row per skill in the given order, which is
-- exactly the order of ix_member_skills_skill_endorse (skill_id, endorsements
-- DESC, member_id), so it reads the index in order with no sort and no
-- numbering of every row. Same tie-break: highest endorsements, then lowest member_id.
SELECT s.skill_name, t.member_id, t.endorsements
FROM (
    SELECT DISTINCT ON (ms.skill_id) ms.skill_id, ms.member_id, ms.endorsements
    FROM member_skills ms
    ORDER BY ms.skill_id, ms.endorsements DESC, ms.member_id
) t
JOIN skills s ON s.skill_id = t.skill_id
ORDER BY t.endorsements DESC;

-- @R22
-- Trust & safety console: all applications, newest first, page 4,001 (25 per page)
-- CHANGE: OFFSET pagination becomes keyset ("seek") pagination.
-- WHY: OFFSET 100000 reads and throws away 100,000 rows to show 25. Keyset
-- remembers where the previous page ended (the applied_at of its last row)
-- and starts right after it, using ix_applications_applied_at.
-- The literal below is the applied_at of row 100,000 in this dataset, so this
-- returns exactly the same 25 rows (no two applications share an applied_at).
-- In the app, the value comes from the last row of the previous page.
SELECT application_id, job_id, member_id, status, applied_at
FROM applications
WHERE applied_at < TIMESTAMPTZ '2025-07-01 23:07:35+05:30'
ORDER BY applied_at DESC
LIMIT 25;

-- @R23
-- Sign-in: find the member by email, ignoring case
-- UNCHANGED.
SELECT member_id, first_name, last_name, is_premium
FROM members
WHERE lower(email) = 'yash.sharma1023@gmail.com';

-- @R24
-- Growth: invitation acceptance rate of Premium vs free senders (2026)
-- CHANGE: none to the logic; the date literal is made an explicit India-time
-- timestamp so the result does not depend on the session time zone.
-- WHY: with ix_invitations_sent_at the 2026 filter is an index range scan.
SELECT m.is_premium, count(*) AS invitations,
       round(100.0 * count(*) FILTER (WHERE i.status = 'ACCEPTED') / count(*), 1) AS accept_pct
FROM invitations i
JOIN members m ON m.member_id = i.sender_id
WHERE i.sent_at >= TIMESTAMPTZ '2026-01-01 00:00:00+05:30'
GROUP BY m.is_premium;

-- @R25
-- Career insights: members with a career break of more than 6 months between two positions
-- UNCHANGED.
SELECT member_id, prev_end, start_date, start_date - prev_end AS gap_days
FROM (
    SELECT member_id, start_date,
           lag(end_date) OVER (PARTITION BY member_id ORDER BY start_date) AS prev_end
    FROM positions
) t
WHERE start_date - prev_end > 182
ORDER BY gap_days DESC, member_id
LIMIT 100;

-- @W01
-- "Easy Apply": member 1023 applies to job 14075
-- UNCHANGED.
INSERT INTO applications (application_id, job_id, member_id, applied_at, easy_apply, status, status_updated_at)
VALUES (90000001, 14075, 1023, '2026-07-01 09:00:00+05:30', TRUE, 'APPLIED', '2026-07-01 09:00:00+05:30')
ON CONFLICT (job_id, member_id) DO NOTHING;

-- @W02
-- Member 1023 accepts their oldest pending invitation
-- UNCHANGED.
UPDATE invitations
SET status = 'ACCEPTED', responded_at = '2026-07-01 09:10:00+05:30'
WHERE invitation_id = (SELECT min(invitation_id) FROM invitations WHERE recipient_id = 1023 AND status = 'PENDING');

-- @W03
-- …and the new connection is stored once, smaller member id first
-- UNCHANGED.
INSERT INTO connections (member_a, member_b, connected_at)
SELECT least(sender_id, recipient_id), greatest(sender_id, recipient_id), '2026-07-01 09:10:00+05:30'
FROM invitations
WHERE invitation_id = (SELECT min(invitation_id) FROM invitations WHERE recipient_id = 1023 AND status = 'PENDING')
ON CONFLICT DO NOTHING;

-- @W04
-- Nightly job: close every job whose closing date has passed
-- UNCHANGED.
UPDATE jobs
SET status = 'CLOSED'
WHERE status = 'OPEN' AND closes_at < '2026-07-01 00:00:00+05:30';

-- @W05
-- Recruiter clean-up: reject applications to TCS jobs still unreviewed after 60 days
-- UNCHANGED.
UPDATE applications a
SET status = 'REJECTED', status_updated_at = '2026-07-01 10:00:00+05:30'
FROM jobs j
JOIN companies c ON c.company_id = j.company_id
WHERE a.job_id = j.job_id
  AND c.company_name = 'TCS'
  AND a.status = 'APPLIED'
  AND a.applied_at < TIMESTAMPTZ '2026-07-01 00:00:00+05:30' - interval '60 days';

-- @END
ROLLBACK;
