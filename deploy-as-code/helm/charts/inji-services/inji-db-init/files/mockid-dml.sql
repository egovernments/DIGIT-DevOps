-- ============================================================================
-- mock-identity-system seed data (DML)
--
-- DERIVED from mosip/esignet-mock-services @ v0.13.0 (a54f550cffca)
--   db_scripts/mosip_mockidentitysystem/dml.sql + dml/*.csv
--
-- Upstream uses psql \COPY ... FROM './dml/<file>.csv' (client-side, relative
-- path). ConfigMap keys cannot contain '/', so there is no dml/ directory to
-- read from; the CSV rows are expanded into INSERTs. ON CONFLICT DO NOTHING
-- added for re-run safety.
-- ============================================================================

-- 2 rows from mockidentitysystem-key_policy_def.csv
INSERT INTO mockidentitysystem.key_policy_def (APP_ID,KEY_VALIDITY_DURATION,PRE_EXPIRE_DAYS,ACCESS_ALLOWED,IS_ACTIVE,CR_BY,CR_DTIMES) VALUES
  ('ROOT',2920,1125,'NA',TRUE,'mosipadmin',now()),
  ('MOCK_AUTHENTICATION_SERVICE',1095,60,'NA',TRUE,'mosipadmin',now())
ON CONFLICT DO NOTHING;

