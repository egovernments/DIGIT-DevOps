-- ============================================================================
-- eSignet schema DDL
--
-- VENDORED VERBATIM from mosip/esignet @ v1.8.0 (8f662ca6c070)
--   db_scripts/mosip_esignet/ddl.sql
-- Files concatenated in the order that orchestrator specifies -- the order
-- matters, foreign keys depend on it. Do not reorder or edit the SQL; to
-- update, re-vendor from the matching upstream tag.
--
-- The upstream \c and \ir directives are dropped: this file is \ir'd from
-- provision.sql, which is already connected to mosip_esignet.
-- ============================================================================

-- ---------- ddl/esignet-client_detail.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: mosip_esignet
-- Table Name : client_detail
-- Purpose    : Client Detail: Table to store all registered OIDC client details.
--           
-- Create By   	: Anusha S E
-- Created Date	: Aug-2022
-- 
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------

-- object: client_detail.client_detail | type: TABLE --

CREATE TABLE client_detail(
	id varchar(100) NOT NULL,
	name varchar(600) NOT NULL,
	rp_id varchar(100) NOT NULL,
	logo_uri varchar(2048) NOT NULL,
	redirect_uris varchar(2048) NOT NULL,
	claims varchar(2048) NOT NULL,
	acr_values varchar(1024) NOT NULL,
	public_key varchar(1024) NOT NULL,
	public_key_hash varchar(128) NOT NULL,
	enc_public_key varchar(1024),
	enc_public_key_hash varchar(128),
	enc_public_key_cert varchar(4000),
	grant_types varchar(512) NOT NULL,
	auth_methods varchar(512) NOT NULL,
	status varchar(20) NOT NULL,
	additional_config varchar(2048),
	cr_dtimes timestamp NOT NULL,
	upd_dtimes timestamp,
	CONSTRAINT pk_clntdtl_id PRIMARY KEY (id),
	CONSTRAINT uk_clntdtl_public_key_hash UNIQUE (public_key_hash)
);

-- COMMENT ON TABLE client_detail IS 'Contains key alias and  metadata of all the keys used in MOSIP system.';
-- COMMENT ON COLUMN client_detail.id IS 'Client ID: Unique id assigned to registered OIDC client.';
-- COMMENT ON COLUMN client_detail.name IS 'Client Name: Registered name of OIDC client.';
-- COMMENT ON COLUMN client_detail.logo_uri IS 'Client Logo URL: Client logo to be displayed on IDP UI.';
-- COMMENT ON COLUMN client_detail.redirect_uris IS 'Recirect URLS: Comma separated client redirect URLs.';
-- COMMENT ON COLUMN client_detail.rp_id IS 'relying Party Id: Id of the relying Party who has created this OIDC client.';
-- COMMENT ON COLUMN client_detail.status IS 'Client status: Allowed values - ACTIVE / INACTIVE.';
-- COMMENT ON COLUMN client_detail.public_key IS 'Public key: JWK format.';
-- COMMENT ON COLUMN client_detail.public_key_hash IS 'Public key hash: SHA-256 hash of some fields of the public key for unique public key check.';
-- COMMENT ON COLUMN client_detail.enc_public_key IS 'Encryption Public key: JWK format of the encryption public key for encryption of userinfo response.';
-- COMMENT ON COLUMN client_detail.enc_public_key_hash IS 'Encryption Public key hash: SHA-256 hash of some fields of the encryption public key for unique encryption public key check.';
-- COMMENT ON COLUMN client_detail.enc_public_key_cert IS 'Encryption Public key certificate: PEM format of the encryption public key as crypto-manager service requires the encryption key as a certificate.';
-- COMMENT ON COLUMN client_detail.grant_types IS 'Grant Types: Allowed grant types for the client, comma separated string.';
-- COMMENT ON COLUMN client_detail.auth_methods IS 'Client Auth methods: Allowed token endpoint authentication methods, comma separated string.';
-- COMMENT ON COLUMN client_detail.claims IS 'Requested Claims: claims json as per policy defined for relying party, comma separated string.';
-- COMMENT ON COLUMN client_detail.acr_values IS 'Allowed Authentication context References(acr), comma separated string.';
-- COMMENT ON COLUMN client_detail.cr_dtimes IS 'Created DateTimestamp : Date and Timestamp when the record is created/inserted';
-- COMMENT ON COLUMN client_detail.upd_dtimes IS 'Updated DateTimestamp : Date and Timestamp when any of the fields in the record is updated with new values.';

-- ---------- ddl/esignet-key_alias.sql ----------
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
CREATE TABLE key_alias(
    id varchar(36) NOT NULL,
    app_id varchar(36) NOT NULL,
    ref_id varchar(128),
    key_gen_dtimes timestamp,
    key_expire_dtimes timestamp,
    status_code varchar(36),
    lang_code varchar(3),
    cr_by varchar(256) NOT NULL,
    cr_dtimes timestamp NOT NULL,
    upd_by varchar(256),
    upd_dtimes timestamp,
    is_deleted boolean DEFAULT FALSE,
    del_dtimes timestamp,
    cert_thumbprint varchar(100),
    uni_ident varchar(50),
    CONSTRAINT pk_keymals_id PRIMARY KEY (id),
    CONSTRAINT uni_ident_const UNIQUE (uni_ident)
);

-- COMMENT ON TABLE key_alias IS 'Contains key alias and  metadata of all the keys used in MOSIP system.';
-- COMMENT ON COLUMN key_alias.id IS 'Unique identifier (UUID) used for referencing keys in key_store table and HSM';
-- COMMENT ON COLUMN key_alias.app_id IS 'To reference a Module key';
-- COMMENT ON COLUMN key_alias.ref_id IS 'To reference a Encryption key ';
-- COMMENT ON COLUMN key_alias.key_gen_dtimes IS 'Date and time when the key was generated.';
-- COMMENT ON COLUMN key_alias.key_expire_dtimes IS 'Date and time when the key will be expired. This will be derived based on the configuration / policy defined in Key policy definition.';
-- COMMENT ON COLUMN key_alias.status_code IS 'Status of the key, whether it is active or expired.';
-- COMMENT ON COLUMN key_alias.lang_code IS 'For multilanguage implementation this attribute Refers master.language.code. The value of some of the attributes in current record is stored in this respective language. ';
-- COMMENT ON COLUMN key_alias.cr_by IS 'ID or name of the user who create / insert record';
-- COMMENT ON COLUMN key_alias.cr_dtimes IS 'Date and Timestamp when the record is created/inserted';
-- COMMENT ON COLUMN key_alias.upd_by IS 'ID or name of the user who update the record with new values';
-- COMMENT ON COLUMN key_alias.upd_dtimes IS 'Date and Timestamp when any of the fields in the record is updated with new values.';
-- COMMENT ON COLUMN key_alias.is_deleted IS 'Flag to mark whether the record is Soft deleted.';
-- COMMENT ON COLUMN key_alias.del_dtimes IS 'Date and Timestamp when the record is soft deleted with is_deleted=TRUE';

-- ---------- ddl/esignet-key_policy_def.sql ----------
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

CREATE TABLE key_policy_def(
    app_id varchar(36) NOT NULL,
    key_validity_duration smallint,
    is_active boolean NOT NULL,
    pre_expire_days smallint,
    access_allowed varchar(1024),
    cr_by varchar(256) NOT NULL,
    cr_dtimes timestamp NOT NULL,
    upd_by varchar(256),
    upd_dtimes timestamp,
    is_deleted boolean DEFAULT FALSE,
    del_dtimes timestamp,
    CONSTRAINT pk_keypdef_id PRIMARY KEY (app_id)
);

-- COMMENT ON TABLE key_policy_def IS 'Key Policy Defination: Policy related to encryption key management is defined here. For eg. Expiry duration of a key generated.';
-- COMMENT ON COLUMN key_policy_def.app_id IS 'Application ID: Application id for which the key policy is defined';
-- COMMENT ON COLUMN key_policy_def.key_validity_duration IS 'Key Validity Duration: Duration for which key is valid';
-- COMMENT ON COLUMN key_policy_def.is_active IS 'IS_Active : Flag to mark whether the record is Active or In-active';
-- COMMENT ON COLUMN key_policy_def.cr_by IS 'Created By : ID or name of the user who create / insert record';
-- COMMENT ON COLUMN key_policy_def.cr_dtimes IS 'Created DateTimestamp : Date and Timestamp when the record is created/inserted';
-- COMMENT ON COLUMN key_policy_def.upd_by IS 'Updated By : ID or name of the user who update the record with new values';
-- COMMENT ON COLUMN key_policy_def.upd_dtimes IS 'Updated DateTimestamp : Date and Timestamp when any of the fields in the record is updated with new values.';
-- COMMENT ON COLUMN key_policy_def.is_deleted IS 'IS_Deleted : Flag to mark whether the record is Soft deleted.';
-- COMMENT ON COLUMN key_policy_def.del_dtimes IS 'Deleted DateTimestamp : Date and Timestamp when the record is soft deleted with is_deleted=TRUE';

-- ---------- ddl/esignet-key_store.sql ----------
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

CREATE TABLE key_store(
	id varchar(36) NOT NULL,
	master_key varchar(36) NOT NULL,
	private_key varchar(2500) NOT NULL,
	certificate_data varchar(4000) NOT NULL,
	cr_by varchar(256) NOT NULL,
	cr_dtimes timestamp NOT NULL,
	upd_by varchar(256),
	upd_dtimes timestamp,
	is_deleted boolean DEFAULT FALSE,
	del_dtimes timestamp,
	CONSTRAINT pk_keystr_id PRIMARY KEY (id)
);

-- COMMENT ON TABLE key_store IS 'Stores Encryption (Base) private keys along with certificates';
-- COMMENT ON COLUMN key_store.id IS 'Unique identifier (UUID) for referencing keys';
-- COMMENT ON COLUMN key_store.master_key IS 'UUID of the master key used to encrypt this key';
-- COMMENT ON COLUMN key_store.private_key IS 'Encrypted private key';
-- COMMENT ON COLUMN key_store.certificate_data IS 'X.509 encoded certificate data';
-- COMMENT ON COLUMN key_store.cr_by IS 'ID or name of the user who create / insert record';
-- COMMENT ON COLUMN key_store.cr_dtimes IS 'Date and Timestamp when the record is created/inserted';
-- COMMENT ON COLUMN key_store.upd_by IS 'ID or name of the user who update the record with new values';
-- COMMENT ON COLUMN key_store.upd_dtimes IS 'Date and Timestamp when any of the fields in the record is updated with new values.';
-- COMMENT ON COLUMN key_store.is_deleted IS 'Flag to mark whether the record is Soft deleted.';
-- COMMENT ON COLUMN key_store.del_dtimes IS 'Date and Timestamp when the record is soft deleted with is_deleted=TRUE';

-- ---------- ddl/esignet-public_key_registry.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: mosip_esignet
-- Table Name : public_key_registry
-- Purpose    : Public Key Registry: Table to store Id Hash and its respective PSU Token,Public Key and Wallet Binding Id.
--
-- Create By   	: Himaja D
-- Created Date	: Nov-2022
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------

-- object: public_key_registry.public_key_registry | type: TABLE --

CREATE TABLE public_key_registry(
    id_hash varchar(100) NOT NULL,
    auth_factor varchar(25) NOT NULL,
	psu_token varchar(256) NOT NULL,
	public_key varchar(2500) NOT NULL,
	expire_dtimes timestamp NOT NULL,
	wallet_binding_id varchar(256) NOT NULL,
	public_key_hash varchar(100) NOT NULL,
	certificate varchar(4000) NOT NULL,
	cr_dtimes timestamp NOT NULL,
	thumbprint varchar(128) NOT NULL,
	CONSTRAINT pk_public_key_registry PRIMARY KEY (id_hash, auth_factor)
);

-- COMMENT ON TABLE public_key_registry IS 'Contains id_hash and their respective PSU Tokens,public keys and wallet binding ids.';
-- COMMENT ON COLUMN public_key_registry.id_hash IS 'Contains Id hash.';
-- COMMENT ON COLUMN public_key_registry.psu_token IS 'PSU Token: Partner Specific User Token.';
-- COMMENT ON COLUMN public_key_registry.public_key IS 'Public Key: Used to validate JWT signature and encrypt Wallet Binding Id.';
-- COMMENT ON COLUMN public_key_registry.expire_dtimes IS 'Expiry DateTimestamp : Date and Timestamp of the expiry of the binding entry.';
-- COMMENT ON COLUMN public_key_registry.wallet_binding_id IS 'Wallet Binding Id: hash of PSU  Token and salt.';
-- COMMENT ON COLUMN public_key_registry.public_key_hash IS 'Public Key Hash: Hash of  Public Key.';
-- COMMENT ON COLUMN public_key_registry.auth_factor IS 'Supported auth factor type.';
-- COMMENT ON COLUMN public_key_registry.certificate IS 'Signed certificate';
-- COMMENT ON COLUMN public_key_registry.cr_dtimes IS 'Created DateTimestamp : Date and Timestamp when the record is created/inserted.';
-- COMMENT ON COLUMN public_key_registry.thumbprint IS 'Thumbprint generated from the certificate'

-- ---------- ddl/esignet-consent.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: mosip_esignet
-- Table Name : consent_detail
-- Purpose    : To store user consent details
--
-- Create By   	: Hitesh C
-- Created Date	: May-2023
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------

CREATE TABLE consent_detail (
    id VARCHAR(36) NOT NULL,
    client_id VARCHAR(256) NOT NULL,
    psu_token VARCHAR(256) NOT NULL,
    claims VARCHAR(2048) NOT NULL,
    authorization_scopes VARCHAR(1024) NOT NULL,
    cr_dtimes TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expire_dtimes TIMESTAMP,
    signature VARCHAR(1024),
    hash VARCHAR(100),
    accepted_claims VARCHAR(1024),
    permitted_scopes VARCHAR(1024),
    PRIMARY KEY (id),
    CONSTRAINT unique_client_token UNIQUE (client_id, psu_token)
);

CREATE INDEX idx_consent_psu_client ON consent_detail(psu_token, client_id);

-- COMMENT ON TABLE consent_detail IS 'Contains user consent details';
-- COMMENT ON COLUMN consent_detail.id IS 'UUID : Unique id associated with each consent';
-- COMMENT ON COLUMN consent_detail.client_id IS 'Client_id: associated with relying party';
-- COMMENT ON COLUMN consent_detail.psu_token IS 'PSU token associated with user consent';
-- COMMENT ON COLUMN consent_detail.claims IS 'Json of requested and user accepted claims';
-- COMMENT ON COLUMN consent_detail.authorization_scopes IS 'Json string of requested authorization scope';
-- COMMENT ON COLUMN consent_detail.cr_dtimes IS 'Consent creation date';
-- COMMENT ON COLUMN consent_detail.expire_dtimes IS 'Expiration date';
-- COMMENT ON COLUMN consent_detail.signature IS 'Signature of consent object ';
-- COMMENT ON COLUMN consent_detail.hash IS 'hash of consent object';
-- COMMENT ON COLUMN consent_detail.accepted_claims IS 'Accepted Claims by the user';
-- COMMENT ON COLUMN consent_detail.permitted_scopes IS 'Accepted Scopes by the user';

-- ---------- ddl/esignet-consent_history.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: mosip_esignet
-- Table Name : consent_history
-- Purpose    : To store user consent details
--
-- Create By   	: Hitesh C
-- Created Date	: May-2023
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------

CREATE TABLE consent_history (
    id varchar(36) NOT NULL,
    client_id VARCHAR(256) NOT NULL,
    psu_token VARCHAR(256) NOT NULL,
    claims VARCHAR(2048) NOT NULL,
    authorization_scopes VARCHAR(1024) NOT NULL,
    cr_dtimes TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expire_dtimes TIMESTAMP,
    signature VARCHAR(1024),
    hash VARCHAR(100),
    accepted_claims VARCHAR(1024),
    permitted_scopes VARCHAR(1024),
    PRIMARY KEY (id)
);

CREATE INDEX idx_consent_history_psu_client ON consent_history(psu_token, client_id);

-- COMMENT ON TABLE consent_history IS 'Contains user consent details';
-- COMMENT ON COLUMN consent_history.id IS 'UUID : Unique id associated with each consent';
-- COMMENT ON COLUMN consent_history.client_id IS 'Client_id: associated with relying party';
-- COMMENT ON COLUMN consent_history.psu_token IS 'PSU token associated with user consent';
-- COMMENT ON COLUMN consent_history.claims IS 'Json of requested and user accepted claims';
-- COMMENT ON COLUMN consent_history.authorization_scopes IS 'Json string of requested authorization scope';
-- COMMENT ON COLUMN consent_history.cr_dtimes IS 'Consent creation date';
-- COMMENT ON COLUMN consent_history.expire_dtimes IS 'Expiration date';
-- COMMENT ON COLUMN consent_history.signature IS 'Signature of consent object ';
-- COMMENT ON COLUMN consent_history.hash IS 'hash of consent object';
-- COMMENT ON COLUMN consent_history.accepted_claims IS 'Accepted Claims by the user';
-- COMMENT ON COLUMN consent_history.permitted_scopes IS 'Accepted Scopes by the user';

-- ---------- ddl/esignet-ca_cert_store.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: mosip_esignet
-- Table Name : ca_cert_store
-- Purpose    : CA Certificate Store Table

CREATE TABLE ca_cert_store(
	cert_id varchar(36) NOT NULL,
	cert_subject varchar(500) NOT NULL,
	cert_issuer varchar(500) NOT NULL,
	issuer_id varchar(36) NOT NULL,
	cert_not_before timestamp,
	cert_not_after timestamp,
	crl_uri varchar(120),
	cert_data varchar(4000),
	cert_thumbprint varchar(100),
	cert_serial_no varchar(50),
	partner_domain varchar(36),
	cr_by varchar(256),
	cr_dtimes timestamp,
	upd_by varchar(256),
	upd_dtimes timestamp,
	is_deleted boolean DEFAULT FALSE,
	del_dtimes timestamp,
	ca_cert_type varchar(25),
	CONSTRAINT pk_cacs_id PRIMARY KEY (cert_id),
	CONSTRAINT cert_thumbprint_unique UNIQUE (cert_thumbprint,partner_domain)
);

-- COMMENT ON TABLE ca_cert_store IS 'Certificate Authority Certificate Store: Store details of all the certificate provided by certificate authority which will be used by MOSIP';
-- COMMENT ON COLUMN ca_cert_store.cert_id IS 'Certificate ID: Unique ID (UUID) will be generated and assigned to the uploaded CA/Sub-CA certificate';
-- COMMENT ON COLUMN ca_cert_store.cert_subject IS 'Certificate Subject: Subject DN of the certificate';
-- COMMENT ON COLUMN ca_cert_store.cert_issuer IS 'Certificate Issuer: Issuer DN of the certificate';
-- COMMENT ON COLUMN ca_cert_store.issuer_id IS 'Issuer UUID of the certificate. (Issuer certificate should be available in the DB)';
-- COMMENT ON COLUMN ca_cert_store.cert_not_before IS 'Certificate Start Date: Certificate Interval - Validity Start Date & Time';
-- COMMENT ON COLUMN ca_cert_store.cert_not_after IS 'Certificate Validity end Date: Certificate Interval - Validity End Date & Time';
-- COMMENT ON COLUMN ca_cert_store.crl_uri IS 'CRL URL: CRL URI of the issuer.';
-- COMMENT ON COLUMN ca_cert_store.cert_data IS 'Certificate Data: PEM Encoded actual certificate data.';
-- COMMENT ON COLUMN ca_cert_store.cert_thumbprint IS 'Certificate Thumb Print: SHA1 generated certificate thumbprint.';
-- COMMENT ON COLUMN ca_cert_store.cert_serial_no IS 'Certificate Serial No: Serial Number of the certificate.';
-- COMMENT ON COLUMN ca_cert_store.partner_domain IS 'Partner Domain : To add Partner Domain in CA/Sub-CA certificate chain';
-- COMMENT ON COLUMN ca_cert_store.cr_by IS 'Created By : ID or name of the user who create / insert record';
-- COMMENT ON COLUMN ca_cert_store.cr_dtimes IS 'Created DateTimestamp : Date and Timestamp when the record is created/inserted';
-- COMMENT ON COLUMN ca_cert_store.upd_by IS 'Updated By : ID or name of the user who update the record with new values';
-- COMMENT ON COLUMN ca_cert_store.upd_dtimes IS 'Updated DateTimestamp : Date and Timestamp when any of the fields in the record is updated with new values.';
-- COMMENT ON COLUMN ca_cert_store.is_deleted IS 'IS_Deleted : Flag to mark whether the record is Soft deleted.';
-- COMMENT ON COLUMN ca_cert_store.del_dtimes IS 'Deleted DateTimestamp : Date and Timestamp when the record is soft deleted with is_deleted=TRUE';
-- COMMENT ON COLUMN ca_cert_store.ca_cert_type IS 'CA Certificate Type : Indicates if the certificate is a ROOT or INTERMEDIATE CA certificate';

-- ---------- ddl/esignet-server_profile.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: mosip_esignet
-- Table Name : server_profile
-- Purpose    : Server profile: static table to store the profile and feature(as part of profile) mapping
--
-- Create By   	: Md Humair K
-- Created Date	: Nov-2025
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------

-- Table: server_profile
CREATE TABLE IF NOT EXISTS server_profile (
    profile_name VARCHAR(100) NOT NULL,
    feature VARCHAR(100) NOT NULL,
    additional_config_key VARCHAR(200) NOT NULL,
    CONSTRAINT pk_server_profile PRIMARY KEY (profile_name, feature)
);

-- COMMENT ON TABLE server_profile IS 'Static table for global configuration: profile name and feature mapping.';
-- COMMENT ON COLUMN server_profile.profile_name IS 'Profile name for configuration.';
-- COMMENT ON COLUMN server_profile.feature IS 'Feature enabled for the profile.';
-- COMMENT ON COLUMN server_profile.additional_config_key IS 'Additional config key name for the feature.';

