CREATE OR REPLACE PACKAGE BODY pfc_remarks_api AS
    c_record_type_code CONSTANT VARCHAR2(20) := 'D23001900NTE182';

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
        new_hef_count           PLS_INTEGER,
        state_hash              VARCHAR2(64)
    );

    FUNCTION saved_lob(
        p_payor_guid IN payors.payor_guid%TYPE,
        p_lock       IN VARCHAR2
    ) RETURN pfc_remarks.t_line_of_business
    IS
        l_lob pfc_config_payor_context.line_of_business%TYPE;
    BEGIN
        pfc_line_of_business.require_defined(p_payor_guid, p_lock);
        IF UPPER(TRIM(p_lock)) = 'Y' THEN
            SELECT line_of_business INTO l_lob
            FROM pfc_config_payor_context
            WHERE payor_guid = TRIM(p_payor_guid)
            FOR UPDATE;
        ELSE
            SELECT line_of_business INTO l_lob
            FROM pfc_config_payor_context
            WHERE payor_guid = TRIM(p_payor_guid);
        END IF;
        RETURN UPPER(TRIM(l_lob));
    END saved_lob;

    PROCEDURE inspect_intent(
        p_payor_guid   IN payors.payor_guid%TYPE,
        p_plan_guid    IN pfc.plan_guid%TYPE,
        p_lob          IN pfc_remarks.t_line_of_business,
        p_mode         IN pfc_remarks.t_mode,
        p_custom_remark IN pfc_remarks.t_custom_remark,
        p_result       OUT t_engine_result
    ) IS
        l_summary SYS_REFCURSOR;
        l_changes SYS_REFCURSOR;
        l_option_code pfc_option_types.t_option_code;
        l_ignored_option_code VARCHAR2(100);
        l_ignored_payor_guid VARCHAR2(36);
        l_ignored_plan_guid VARCHAR2(36);
        l_ignored_record_type VARCHAR2(20);
        l_change_count PLS_INTEGER;
    BEGIN
        l_option_code := pfc_remarks.prepare_private_option(
            p_lob, p_mode, p_custom_remark);
        pfc_apply_option(
            p_payor_guid, p_plan_guid, l_option_code, 'REMARKS_CURRENT',
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
            p_result.new_hef_count, p_result.state_hash, l_change_count;
        CLOSE l_summary;
    END inspect_intent;

    PROCEDURE current_configuration (
        p_payor_guid IN payors.payor_guid%TYPE,
        p_plan_guid  IN pfc.plan_guid%TYPE DEFAULT NULL,
        p_result     OUT SYS_REFCURSOR
    ) IS
        l_lob pfc_remarks.t_line_of_business;
        l_default_engine t_engine_result;
        l_custom_engine t_engine_result;
        l_engine t_engine_result;
        l_status VARCHAR2(40);
        l_mode pfc_remarks.t_mode;
        l_custom_remark pfc_remarks.t_custom_remark;
        l_canonical_status VARCHAR2(40);
        l_display_summary VARCHAR2(200);
        l_current_guid hcfa_electronic_records.electronic_rec_guid%TYPE;
        l_current_her_sto hcfa_electronic_records.sto_proc_name%TYPE;
        l_nte00_count PLS_INTEGER := 0;
        l_nte01_count PLS_INTEGER := 0;
        l_nte02_count PLS_INTEGER := 0;
        l_pattern_valid BOOLEAN := TRUE;
        l_source_hef_count PLS_INTEGER;
    BEGIN
        l_lob := saved_lob(p_payor_guid, 'N');
        inspect_intent(p_payor_guid, p_plan_guid, l_lob,
            pfc_remarks.c_mode_default, NULL, l_default_engine);
        l_engine := l_default_engine;

        IF l_default_engine.existing_her_count > 1 THEN
            l_status := 'BLOCKED_DUPLICATE_PAYOR_HER';
            l_canonical_status := 'DUPLICATE_OVERRIDE';
            l_display_summary :=
                'Multiple payor Remarks configurations require support review.';
        ELSIF l_default_engine.existing_her_count = 0 THEN
            l_status := 'RESOLVED';
            l_mode := pfc_remarks.c_mode_default;
            l_canonical_status := 'INHERITED';
            l_display_summary := 'Default';
        ELSIF l_default_engine.current_matches_source = 'Y' THEN
            l_status := 'RESOLVED';
            l_mode := pfc_remarks.c_mode_default;
            l_canonical_status := 'REDUNDANT_OVERRIDE';
            l_display_summary := 'Default';
        ELSE
            SELECT h.electronic_rec_guid, h.sto_proc_name
            INTO l_current_guid, l_current_her_sto
            FROM hcfa_electronic_records h
            WHERE h.payor_guid = TRIM(p_payor_guid)
              AND h.billing_form_code = l_default_engine.billing_form_code
              AND h.record_type_code = c_record_type_code;

            IF l_current_her_sto <> 'RETURN_1' OR l_current_her_sto IS NULL THEN
                l_pattern_valid := FALSE;
            END IF;
            FOR field_row IN (
                SELECT f.field_number, f.field_name, f.sto_proc_name,
                       f.hard_coded_data
                FROM hcfa_electronic_fields f
                WHERE f.electronic_rec_guid = l_current_guid
                  AND ((f.field_number = '00' AND f.field_name = 'NTE00')
                    OR (f.field_number = '01' AND f.field_name = 'NTE01')
                    OR (f.field_number = '02' AND f.field_name = 'NTE02'))
            ) LOOP
                IF field_row.field_number = '00' THEN
                    l_nte00_count := l_nte00_count + 1;
                    IF field_row.sto_proc_name IS NOT NULL
                       OR field_row.hard_coded_data <> 'NTE'
                       OR field_row.hard_coded_data IS NULL THEN
                        l_pattern_valid := FALSE;
                    END IF;
                ELSIF field_row.field_number = '01' THEN
                    l_nte01_count := l_nte01_count + 1;
                    IF field_row.sto_proc_name IS NOT NULL
                       OR field_row.hard_coded_data <> 'ADD'
                       OR field_row.hard_coded_data IS NULL THEN
                        l_pattern_valid := FALSE;
                    END IF;
                ELSE
                    l_nte02_count := l_nte02_count + 1;
                    IF field_row.sto_proc_name IS NOT NULL
                       OR TRIM(field_row.hard_coded_data) IS NULL
                       OR LENGTH(field_row.hard_coded_data) >
                            pfc_remarks.c_custom_remark_max_length
                       OR field_row.hard_coded_data <> TRIM(field_row.hard_coded_data) THEN
                        l_pattern_valid := FALSE;
                    ELSE
                        l_custom_remark := field_row.hard_coded_data;
                    END IF;
                END IF;
            END LOOP;
            IF l_nte00_count <> 1 OR l_nte01_count <> 1 OR l_nte02_count <> 1 THEN
                l_pattern_valid := FALSE;
            END IF;

            IF l_pattern_valid THEN
                inspect_intent(p_payor_guid, p_plan_guid, l_lob,
                    pfc_remarks.c_mode_custom, l_custom_remark,
                    l_custom_engine);
                IF l_custom_engine.current_matches_desired = 'Y' THEN
                    l_status := 'RESOLVED';
                    l_mode := pfc_remarks.c_mode_custom;
                    l_canonical_status := 'CANONICAL_OVERRIDE';
                    l_display_summary := 'Custom remark';
                    l_engine := l_custom_engine;
                ELSE
                    l_pattern_valid := FALSE;
                END IF;
            END IF;
            IF NOT l_pattern_valid THEN
                l_status := 'UNRECOGNIZED';
                l_canonical_status := 'UNSUPPORTED_OVERRIDE';
                l_display_summary :=
                    'The current Remarks configuration needs support review.';
                l_custom_remark := NULL;
            END IF;
        END IF;

        SELECT COUNT(*) INTO l_source_hef_count
        FROM hcfa_electronic_fields f
        WHERE f.electronic_rec_guid = l_engine.source_guid;

        OPEN p_result FOR SELECT
            CAST(l_status AS VARCHAR2(40)) configuration_status,
            CAST(l_lob AS VARCHAR2(20)) line_of_business,
            CAST(l_mode AS VARCHAR2(10)) remarks_mode,
            CAST(l_custom_remark AS VARCHAR2(128)) custom_remark,
            CAST(l_canonical_status AS VARCHAR2(40)) canonical_status,
            CAST(l_display_summary AS VARCHAR2(200)) display_summary,
            CAST(l_engine.pfc_guid AS VARCHAR2(36)) pfc_guid,
            CAST(l_engine.billing_form_code AS VARCHAR2(10)) billing_form_code,
            CAST(l_engine.source_guid AS VARCHAR2(36)) source_electronic_rec_guid,
            CAST(l_engine.target_action AS VARCHAR2(30)) target_action,
            CAST(l_engine.existing_her_count AS NUMBER) existing_payor_her_count,
            CAST(l_engine.existing_hef_count AS NUMBER) existing_payor_hef_count,
            CAST(l_source_hef_count AS NUMBER) source_hef_count,
            CAST(l_engine.state_hash AS VARCHAR2(64)) state_hash
        FROM dual;
    END current_configuration;

    PROCEDURE run_change(
        p_payor_guid          IN payors.payor_guid%TYPE,
        p_plan_guid           IN pfc.plan_guid%TYPE,
        p_mode                IN pfc_remarks.t_mode,
        p_custom_remark       IN pfc_remarks.t_custom_remark,
        p_audit_user          IN hcfa_electronic_records.rec_ent_user%TYPE,
        p_operation_mode      IN VARCHAR2,
        p_expected_state_hash IN VARCHAR2,
        p_summary             OUT SYS_REFCURSOR,
        p_changes             OUT SYS_REFCURSOR
    ) IS
        l_lob pfc_remarks.t_line_of_business;
        l_option_code pfc_option_types.t_option_code;
    BEGIN
        l_lob := saved_lob(p_payor_guid,
            CASE WHEN p_operation_mode = 'APPLY' THEN 'Y' ELSE 'N' END);
        l_option_code := pfc_remarks.prepare_private_option(
            l_lob, p_mode, p_custom_remark);
        pfc_apply_option(p_payor_guid, p_plan_guid, l_option_code,
            p_audit_user, p_operation_mode, p_expected_state_hash,
            p_summary, p_changes);
    END run_change;

    PROCEDURE preview_configuration (
        p_payor_guid IN payors.payor_guid%TYPE,
        p_plan_guid IN pfc.plan_guid%TYPE DEFAULT NULL,
        p_mode IN pfc_remarks.t_mode,
        p_custom_remark IN pfc_remarks.t_custom_remark,
        p_audit_user IN hcfa_electronic_records.rec_ent_user%TYPE,
        p_summary OUT SYS_REFCURSOR,
        p_changes OUT SYS_REFCURSOR
    ) IS
    BEGIN
        run_change(p_payor_guid, p_plan_guid, p_mode, p_custom_remark,
            p_audit_user, 'PREVIEW', NULL, p_summary, p_changes);
    END preview_configuration;

    PROCEDURE apply_configuration (
        p_payor_guid IN payors.payor_guid%TYPE,
        p_plan_guid IN pfc.plan_guid%TYPE DEFAULT NULL,
        p_mode IN pfc_remarks.t_mode,
        p_custom_remark IN pfc_remarks.t_custom_remark,
        p_audit_user IN hcfa_electronic_records.rec_ent_user%TYPE,
        p_expected_state_hash IN VARCHAR2,
        p_summary OUT SYS_REFCURSOR,
        p_changes OUT SYS_REFCURSOR
    ) IS
    BEGIN
        run_change(p_payor_guid, p_plan_guid, p_mode, p_custom_remark,
            p_audit_user, 'APPLY', p_expected_state_hash,
            p_summary, p_changes);
    END apply_configuration;
END pfc_remarks_api;
/
