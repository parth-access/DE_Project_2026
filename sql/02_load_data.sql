-- =====================================================================
-- sql/02_load_data.sql   Load the 12 seed CSV files into the linkedin schema
--
-- Run from the PROJECT ROOT (the folder that contains seed_data/), after 01_schema.sql:
--     unzip seed_data.zip                     # creates seed_data/ (never commit the CSVs)
--     psql -d <db> -f sql/01_schema.sql
--     psql -d <db> -f sql/02_load_data.sql
-- For the large dataset only the folder name changes (seed_data -> large_data).
--
-- Order: parents before children so every foreign key is satisfied.
-- =====================================================================
SET search_path TO linkedin;

\copy cities        FROM 'seed_data/cities.csv'        WITH (FORMAT csv, HEADER true)
\copy members       FROM 'seed_data/members.csv'       WITH (FORMAT csv, HEADER true)
\copy companies     FROM 'seed_data/companies.csv'     WITH (FORMAT csv, HEADER true)
\copy positions     FROM 'seed_data/positions.csv'     WITH (FORMAT csv, HEADER true)
\copy skills        FROM 'seed_data/skills.csv'        WITH (FORMAT csv, HEADER true)
\copy member_skills FROM 'seed_data/member_skills.csv' WITH (FORMAT csv, HEADER true)
\copy connections   FROM 'seed_data/connections.csv'   WITH (FORMAT csv, HEADER true)
\copy invitations   FROM 'seed_data/invitations.csv'   WITH (FORMAT csv, HEADER true)
\copy jobs          FROM 'seed_data/jobs.csv'          WITH (FORMAT csv, HEADER true)
\copy job_skills    FROM 'seed_data/job_skills.csv'    WITH (FORMAT csv, HEADER true)
\copy applications  FROM 'seed_data/applications.csv'  WITH (FORMAT csv, HEADER true)
\copy profile_views FROM 'seed_data/profile_views.csv' WITH (FORMAT csv, HEADER true)

ANALYZE;

-- =====================================================================
-- VERIFICATION 1: row counts must match the project brief
-- =====================================================================
SELECT t.table_name, t.loaded, t.expected,
       CASE WHEN t.loaded = t.expected THEN 'OK' ELSE 'MISMATCH' END AS result
FROM (
    SELECT 'cities'        AS table_name, (SELECT count(*) FROM cities)        AS loaded,        10 AS expected UNION ALL
    SELECT 'members',                     (SELECT count(*) FROM members),                    40000 UNION ALL
    SELECT 'companies',                   (SELECT count(*) FROM companies),                   2000 UNION ALL
    SELECT 'positions',                   (SELECT count(*) FROM positions),                  99940 UNION ALL
    SELECT 'skills',                      (SELECT count(*) FROM skills),                        72 UNION ALL
    SELECT 'member_skills',               (SELECT count(*) FROM member_skills),             212417 UNION ALL
    SELECT 'connections',                 (SELECT count(*) FROM connections),               219966 UNION ALL
    SELECT 'invitations',                 (SELECT count(*) FROM invitations),                60000 UNION ALL
    SELECT 'jobs',                        (SELECT count(*) FROM jobs),                       15000 UNION ALL
    SELECT 'job_skills',                  (SELECT count(*) FROM job_skills),                 65719 UNION ALL
    SELECT 'applications',                (SELECT count(*) FROM applications),              149984 UNION ALL
    SELECT 'profile_views',               (SELECT count(*) FROM profile_views),             199996
) t;

-- =====================================================================
-- VERIFICATION 2: integrity checks the constraints cannot express.
-- violations = 0 means the rule holds. A non-zero count is a DATA PROBLEM
-- that is documented in docs/02_schema_design.md (the data is kept as it is).
-- =====================================================================
SELECT check_name, violations FROM (
    -- rules that hold ------------------------------------------------
    SELECT 1 AS n, 'A1 member has two overlapping positions (pairs)' AS check_name,
           (SELECT count(*) FROM positions a JOIN positions b
              ON a.member_id = b.member_id AND a.position_id < b.position_id
             AND a.start_date < COALESCE(b.end_date, DATE '9999-12-31')
             AND b.start_date < COALESCE(a.end_date, DATE '9999-12-31')) AS violations
    UNION ALL
    SELECT 2, 'A2 member has more than one current position',
           (SELECT count(*) FROM (SELECT member_id FROM positions WHERE end_date IS NULL
                                  GROUP BY member_id HAVING count(*) > 1) x)
    UNION ALL
    SELECT 3, 'A3 application sent before the job was posted',
           (SELECT count(*) FROM applications a JOIN jobs j USING (job_id) WHERE a.applied_at < j.posted_at)
    UNION ALL
    SELECT 4, 'A4 job that requires no skill at all',
           (SELECT count(*) FROM jobs j WHERE NOT EXISTS (SELECT 1 FROM job_skills s WHERE s.job_id = j.job_id))
    UNION ALL
    -- rules the data breaks (data problems) -------------------------
    SELECT 5, 'B1 application sent after the job closes_at',
           (SELECT count(*) FROM applications a JOIN jobs j USING (job_id) WHERE a.applied_at > j.closes_at)
    UNION ALL
    SELECT 6, 'B2 ACCEPTED invitation with no row in connections',
           (SELECT count(*) FROM invitations i WHERE i.status = 'ACCEPTED'
              AND NOT EXISTS (SELECT 1 FROM connections c
                               WHERE c.member_a = least(i.sender_id, i.recipient_id)
                                 AND c.member_b = greatest(i.sender_id, i.recipient_id)))
    UNION ALL
    SELECT 7, 'B3 connection with no ACCEPTED invitation',
           (SELECT count(*) FROM connections c WHERE NOT EXISTS (
                SELECT 1 FROM invitations i WHERE i.status = 'ACCEPTED'
                   AND least(i.sender_id, i.recipient_id) = c.member_a
                   AND greatest(i.sender_id, i.recipient_id) = c.member_b))
    UNION ALL
    SELECT 8, 'B4 pair of members invited more than once (unordered pairs)',
           (SELECT count(*) FROM (SELECT 1 FROM invitations
                                  GROUP BY least(sender_id, recipient_id), greatest(sender_id, recipient_id)
                                  HAVING count(*) > 1) x)
    UNION ALL
    SELECT 9, 'B5 OPEN job whose closes_at is before 2026-07-01 (W04 targets)',
           (SELECT count(*) FROM jobs WHERE status = 'OPEN' AND closes_at < TIMESTAMPTZ '2026-07-01 00:00:00+05:30')
    UNION ALL
    SELECT 10, 'B6 CLOSED job whose closes_at is on/after 2026-07-01',
           (SELECT count(*) FROM jobs WHERE status = 'CLOSED' AND closes_at >= TIMESTAMPTZ '2026-07-01 00:00:00+05:30')
    UNION ALL
    SELECT 11, 'B7 invitation sent before the sender joined',
           (SELECT count(*) FROM invitations i JOIN members m ON m.member_id = i.sender_id WHERE i.sent_at < m.created_at)
    UNION ALL
    SELECT 12, 'B8 application sent before the member joined',
           (SELECT count(*) FROM applications a JOIN members m USING (member_id) WHERE a.applied_at < m.created_at)
    UNION ALL
    SELECT 13, 'B9 profile viewed before the viewed member joined',
           (SELECT count(*) FROM profile_views v JOIN members m ON m.member_id = v.viewed_id WHERE v.viewed_at < m.created_at)
    UNION ALL
    SELECT 14, 'B10 connection made before either member joined',
           (SELECT count(*) FROM connections c JOIN members a ON a.member_id = c.member_a
              JOIN members b ON b.member_id = c.member_b
             WHERE c.connected_at < greatest(a.created_at, b.created_at))
    UNION ALL
    SELECT 15, 'B11 position started before the company was founded (year)',
           (SELECT count(*) FROM positions p JOIN companies c USING (company_id)
             WHERE extract(year FROM p.start_date) < c.founded_year)
) r ORDER BY n;

-- =====================================================================
-- VERIFICATION 3: facts used in the design document
-- =====================================================================
SELECT 'profile views with no viewer (private mode)'  AS fact, count(*) AS value FROM profile_views WHERE viewer_id IS NULL
UNION ALL SELECT 'members who never viewed anyone (correct answer to R13)',
          (SELECT count(*) FROM members m WHERE NOT EXISTS (SELECT 1 FROM profile_views v WHERE v.viewer_id = m.member_id))
UNION ALL SELECT 'rows returned by R13 as written (NOT IN with NULLs)',
          (SELECT count(*) FROM members m WHERE m.member_id NOT IN (SELECT v.viewer_id FROM profile_views v))
UNION ALL SELECT 'members whose email differs from lower(email)', (SELECT count(*) FROM members WHERE email <> lower(email))
UNION ALL SELECT 'distinct lower(email) values = members?',
          (SELECT count(DISTINCT lower(email)) FROM members)
UNION ALL SELECT 'members with no current position', (SELECT count(*) FROM members m WHERE NOT EXISTS
          (SELECT 1 FROM positions p WHERE p.member_id = m.member_id AND p.end_date IS NULL));

-- Indexes that exist after loading (all created by PRIMARY KEY / UNIQUE constraints)
SELECT tablename, indexname FROM pg_indexes WHERE schemaname = 'linkedin' ORDER BY tablename, indexname;
