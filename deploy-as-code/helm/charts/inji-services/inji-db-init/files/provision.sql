-- =============================================================================
-- Inji stack — database provisioning on postgres.egov (digit-lts)
-- Applied by the inji-db-init Job as an ArgoCD PreSync hook. Do not run by hand.
-- Idempotent: re-running makes no changes.
-- =============================================================================
--
-- WHY THIS EXISTS
-- MOSIP ships its own init_db.sh per module which creates these same objects,
-- but those scripts assume a dedicated Postgres instance. postgres.egov is not
-- dedicated: its `postgres` database holds ~90 DIGIT tenant schemas AND Kong's
-- control-plane tables (routes/services/plugins/consumers). Provisioning
-- explicitly, with connection limits, means Inji cannot starve Kong of
-- connections or be pointed at the wrong database by a stray script.
--
-- Once these objects exist, each module's own init_db.sh finds them present and
-- only applies DDL/DML inside its own database.
--
-- NAMES ARE NOT INVENTED. Sourced from upstream:
--   inji_certify  / schema certify / certifyuser
--       inji/inji-certify @ master db_scripts/inji_certify/{db,role_dbuser,grants}.sql
--   inji_mimoto   / schema mimoto  / mimotouser
--       mosip/mimoto @ develop db_scripts/inji_mimoto/{db.sql,deploy.properties}
--   inji_verify   / schema verify  / verifyuser
--       mosip/inji-verify @ develop db_scripts/inji_verify/{db.sql,deploy.properties}
--   mosip_esignet / schema esignet / esignetuser
--       mosip/esignet @ develop db_scripts/mosip_esignet/{db.sql,deploy.properties}
--
-- DELIBERATE DEVIATIONS FROM UPSTREAM (each is a hardening change):
--   1. LC_COLLATE/LC_CTYPE are 'en_US.utf8', not upstream's 'en_US.UTF-8'.
--      This server's lc_collate is literally 'en_US.utf8' and glibc in the
--      server image exposes only that spelling. glibc normalises
--      'en_US.UTF-8' to the same locale so upstream would also work; matching
--      exactly removes the ambiguity.
--   2. Roles get CONNECTION LIMIT 25, databases CONNECTION LIMIT 30. Upstream
--      sets neither. This is the safeguard that protects Kong: 4 x 25 = 100
--      connections maximum against max_connections 750.
--   3. REVOKE CONNECT ... FROM PUBLIC on each new database, so keycloak,
--      metabase and any future DIGIT role cannot reach Inji data.
--   4. Passwords come from psql variables, never literals.
--   Everything else — database options, schema names, search_path, the grant
--   set, role attributes — is upstream behaviour unchanged.
--
-- REQUIRED psql VARIABLES (passed by the Job from the `inji-db` secret):
--   certifypwd, mimotopwd, verifypwd, esignetpwd
-- =============================================================================

\set ON_ERROR_STOP on
\echo ''
\echo '=== Inji DB provisioning — preflight ==='

-- -----------------------------------------------------------------------------
-- SECTION 0 — Preflight. Read-only. Aborts if we are on the wrong server.
-- -----------------------------------------------------------------------------

-- 0.1 Refuse to run anywhere that does not look like postgres.egov. Guards
--     against the Job being pointed at postgresql-lts (being decommissioned)
--     or at another cluster entirely.
DO $$
DECLARE
    v_kong_tables int;
    v_digit_schemas int;
BEGIN
    SELECT count(*) INTO v_kong_tables
      FROM information_schema.tables
     WHERE table_catalog = 'postgres'
       AND table_name IN ('routes','services','plugins','consumers');

    SELECT count(*) INTO v_digit_schemas
      FROM pg_namespace
     WHERE nspname NOT LIKE 'pg_%'
       AND nspname NOT IN ('information_schema','public');

    IF v_kong_tables < 4 THEN
        RAISE EXCEPTION
          'Preflight failed: Kong tables not found in this database (found %). '
          'Expected the `postgres` database on postgres.egov. Refusing to continue.',
          v_kong_tables;
    END IF;

    IF v_digit_schemas < 50 THEN
        RAISE EXCEPTION
          'Preflight failed: only % non-system schemas present. postgres.egov '
          'should have ~90 DIGIT tenant schemas. This may be postgresql-lts or a '
          'different cluster. Refusing to continue.', v_digit_schemas;
    END IF;

    RAISE NOTICE 'Preflight OK: Kong tables present, % DIGIT schemas found.',
        v_digit_schemas;
END $$;

-- 0.2 Confirm the locale we are about to request actually exists.
DO $$
DECLARE v_collate text;
BEGIN
    SELECT setting INTO v_collate FROM pg_settings WHERE name = 'lc_collate';
    IF v_collate <> 'en_US.utf8' THEN
        RAISE EXCEPTION
          'Preflight failed: server lc_collate is "%", expected "en_US.utf8". '
          'Adjust LC_COLLATE/LC_CTYPE below to match.', v_collate;
    END IF;
    RAISE NOTICE 'Preflight OK: lc_collate = %', v_collate;
END $$;

-- 0.3 Confirm there is connection headroom. We are about to reserve up to 100.
DO $$
DECLARE
    v_max int;
    v_used int;
BEGIN
    SELECT setting::int INTO v_max FROM pg_settings WHERE name='max_connections';
    SELECT count(*) INTO v_used FROM pg_stat_activity;
    RAISE NOTICE 'Connections: % in use of % max. Inji will reserve <= 100.',
        v_used, v_max;
    IF v_max - v_used < 150 THEN
        RAISE EXCEPTION
          'Preflight failed: only % connections free. Not enough headroom to add '
          'Inji alongside Kong.', v_max - v_used;
    END IF;
END $$;

-- 0.4 Note any target name already present; it will be left untouched.
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT datname FROM pg_database
         WHERE datname IN ('inji_certify','inji_mimoto','inji_verify','mosip_esignet','mosip_mockidentitysystem')
    LOOP
        RAISE NOTICE 'Note: database % already exists; leaving untouched.', r.datname;
    END LOOP;
END $$;

\echo ''
\echo '=== Section 1: roles ==='

-- -----------------------------------------------------------------------------
-- SECTION 1 — Application roles.
--
-- Attributes match upstream role_dbuser.sql (INHERIT, LOGIN, password).
-- NOSUPERUSER/NOCREATEDB/NOCREATEROLE are PostgreSQL defaults, stated
-- explicitly so the intent is visible: these roles must never reach outside
-- their own database.
--
-- IMPLEMENTATION NOTE — why \gexec and not a DO block:
-- psql does not interpolate :variables inside dollar-quoted strings, so
-- `DO $$ ... PASSWORD :'certifypwd' ... $$` would store the literal text
-- ":'certifypwd'" as the password, and would appear to succeed. Building the
-- statement with format() outside any quoting and running it through \gexec
-- substitutes correctly; %L quotes the value safely for SQL.
--
-- SECURITY NOTE: the generated CREATE ROLE contains the password in cleartext.
-- On this server log_statement=none, log_min_duration_statement=-1 and
-- logging_collector=off (verified 2026-09-16), so nothing reaches a log.
-- Re-check if those settings change. Rotate with ALTER ROLE ... PASSWORD
-- rather than by re-running this script.
-- -----------------------------------------------------------------------------

SELECT format(
    'CREATE ROLE certifyuser INHERIT LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE '
    'NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 25 PASSWORD %L', :'certifypwd')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'certifyuser')
\gexec

SELECT format(
    'CREATE ROLE mimotouser INHERIT LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE '
    'NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 25 PASSWORD %L', :'mimotopwd')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mimotouser')
\gexec

SELECT format(
    'CREATE ROLE verifyuser INHERIT LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE '
    'NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 25 PASSWORD %L', :'verifypwd')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'verifyuser')
\gexec

SELECT format(
    'CREATE ROLE esignetuser INHERIT LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE '
    'NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 25 PASSWORD %L', :'esignetpwd')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'esignetuser')
\gexec

-- mock-identity-system. Added with step 05b: eSignet's MockAuthenticationService
-- has no backend without it, so login fails even though eSignet is healthy.
SELECT format(
    'CREATE ROLE mockidsystemuser INHERIT LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE '
    'NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 25 PASSWORD %L', :'mockidpwd')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mockidsystemuser')
\gexec

-- Report what exists, without echoing any password.
SELECT rolname AS role_created_or_present
  FROM pg_roles
 WHERE rolname IN ('certifyuser','mimotouser','verifyuser','esignetuser','mockidsystemuser')
 ORDER BY rolname;

\echo ''
\echo '=== Section 2: databases ==='

-- -----------------------------------------------------------------------------
-- SECTION 2 — Databases.
--
-- CREATE DATABASE has no IF NOT EXISTS and cannot run inside a transaction or
-- a DO block, so each is emitted conditionally via \gexec: the SELECT yields
-- the DDL text only when the database is absent, and \gexec runs whatever came
-- back (nothing, if it already exists).
--
-- OWNER = postgres matches upstream. The app roles are granted access in
-- Section 3 rather than owning the database, which is also upstream's model
-- and means a compromised app role cannot DROP its own schema.
-- -----------------------------------------------------------------------------

SELECT $ddl$CREATE DATABASE inji_certify
    WITH ENCODING = 'UTF8'
         LC_COLLATE = 'en_US.utf8'
         LC_CTYPE = 'en_US.utf8'
         TABLESPACE = pg_default
         OWNER = postgres
         TEMPLATE = template0
         CONNECTION LIMIT = 30$ddl$
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'inji_certify')
\gexec

SELECT $ddl$CREATE DATABASE inji_mimoto
    WITH ENCODING = 'UTF8'
         LC_COLLATE = 'en_US.utf8'
         LC_CTYPE = 'en_US.utf8'
         TABLESPACE = pg_default
         OWNER = postgres
         TEMPLATE = template0
         CONNECTION LIMIT = 30$ddl$
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'inji_mimoto')
\gexec

SELECT $ddl$CREATE DATABASE inji_verify
    WITH ENCODING = 'UTF8'
         LC_COLLATE = 'en_US.utf8'
         LC_CTYPE = 'en_US.utf8'
         TABLESPACE = pg_default
         OWNER = postgres
         TEMPLATE = template0
         CONNECTION LIMIT = 30$ddl$
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'inji_verify')
\gexec

SELECT $ddl$CREATE DATABASE mosip_esignet
    WITH ENCODING = 'UTF8'
         LC_COLLATE = 'en_US.utf8'
         LC_CTYPE = 'en_US.utf8'
         TABLESPACE = pg_default
         OWNER = postgres
         TEMPLATE = template0
         CONNECTION LIMIT = 30$ddl$
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'mosip_esignet')
\gexec

SELECT $ddl$CREATE DATABASE mosip_mockidentitysystem
    WITH ENCODING = 'UTF8'
         LC_COLLATE = 'en_US.utf8'
         LC_CTYPE = 'en_US.utf8'
         TABLESPACE = pg_default
         OWNER = postgres
         TEMPLATE = template0
         CONNECTION LIMIT = 30$ddl$
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'mosip_mockidentitysystem')
\gexec

-- search_path per upstream db.sql. Safe to re-run.
ALTER DATABASE inji_certify  SET search_path TO certify,pg_catalog,public;
ALTER DATABASE inji_mimoto   SET search_path TO mimoto,pg_catalog,public;
ALTER DATABASE inji_verify   SET search_path TO verify,pg_catalog,public;
ALTER DATABASE mosip_esignet SET search_path TO esignet,pg_catalog,public;
ALTER DATABASE mosip_mockidentitysystem SET search_path TO mockidentitysystem,pg_catalog,public;

-- Hardening: PUBLIC holds CONNECT on every new database by default, which
-- would let keycloak / metabase / any future DIGIT role connect here.
REVOKE CONNECT ON DATABASE inji_certify  FROM PUBLIC;
REVOKE CONNECT ON DATABASE inji_mimoto   FROM PUBLIC;
REVOKE CONNECT ON DATABASE inji_verify   FROM PUBLIC;
REVOKE CONNECT ON DATABASE mosip_esignet FROM PUBLIC;
REVOKE CONNECT ON DATABASE mosip_mockidentitysystem FROM PUBLIC;

\echo ''
\echo '=== Section 3: schemas and grants (per database) ==='

-- -----------------------------------------------------------------------------
-- SECTION 3 — Inside each database: schema, grants, default privileges.
--
-- The grant set is exactly upstream grants.sql. ALTER DEFAULT PRIVILEGES is
-- what lets each module's init_db.sh work afterwards: tables it creates as
-- `postgres` become reachable by the app role with no re-grant.
--
-- There is deliberately no GRANT CREATE on the schema. The app role reads and
-- writes rows; migrations run as postgres. If a module's Flyway is configured
-- to migrate as the app user it will fail here, and the correct fix is to
-- point migrations at postgres, not to widen this grant.
-- -----------------------------------------------------------------------------

\connect inji_certify
\echo '--- inji_certify ---'
CREATE SCHEMA IF NOT EXISTS certify AUTHORIZATION postgres;
ALTER SCHEMA certify OWNER TO postgres;
GRANT CONNECT ON DATABASE inji_certify TO certifyuser;
GRANT USAGE ON SCHEMA certify TO certifyuser;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES
    ON ALL TABLES IN SCHEMA certify TO certifyuser;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA certify TO certifyuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA certify
    GRANT SELECT,INSERT,UPDATE,DELETE,REFERENCES ON TABLES TO certifyuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA certify
    GRANT USAGE, SELECT ON SEQUENCES TO certifyuser;

-- -----------------------------------------------------------------------------
-- SECTION 3b — Credential source table for the Postgres data-provider plugin.
--
-- ADDED AFTER THE FIRST RUN. The Job is keyed by a checksum of this file, so
-- editing it produces a new Job name and the SQL re-runs; every statement
-- above is guarded, so the already-provisioned databases and roles are
-- untouched and only this section does new work.
--
-- Certify's certify-digit-landregistry profile maps an OIDC scope to
--   select * from certify_source.license_data where license_id=:id
-- with :id bound from the access token's `sub` claim.
--
-- A DEDICATED table in a DEDICATED schema, not a DIGIT table.
--
-- Precisely what certifyuser can and cannot reach in the shared `postgres`
-- database, measured on 2026-09-16 with SET ROLE:
--   CONNECT:            yes. Section 2's REVOKE CONNECT ... FROM PUBLIC applies
--                       only to the four databases it creates; the pre-existing
--                       `postgres` database still grants PUBLIC connect, and
--                       revoking that is not safe to do blind on a shared
--                       database.
--   readable tables:    3, all PostGIS metadata (spatial_ref_sys,
--                       geometry_columns, geography_columns), which PostGIS
--                       grants to PUBLIC by design. No DIGIT business data.
--   Kong routes/consumers: NOT readable.
--   DIGIT tenant schemas (e.g. ACC10): no USAGE.
--
-- So pointing scope-query-mapping at DIGIT data would require new explicit
-- grants, not merely a different query. Populate this table from DIGIT with
-- whatever ETL suits instead, and the isolation holds.
--
-- Kept OUT of the `certify` schema on purpose: that schema is owned by
-- Certify's own Flyway migrations, and a hand-made table sitting in it would
-- be indistinguishable from a migration artefact.
-- -----------------------------------------------------------------------------

\connect inji_certify
\echo '--- inji_certify: credential source schema ---'

CREATE SCHEMA IF NOT EXISTS certify_source AUTHORIZATION postgres;

CREATE TABLE IF NOT EXISTS certify_source.license_data (
    license_id    text PRIMARY KEY,
    holder_name   text NOT NULL,
    license_type  text,
    trade_name    text,
    tenant_id     text,
    issued_date   date,
    valid_upto    date,
    -- Provenance of the row, so it is always clear which ETL run produced a
    -- credential's source data.
    source_system text DEFAULT 'digit-lts',
    updated_at    timestamptz DEFAULT now()
);

-- SELECT only. The plugin reads; it never writes. Deliberately no INSERT /
-- UPDATE / DELETE: if Certify is ever compromised it must not be able to mint
-- itself a credential subject.
GRANT USAGE ON SCHEMA certify_source TO certifyuser;
GRANT SELECT ON ALL TABLES IN SCHEMA certify_source TO certifyuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA certify_source
    GRANT SELECT ON TABLES TO certifyuser;

-- -----------------------------------------------------------------------------
-- SECTION 3c — eSignet schema objects.
--
-- inji-db-init originally created databases, schemas, roles and grants but NO
-- module tables. eSignet crash-looped on
--   SQLState 42P01: relation "key_alias" does not exist
-- because upstream expects db_scripts/init_db.sh to have been run out of band.
-- That step has no place in a GitOps flow, so the SQL is vendored and applied
-- here instead (files/esignet-ddl.sql, files/esignet-dml.sql).
--
-- GUARDED, and the guard is not optional:
--   * 8 of the 9 upstream DDL files use bare CREATE TABLE with no
--     IF NOT EXISTS, so a second run errors and fails the Job.
--   * dml.sql TRUNCATEs esignet.client_detail and esignet.server_profile.
--     client_detail is where registered OIDC clients live -- including the
--     Mimoto client. Re-running it would silently delete them.
--
-- This Job re-runs whenever ANY file in files/ changes (the Job name is a
-- checksum), so an unguarded block would eventually do exactly that. The guard
-- keys on esignet.key_alias: present means the schema is already built, so DDL
-- and seed data are both skipped.
--
-- To intentionally rebuild eSignet's schema, drop the database and let this
-- run again -- do not remove the guard.
-- -----------------------------------------------------------------------------

\connect mosip_esignet
\echo '--- mosip_esignet: schema objects ---'

SELECT NOT EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'esignet' AND table_name = 'key_alias'
) AS esignet_needs_schema \gset

\if :esignet_needs_schema
    \echo '    key_alias absent -> applying eSignet DDL + seed data'
    \ir esignet-ddl.sql
    \ir esignet-dml.sql
    \echo '    eSignet schema created'
\else
    \echo '    key_alias present -> schema already built, skipping (idempotent)'
\endif

-- Re-assert grants: the DDL above creates tables as postgres, and while
-- ALTER DEFAULT PRIVILEGES from Section 3 covers tables created after it was
-- set, being explicit here means a re-vendored DDL cannot leave esignetuser
-- without access.
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES
    ON ALL TABLES IN SCHEMA esignet TO esignetuser;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA esignet TO esignetuser;

\connect inji_mimoto
\echo '--- inji_mimoto ---'
CREATE SCHEMA IF NOT EXISTS mimoto AUTHORIZATION postgres;
ALTER SCHEMA mimoto OWNER TO postgres;
GRANT CONNECT ON DATABASE inji_mimoto TO mimotouser;
GRANT USAGE ON SCHEMA mimoto TO mimotouser;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES
    ON ALL TABLES IN SCHEMA mimoto TO mimotouser;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA mimoto TO mimotouser;
ALTER DEFAULT PRIVILEGES IN SCHEMA mimoto
    GRANT SELECT,INSERT,UPDATE,DELETE,REFERENCES ON TABLES TO mimotouser;
ALTER DEFAULT PRIVILEGES IN SCHEMA mimoto
    GRANT USAGE, SELECT ON SEQUENCES TO mimotouser;

\connect inji_verify
\echo '--- inji_verify ---'
CREATE SCHEMA IF NOT EXISTS verify AUTHORIZATION postgres;
ALTER SCHEMA verify OWNER TO postgres;
GRANT CONNECT ON DATABASE inji_verify TO verifyuser;
GRANT USAGE ON SCHEMA verify TO verifyuser;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES
    ON ALL TABLES IN SCHEMA verify TO verifyuser;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA verify TO verifyuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA verify
    GRANT SELECT,INSERT,UPDATE,DELETE,REFERENCES ON TABLES TO verifyuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA verify
    GRANT USAGE, SELECT ON SEQUENCES TO verifyuser;

\connect mosip_esignet
\echo '--- mosip_esignet ---'
CREATE SCHEMA IF NOT EXISTS esignet AUTHORIZATION postgres;
ALTER SCHEMA esignet OWNER TO postgres;
GRANT CONNECT ON DATABASE mosip_esignet TO esignetuser;
GRANT USAGE ON SCHEMA esignet TO esignetuser;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES
    ON ALL TABLES IN SCHEMA esignet TO esignetuser;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA esignet TO esignetuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA esignet
    GRANT SELECT,INSERT,UPDATE,DELETE,REFERENCES ON TABLES TO esignetuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA esignet
    GRANT USAGE, SELECT ON SEQUENCES TO esignetuser;

-- -----------------------------------------------------------------------------
-- certify schema objects.
--
-- Same reasoning as the eSignet section: inji-db-init creates databases,
-- schemas, roles and grants, but upstream expects db_scripts/init_db.sh to
-- create the TABLES out of band, and the certify chart ships no migration hook.
-- The SQL is vendored (certify-ddl.sql, certify-dml.sql) and applied here.
--
-- GUARDED on certify.key_alias: only 2 of 11 upstream CREATE TABLE statements use IF NOT EXISTS.
-- This Job re-runs whenever any files/*.sql changes, so without the guard a
-- later edit would re-run CREATE TABLE against an existing schema and fail.
-- -----------------------------------------------------------------------------

\connect inji_certify
\echo '--- inji_certify: schema objects ---'

SELECT NOT EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'certify' AND table_name = 'key_alias'
) AS certify_needs_schema \gset

\if :certify_needs_schema
    \echo '    key_alias absent -> applying certify DDL + seed data'
    \ir certify-ddl.sql
    \ir certify-dml.sql
    \echo '    certify schema created'
\else
    \echo '    key_alias present -> schema already built, skipping (idempotent)'
\endif

-- Re-assert grants for tables the vendored DDL just created.
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES
    ON ALL TABLES IN SCHEMA certify TO certifyuser;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA certify TO certifyuser;

-- -----------------------------------------------------------------------------
-- mimoto schema objects.
--
-- Same reasoning as the eSignet section: inji-db-init creates databases,
-- schemas, roles and grants, but upstream expects db_scripts/init_db.sh to
-- create the TABLES out of band, and the mimoto chart ships no migration hook.
-- The SQL is vendored (mimoto-ddl.sql, mimoto-dml.sql) and applied here.
--
-- GUARDED on mimoto.key_alias: only 6 of 10 upstream CREATE TABLE statements use IF NOT EXISTS.
-- This Job re-runs whenever any files/*.sql changes, so without the guard a
-- later edit would re-run CREATE TABLE against an existing schema and fail.
-- -----------------------------------------------------------------------------

\connect inji_mimoto
\echo '--- inji_mimoto: schema objects ---'

SELECT NOT EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'mimoto' AND table_name = 'key_alias'
) AS mimoto_needs_schema \gset

\if :mimoto_needs_schema
    \echo '    key_alias absent -> applying mimoto DDL + seed data'
    \ir mimoto-ddl.sql
    \ir mimoto-dml.sql
    \echo '    mimoto schema created'
\else
    \echo '    key_alias present -> schema already built, skipping (idempotent)'
\endif

-- Re-assert grants for tables the vendored DDL just created.
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES
    ON ALL TABLES IN SCHEMA mimoto TO mimotouser;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA mimoto TO mimotouser;

-- -----------------------------------------------------------------------------
-- mock-identity-system schema objects (step 05b).
--
-- Database mosip_mockidentitysystem, schema mockidentitysystem, role
-- mockidsystemuser -- names taken from
-- mosip/esignet-mock-services@v0.13.0 db_scripts/mosip_mockidentitysystem
-- (db.sql, role_dbuser.sql, deploy.properties), not invented.
--
-- GUARDED on mockidentitysystem.key_alias: NONE of the 8 upstream CREATE TABLE
-- statements uses IF NOT EXISTS, so a re-run without the guard fails the Job.
-- -----------------------------------------------------------------------------

\connect mosip_mockidentitysystem
\echo '--- mosip_mockidentitysystem: schema objects ---'

CREATE SCHEMA IF NOT EXISTS mockidentitysystem AUTHORIZATION postgres;
ALTER SCHEMA mockidentitysystem OWNER TO postgres;
GRANT CONNECT ON DATABASE mosip_mockidentitysystem TO mockidsystemuser;
GRANT USAGE ON SCHEMA mockidentitysystem TO mockidsystemuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA mockidentitysystem
    GRANT SELECT,INSERT,UPDATE,DELETE,REFERENCES ON TABLES TO mockidsystemuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA mockidentitysystem
    GRANT USAGE, SELECT ON SEQUENCES TO mockidsystemuser;

SELECT NOT EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'mockidentitysystem' AND table_name = 'key_alias'
) AS mockid_needs_schema \gset

\if :mockid_needs_schema
    \echo '    key_alias absent -> applying mock-identity DDL + seed data'
    \ir mockid-ddl.sql
    \ir mockid-dml.sql
    \echo '    mock-identity schema created'
\else
    \echo '    key_alias present -> schema already built, skipping (idempotent)'
\endif

GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES
    ON ALL TABLES IN SCHEMA mockidentitysystem TO mockidsystemuser;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA mockidentitysystem TO mockidsystemuser;

\echo ''
\echo '=== Section 4: verification ==='

-- -----------------------------------------------------------------------------
-- SECTION 4 — Verification. Read-only. Visible in the Job's logs.
-- -----------------------------------------------------------------------------

\connect postgres

\echo '--- new databases ---'
SELECT datname,
       pg_get_userbyid(datdba) AS owner,
       datconnlimit            AS conn_limit,
       datcollate              AS collate,
       pg_encoding_to_char(encoding) AS encoding
  FROM pg_database
 WHERE datname IN ('inji_certify','inji_mimoto','inji_verify','mosip_esignet','mosip_mockidentitysystem')
 ORDER BY datname;

\echo '--- new roles (must be no superuser, no createdb, capped at 25) ---'
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolcanlogin, rolconnlimit
  FROM pg_roles
 WHERE rolname IN ('certifyuser','mimotouser','verifyuser','esignetuser','mockidsystemuser')
 ORDER BY rolname;

\echo '--- PUBLIC must NOT hold CONNECT on the new databases ---'
SELECT datname,
       has_database_privilege('public', datname, 'CONNECT') AS public_can_connect
  FROM pg_database
 WHERE datname IN ('inji_certify','inji_mimoto','inji_verify','mosip_esignet','mosip_mockidentitysystem')
 ORDER BY datname;

\echo '--- Kong and DIGIT untouched ---'
SELECT (SELECT count(*) FROM information_schema.tables
         WHERE table_name IN ('routes','services','plugins','consumers'))
         AS kong_tables_expect_4,
       (SELECT count(*) FROM pg_namespace
         WHERE nspname NOT LIKE 'pg_%'
           AND nspname NOT IN ('information_schema','public'))
         AS digit_schemas_expect_about_90;

\echo ''
\echo 'Done. Nothing in the `postgres` database was modified.'
