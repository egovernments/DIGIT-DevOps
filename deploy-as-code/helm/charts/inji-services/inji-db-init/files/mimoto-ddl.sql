-- ============================================================================
-- mimoto schema DDL
--
-- VENDORED VERBATIM from mosip/mimoto @ v0.20.0 (f426da315047)
--   db_scripts/inji_mimoto/ddl.sql
-- Concatenated in that orchestrator's order; foreign keys depend on it.
-- Upstream \c / \ir directives dropped -- provision.sql is already
-- connected to inji_mimoto when this is included.
-- ============================================================================

-- ---------- ddl/mimoto-key_alias.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_mimoto
-- Table Name : key_alias
-- Purpose    : Key Alias table
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE key_alias(
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

COMMENT ON TABLE key_alias IS 'Contains key alias and  metadata of all the keys used in MOSIP system.';

COMMENT ON COLUMN key_alias.id IS 'Unique identifier (UUID) used for referencing keys in key_store table and HSM';
COMMENT ON COLUMN key_alias.app_id IS 'To reference a Module key';
COMMENT ON COLUMN key_alias.ref_id IS 'To reference a Encryption key ';
COMMENT ON COLUMN key_alias.key_gen_dtimes IS 'Date and time when the key was generated.';
COMMENT ON COLUMN key_alias.key_expire_dtimes IS 'Date and time when the key will be expired. This will be derived based on the configuration / policy defined in Key policy definition.';
COMMENT ON COLUMN key_alias.status_code IS 'Status of the key, whether it is active or expired.';
COMMENT ON COLUMN key_alias.lang_code IS 'For multilanguage implementation this attribute Refers master.language.code. The value of some of the attributes in current record is stored in this respective language. ';
COMMENT ON COLUMN key_alias.cr_by IS 'ID or name of the user who create / insert record';
COMMENT ON COLUMN key_alias.cr_dtimes IS 'Date and Timestamp when the record is created/inserted';
COMMENT ON COLUMN key_alias.upd_by IS 'ID or name of the user who update the record with new values';
COMMENT ON COLUMN key_alias.upd_dtimes IS 'Date and Timestamp when any of the fields in the record is updated with new values.';
COMMENT ON COLUMN key_alias.is_deleted IS 'Flag to mark whether the record is Soft deleted.';
COMMENT ON COLUMN key_alias.del_dtimes IS 'Date and Timestamp when the record is soft deleted with is_deleted=TRUE';

-- ---------- ddl/mimoto-key_policy_def.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_mimoto
-- Table Name : key_policy_def
-- Purpose    : Key Policy definition table
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE key_policy_def(
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
COMMENT ON TABLE key_policy_def IS 'Key Policy Defination: Policy related to encryption key management is defined here. For eg. Expiry duration of a key generated.';
COMMENT ON COLUMN key_policy_def.app_id IS 'Application ID: Application id for which the key policy is defined';
COMMENT ON COLUMN key_policy_def.key_validity_duration IS 'Key Validity Duration: Duration for which key is valid';
COMMENT ON COLUMN key_policy_def.is_active IS 'IS_Active : Flag to mark whether the record is Active or In-active';
COMMENT ON COLUMN key_policy_def.cr_by IS 'Created By : ID or name of the user who create / insert record';
COMMENT ON COLUMN key_policy_def.cr_dtimes IS 'Created DateTimestamp : Date and Timestamp when the record is created/inserted';
COMMENT ON COLUMN key_policy_def.upd_by IS 'Updated By : ID or name of the user who update the record with new values';
COMMENT ON COLUMN key_policy_def.upd_dtimes IS 'Updated DateTimestamp : Date and Timestamp when any of the fields in the record is updated with new values.';
COMMENT ON COLUMN key_policy_def.is_deleted IS 'IS_Deleted : Flag to mark whether the record is Soft deleted.';
COMMENT ON COLUMN key_policy_def.del_dtimes IS 'Deleted DateTimestamp : Date and Timestamp when the record is soft deleted with is_deleted=TRUE';

-- ---------- ddl/mimoto-key_store.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_mimoto
-- Table Name : key_store
-- Purpose    : Key Store table
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE key_store(
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

COMMENT ON TABLE key_store IS 'Stores Encryption (Base) private keys along with certificates';
COMMENT ON COLUMN key_store.id IS 'Unique identifier (UUID) for referencing keys';
COMMENT ON COLUMN key_store.master_key IS 'UUID of the master key used to encrypt this key';
COMMENT ON COLUMN key_store.private_key IS 'Encrypted private key';
COMMENT ON COLUMN key_store.certificate_data IS 'X.509 encoded certificate data';
COMMENT ON COLUMN key_store.cr_by IS 'ID or name of the user who create / insert record';
COMMENT ON COLUMN key_store.cr_dtimes IS 'Date and Timestamp when the record is created/inserted';
COMMENT ON COLUMN key_store.upd_by IS 'ID or name of the user who update the record with new values';
COMMENT ON COLUMN key_store.upd_dtimes IS 'Date and Timestamp when any of the fields in the record is updated with new values.';
COMMENT ON COLUMN key_store.is_deleted IS 'Flag to mark whether the record is Soft deleted.';
COMMENT ON COLUMN key_store.del_dtimes IS 'Date and Timestamp when the record is soft deleted with is_deleted=TRUE';

-- ---------- ddl/mimoto-ca_cert_store.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_mimoto
-- Table Name : ca_cert_store
-- Purpose    : Key Store table
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE ca_cert_store(
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
COMMENT ON TABLE ca_cert_store IS 'Certificate Authority Certificate Store: Store details of all the certificate provided by certificate authority which will be used by MOSIP';
COMMENT ON COLUMN ca_cert_store.cert_id IS 'Certificate ID: Unique ID (UUID) will be generated and assigned to the uploaded CA/Sub-CA certificate';
COMMENT ON COLUMN ca_cert_store.cert_subject IS 'Certificate Subject: Subject DN of the certificate';
COMMENT ON COLUMN ca_cert_store.cert_issuer IS 'Certificate Issuer: Issuer DN of the certificate';
COMMENT ON COLUMN ca_cert_store.issuer_id IS 'Issuer UUID of the certificate. (Issuer certificate should be available in the DB)';
COMMENT ON COLUMN ca_cert_store.cert_not_before IS 'Certificate Start Date: Certificate Interval - Validity Start Date & Time';
COMMENT ON COLUMN ca_cert_store.cert_not_after IS 'Certificate Validity end Date: Certificate Interval - Validity End Date & Time';
COMMENT ON COLUMN ca_cert_store.crl_uri IS 'CRL URL: CRL URI of the issuer.';
COMMENT ON COLUMN ca_cert_store.cert_data IS 'Certificate Data: PEM Encoded actual certificate data.';
COMMENT ON COLUMN ca_cert_store.cert_thumbprint IS 'Certificate Thumb Print: SHA1 generated certificate thumbprint.';
COMMENT ON COLUMN ca_cert_store.cert_serial_no IS 'Certificate Serial No: Serial Number of the certificate.';
COMMENT ON COLUMN ca_cert_store.partner_domain IS 'Partner Domain : To add Partner Domain in CA/Sub-CA certificate chain';
COMMENT ON COLUMN ca_cert_store.cr_by IS 'Created By : ID or name of the user who create / insert record';
COMMENT ON COLUMN ca_cert_store.cr_dtimes IS 'Created DateTimestamp : Date and Timestamp when the record is created/inserted';
COMMENT ON COLUMN ca_cert_store.upd_by IS 'Updated By : ID or name of the user who update the record with new values';
COMMENT ON COLUMN ca_cert_store.upd_dtimes IS 'Updated DateTimestamp : Date and Timestamp when any of the fields in the record is updated with new values.';
COMMENT ON COLUMN ca_cert_store.is_deleted IS 'IS_Deleted : Flag to mark whether the record is Soft deleted.';
COMMENT ON COLUMN ca_cert_store.del_dtimes IS 'Deleted DateTimestamp : Date and Timestamp when the record is soft deleted with is_deleted=TRUE';
COMMENT ON COLUMN ca_cert_store.ca_cert_type IS 'CA Certificate Type : Indicates if the certificate is a ROOT or INTERMEDIATE CA certificate';

-- ---------- ddl/mimoto-user_metadata.sql ----------
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_mimoto
-- Table Name : user_metadata
-- Purpose    : User Metadata table
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS user_metadata (
    id character varying(36) PRIMARY KEY,  -- Primary key for the table
    provider_subject_id character varying(255) NOT NULL,  -- Unique identifier for the provider subject
    identity_provider character varying(255) NOT NULL,  -- Unique identifier for the identity provider
    display_name TEXT NOT NULL,  -- Display name of the user
    profile_picture_url TEXT,  -- URL of the user's profile picture
    phone_number TEXT,  -- Phone number of the user
    email TEXT NOT NULL,  -- Email of the user (Required field)
    created_at TIMESTAMP DEFAULT now(),  -- Timestamp of record creation (defaults to current time)
    updated_at TIMESTAMP DEFAULT now()  -- Timestamp of last update (defaults to current time)
);

COMMENT ON TABLE user_metadata IS 'User Metadata: Contains details about the user such as identity provider, contact details, and display name';

COMMENT ON COLUMN user_metadata.id IS 'Primary Key: Unique identifier for the user metadata';
COMMENT ON COLUMN user_metadata.provider_subject_id IS 'Provider Subject ID: Unique identifier for the subject assigned by the identity provider';
COMMENT ON COLUMN user_metadata.identity_provider IS 'Identity Provider: The identity provider associated with the user';
COMMENT ON COLUMN user_metadata.display_name IS 'Display Name: Name of the user';
COMMENT ON COLUMN user_metadata.profile_picture_url IS 'Profile Picture URL: The URL link to the user''s profile picture';
COMMENT ON COLUMN user_metadata.phone_number IS 'Phone Number: User''s phone number, if available';
COMMENT ON COLUMN user_metadata.email IS 'Email: User''s email address';
COMMENT ON COLUMN user_metadata.created_at IS 'Created At: The date and time when the metadata was created';
COMMENT ON COLUMN user_metadata.updated_at IS 'Updated At: The date and time when the metadata was last updated';

-- ---------- ddl/mimoto-wallet.sql ----------
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_mimoto
-- Table Name : wallet
-- Purpose    : Wallet Information table for user, encrypted with AES256-GCM, including key metadata
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS wallet (
    id character varying(36) PRIMARY KEY,  -- Primary key for the table
    user_id character varying(36) NOT NULL,  -- Foreign key referencing user_metadata
    wallet_key TEXT NOT NULL,  -- Encrypted wallet key (retained here)
    wallet_metadata JSONB NOT NULL,  -- Metadata about the wallet, including encryption info
    created_at TIMESTAMP DEFAULT now(),  -- Timestamp of record creation (defaults to current time)
    updated_at TIMESTAMP DEFAULT now(),  -- Timestamp of last update (defaults to current time)

    CONSTRAINT fk_user_id FOREIGN KEY (user_id) REFERENCES user_metadata (id) ON DELETE CASCADE
);

COMMENT ON TABLE wallet IS 'Wallet: Contains general information about the user''s wallet and metadata';
COMMENT ON COLUMN wallet.id IS 'Primary Key: Unique identifier for the wallet';
COMMENT ON COLUMN wallet.user_id IS 'User ID: Foreign key referring to the user_metadata table';
COMMENT ON COLUMN wallet.wallet_key IS 'Wallet Key: Encrypted wallet key used to encrypt secret keys in wallet_keys';
COMMENT ON COLUMN wallet.wallet_metadata IS 'Wallet Metadata: Contains information about the wallet, including encryption and PIN usage';
COMMENT ON COLUMN wallet.created_at IS 'Created At: The date and time when the wallet was created';
COMMENT ON COLUMN wallet.updated_at IS 'Updated At: The date and time when the wallet was last updated';

-- ---------- ddl/mimoto-proof_signing_keys.sql ----------
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_mimoto
-- Table Name : proof_signing_key
-- Purpose    : Stores wallet key-related information, including encrypted secret keys and metadata
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- 2025-03-27          User                 Initial table creation, referencing wallet for proof_signing_key encryption
-- ------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS proof_signing_key (
    id character varying(36) PRIMARY KEY,  -- Primary key for the table
    wallet_id character varying(36) NOT NULL,  -- Foreign key referencing the wallet table
    public_key TEXT NOT NULL,  -- Public key for wallet
    secret_key TEXT NOT NULL,  -- Secret key, encrypted using proof_signing_key
    key_metadata JSONB NOT NULL,  -- Metadata about the public and private keys
    created_at TIMESTAMP DEFAULT now(),  -- Timestamp of record creation (defaults to current time)
    updated_at TIMESTAMP DEFAULT now(),  -- Timestamp of last update (defaults to current time)

    CONSTRAINT fk_wallet_id FOREIGN KEY (wallet_id) REFERENCES wallet (id) ON DELETE CASCADE
);

COMMENT ON TABLE proof_signing_key IS 'Wallet Keys: Contains information about the wallet keys, including encrypted keys and metadata';
COMMENT ON COLUMN proof_signing_key.id IS 'Primary Key: Unique identifier for the key';
COMMENT ON COLUMN proof_signing_key.wallet_id IS 'Wallet ID: Foreign key referring to the wallet table';
COMMENT ON COLUMN proof_signing_key.public_key IS 'Public Key: The public key of the wallet';
COMMENT ON COLUMN proof_signing_key.secret_key IS 'Secret Key: Encrypted using the proof_signing_key from wallet table';
COMMENT ON COLUMN proof_signing_key.key_metadata IS 'Key Metadata: Contains additional information about the public and private keys';
COMMENT ON COLUMN proof_signing_key.created_at IS 'Created At: The date and time when the key information was created';
COMMENT ON COLUMN proof_signing_key.updated_at IS 'Updated At: The date and time when the key information was last updated';

-- ---------- ddl/mimoto-verifiable_credentials.sql ----------
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_mimoto
-- Table Name : verifiable_credentials
-- Purpose    : Stores verifiable credentials related to the user, encrypted with wallet_key
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS verifiable_credentials (
    id character varying(36) PRIMARY KEY,  -- Primary key for the table
    wallet_id character varying(36) NOT NULL,  -- Foreign key referring to the wallet table (wallet.id)
    credential TEXT NOT NULL,  -- Encrypted credential (using wallet_key for encryption/decryption)
    credential_metadata JSONB NOT NULL,  -- Metadata about the credential
    created_at TIMESTAMP DEFAULT now(),  -- Timestamp of record creation (defaults to current time)
    updated_at TIMESTAMP DEFAULT now(),  -- Timestamp of last update (defaults to current time)

    CONSTRAINT fk_wallet_id FOREIGN KEY (wallet_id) REFERENCES wallet (id) ON DELETE CASCADE
);

COMMENT ON TABLE verifiable_credentials IS 'Verifiable Credentials: Contains user credentials, encrypted using wallet key';
COMMENT ON COLUMN verifiable_credentials.id IS 'Primary Key: Unique identifier for the verifiable credential record';
COMMENT ON COLUMN verifiable_credentials.wallet_id IS 'Wallet ID: Foreign key referring to the wallet table, linked to the user''s wallet';
COMMENT ON COLUMN verifiable_credentials.credential IS 'Credential: Encrypted credential using the wallet''s key';
COMMENT ON COLUMN verifiable_credentials.credential_metadata IS 'Credential Metadata: Additional information about the credential (e.g., issuer, claims)';
COMMENT ON COLUMN verifiable_credentials.created_at IS 'Created At: The date and time when the credential was created';
COMMENT ON COLUMN verifiable_credentials.updated_at IS 'Updated At: The date and time when the credential was last updated';

-- ---------- ddl/mimoto-trusted-verifiers.sql ----------
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_mimoto
-- Table Name : trusted_verifiers
-- Purpose    : Stores trusted verifiers associated with a user's wallet
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS trusted_verifiers (
    id character varying(36) PRIMARY KEY,  -- Primary key for the table
    wallet_id character varying(36) NOT NULL,  -- Foreign key referring to the wallet table (wallet.id)
    verifier_id character varying(255) NOT NULL,  -- Stores the unique identifier (client_id) of the trusted verifier
    created_at TIMESTAMP DEFAULT now()  -- Timestamp of record creation (defaults to current time)
);

COMMENT ON TABLE trusted_verifiers IS 'Trusted Verifiers: Contains information about verifiers trusted by a user''s wallet';

COMMENT ON COLUMN trusted_verifiers.id IS 'Primary Key: Unique identifier for the trusted verifier record';
COMMENT ON COLUMN trusted_verifiers.wallet_id IS 'Wallet ID: Foreign key referring to the wallet table, linking the verifier to a specific wallet';
COMMENT ON COLUMN trusted_verifiers.verifier_id IS 'Verifier ID: Unique identifier (client_id) of the trusted verifier';
COMMENT ON COLUMN trusted_verifiers.created_at IS 'Created At: The date and time when the trusted verifier record was created';

-- ---------- ddl/mimoto-verifiable_presentations.sql ----------
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_mimoto
-- Table Name : verifiable_presentations
-- Purpose    : Stores records of verifiable presentations submitted by a wallet to a verifier
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS verifiable_presentations (
    id character varying(36) PRIMARY KEY,               -- Primary key for the presentation record (use presentationId)
    wallet_id character varying(36) NOT NULL,           -- Foreign key referring to the wallet table (wallet.id)
    auth_request JSONB NOT NULL,                        -- Verifier's authorization request payload (as JSON)
    presentation_data JSONB NOT NULL,                   -- Additional metadata including shared credential ids
    verifier_id character varying(255),                 -- Verifier identifier (e.g., client_id)
    status character varying(32) NOT NULL,              -- Submission status: in-progress/success/error
    requested_at TIMESTAMP,                             -- Verifier request timestamp
    created_at TIMESTAMP DEFAULT now(),                 -- Submission timestamp (defaults to current time)
    consent BOOLEAN NOT NULL DEFAULT TRUE,              -- User consent flag

    CONSTRAINT fk_vp_wallet_id FOREIGN KEY (wallet_id) REFERENCES wallet (id) ON DELETE CASCADE
);

COMMENT ON TABLE verifiable_presentations IS 'Verifiable Presentations: Records of presentations shared with verifiers';
COMMENT ON COLUMN verifiable_presentations.id IS 'Primary Key: Unique identifier for the presentation (presentationId)';
COMMENT ON COLUMN verifiable_presentations.wallet_id IS 'Wallet ID: Foreign key referring to the wallet table';
COMMENT ON COLUMN verifiable_presentations.auth_request IS 'Authorization Request: The authorization request payload from the verifier';
COMMENT ON COLUMN verifiable_presentations.presentation_data IS 'Presentation Data: Additional metadata including shared credential ids';
COMMENT ON COLUMN verifiable_presentations.verifier_id IS 'Verifier Identifier: The verifier''s client_id or equivalent identifier';
COMMENT ON COLUMN verifiable_presentations.status IS 'Status: in-progress/success/error';
COMMENT ON COLUMN verifiable_presentations.requested_at IS 'Requested At: Timestamp when verifier requested the presentation';
COMMENT ON COLUMN verifiable_presentations.created_at IS 'Created At: Timestamp when the submission record was created';
COMMENT ON COLUMN verifiable_presentations.consent IS 'Consent: Indicates whether user consented to sharing';

