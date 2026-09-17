-- ============================================================================
-- mock-identity-system schema DDL
--
-- VENDORED VERBATIM from mosip/esignet-mock-services @ v0.13.0 (a54f550cffca)
--   db_scripts/mosip_mockidentitysystem/ddl.sql
-- Concatenated in that orchestrator's order. Upstream \c / \ir dropped --
-- provision.sql is already connected to mosip_mockidentitysystem.
-- ============================================================================

-- ---------- ddl/mockidentitysystem-mock_identity.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: mosip_mockidentitysystem
-- Table Name : mock_identity
-- Purpose    : To store mock Identity
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE mockidentitysystem.mock_identity(
	individual_id VARCHAR(36) NOT NULL,
	identity_json VARCHAR NOT NULL,
    CONSTRAINT pk_mock_id_code PRIMARY KEY (individual_id)
);

-- ---------- ddl/mockidentitysystem-kyc_auth.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: mosip_mockidentitysystem
-- Table Name : kyc_auth
-- Purpose    : To store authentication data
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE mockidentitysystem.kyc_auth(
    kyc_token VARCHAR(255),
    individual_id VARCHAR(255),
    partner_specific_user_token VARCHAR(255),
    response_time TIMESTAMP,
    transaction_id VARCHAR(255),
    validity INTEGER
);

-- ---------- ddl/mockidentitysystem-key_alias.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: mosip_esignet
-- Table Name : key_alias
-- Purpose    : Key Alias table
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE mockidentitysystem.key_alias(
    id character varying(36) NOT NULL,
    app_id character varying(36) NOT NULL,
    ref_id character varying(128),
    key_gen_dtimes timestamp,
    key_expire_dtimes timestamp,
    status_code character varying(36),
    lang_code character varying(3),
    cr_by character varying(256) NOT NULL,
    cr_dtimes timestamp NOT NULL,
    upd_by character varying(256),
    upd_dtimes timestamp,
    is_deleted boolean DEFAULT FALSE,
    del_dtimes timestamp,
    cert_thumbprint character varying(100),
    uni_ident character varying(50),
    CONSTRAINT pk_keymals_id PRIMARY KEY (id),
    CONSTRAINT uni_ident_const UNIQUE (uni_ident)
);

COMMENT ON TABLE mockidentitysystem.key_alias IS 'Contains key alias and  metadata of all the keys used in MOSIP system.';

COMMENT ON COLUMN mockidentitysystem.key_alias.id IS 'Unique identifier (UUID) used for referencing keys in key_store table and HSM';
COMMENT ON COLUMN mockidentitysystem.key_alias.app_id IS 'To reference a Module key';
COMMENT ON COLUMN mockidentitysystem.key_alias.ref_id IS 'To reference a Encryption key ';
COMMENT ON COLUMN mockidentitysystem.key_alias.key_gen_dtimes IS 'Date and time when the key was generated.';
COMMENT ON COLUMN mockidentitysystem.key_alias.key_expire_dtimes IS 'Date and time when the key will be expired. This will be derived based on the configuration / policy defined in Key policy definition.';
COMMENT ON COLUMN mockidentitysystem.key_alias.status_code IS 'Status of the key, whether it is active or expired.';
COMMENT ON COLUMN mockidentitysystem.key_alias.lang_code IS 'For multilanguage implementation this attribute Refers master.language.code. The value of some of the attributes in current record is stored in this respective language. ';
COMMENT ON COLUMN mockidentitysystem.key_alias.cr_by IS 'ID or name of the user who create / insert record';
COMMENT ON COLUMN mockidentitysystem.key_alias.cr_dtimes IS 'Date and Timestamp when the record is created/inserted';
COMMENT ON COLUMN mockidentitysystem.key_alias.upd_by IS 'ID or name of the user who update the record with new values';
COMMENT ON COLUMN mockidentitysystem.key_alias.upd_dtimes IS 'Date and Timestamp when any of the fields in the record is updated with new values.';
COMMENT ON COLUMN mockidentitysystem.key_alias.is_deleted IS 'Flag to mark whether the record is Soft deleted.';
COMMENT ON COLUMN mockidentitysystem.key_alias.del_dtimes IS 'Date and Timestamp when the record is soft deleted with is_deleted=TRUE';

-- ---------- ddl/mockidentitysystem-key_policy_def.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: mosip_esignet
-- Table Name : key_policy_def
-- Purpose    : Key Policy definition table
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE mockidentitysystem.key_policy_def(
    app_id character varying(36) NOT NULL,
    key_validity_duration smallint,
    is_active boolean NOT NULL,
    pre_expire_days smallint,
    access_allowed character varying(1024),
    cr_by character varying(256) NOT NULL,
    cr_dtimes timestamp NOT NULL,
    upd_by character varying(256),
    upd_dtimes timestamp,
    is_deleted boolean DEFAULT FALSE,
    del_dtimes timestamp,
    CONSTRAINT pk_keypdef_id PRIMARY KEY (app_id)
);
COMMENT ON TABLE mockidentitysystem.key_policy_def IS 'Key Policy Defination: Policy related to encryption key management is defined here. For eg. Expiry duration of a key generated.';
COMMENT ON COLUMN mockidentitysystem.key_policy_def.app_id IS 'Application ID: Application id for which the key policy is defined';
COMMENT ON COLUMN mockidentitysystem.key_policy_def.key_validity_duration IS 'Key Validity Duration: Duration for which key is valid';
COMMENT ON COLUMN mockidentitysystem.key_policy_def.is_active IS 'IS_Active : Flag to mark whether the record is Active or In-active';
COMMENT ON COLUMN mockidentitysystem.key_policy_def.cr_by IS 'Created By : ID or name of the user who create / insert record';
COMMENT ON COLUMN mockidentitysystem.key_policy_def.cr_dtimes IS 'Created DateTimestamp : Date and Timestamp when the record is created/inserted';
COMMENT ON COLUMN mockidentitysystem.key_policy_def.upd_by IS 'Updated By : ID or name of the user who update the record with new values';
COMMENT ON COLUMN mockidentitysystem.key_policy_def.upd_dtimes IS 'Updated DateTimestamp : Date and Timestamp when any of the fields in the record is updated with new values.';
COMMENT ON COLUMN mockidentitysystem.key_policy_def.is_deleted IS 'IS_Deleted : Flag to mark whether the record is Soft deleted.';
COMMENT ON COLUMN mockidentitysystem.key_policy_def.del_dtimes IS 'Deleted DateTimestamp : Date and Timestamp when the record is soft deleted with is_deleted=TRUE';

-- ---------- ddl/mockidentitysystem-key_store.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: mosip_esignet
-- Table Name : key_store
-- Purpose    : Key Store table
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE mockidentitysystem.key_store(
	id character varying(36) NOT NULL,
	master_key character varying(36) NOT NULL,
	private_key character varying(2500) NOT NULL,
	certificate_data character varying NOT NULL,
	cr_by character varying(256) NOT NULL,
	cr_dtimes timestamp NOT NULL,
	upd_by character varying(256),
	upd_dtimes timestamp,
	is_deleted boolean DEFAULT FALSE,
	del_dtimes timestamp,
	CONSTRAINT pk_keystr_id PRIMARY KEY (id)
);

COMMENT ON TABLE mockidentitysystem.key_store IS 'Stores Encryption (Base) private keys along with certificates';
COMMENT ON COLUMN mockidentitysystem.key_store.id IS 'Unique identifier (UUID) for referencing keys';
COMMENT ON COLUMN mockidentitysystem.key_store.master_key IS 'UUID of the master key used to encrypt this key';
COMMENT ON COLUMN mockidentitysystem.key_store.private_key IS 'Encrypted private key';
COMMENT ON COLUMN mockidentitysystem.key_store.certificate_data IS 'X.509 encoded certificate data';
COMMENT ON COLUMN mockidentitysystem.key_store.cr_by IS 'ID or name of the user who create / insert record';
COMMENT ON COLUMN mockidentitysystem.key_store.cr_dtimes IS 'Date and Timestamp when the record is created/inserted';
COMMENT ON COLUMN mockidentitysystem.key_store.upd_by IS 'ID or name of the user who update the record with new values';
COMMENT ON COLUMN mockidentitysystem.key_store.upd_dtimes IS 'Date and Timestamp when any of the fields in the record is updated with new values.';
COMMENT ON COLUMN mockidentitysystem.key_store.is_deleted IS 'Flag to mark whether the record is Soft deleted.';
COMMENT ON COLUMN mockidentitysystem.key_store.del_dtimes IS 'Date and Timestamp when the record is soft deleted with is_deleted=TRUE';

-- ---------- ddl/mockidentitysystem-verified_claim.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: mosip_mockidentitysystem
-- Table Name : verified_claim
-- Purpose    : To store verified claim metadata for individual
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE mockidentitysystem.verified_claim(
    id VARCHAR(100) NOT NULL,
	individual_id VARCHAR(36) NOT NULL,
	claim VARCHAR NOT NULL,
	trust_framework VARCHAR NOT NULL,
	detail VARCHAR,
	cr_by character varying(256) NOT NULL,
    cr_dtimes timestamp NOT NULL,
    upd_by character varying(256),
    upd_dtimes timestamp,
    is_active boolean DEFAULT TRUE,
    CONSTRAINT pk_verified_claim_id PRIMARY KEY (id)
);

-- ---------- ddl/mockidentitysystem-ca_cert_store.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: mosip_mockidentitysystem
-- Table Name : key_alias
-- Purpose    : CA Cert Store Table

CREATE TABLE mockidentitysystem.ca_cert_store(
	cert_id character varying(36) NOT NULL,
	cert_subject character varying(500) NOT NULL,
	cert_issuer character varying(500) NOT NULL,
	issuer_id character varying(36) NOT NULL,
	cert_not_before timestamp,
	cert_not_after timestamp,
	crl_uri character varying(120),
	cert_data character varying,
	cert_thumbprint character varying(100),
	cert_serial_no character varying(50),
	partner_domain character varying(36),
	cr_by character varying(256),
	cr_dtimes timestamp,
	upd_by character varying(256),
	upd_dtimes timestamp,
	is_deleted boolean DEFAULT FALSE,
	del_dtimes timestamp,
	ca_cert_type character varying(25),
	CONSTRAINT pk_cacs_id PRIMARY KEY (cert_id),
	CONSTRAINT cert_thumbprint_unique UNIQUE (cert_thumbprint,partner_domain)
);

COMMENT ON TABLE mockidentitysystem.ca_cert_store IS 'Certificate Authority Certificate Store: Store details of all the certificate provided by certificate authority which will be used by MOSIP';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.cert_id IS 'Certificate ID: Unique ID (UUID) will be generated and assigned to the uploaded CA/Sub-CA certificate';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.cert_subject IS 'Certificate Subject: Subject DN of the certificate';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.cert_issuer IS 'Certificate Issuer: Issuer DN of the certificate';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.issuer_id IS 'Issuer UUID of the certificate. (Issuer certificate should be available in the DB)';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.cert_not_before IS 'Certificate Start Date: Certificate Interval - Validity Start Date & Time';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.cert_not_after IS 'Certificate Validity end Date: Certificate Interval - Validity End Date & Time';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.crl_uri IS 'CRL URL: CRL URI of the issuer.';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.cert_data IS 'Certificate Data: PEM Encoded actual certificate data.';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.cert_thumbprint IS 'Certificate Thumb Print: SHA1 generated certificate thumbprint.';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.cert_serial_no IS 'Certificate Serial No: Serial Number of the certificate.';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.partner_domain IS 'Partner Domain : To add Partner Domain in CA/Sub-CA certificate chain';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.cr_by IS 'Created By : ID or name of the user who create / insert record';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.cr_dtimes IS 'Created DateTimestamp : Date and Timestamp when the record is created/inserted';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.upd_by IS 'Updated By : ID or name of the user who update the record with new values';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.upd_dtimes IS 'Updated DateTimestamp : Date and Timestamp when any of the fields in the record is updated with new values.';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.is_deleted IS 'IS_Deleted : Flag to mark whether the record is Soft deleted.';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.del_dtimes IS 'Deleted DateTimestamp : Date and Timestamp when the record is soft deleted with is_deleted=TRUE';
COMMENT ON COLUMN mockidentitysystem.ca_cert_store.ca_cert_type IS 'CA Certificate Type : Indicates if the certificate is a ROOT or INTERMEDIATE CA certificate';

-- ---------- ddl/mockidentitysystem-partner_data.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: mosip_mockidentitysystem
-- Table Name : partner_data
-- Purpose    : To store relying party data
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE mockidentitysystem.partner_data (
    partner_id character varying(100) NOT NULL,
    client_id character varying(100) NOT NULL,
    public_key text,
    status character varying(50),
    cr_dtimes timestamp NOT NULL,
    CONSTRAINT pk_partner_data_partner_id_client_id PRIMARY KEY (partner_id, client_id)
);

COMMENT ON COLUMN mockidentitysystem.partner_data.public_key IS 'public key of the relying party';
COMMENT ON COLUMN mockidentitysystem.partner_data.status IS 'status of the relying party';
COMMENT ON COLUMN mockidentitysystem.partner_data.cr_dtimes IS 'creation date time of the record';
COMMENT ON TABLE mockidentitysystem.partner_data IS 'To store relying party data';

