-- ============================================================================
-- mimoto seed data (DML)
--
-- DERIVED from mosip/mimoto @ v0.20.0 (f426da315047)
--   db_scripts/inji_mimoto/dml.sql + dml/*.csv
--
-- Upstream uses psql \COPY ... FROM './dml/<file>.csv', a CLIENT-side copy
-- with a relative path. That cannot work here: the SQL is delivered in a
-- ConfigMap and ConfigMap keys cannot contain '/', so there is no dml/
-- subdirectory to read from. The CSV rows are therefore expanded into
-- explicit INSERTs below -- same data, no filesystem dependency.
--
-- ON CONFLICT DO NOTHING is added so this is safe if it is ever reached
-- with rows already present; upstream has no such guard.
-- ============================================================================

-- 3 rows, from mimoto-key_policy_def.csv
INSERT INTO mimoto.key_policy_def (APP_ID,KEY_VALIDITY_DURATION,PRE_EXPIRE_DAYS,ACCESS_ALLOWED,IS_ACTIVE,CR_BY,CR_DTIMES) VALUES
  ('ROOT',2920,1125,'NA',TRUE,'mosipadmin',now()),
  ('MIMOTO',1095,60,'NA',TRUE,'mosipadmin',now()),
  ('BASE',730,60,'NA',TRUE,'mosipadmin',now())
ON CONFLICT DO NOTHING;

