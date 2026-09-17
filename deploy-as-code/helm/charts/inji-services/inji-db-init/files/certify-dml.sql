-- ============================================================================
-- certify seed data (DML)
--
-- DERIVED from inji/inji-certify @ v0.13.1 (618684d326a1)
--   db_scripts/inji_certify/dml.sql + dml/*.csv
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

-- 8 rows, from certify-key_policy_def.csv
INSERT INTO certify.key_policy_def (APP_ID,KEY_VALIDITY_DURATION,PRE_EXPIRE_DAYS,ACCESS_ALLOWED,IS_ACTIVE,CR_BY,CR_DTIMES) VALUES
  ('ROOT',2920,1125,'NA',TRUE,'mosipadmin',now()),
  ('CERTIFY_SERVICE',1095,60,'NA',TRUE,'mosipadmin',now()),
  ('CERTIFY_PARTNER',1095,60,'NA',TRUE,'mosipadmin',now()),
  ('CERTIFY_VC_SIGN_RSA',1095,60,'NA',TRUE,'mosipadmin',now()),
  ('BASE',730,60,'NA',TRUE,'mosipadmin',now()),
  ('CERTIFY_VC_SIGN_ED25519',1095,60,'NA',TRUE,'mosipadmin',now()),
  ('CERTIFY_VC_SIGN_EC_K1',1095,60,'NA',TRUE,'mosipadmin',now()),
  ('CERTIFY_VC_SIGN_EC_R1',1095,60,'NA',TRUE,'mosipadmin',now())
ON CONFLICT DO NOTHING;

