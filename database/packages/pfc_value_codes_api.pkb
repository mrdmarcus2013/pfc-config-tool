CREATE OR REPLACE PACKAGE BODY pfc_value_codes_api AS
    TYPE t_engine_result IS RECORD (
        status                  VARCHAR2(20),
        display_label           VARCHAR2(200),
        pfc_guid                VARCHAR2(36),
        billing_form_code       VARCHAR2(10),
        source_guid             VARCHAR2(36),
        target_action           VARCHAR2(30),
        current_matches_source  VARCHAR2(1),
        current_matches_desired VARCHAR2(1),
        existing_her_count      PLS_INTEGER,
        existing_hef_count      PLS_INTEGER,
        state_hash              VARCHAR2(64)
    );

    FUNCTION saved_lob (
        p_payor_guid IN payors.payor_guid%TYPE,
        p_lock       IN VARCHAR2
    ) RETURN pfc_value_codes.t_line_of_business
    IS
    BEGIN
        RETURN pfc_line_of_business.get_defined_lob(p_payor_guid, p_lock);
    END saved_lob;

    FUNCTION selections (
        p_cbsa                       VARCHAR2,
        p_fips                       VARCHAR2,
        p_care_location_value_code   VARCHAR2,
        p_patient_entered_value_code VARCHAR2,
        p_covered_days_value_code    VARCHAR2
    ) RETURN pfc_value_codes.t_selections
    IS
        l_selections pfc_value_codes.t_selections;
    BEGIN
        l_selections.cbsa := p_cbsa;
        l_selections.fips := p_fips;
        l_selections.care_location_value_code := p_care_location_value_code;
        l_selections.patient_entered_value_code := p_patient_entered_value_code;
        l_selections.covered_days_value_code := p_covered_days_value_code;
        RETURN l_selections;
    END selections;

    PROCEDURE inspect_selection (
        p_payor_guid IN payors.payor_guid%TYPE,
        p_plan_guid  IN pfc.plan_guid%TYPE,
        p_lob        IN pfc_value_codes.t_line_of_business,
        p_selections IN pfc_value_codes.t_selections,
        p_result     OUT t_engine_result,
        p_empty_selection_behavior IN VARCHAR2 DEFAULT 'INHERIT'
    )
    IS
        l_summary SYS_REFCURSOR;
        l_changes SYS_REFCURSOR;
        l_option_code VARCHAR2(100);
        l_ignored_option_code VARCHAR2(100);
        l_ignored_payor_guid VARCHAR2(36);
        l_ignored_plan_guid VARCHAR2(36);
        l_ignored_record_type VARCHAR2(20);
        l_new_hef_count PLS_INTEGER;
        l_change_count PLS_INTEGER;
    BEGIN
        l_option_code := pfc_value_codes.private_option_code(p_lob, p_selections, p_empty_selection_behavior);
        pfc_apply_option(
            p_payor_guid, p_plan_guid, l_option_code, 'VALUE_CODES_CURRENT',
            'PREVIEW', NULL, l_summary, l_changes
        );
        CLOSE l_changes;
        FETCH l_summary INTO
            p_result.status, l_ignored_option_code, p_result.display_label,
            l_ignored_payor_guid, l_ignored_plan_guid, p_result.pfc_guid,
            p_result.billing_form_code, l_ignored_record_type,
            p_result.source_guid, p_result.target_action,
            p_result.current_matches_source,
            p_result.current_matches_desired,
            p_result.existing_her_count, p_result.existing_hef_count,
            l_new_hef_count, p_result.state_hash, l_change_count;
        CLOSE l_summary;
    END inspect_selection;

    PROCEDURE current_configuration (
        p_payor_guid IN payors.payor_guid%TYPE,
        p_plan_guid  IN pfc.plan_guid%TYPE DEFAULT NULL,
        p_result     OUT SYS_REFCURSOR
    )
    IS
        l_inherited pfc_value_codes.t_configuration_state;
        l_recipe VARCHAR2(50);
        l_i PLS_INTEGER := 0;
        l_owner_guid VARCHAR2(36);
        l_owners VARCHAR2(4000);
        l_lob pfc_value_codes.t_line_of_business;
        l_none pfc_value_codes.t_selections := pfc_value_codes.no_selections;
        l_candidate pfc_value_codes.t_selections;
        l_engine t_engine_result;
        l_candidate_engine t_engine_result;
        l_match_count PLS_INTEGER := 0;
        l_is_default VARCHAR2(1) := 'N';
        l_status VARCHAR2(40);
        l_canonical_status VARCHAR2(40);
        l_summary_text VARCHAR2(200);
        l_selected pfc_value_codes.t_selections := pfc_value_codes.no_selections;
        l_inherited_json VARCHAR2(1000);
        l_effective_json VARCHAR2(1000);

        FUNCTION selections_json(p_value pfc_value_codes.t_selections)
            RETURN VARCHAR2
        IS
            FUNCTION json_flag(p_flag VARCHAR2) RETURN VARCHAR2 IS
            BEGIN
                RETURN CASE p_flag WHEN 'Y' THEN 'true' ELSE 'false' END;
            END;
        BEGIN
            RETURN '{"cbsa":' || json_flag(p_value.cbsa) ||
                ',"fips":' || json_flag(p_value.fips) ||
                ',"care_location_value_code":' || json_flag(p_value.care_location_value_code) ||
                ',"patient_entered_value_code":' || json_flag(p_value.patient_entered_value_code) ||
                ',"covered_days_value_code":' || json_flag(p_value.covered_days_value_code) || '}';
        END;

        FUNCTION inherited_selections_json RETURN VARCHAR2 IS
            l_value pfc_value_codes.t_selections := pfc_value_codes.no_selections;
        BEGIN
            CASE l_recipe
                WHEN pfc_value_codes.c_recipe_home_health_neutral THEN NULL;
                WHEN pfc_value_codes.c_recipe_hospice_off THEN NULL;
                WHEN pfc_value_codes.c_recipe_home_health_cbsa THEN
                    l_value.cbsa := 'Y';
                WHEN pfc_value_codes.c_recipe_home_health_cbsa_fips THEN
                    l_value.cbsa := 'Y'; l_value.fips := 'Y';
                WHEN pfc_value_codes.c_recipe_hospice_61_g8 THEN
                    l_value.care_location_value_code := 'Y';
                WHEN pfc_value_codes.c_recipe_hospice_61_g8_vc80 THEN
                    l_value.care_location_value_code := 'Y'; l_value.covered_days_value_code := 'Y';
                WHEN pfc_value_codes.c_recipe_hospice_patient THEN
                    l_value.patient_entered_value_code := 'Y';
                WHEN pfc_value_codes.c_recipe_hospice_patient_vc80 THEN
                    l_value.patient_entered_value_code := 'Y'; l_value.covered_days_value_code := 'Y';
                WHEN pfc_value_codes.c_recipe_hospice_vc80 THEN
                    l_value.covered_days_value_code := 'Y';
                ELSE
                    -- Default inspection has already validated inherited HER safety.
                    -- An unrecognized enabled configuration is not known to be Off.
                    IF l_inherited.her_sto_proc_name <> 'RETURN_0'
                       OR l_inherited.her_sto_proc_name IS NULL THEN
                        RETURN NULL;
                    END IF;
            END CASE;
            RETURN selections_json(l_value);
        END;

        PROCEDURE try_candidate(p_value pfc_value_codes.t_selections,
            p_empty_selection_behavior VARCHAR2 DEFAULT 'INHERIT') IS
        BEGIN
            inspect_selection(p_payor_guid, p_plan_guid, l_lob,
                p_value, l_candidate_engine, p_empty_selection_behavior);
            IF l_candidate_engine.current_matches_desired = 'Y' THEN
                l_match_count := l_match_count + 1;
                l_selected := p_value;
                l_summary_text := l_candidate_engine.display_label;
            END IF;
        END;
    BEGIN
        l_lob := saved_lob(p_payor_guid, 'N');
        inspect_selection(p_payor_guid, p_plan_guid, l_lob, l_none, l_engine);

        IF l_engine.existing_her_count > 1 THEN
            l_status := 'BLOCKED_DUPLICATE_PAYOR_HER';
            l_canonical_status := 'DUPLICATE_OVERRIDE';
            l_summary_text := 'Multiple payor Value Codes configurations require support review.';
        ELSIF l_engine.existing_her_count = 0 THEN
            l_status := 'RESOLVED';
            l_is_default := 'Y';
            l_canonical_status := 'INHERITED';
            l_summary_text := 'Default';
        ELSIF l_engine.current_matches_source = 'Y' THEN
            l_status := 'RESOLVED';
            l_is_default := 'Y';
            l_canonical_status := 'REDUNDANT_OVERRIDE';
            l_summary_text := 'Default';
        ELSE
            try_candidate(l_none, 'OFF');
            IF l_lob = pfc_value_codes.c_home_health THEN
                l_candidate := l_none;
                l_candidate.cbsa := 'Y';
                try_candidate(l_candidate);
                l_candidate.fips := 'Y';
                try_candidate(l_candidate);
            ELSE
                l_candidate := l_none;
                l_candidate.care_location_value_code := 'Y';
                try_candidate(l_candidate);
                l_candidate.covered_days_value_code := 'Y';
                try_candidate(l_candidate);
                l_candidate := l_none;
                l_candidate.patient_entered_value_code := 'Y';
                try_candidate(l_candidate);
                l_candidate.covered_days_value_code := 'Y';
                try_candidate(l_candidate);
                l_candidate := l_none;
                l_candidate.covered_days_value_code := 'Y';
                try_candidate(l_candidate);
            END IF;
            IF l_match_count = 1 THEN
                l_status := 'RESOLVED';
                l_canonical_status := 'CANONICAL_OVERRIDE';
            ELSIF l_match_count = 0 THEN
                l_status := 'UNRECOGNIZED';
                l_canonical_status := 'UNSUPPORTED_OVERRIDE';
                l_summary_text := 'The current Value Codes configuration needs support review.';
                l_selected := l_none;
            ELSE
                l_status := 'AMBIGUOUS';
                l_canonical_status := 'UNSUPPORTED_OVERRIDE';
                l_summary_text := 'The current Value Codes configuration is ambiguous.';
                l_selected := l_none;
            END IF;
        END IF;

        SELECT sto_proc_name INTO l_inherited.her_sto_proc_name
        FROM hcfa_electronic_records WHERE electronic_rec_guid = l_engine.source_guid;
        FOR f IN (SELECT field_number, field_name, sto_proc_name, hard_coded_data
            FROM hcfa_electronic_fields WHERE electronic_rec_guid = l_engine.source_guid) LOOP
            l_i := l_i + 1;
            l_inherited.hefs(l_i).field_number := f.field_number;
            l_inherited.hefs(l_i).field_name := f.field_name;
            l_inherited.hefs(l_i).sto_proc_name := f.sto_proc_name;
            l_inherited.hefs(l_i).hard_coded_data := f.hard_coded_data;
        END LOOP;
        l_recipe := pfc_value_codes.recognize_state(l_lob, l_inherited);
        l_inherited_json := inherited_selections_json;
        IF l_is_default = 'Y' THEN
            l_effective_json := l_inherited_json;
            l_summary_text := CASE l_recipe
                WHEN 'HOME_HEALTH_NO_CBSA_FIPS' THEN
                    CASE WHEN l_inherited.her_sto_proc_name = 'RETURN_0'
                        THEN 'Off (inherited)' ELSE 'CBSA and FIPS off (inherited)' END
                WHEN 'HOSPICE_OFF' THEN 'Off (inherited)'
                WHEN 'HOME_HEALTH_CBSA' THEN 'CBSA (inherited)'
                WHEN 'HOME_HEALTH_CBSA_FIPS' THEN 'CBSA and FIPS (inherited)'
                WHEN 'HOSPICE_61_G8' THEN 'Care-location value code 61/G8 (inherited)'
                WHEN 'HOSPICE_61_G8_VC80_DAYS' THEN 'Care-location value code 61/G8 and value code 80 with days covered (inherited)'
                WHEN 'HOSPICE_PATIENT_VALUE' THEN 'Patient-entered value code and amount (inherited)'
                WHEN 'HOSPICE_PATIENT_VALUE_VC80_DAYS' THEN 'Patient-entered value code and amount and value code 80 with days covered (inherited)'
                WHEN 'HOSPICE_VC80_DAYS' THEN 'Value code 80 with days covered (inherited)'
                ELSE CASE WHEN l_inherited.her_sto_proc_name = 'RETURN_0' THEN 'Off (inherited)' ELSE 'Default' END END;
        ELSIF l_canonical_status = 'CANONICAL_OVERRIDE' THEN
            l_effective_json := selections_json(l_selected);
        END IF;

        l_owner_guid := l_engine.source_guid;
        IF l_engine.existing_her_count = 1 THEN
            SELECT electronic_rec_guid INTO l_owner_guid FROM hcfa_electronic_records
            WHERE payor_guid = TRIM(p_payor_guid)
              AND (plan_guid = p_plan_guid OR (plan_guid IS NULL AND p_plan_guid IS NULL)) AND billing_form_code = l_engine.billing_form_code
              AND record_type_code = 'D23002310HI286';
        END IF;
        l_owners := '[' || pfc_config_internal.owner_json(l_owner_guid, 'Value Codes') || ']';

        OPEN p_result FOR SELECT
            CAST(l_status AS VARCHAR2(40)) configuration_status,
            CAST(l_lob AS VARCHAR2(20)) line_of_business,
            CAST(l_is_default AS VARCHAR2(1)) is_default,
            CAST(l_selected.cbsa AS VARCHAR2(1)) cbsa,
            CAST(l_selected.fips AS VARCHAR2(1)) fips,
            CAST(l_selected.care_location_value_code AS VARCHAR2(1)) care_location_value_code,
            CAST(l_selected.patient_entered_value_code AS VARCHAR2(1)) patient_entered_value_code,
            CAST(l_selected.covered_days_value_code AS VARCHAR2(1)) covered_days_value_code,
            CAST(l_canonical_status AS VARCHAR2(40)) canonical_status,
            CAST(l_summary_text AS VARCHAR2(200)) display_summary,
            CAST(l_engine.pfc_guid AS VARCHAR2(36)) pfc_guid,
            CAST(l_engine.billing_form_code AS VARCHAR2(10)) billing_form_code,
            CAST(l_engine.source_guid AS VARCHAR2(36)) source_electronic_rec_guid,
            CAST(l_engine.existing_her_count AS NUMBER) existing_payor_her_count,
            CAST(l_engine.existing_hef_count AS NUMBER) existing_payor_hef_count,
            CAST(l_engine.state_hash AS VARCHAR2(64)) state_hash,
            l_owners configuration_owners,
            CAST(l_effective_json AS VARCHAR2(1000)) effective_selections,
            CAST(l_inherited_json AS VARCHAR2(1000)) inherited_selections
        FROM dual;
    END current_configuration;

    PROCEDURE run_change (
        p_payor_guid                 IN payors.payor_guid%TYPE,
        p_plan_guid                  IN pfc.plan_guid%TYPE,
        p_cbsa                       IN VARCHAR2,
        p_fips                       IN VARCHAR2,
        p_care_location_value_code   IN VARCHAR2,
        p_patient_entered_value_code IN VARCHAR2,
        p_covered_days_value_code    IN VARCHAR2,
        p_audit_user                 IN hcfa_electronic_records.rec_ent_user%TYPE,
        p_mode                       IN VARCHAR2,
        p_expected_state_hash        IN VARCHAR2,
        p_summary                    OUT SYS_REFCURSOR,
        p_changes                    OUT SYS_REFCURSOR,
        p_empty_selection_behavior IN VARCHAR2
    ) IS
        l_lob pfc_value_codes.t_line_of_business;
        l_selections pfc_value_codes.t_selections;
        l_option_code pfc_option_types.t_option_code;
        l_off_check t_engine_result;
        l_source_gate hcfa_electronic_records.sto_proc_name%TYPE;
    BEGIN
        l_lob := saved_lob(p_payor_guid,
            CASE WHEN p_mode = 'APPLY' THEN 'Y' ELSE 'N' END);
        l_selections := selections(p_cbsa, p_fips,
            p_care_location_value_code, p_patient_entered_value_code,
            p_covered_days_value_code);
        l_option_code := pfc_value_codes.private_option_code(l_lob, l_selections, p_empty_selection_behavior);
        IF l_lob = pfc_value_codes.c_home_health
           AND l_option_code = pfc_value_codes.private_option_code(
               pfc_value_codes.c_home_health, pfc_value_codes.no_selections, 'OFF') THEN
            -- A neutral result that collapses into unknown inheritance cannot be
            -- confirmed as checked-off capabilities. Inspect only this new path.
            inspect_selection(p_payor_guid, p_plan_guid, l_lob, l_selections,
                l_off_check, 'OFF');
            IF l_off_check.target_action = 'REMOVE_OVERRIDE'
               OR (l_off_check.target_action = 'NO_CHANGE' AND l_off_check.existing_her_count = 0) THEN
                SELECT sto_proc_name INTO l_source_gate FROM hcfa_electronic_records
                WHERE electronic_rec_guid = l_off_check.source_guid;
                IF l_source_gate IS NULL OR l_source_gate NOT IN ('RETURN_1', 'RETURN_0') THEN
                    RAISE_APPLICATION_ERROR(pfc_value_codes.c_err_invalid_state,
                        'The inherited Value Codes settings cannot be confirmed safely. Review the inherited configuration before changing these selections.');
                END IF;
            END IF;
        END IF;
        pfc_apply_option(p_payor_guid, p_plan_guid, l_option_code,
            p_audit_user, p_mode, p_expected_state_hash, p_summary, p_changes);
    END run_change;

    PROCEDURE preview_configuration (
        p_payor_guid IN payors.payor_guid%TYPE, p_plan_guid IN pfc.plan_guid%TYPE DEFAULT NULL,
        p_cbsa IN VARCHAR2, p_fips IN VARCHAR2,
        p_care_location_value_code IN VARCHAR2, p_patient_entered_value_code IN VARCHAR2,
        p_covered_days_value_code IN VARCHAR2,
        p_audit_user IN hcfa_electronic_records.rec_ent_user%TYPE,
        p_summary OUT SYS_REFCURSOR, p_changes OUT SYS_REFCURSOR,
        p_empty_selection_behavior IN VARCHAR2 DEFAULT 'INHERIT'
    ) IS
    BEGIN
        run_change(p_payor_guid, p_plan_guid, p_cbsa, p_fips,
            p_care_location_value_code, p_patient_entered_value_code,
            p_covered_days_value_code, p_audit_user, 'PREVIEW', NULL,
            p_summary, p_changes, p_empty_selection_behavior);
    END preview_configuration;

    PROCEDURE apply_configuration (
        p_payor_guid IN payors.payor_guid%TYPE, p_plan_guid IN pfc.plan_guid%TYPE DEFAULT NULL,
        p_cbsa IN VARCHAR2, p_fips IN VARCHAR2,
        p_care_location_value_code IN VARCHAR2, p_patient_entered_value_code IN VARCHAR2,
        p_covered_days_value_code IN VARCHAR2,
        p_audit_user IN hcfa_electronic_records.rec_ent_user%TYPE,
        p_expected_state_hash IN VARCHAR2,
        p_summary OUT SYS_REFCURSOR, p_changes OUT SYS_REFCURSOR,
        p_empty_selection_behavior IN VARCHAR2 DEFAULT 'INHERIT'
    ) IS
    BEGIN
        run_change(p_payor_guid, p_plan_guid, p_cbsa, p_fips,
            p_care_location_value_code, p_patient_entered_value_code,
            p_covered_days_value_code, p_audit_user, 'APPLY',
            p_expected_state_hash, p_summary, p_changes, p_empty_selection_behavior);
    END apply_configuration;
END pfc_value_codes_api;
/
