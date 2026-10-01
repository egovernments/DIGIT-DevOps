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
-- Data for Name: certificate_type; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.certificate_type (id, code, name, description, sector, instrument_type, allowed_issue_type, validity_mode, validity_period_days, max_validity_period_days, grace_period_days, is_active, submission_verification_mode, id_format_config, eligibility_criteria, category_config, boundary_config, config_version, is_latest, version, created_by, created_time, last_modified_by, last_modified_time, is_template, is_renewable, auto_approve, template_code) VALUES ('a86fbdb2-fbe2-4bbd-a40f-53aae02a36cc', 'BUSINESS_LICENSE', 'Business License', NULL, 'TRADE', 'LICENSE', 'BOTH', 'FIXED', 365, NULL, 30, true, 'NONE', NULL, NULL, NULL, NULL, 1, true, 0, NULL, '2026-09-01 10:57:36.877611+00', NULL, '2026-09-01 10:57:36.877611+00', true, true, false, NULL);
INSERT INTO public.certificate_type (id, code, name, description, sector, instrument_type, allowed_issue_type, validity_mode, validity_period_days, max_validity_period_days, grace_period_days, is_active, submission_verification_mode, id_format_config, eligibility_criteria, category_config, boundary_config, config_version, is_latest, version, created_by, created_time, last_modified_by, last_modified_time, is_template, is_renewable, auto_approve, template_code) VALUES ('7b523085-53c5-445c-bd6e-78c08d580fde', 'FIRE_NOC', 'Fire NOC', NULL, 'OTHER', 'NOC', 'BOTH', 'FIXED', 365, NULL, 30, true, 'NONE', NULL, NULL, NULL, NULL, 1, true, 0, NULL, '2026-09-01 10:57:36.877611+00', NULL, '2026-09-01 10:57:36.877611+00', true, true, false, NULL);
INSERT INTO public.certificate_type (id, code, name, description, sector, instrument_type, allowed_issue_type, validity_mode, validity_period_days, max_validity_period_days, grace_period_days, is_active, submission_verification_mode, id_format_config, eligibility_criteria, category_config, boundary_config, config_version, is_latest, version, created_by, created_time, last_modified_by, last_modified_time, is_template, is_renewable, auto_approve, template_code) VALUES ('1f61b292-47ad-41a6-801c-870c6d12c367', 'LEARNER_LICENSE', 'Learner License', NULL, 'TRANSPORT', 'LICENSE', 'INDIVIDUAL', 'FIXED', 365, NULL, 30, true, 'NONE', NULL, NULL, NULL, NULL, 1, true, 0, NULL, '2026-09-01 10:57:36.877611+00', NULL, '2026-09-01 10:57:36.877611+00', true, true, false, NULL);


--
-- PostgreSQL database dump complete
--

