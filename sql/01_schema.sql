-- =====================================================================
-- sql/01_schema.sql   LinkedIn Professional Network database
-- Team T0016 · Section E · Phase 2: schema rebuilt from the seed-data export
--
-- Run on an EMPTY PostgreSQL 15+ database:   psql -d <db> -f sql/01_schema.sql
--
-- Phase-2 rule: constraints only (PK, FK, UNIQUE, NOT NULL, CHECK). The only
-- indexes that exist are the ones PostgreSQL builds for PRIMARY KEY and UNIQUE
-- constraints (listed in docs/02_schema_design.md). Foreign-key columns are
-- NOT indexed on purpose: that is Phase 4 work.
--
-- Column names are exactly the CSV headers, because the 30 queries use them.
-- Ids come from the source system, so keys are plain INTEGER/SMALLINT (no
-- serial/identity): the export is the system of record and W01 inserts an
-- explicit application_id.
-- =====================================================================

DROP SCHEMA IF EXISTS linkedin CASCADE;   -- makes the script re-runnable
CREATE SCHEMA linkedin;
SET search_path TO linkedin;

-- ---------------------------------------------------------------------
-- cities: lookup of the 10 cities members and companies refer to
-- ---------------------------------------------------------------------
CREATE TABLE cities (
    city_id    SMALLINT    PRIMARY KEY,
    city_name  VARCHAR(50) NOT NULL,
    state      VARCHAR(50) NOT NULL,
    -- same city name can exist in two states, so the natural key is (name, state)
    CONSTRAINT uq_cities_name_state UNIQUE (city_name, state)
);

-- ---------------------------------------------------------------------
-- members: one row per LinkedIn member
-- ---------------------------------------------------------------------
CREATE TABLE members (
    member_id    INTEGER      PRIMARY KEY,
    first_name   VARCHAR(50)  NOT NULL,
    last_name    VARCHAR(50)  NOT NULL,
    headline     VARCHAR(220),                       -- NULL: member never wrote one (5,946 rows)
    email        VARCHAR(254) NOT NULL,              -- sign-in id (R23 compares lower(email))
    city_id      SMALLINT,                           -- NULL: member did not give a location (1,231 rows)
    industry     VARCHAR(50)  NOT NULL,
    is_premium   BOOLEAN      NOT NULL DEFAULT FALSE,
    open_to_work BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_members_email        UNIQUE (email),
    CONSTRAINT fk_members_city         FOREIGN KEY (city_id) REFERENCES cities (city_id)
                                       ON DELETE SET NULL,   -- losing a city only blanks the location
    CONSTRAINT chk_members_names       CHECK (length(btrim(first_name)) > 0 AND length(btrim(last_name)) > 0),
    CONSTRAINT chk_members_email_shape CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
);

-- ---------------------------------------------------------------------
-- companies
-- ---------------------------------------------------------------------
CREATE TABLE companies (
    company_id   INTEGER      PRIMARY KEY,
    company_name VARCHAR(100) NOT NULL,              -- not UNIQUE: two real companies can share a name
    industry     VARCHAR(50)  NOT NULL,
    company_size VARCHAR(12)  NOT NULL,
    hq_city_id   SMALLINT     NOT NULL,
    founded_year SMALLINT     NOT NULL,
    website      VARCHAR(255),                       -- NULL: no website on the page (400 rows)
    CONSTRAINT fk_companies_hq_city  FOREIGN KEY (hq_city_id) REFERENCES cities (city_id)
                                     ON DELETE RESTRICT,     -- a company must always have an HQ
    CONSTRAINT chk_companies_size    CHECK (company_size IN ('1-10','11-50','51-200','201-1000',
                                                             '1001-5000','5001-10000','10001+')),
    CONSTRAINT chk_companies_founded CHECK (founded_year BETWEEN 1800 AND 2100),
    CONSTRAINT chk_companies_website CHECK (website IS NULL OR website ~ '^https?://')
);

-- ---------------------------------------------------------------------
-- positions: work history. end_date IS NULL means "current position"
-- ---------------------------------------------------------------------
CREATE TABLE positions (
    position_id     INTEGER      PRIMARY KEY,
    member_id       INTEGER      NOT NULL,
    company_id      INTEGER      NOT NULL,
    title           VARCHAR(100) NOT NULL,
    employment_type VARCHAR(12)  NOT NULL,
    start_date      DATE         NOT NULL,
    end_date        DATE,                            -- NULL: still working there (34,238 rows)
    CONSTRAINT fk_positions_member  FOREIGN KEY (member_id)  REFERENCES members (member_id)
                                    ON DELETE CASCADE,       -- history belongs to the member
    CONSTRAINT fk_positions_company FOREIGN KEY (company_id) REFERENCES companies (company_id)
                                    ON DELETE RESTRICT,      -- do not silently erase talent-flow history
    CONSTRAINT chk_positions_type   CHECK (employment_type IN ('FULL_TIME','CONTRACT','INTERNSHIP')),
    CONSTRAINT chk_positions_dates  CHECK (end_date IS NULL OR end_date >= start_date)
);

-- ---------------------------------------------------------------------
-- skills + member_skills (M:N members <-> skills, with an endorsement counter)
-- ---------------------------------------------------------------------
CREATE TABLE skills (
    skill_id   SMALLINT    PRIMARY KEY,
    skill_name VARCHAR(50) NOT NULL,
    CONSTRAINT uq_skills_name UNIQUE (skill_name)
);

CREATE TABLE member_skills (
    member_id    INTEGER  NOT NULL,
    skill_id     SMALLINT NOT NULL,
    endorsements INTEGER  NOT NULL DEFAULT 0,
    CONSTRAINT pk_member_skills      PRIMARY KEY (member_id, skill_id),   -- a skill is listed once per member
    CONSTRAINT fk_member_skills_m    FOREIGN KEY (member_id) REFERENCES members (member_id) ON DELETE CASCADE,
    CONSTRAINT fk_member_skills_s    FOREIGN KEY (skill_id)  REFERENCES skills (skill_id)   ON DELETE CASCADE,
    CONSTRAINT chk_member_skills_end CHECK (endorsements >= 0)
);

-- ---------------------------------------------------------------------
-- connections: a two-way relationship stored ONCE, smaller member id first
-- ---------------------------------------------------------------------
CREATE TABLE connections (
    member_a     INTEGER     NOT NULL,
    member_b     INTEGER     NOT NULL,
    connected_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT pk_connections    PRIMARY KEY (member_a, member_b),
    CONSTRAINT fk_connections_a  FOREIGN KEY (member_a) REFERENCES members (member_id) ON DELETE CASCADE,
    CONSTRAINT fk_connections_b  FOREIGN KEY (member_b) REFERENCES members (member_id) ON DELETE CASCADE,
    -- a < b forbids self-connections AND makes (5,9) and (9,5) the same single row
    CONSTRAINT chk_connections_order CHECK (member_a < member_b)
);

-- ---------------------------------------------------------------------
-- invitations: connection requests. Not unique per (sender, recipient):
-- the data contains a pair that was invited twice (see docs/02_schema_design.md)
-- ---------------------------------------------------------------------
CREATE TABLE invitations (
    invitation_id INTEGER     PRIMARY KEY,
    sender_id     INTEGER     NOT NULL,
    recipient_id  INTEGER     NOT NULL,
    note          VARCHAR(300),                      -- NULL: sent without a personal note (45,168 rows)
    sent_at       TIMESTAMPTZ NOT NULL,
    status        VARCHAR(9)  NOT NULL DEFAULT 'PENDING',
    responded_at  TIMESTAMPTZ,                       -- NULL exactly while the invitation is PENDING
    CONSTRAINT fk_invitations_sender    FOREIGN KEY (sender_id)    REFERENCES members (member_id) ON DELETE CASCADE,
    CONSTRAINT fk_invitations_recipient FOREIGN KEY (recipient_id) REFERENCES members (member_id) ON DELETE CASCADE,
    CONSTRAINT chk_invitations_status   CHECK (status IN ('PENDING','ACCEPTED','IGNORED','WITHDRAWN')),
    CONSTRAINT chk_invitations_self     CHECK (sender_id <> recipient_id),
    CONSTRAINT chk_invitations_pending  CHECK ((status = 'PENDING') = (responded_at IS NULL)),
    CONSTRAINT chk_invitations_order    CHECK (responded_at IS NULL OR responded_at >= sent_at)
);

-- ---------------------------------------------------------------------
-- jobs
-- ---------------------------------------------------------------------
CREATE TABLE jobs (
    job_id          INTEGER      PRIMARY KEY,
    company_id      INTEGER      NOT NULL,
    title           VARCHAR(100) NOT NULL,
    city_id         SMALLINT,                        -- NULL exactly for REMOTE jobs (2,217 rows)
    workplace_type  VARCHAR(6)   NOT NULL,
    employment_type VARCHAR(12)  NOT NULL,
    min_experience  SMALLINT     NOT NULL DEFAULT 0, -- years
    min_salary_lpa  NUMERIC(5,1),                    -- lakh per annum; NULL: salary not advertised
    max_salary_lpa  NUMERIC(5,1),                    -- NULL: no upper bound advertised
    posted_at       TIMESTAMPTZ  NOT NULL,
    closes_at       TIMESTAMPTZ  NOT NULL,
    status          VARCHAR(6)   NOT NULL DEFAULT 'OPEN',
    CONSTRAINT fk_jobs_company    FOREIGN KEY (company_id) REFERENCES companies (company_id)
                                  ON DELETE CASCADE,         -- a job belongs to its company page
    CONSTRAINT fk_jobs_city       FOREIGN KEY (city_id)    REFERENCES cities (city_id)
                                  ON DELETE RESTRICT,        -- SET NULL would break chk_jobs_remote_city
    CONSTRAINT chk_jobs_workplace CHECK (workplace_type IN ('ONSITE','HYBRID','REMOTE')),
    CONSTRAINT chk_jobs_type      CHECK (employment_type IN ('FULL_TIME','CONTRACT','INTERNSHIP')),
    CONSTRAINT chk_jobs_status    CHECK (status IN ('OPEN','CLOSED')),
    CONSTRAINT chk_jobs_exp       CHECK (min_experience BETWEEN 0 AND 50),
    CONSTRAINT chk_jobs_remote_city CHECK ((workplace_type = 'REMOTE') = (city_id IS NULL)),
    CONSTRAINT chk_jobs_salary_pos  CHECK (min_salary_lpa > 0 AND (max_salary_lpa IS NULL OR max_salary_lpa > 0)),
    CONSTRAINT chk_jobs_salary_order CHECK (max_salary_lpa >= min_salary_lpa),
    CONSTRAINT chk_jobs_salary_pair  CHECK (max_salary_lpa IS NULL OR min_salary_lpa IS NOT NULL),
    CONSTRAINT chk_jobs_dates     CHECK (closes_at > posted_at)
);

-- ---------------------------------------------------------------------
-- job_skills (M:N jobs <-> skills)
-- ---------------------------------------------------------------------
CREATE TABLE job_skills (
    job_id   INTEGER  NOT NULL,
    skill_id SMALLINT NOT NULL,
    CONSTRAINT pk_job_skills   PRIMARY KEY (job_id, skill_id),
    CONSTRAINT fk_job_skills_j FOREIGN KEY (job_id)   REFERENCES jobs (job_id)     ON DELETE CASCADE,
    CONSTRAINT fk_job_skills_s FOREIGN KEY (skill_id) REFERENCES skills (skill_id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- applications (M:N members <-> jobs, one application per member per job)
-- ---------------------------------------------------------------------
CREATE TABLE applications (
    application_id    INTEGER     PRIMARY KEY,
    job_id            INTEGER     NOT NULL,
    member_id         INTEGER     NOT NULL,
    applied_at        TIMESTAMPTZ NOT NULL,
    easy_apply        BOOLEAN     NOT NULL DEFAULT FALSE,
    status            VARCHAR(12) NOT NULL DEFAULT 'APPLIED',
    status_updated_at TIMESTAMPTZ NOT NULL,
    -- stops a member applying twice to the same job; W01 relies on ON CONFLICT (job_id, member_id)
    CONSTRAINT uq_applications_job_member UNIQUE (job_id, member_id),
    CONSTRAINT fk_applications_job    FOREIGN KEY (job_id)    REFERENCES jobs (job_id)       ON DELETE CASCADE,
    CONSTRAINT fk_applications_member FOREIGN KEY (member_id) REFERENCES members (member_id) ON DELETE CASCADE,
    CONSTRAINT chk_applications_status CHECK (status IN ('APPLIED','VIEWED','SHORTLISTED','INTERVIEW',
                                                         'OFFER','HIRED','REJECTED','WITHDRAWN')),
    CONSTRAINT chk_applications_dates  CHECK (status_updated_at >= applied_at)
);

-- ---------------------------------------------------------------------
-- profile_views. viewer_id IS NULL means the viewer browsed in private mode
-- ---------------------------------------------------------------------
CREATE TABLE profile_views (
    view_id   INTEGER     PRIMARY KEY,
    viewer_id INTEGER,                               -- NULL: private mode (50,173 rows). Must stay nullable.
    viewed_id INTEGER     NOT NULL,
    viewed_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_views_viewer FOREIGN KEY (viewer_id) REFERENCES members (member_id)
                               ON DELETE SET NULL,       -- a deleted viewer becomes anonymous, the view still counts
    CONSTRAINT fk_views_viewed FOREIGN KEY (viewed_id) REFERENCES members (member_id)
                               ON DELETE CASCADE,
    CONSTRAINT chk_views_self  CHECK (viewer_id IS NULL OR viewer_id <> viewed_id)
);
