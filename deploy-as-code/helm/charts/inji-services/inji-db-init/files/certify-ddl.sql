-- ============================================================================
-- certify schema DDL
--
-- VENDORED VERBATIM from inji/inji-certify @ v0.13.1 (618684d326a1)
--   db_scripts/inji_certify/ddl.sql
-- Concatenated in that orchestrator's order; foreign keys depend on it.
-- Upstream \c / \ir directives dropped -- provision.sql is already
-- connected to inji_certify when this is included.
-- ============================================================================

-- ---------- ddl/certify-key_alias.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_certify
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

-- ---------- ddl/certify-key_policy_def.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_certify
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

-- ---------- ddl/certify-key_store.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_certify
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

-- ---------- ddl/certify-ca_cert_store.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_certify
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

-- ---------- ddl/certify-rendering_template.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_certify
-- Table Name : rendering_template
-- Purpose    : Svg Template table
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------

CREATE TABLE rendering_template (
    id VARCHAR(128) NOT NULL,
    template VARCHAR NOT NULL,
    cr_dtimes timestamp NOT NULL,
    upd_dtimes timestamp,
    CONSTRAINT pk_rendertmp_id PRIMARY KEY (id)
);

COMMENT ON TABLE rendering_template IS 'SVG Render Template: Contains svg render image for VC.';

COMMENT ON COLUMN rendering_template.id IS 'Template Id: Unique id assigned to save and identify template.';
COMMENT ON COLUMN rendering_template.template IS 'SVG Template Content: SVG Render Image for the VC details.';
COMMENT ON COLUMN rendering_template.cr_dtimes IS 'Date when the template was inserted in table.';
COMMENT ON COLUMN rendering_template.upd_dtimes IS 'Date when the template was last updated in table.';

-- ---------- ddl/certify-credential_config.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_certify
-- Table Name : credential_config
-- Purpose    : Credential Configuration Table
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------

CREATE TABLE credential_config (
    credential_config_key_id VARCHAR(2048) NOT NULL UNIQUE,
    config_id VARCHAR(255) NOT NULL,
    status VARCHAR(255),
    vc_template VARCHAR,
    doctype VARCHAR,
    sd_jwt_vct VARCHAR,
    context VARCHAR,
    credential_type VARCHAR,
    credential_format VARCHAR(255) NOT NULL,
    did_url VARCHAR,
    key_manager_app_id VARCHAR(36),
    key_manager_ref_id VARCHAR(128),
    signature_algo VARCHAR(36),
    signature_crypto_suite VARCHAR(128),
    sd_claim VARCHAR,
    display JSONB NOT NULL,
    display_order TEXT[] NOT NULL,
    scope VARCHAR(255) NOT NULL,
    cryptographic_binding_methods_supported TEXT[] NOT NULL,
    credential_signing_alg_values_supported TEXT[] NOT NULL,
    proof_types_supported JSONB NOT NULL,
    credential_subject JSONB,
    mso_mdoc_claims JSONB,
    sd_jwt_claims JSONB,
    plugin_configurations JSONB,
    credential_status_purpose TEXT[],
    cr_dtimes TIMESTAMP NOT NULL,
    upd_dtimes TIMESTAMP,
    CONSTRAINT pk_config_id PRIMARY KEY (config_id)
);

CREATE UNIQUE INDEX idx_credential_config_type_context_unique
ON credential_config(credential_type, context, credential_format)
WHERE credential_type IS NOT NULL AND credential_type <> ''
AND context IS NOT NULL AND context <> '';

CREATE UNIQUE INDEX idx_credential_config_sd_jwt_vct_unique
ON credential_config(sd_jwt_vct, credential_format)
WHERE sd_jwt_vct IS NOT NULL and sd_jwt_vct <> '';

CREATE UNIQUE INDEX idx_credential_config_doctype_unique
ON credential_config(doctype, credential_format)
WHERE doctype IS NOT NULL and doctype <> '';

COMMENT ON TABLE credential_config IS 'Credential Config: Contains details of credential configuration.';

COMMENT ON COLUMN credential_config.config_id IS 'Credential Config ID: Unique id assigned to save and identify configuration.';
COMMENT ON COLUMN credential_config.status IS 'Credential Config Status: Status of the credential configuration.';
COMMENT ON COLUMN credential_config.vc_template IS 'VC Template: Template used for the verifiable credential.';
COMMENT ON COLUMN credential_config.doctype IS 'Doc Type: Doc Type specifically for Mdoc VC.';
COMMENT ON COLUMN credential_config.sd_jwt_vct IS 'VCT field: VC Type specifically for SD-JWT VC.';
COMMENT ON COLUMN credential_config.context IS 'Context: Array of context URIs for the credential.';
COMMENT ON COLUMN credential_config.credential_type IS 'Credential Type: Array of credential types supported.';
COMMENT ON COLUMN credential_config.credential_format IS 'Credential Format: Format of the credential (e.g., JWT, JSON-LD).';
COMMENT ON COLUMN credential_config.did_url IS 'DID URL: Decentralized Identifier URL for the issuer.';
COMMENT ON COLUMN credential_config.key_manager_app_id IS 'Key Manager App Id: AppId of the keymanager';
COMMENT ON COLUMN credential_config.key_manager_ref_id IS 'Key Manager Reference Id: RefId of the keymanager';
COMMENT ON COLUMN credential_config.signature_algo IS 'Signature Algorithm: This is for VC signature or proof algorithm';
COMMENT ON COLUMN credential_config.sd_claim IS 'SD Claim: This is a comma separated list for selective disclosure';
COMMENT ON COLUMN credential_config.display IS 'Display: Credential Display object';
COMMENT ON COLUMN credential_config.display_order IS 'Display Order: Array defining the order of display elements.';
COMMENT ON COLUMN credential_config.scope IS 'Scope: Authorization scope for the credential.';
COMMENT ON COLUMN credential_config.cryptographic_binding_methods_supported IS 'Cryptographic Binding Methods: Array of supported binding methods.';
COMMENT ON COLUMN credential_config.credential_signing_alg_values_supported IS 'Credential Signing Algorithms: Array of supported signing algorithms.';
COMMENT ON COLUMN credential_config.proof_types_supported IS 'Proof Types: JSON object containing supported proof types and their configurations.';
COMMENT ON COLUMN credential_config.credential_subject IS 'Credential Subject: JSON object containing subject attributes schema.';
COMMENT ON COLUMN credential_config.mso_mdoc_claims IS 'Mso_mdoc Claims: JSON object containing subject attributes schema specifically for MSO-MDOC VC.';
COMMENT ON COLUMN credential_config.sd_jwt_claims IS 'SdJwt Claims: JSON object containing subject attributes schema specifically for SdJwt VC.';
COMMENT ON COLUMN credential_config.plugin_configurations IS 'Plugin Configurations: Array of JSON objects for plugin configurations.';
COMMENT ON COLUMN credential_config.cr_dtimes IS 'Created DateTime: Date and time when the config was inserted in table.';
COMMENT ON COLUMN credential_config.upd_dtimes IS 'Updated DateTime: Date and time when the config was last updated in table.';

-- ---------- ddl/certify-status_list_credential.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_certify
-- Table Name : status_list_credential
-- Purpose    : status_list_credential to store status list credential
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
-- Create ENUM type for credential status
CREATE TYPE credential_status_enum AS ENUM ('AVAILABLE', 'FULL');

-- Create status_list_credential table
CREATE TABLE status_list_credential (
    id VARCHAR(255) PRIMARY KEY,          -- The unique ID (URL/DID/URN) extracted from the VC's 'id' field.
    vc_document VARCHAR NOT NULL,           -- Stores the entire Verifiable Credential JSON document.
    credential_type VARCHAR(100) NOT NULL, -- Type of the status list (e.g., 'StatusList2021Credential')
    status_purpose VARCHAR(100),             -- Intended purpose of this list within the system (e.g., 'revocation', 'suspension', 'general'). NULLABLE.
    capacity_in_kb BIGINT,                        --- length of status list
    credential_status credential_status_enum, -- Use the created ENUM type here
    cr_dtimes timestamp NOT NULL default now(),
    upd_dtimes timestamp                    -- When this VC record was last updated in the system
);

-- Add comments for documentation
COMMENT ON TABLE status_list_credential IS 'Stores full Status List Verifiable Credentials, including their type and intended purpose within the system.';
COMMENT ON COLUMN status_list_credential.id IS 'Unique identifier (URL/DID/URN) of the Status List VC (extracted from vc_document.id). Primary Key.';
COMMENT ON COLUMN status_list_credential.vc_document IS 'The complete JSON document of the Status List Verifiable Credential.';
COMMENT ON COLUMN status_list_credential.credential_type IS 'The type of the Status List credential, often found in vc_document.type (e.g., StatusList2021Credential).';
COMMENT ON COLUMN status_list_credential.status_purpose IS 'The intended purpose assigned to this entire Status List within the system (e.g., revocation, suspension, general). This may be based on convention or system policy, distinct from the credentialStatus.statusPurpose used by individual credentials.';
COMMENT ON COLUMN status_list_credential.cr_dtimes IS 'Timestamp when this Status List VC was first added/fetched into the local system.';
COMMENT ON COLUMN status_list_credential.upd_dtimes IS 'Timestamp when this Status List VC record was last updated.';

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_slc_status_purpose ON status_list_credential(status_purpose);
CREATE INDEX IF NOT EXISTS idx_slc_credential_type ON status_list_credential(credential_type);
CREATE INDEX IF NOT EXISTS idx_slc_credential_status ON status_list_credential(credential_status);
CREATE INDEX IF NOT EXISTS idx_slc_cr_dtimes ON status_list_credential(cr_dtimes);

-- ---------- ddl/certify-ledger.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_certify
-- Table Name : ledger
-- Purpose    : Ledger to store status list credential entries
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
-- Create ledger table (insert only table, data once added will not be updated)
CREATE TABLE ledger (
    id SERIAL PRIMARY KEY,                          -- Auto-incrementing serial primary key
    credential_id VARCHAR(255),            -- Unique ID of the Verifiable Credential WHOSE STATUS IS BEING TRACKED
    issuer_id VARCHAR(255) NOT NULL,                -- Issuer of the TRACKED credential
    issuance_date TIMESTAMP NOT NULL,                -- Issuance date of the TRACKED credential
    expiration_date TIMESTAMP,                    -- Expiration date of the TRACKED credential, if any
    credential_type VARCHAR(100) NOT NULL,          -- Type of the TRACKED credential (e.g., 'VerifiableId')
    indexed_attributes JSONB,                       -- Optional searchable attributes from the TRACKED credential
    credential_status_details JSONB NOT NULL DEFAULT '[]'::jsonb,    -- Stores a list of status objects for this credential, defaults to an empty array.
    cr_dtimes TIMESTAMP NOT NULL DEFAULT NOW(),     -- Creation timestamp of this ledger entry for the tracked credential

    -- Constraints
    CONSTRAINT uq_ledger_tracked_credential_id UNIQUE (credential_id), -- Ensure tracked credential_id is unique
    CONSTRAINT ensure_credential_status_details_is_array CHECK (jsonb_typeof(credential_status_details) = 'array') -- Ensure it's always a JSON array
);

-- Add comments for documentation
COMMENT ON TABLE ledger IS 'Stores intrinsic information about tracked Verifiable Credentials and their status history.';
COMMENT ON COLUMN ledger.id IS 'Serial primary key for the ledger table.';
COMMENT ON COLUMN ledger.credential_id IS 'Unique identifier of the Verifiable Credential whose status is being tracked. Must be unique across the table.';
COMMENT ON COLUMN ledger.issuer_id IS 'Identifier of the issuer of the tracked credential.';
COMMENT ON COLUMN ledger.issuance_date IS 'Issuance date of the tracked credential.';
COMMENT ON COLUMN ledger.expiration_date IS 'Expiration date of the tracked credential, if applicable.';
COMMENT ON COLUMN ledger.credential_type IS 'The type(s) of the tracked credential (e.g., VerifiableId, ProofOfEnrollment).';
COMMENT ON COLUMN ledger.indexed_attributes IS 'Stores specific attributes extracted from the tracked credential for optimized searching.';
COMMENT ON COLUMN ledger.credential_status_details IS 'An array of status objects, guaranteed to be a JSON array (list). Defaults to an empty list []. Each object can contain: status_purpose, status_value (boolean), status_list_credential_id, status_list_index, cr_dtimes, upd_dtimes.';
COMMENT ON COLUMN ledger.cr_dtimes IS 'Timestamp of when this ledger record for the tracked credential was created.';

-- Create indexes for ledger
CREATE INDEX IF NOT EXISTS idx_ledger_credential_id ON ledger(credential_id);
CREATE INDEX IF NOT EXISTS idx_ledger_issuer_id ON ledger(issuer_id);
CREATE INDEX IF NOT EXISTS idx_ledger_credential_type ON ledger(credential_type);
CREATE INDEX IF NOT EXISTS idx_ledger_issue_date ON ledger(issuance_date);
CREATE INDEX IF NOT EXISTS idx_ledger_expiration_date ON ledger(expiration_date);
CREATE INDEX IF NOT EXISTS idx_ledger_cr_dtimes ON ledger(cr_dtimes);
CREATE INDEX IF NOT EXISTS idx_gin_ledger_indexed_attrs ON ledger USING GIN (indexed_attributes);
CREATE INDEX IF NOT EXISTS idx_gin_ledger_status_details ON ledger USING GIN (credential_status_details);

-- ---------- ddl/certify-credential_status_transaction.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_certify
-- Table Name : credential_status_transaction
-- Purpose    : Credential Status Transaction Table
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------

-- Create credential_status_transaction table
CREATE TABLE IF NOT EXISTS credential_status_transaction (
    transaction_log_id SERIAL PRIMARY KEY,        -- Unique ID for this transaction log entry
    credential_id VARCHAR(255), -- The ID of the credential this transaction pertains to (should exist in ledger.credential_id)
    status_purpose VARCHAR(100),                  -- The purpose of this status update
    status_value boolean,                         -- The status value (true/false)
    status_list_credential_id VARCHAR(255),       -- The ID of the status list credential involved, if any
    status_list_index BIGINT,                     -- The index on the status list, if any
    cr_dtimes TIMESTAMP NOT NULL DEFAULT NOW(),   -- Creation timestamp
    processed_dtimes TIMESTAMP,                     -- Timestamp when processed by status list batch job
    is_processed BOOLEAN NOT NULL DEFAULT FALSE   -- Indicates if processed by status list batch job
);

-- Add comments for documentation
COMMENT ON TABLE credential_status_transaction IS 'Transaction log for credential status changes and updates.';
COMMENT ON COLUMN credential_status_transaction.transaction_log_id IS 'Serial primary key for the transaction log entry.';
COMMENT ON COLUMN credential_status_transaction.credential_id IS 'The ID of the credential this transaction pertains to (references ledger.credential_id).';
COMMENT ON COLUMN credential_status_transaction.status_purpose IS 'The purpose of this status update (e.g., revocation, suspension).';
COMMENT ON COLUMN credential_status_transaction.status_value IS 'The status value (true for revoked/suspended, false for active).';
COMMENT ON COLUMN credential_status_transaction.status_list_credential_id IS 'The ID of the status list credential involved, if any.';
COMMENT ON COLUMN credential_status_transaction.status_list_index IS 'The index on the status list, if any.';
COMMENT ON COLUMN credential_status_transaction.cr_dtimes IS 'Timestamp when this transaction was created.';
COMMENT ON COLUMN credential_status_transaction.processed_dtimes IS 'Timestamp when this transaction was processed by status list batch job.';
COMMENT ON COLUMN credential_status_transaction.is_processed IS 'Indicates if the transaction has been processed by the status list batch job.';

-- Create indexes for credential_status_transaction
CREATE INDEX IF NOT EXISTS idx_cst_is_processed_created ON certify.credential_status_transaction (is_processed, cr_dtimes);

-- ---------- ddl/certify-status_list_available_indices.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_certify
-- Table Name : status_list_available_indices
-- Purpose    : status_list_available_indices to store status list available indices
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
-- Create status_list_available_indices table
CREATE TABLE status_list_available_indices (
    id SERIAL PRIMARY KEY,                         -- Serial primary key
    status_list_credential_id VARCHAR(255) NOT NULL, -- References status_list_credential.id
    list_index BIGINT NOT NULL,                    -- The numerical index within the status list
    is_assigned BOOLEAN NOT NULL DEFAULT FALSE,   -- Flag indicating if this index has been assigned
    cr_dtimes TIMESTAMP NOT NULL DEFAULT NOW(),   -- Creation timestamp
    upd_dtimes TIMESTAMP,                          -- Update timestamp

    -- Foreign key constraint
    CONSTRAINT fk_status_list_credential
        FOREIGN KEY(status_list_credential_id)
        REFERENCES status_list_credential(id)
        ON DELETE CASCADE -- If a status list credential is deleted, its available index entries are also deleted.
        ON UPDATE CASCADE, -- If the ID of a status list credential changes, update it here too.

    -- Unique constraint to ensure each index within a list is represented only once
    CONSTRAINT uq_list_id_and_index
        UNIQUE (status_list_credential_id, list_index)
);

-- Add comments for documentation
COMMENT ON TABLE status_list_available_indices IS 'Helper table to manage and assign available indices from status list credentials.';
COMMENT ON COLUMN status_list_available_indices.id IS 'Serial primary key for the available index entry.';
COMMENT ON COLUMN status_list_available_indices.status_list_credential_id IS 'Identifier of the status list credential this index belongs to (FK to status_list_credential.id).';
COMMENT ON COLUMN status_list_available_indices.list_index IS 'The numerical index (e.g., 0 to N-1) within the specified status list.';
COMMENT ON COLUMN status_list_available_indices.is_assigned IS 'Flag indicating if this specific index has been assigned (TRUE) or is available (FALSE).';
COMMENT ON COLUMN status_list_available_indices.cr_dtimes IS 'Timestamp when this index entry record was created (typically when the parent status list was populated).';
COMMENT ON COLUMN status_list_available_indices.upd_dtimes IS 'Timestamp when this index entry record was last updated (e.g., when is_assigned changed).';

-- Create indexes for status_list_available_indices
-- Partial index specifically for finding available slots
CREATE INDEX IF NOT EXISTS idx_sla_available_indices
    ON status_list_available_indices (status_list_credential_id, is_assigned, list_index)
    WHERE is_assigned = FALSE;

-- Additional indexes for performance
CREATE INDEX IF NOT EXISTS idx_sla_status_list_credential_id ON status_list_available_indices(status_list_credential_id);
CREATE INDEX IF NOT EXISTS idx_sla_is_assigned ON status_list_available_indices(is_assigned);
CREATE INDEX IF NOT EXISTS idx_sla_list_index ON status_list_available_indices(list_index);
CREATE INDEX IF NOT EXISTS idx_sla_cr_dtimes ON status_list_available_indices(cr_dtimes);

-- ---------- ddl/certify-shedlock.sql ----------
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- -------------------------------------------------------------------------------------------------
-- Database Name: inji_certify
-- Table Name : shedlock
-- Purpose    : Table for managing distributed locks using ShedLock library
--
--
-- Modified Date        Modified By         Comments / Remarks
-- ------------------------------------------------------------------------------------------
-- ------------------------------------------------------------------------------------------
-- Create shedlock table for distributed locking
CREATE TABLE IF NOT EXISTS shedlock (
  name VARCHAR(64),
  lock_until TIMESTAMPTZ(3) NOT NULL,
  locked_at TIMESTAMPTZ(3) NOT NULL,
  locked_by VARCHAR(255) NOT NULL,
  PRIMARY KEY (name)
);

COMMENT ON TABLE shedlock IS 'Table for managing distributed locks using ShedLock library.';
COMMENT ON COLUMN shedlock.name IS 'Unique name of the lock.';
COMMENT ON COLUMN shedlock.lock_until IS 'Timestamp until which the lock is held. NULL if not locked.';
COMMENT ON COLUMN shedlock.locked_at IS 'Timestamp when the lock was acquired. NULL if not locked.';
COMMENT ON COLUMN shedlock.locked_by IS 'Identifier of the node/process that holds the lock. NULL if not locked.';

