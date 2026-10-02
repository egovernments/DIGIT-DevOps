--
-- PostgreSQL database dump
--

-- Dumped from database version 15.8 (Debian 15.8-1.pgdg110+1)
-- Dumped by pg_dump version 15.8 (Debian 15.8-1.pgdg110+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: required_document; Type: TABLE DATA; Schema: BASETENANT; Owner: -
--

INSERT INTO "BASETENANT".required_document (id, certificate_type_id, document_type, document_name, mandatory, description) VALUES ('4bd3601f-4cc8-4808-ab4b-88fe024fbf9f', '9e8dc49e-69b8-4d94-960d-1e0763efb79b', 'ID_CARD_OR_PASSPORT', 'ID Card or Passport', true, 'Government photo ID of the applicant — proof of identity (any one accepted).');
INSERT INTO "BASETENANT".required_document (id, certificate_type_id, document_type, document_name, mandatory, description) VALUES ('720609ce-9b4b-4305-bcda-c7c743db61d9', '9e8dc49e-69b8-4d94-960d-1e0763efb79b', 'PROOF_OF_ADDRESS', 'Proof of Address', true, 'Electricity bill or equivalent — proof of address (any one accepted).');
INSERT INTO "BASETENANT".required_document (id, certificate_type_id, document_type, document_name, mandatory, description) VALUES ('530c6df4-a61f-4f3c-bbbc-a808a8891d4c', '9e8dc49e-69b8-4d94-960d-1e0763efb79b', 'SITE_PLAN', 'Site Plan', true, 'Building Plan — site plan.');
INSERT INTO "BASETENANT".required_document (id, certificate_type_id, document_type, document_name, mandatory, description) VALUES ('32b8d4e5-0ca0-4e8c-a15a-148a174a3f1c', '9e8dc49e-69b8-4d94-960d-1e0763efb79b', 'GROUND_FLOOR_PLAN', 'Ground Floor Plan', true, 'Building Plan — ground floor plan.');
INSERT INTO "BASETENANT".required_document (id, certificate_type_id, document_type, document_name, mandatory, description) VALUES ('9664846e-f1ac-4e73-8792-9753628f21d7', '9e8dc49e-69b8-4d94-960d-1e0763efb79b', 'SECTION_PLAN', 'Section Plan', true, 'Building Plan — section plan.');
INSERT INTO "BASETENANT".required_document (id, certificate_type_id, document_type, document_name, mandatory, description) VALUES ('82556362-3d7d-4a05-b023-e4d7d9871583', '9e8dc49e-69b8-4d94-960d-1e0763efb79b', 'ELEVATION_PLAN', 'Elevation Plan', true, 'Building Plan — elevation plan.');
INSERT INTO "BASETENANT".required_document (id, certificate_type_id, document_type, document_name, mandatory, description) VALUES ('7e25a966-ab6a-4b39-8211-1089b7c90978', '9e8dc49e-69b8-4d94-960d-1e0763efb79b', 'BUILT_UP_AREA_STATEMENT', 'Built-up Area Statement', true, 'Building Plan — built-up area statement.');
INSERT INTO "BASETENANT".required_document (id, certificate_type_id, document_type, document_name, mandatory, description) VALUES ('07327352-9e69-4b1f-aae9-459eafbbe11a', '9e8dc49e-69b8-4d94-960d-1e0763efb79b', 'FIRE_FIGHTING_SYSTEM_DRAWING', 'Fire-Fighting System Drawing', true, 'Fire-Fighting Plan — schematic drawing of the fire-fighting system.');
INSERT INTO "BASETENANT".required_document (id, certificate_type_id, document_type, document_name, mandatory, description) VALUES ('40566792-b6c4-46d1-aff8-ee0e92ecbbb7', '9e8dc49e-69b8-4d94-960d-1e0763efb79b', 'FIRE_DETECTION_SYSTEM_DRAWING', 'Fire-Detection System Drawing', true, 'Fire-Fighting Plan — schematic drawing of the fire-detecting system.');
INSERT INTO "BASETENANT".required_document (id, certificate_type_id, document_type, document_name, mandatory, description) VALUES ('8a5bbf20-5327-41f5-94b4-1779aa4f734b', '9e8dc49e-69b8-4d94-960d-1e0763efb79b', 'OWNERS_FIRE_SAFETY_CHECKLIST', 'Owner''s Fire and Life Safety Checklist', true, 'Fire and life safety checklist, signed by the property owner.');
INSERT INTO "BASETENANT".required_document (id, certificate_type_id, document_type, document_name, mandatory, description) VALUES ('677eec41-6398-4013-829e-22443e77d725', '7773e2ed-3f90-4b97-b3c4-3bcc79e05ecf', 'REGISTRATION_DOCUMENT', 'Business Registration Certificate', true, 'Business registration certificate.');
INSERT INTO "BASETENANT".required_document (id, certificate_type_id, document_type, document_name, mandatory, description) VALUES ('42cac603-834e-4dfc-b7ca-67850beb7852', '7773e2ed-3f90-4b97-b3c4-3bcc79e05ecf', 'PROOF_OF_BUSINESS_LOCATION', 'Proof of Business Location', true, 'Rent agreement, deed or utility bill.');
INSERT INTO "BASETENANT".required_document (id, certificate_type_id, document_type, document_name, mandatory, description) VALUES ('b7b2b136-9894-4552-8e12-5909bbf53a23', '7773e2ed-3f90-4b97-b3c4-3bcc79e05ecf', 'ID_CARD_OR_PASSPORT', 'ID Card or Passport', true, 'Government photo ID of the licence holder.');
INSERT INTO "BASETENANT".required_document (id, certificate_type_id, document_type, document_name, mandatory, description) VALUES ('64629058-a4fc-4881-957c-0ba3cd06f724', '7773e2ed-3f90-4b97-b3c4-3bcc79e05ecf', 'TAX_COMPLIANCE_CERTIFICATE', 'Tax Compliance Certificate', true, 'Proof of tax compliance.');


--
-- PostgreSQL database dump complete
--

