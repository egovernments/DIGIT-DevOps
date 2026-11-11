-- Read-only database login (PostgreSQL 14+). Reads every schema, including tables
-- created later; cannot write. Run as an administrator. Pass the password with
-- psql -v pw=... from a source that is not echoed or logged; store it in your
-- secrets store, never in git.
CREATE ROLE <readonly_user> LOGIN PASSWORD :'pw';
GRANT CONNECT ON DATABASE <database> TO <readonly_user>;
GRANT pg_read_all_data TO <readonly_user>;

-- Verify (as <readonly_user>): SELECT works; CREATE TABLE / UPDATE are refused.
-- Revoke: DROP ROLE <readonly_user>;
