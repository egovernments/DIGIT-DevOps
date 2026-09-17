-- ============================================================================
-- eSignet seed data (DML)
--
-- VENDORED VERBATIM from mosip/esignet @ v1.8.0 (8f662ca6c070)
--   db_scripts/mosip_esignet/dml.sql
-- Files concatenated in the order that orchestrator specifies -- the order
-- matters, foreign keys depend on it. Do not reorder or edit the SQL; to
-- update, re-vendor from the matching upstream tag.
--
-- The upstream \c and \ir directives are dropped: this file is \ir'd from
-- provision.sql, which is already connected to mosip_esignet.
-- ============================================================================

-- from dml.sql itself:
----- TRUNCATE esignet.client_detail TABLE Data and It's reference Data and insert data from sql file -----
TRUNCATE TABLE esignet.client_detail cascade ;
TRUNCATE TABLE esignet.server_profile CASCADE;

-- ---------- dml/esignet-key_policy_def.sql ----------
INSERT INTO key_policy_def (app_id, key_validity_duration, pre_expire_days, access_allowed, is_active, cr_by, cr_dtimes) VALUES
('ROOT', 2920, 1125, 'NA', TRUE, 'mosipadmin', NOW()),
('OIDC_SERVICE', 1095, 60, 'NA', TRUE, 'mosipadmin', NOW()),
('OIDC_PARTNER', 1095, 60, 'NA', TRUE, 'mosipadmin', NOW()),
('BINDING_SERVICE', 1095, 60, 'NA', TRUE, 'mosipadmin', NOW()),
('MOCK_BINDING_SERVICE', 1095, 50, 'NA', TRUE, 'mosipadmin', NOW());

-- ---------- dml/esignet-server_profile.sql ----------
INSERT INTO server_profile (profile_name, feature, additional_config_key) VALUES
('fapi2.0', 'PAR', 'require_pushed_authorization_requests'),
('fapi2.0', 'DPOP', 'dpop_bound_access_tokens'),
('fapi2.0', 'PKCE', 'require_pkce');

