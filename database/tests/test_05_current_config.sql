WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

DECLARE
    c_ui_payor CONSTANT VARCHAR2(36) :=
        '10000000-0000-0000-0000-00000000D001';
    c_audit_user CONSTANT VARCHAR2(36) :=
        '90000000-0000-0000-0000-000000000003';
    c_err_pfc_ambiguous CONSTANT PLS_INTEGER := -20011;
    c_err_source_missing CONSTANT PLS_INTEGER := -20020;
    c_err_source_ambiguous CONSTANT PLS_INTEGER := -20021;

    l_status VARCHAR2(20);
    l_field_number VARCHAR2(10);
    l_capability VARCHAR2(40);
    l_option_code VARCHAR2(100);
    l_mode VARCHAR2(20);
    l_report_address VARCHAR2(1);
    l_enabled VARCHAR2(1);
    l_pfc_guid VARCHAR2(36);
    l_canonical VARCHAR2(1);
    l_state_hash VARCHAR2(64);
    l_before_her_count NUMBER;
    l_after_her_count NUMBER;
    l_before_hef_count NUMBER;
    l_after_hef_count NUMBER;
    l_error_code NUMBER;

    PROCEDURE assert_text (
        p_label IN VARCHAR2,
        p_actual IN VARCHAR2,
        p_expected IN VARCHAR2
    ) IS
    BEGIN
        IF (p_actual IS NULL AND p_expected IS NOT NULL)
           OR (p_actual IS NOT NULL AND p_expected IS NULL)
           OR (p_actual IS NOT NULL AND p_expected IS NOT NULL
               AND p_actual <> p_expected) THEN
            RAISE_APPLICATION_ERROR(
                -20970,
                p_label || ' expected [' || NVL(p_expected, '<NULL>') ||
                '] but found [' || NVL(p_actual, '<NULL>') || '].'
            );
        END IF;
    END assert_text;

    PROCEDURE call_current (
        p_payor_guid IN VARCHAR2,
        p_field IN VARCHAR2
    ) IS
        l_result SYS_REFCURSOR;
    BEGIN
        pfc_get_current_config(
            p_payor_guid => p_payor_guid,
            p_plan_guid => NULL,
            p_field_number => p_field,
            p_result => l_result
        );
        FETCH l_result INTO
            l_status, l_field_number, l_capability, l_option_code,
            l_mode, l_report_address, l_enabled, l_pfc_guid, l_canonical;
        IF l_result%NOTFOUND THEN
            RAISE_APPLICATION_ERROR(-20971, 'Current resolver returned no row.');
        END IF;
        CLOSE l_result;
    END call_current;

    PROCEDURE call_option (
        p_option_code IN VARCHAR2,
        p_mode IN VARCHAR2,
        p_expected_hash IN VARCHAR2 DEFAULT NULL
    ) IS
        l_summary SYS_REFCURSOR;
        l_changes SYS_REFCURSOR;
        l_result_status VARCHAR2(20);
        l_result_option VARCHAR2(100);
        l_display_label VARCHAR2(200);
        l_payor_guid VARCHAR2(36);
        l_plan_guid VARCHAR2(36);
        l_result_pfc_guid VARCHAR2(36);
        l_billing_form VARCHAR2(10);
        l_record_type VARCHAR2(20);
        l_source_guid VARCHAR2(36);
        l_target_action VARCHAR2(30);
        l_matches_source VARCHAR2(1);
        l_matches_desired VARCHAR2(1);
        l_existing_her_count NUMBER;
        l_existing_hef_count NUMBER;
        l_new_hef_count NUMBER;
        l_change_count NUMBER;
    BEGIN
        pfc_apply_option(
            p_payor_guid => c_ui_payor,
            p_plan_guid => NULL,
            p_option_code => p_option_code,
            p_audit_user => c_audit_user,
            p_mode => p_mode,
            p_expected_state_hash => p_expected_hash,
            p_summary => l_summary,
            p_changes => l_changes
        );
        FETCH l_summary INTO
            l_result_status, l_result_option, l_display_label,
            l_payor_guid, l_plan_guid, l_result_pfc_guid, l_billing_form,
            l_record_type, l_source_guid, l_target_action,
            l_matches_source, l_matches_desired, l_existing_her_count,
            l_existing_hef_count, l_new_hef_count, l_state_hash,
            l_change_count;
        CLOSE l_summary;
        CLOSE l_changes;
    END call_option;

    PROCEDURE apply_option (p_option_code IN VARCHAR2) IS
        l_preview_hash VARCHAR2(64);
    BEGIN
        call_option(p_option_code, 'PREVIEW');
        l_preview_hash := l_state_hash;
        call_option(p_option_code, 'APPLY', l_preview_hash);
    END apply_option;

    PROCEDURE assert_service (
        p_option_code IN VARCHAR2,
        p_mode IN VARCHAR2,
        p_address IN VARCHAR2
    ) IS
    BEGIN
        SAVEPOINT current_service_case;
        apply_option(p_option_code);
        call_current(c_ui_payor, '77');
        assert_text(p_option_code || ' status', l_status, 'RESOLVED');
        assert_text(p_option_code || ' option', l_option_code, p_option_code);
        assert_text(p_option_code || ' mode', l_mode, p_mode);
        assert_text(p_option_code || ' address', l_report_address, p_address);
        ROLLBACK TO current_service_case;
    END assert_service;

BEGIN
    SELECT COUNT(*) INTO l_before_her_count
    FROM hcfa_electronic_records
    WHERE payor_guid = c_ui_payor;

    SELECT COUNT(*) INTO l_before_hef_count
    FROM hcfa_electronic_fields f
    JOIN hcfa_electronic_records h
      ON h.electronic_rec_guid = f.electronic_rec_guid
    WHERE h.payor_guid = c_ui_payor;

    call_current(c_ui_payor, '81');
    assert_text('Inherited Provider status', l_status, 'RESOLVED');
    assert_text('Inherited Provider OFF', l_option_code, 'PROVIDER_TAXONOMY_OFF');
    assert_text('Inherited Provider enabled', l_enabled, 'N');

    call_current(c_ui_payor, '77');
    assert_text('Inherited Service Facility status', l_status, 'RESOLVED');
    assert_text('Inherited Service Facility NEVER', l_option_code,
        'SERVICE_FACILITY_NEVER');
    assert_text('Inherited Service Facility mode', l_mode, 'NEVER');
    assert_text('Inherited Service Facility address', l_report_address, 'N');

    SELECT COUNT(*) INTO l_after_her_count
    FROM hcfa_electronic_records
    WHERE payor_guid = c_ui_payor;
    SELECT COUNT(*) INTO l_after_hef_count
    FROM hcfa_electronic_fields f
    JOIN hcfa_electronic_records h
      ON h.electronic_rec_guid = f.electronic_rec_guid
    WHERE h.payor_guid = c_ui_payor;
    IF l_before_her_count <> l_after_her_count
       OR l_before_hef_count <> l_after_hef_count THEN
        RAISE_APPLICATION_ERROR(-20972, 'Current-state read performed DML.');
    END IF;

    call_current('10000000-0000-0000-0000-0000000000A2', '81');
    assert_text('Canonical Provider override ON', l_option_code,
        'PROVIDER_TAXONOMY_ON');
    assert_text('Canonical Provider flag', l_canonical, 'Y');

    call_current('10000000-0000-0000-0000-0000000000A5', '81');
    assert_text('Template inherited Provider ON', l_option_code,
        'PROVIDER_TAXONOMY_ON');

    call_current('10000000-0000-0000-0000-0000000000A4', '81');
    assert_text('Hard-coded Provider effective ON', l_option_code,
        'PROVIDER_TAXONOMY_ON');
    assert_text('Hard-coded Provider noncanonical', l_canonical, 'N');

    assert_service('SERVICE_FACILITY_ALWAYS_ADDRESS_YES', 'ALWAYS', 'Y');
    assert_service('SERVICE_FACILITY_ALWAYS_ADDRESS_NO', 'ALWAYS', 'N');
    assert_service('SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES', 'CONDITIONAL', 'Y');
    assert_service('SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO', 'CONDITIONAL', 'N');
    assert_service('SERVICE_FACILITY_NEVER', 'NEVER', 'N');

    SAVEPOINT inconsistent_service_case;
    apply_option('SERVICE_FACILITY_ALWAYS_ADDRESS_YES');
    UPDATE hcfa_electronic_records
    SET sto_proc_name = 'RETURN_0'
    WHERE payor_guid = c_ui_payor
      AND billing_form_code = '837I_5010'
      AND record_type_code = 'D2310E2650N3346';
    BEGIN
        call_current(c_ui_payor, '77');
        RAISE_APPLICATION_ERROR(-20973, 'Mixed Service Facility state was accepted.');
    EXCEPTION
        WHEN OTHERS THEN
            l_error_code := SQLCODE;
            IF l_error_code <> -20041 THEN
                RAISE;
            END IF;
    END;
    ROLLBACK TO inconsistent_service_case;

    BEGIN
        call_current('10000000-0000-0000-0000-00000000FFFF', '81');
        RAISE_APPLICATION_ERROR(-20974, 'Missing PFC was accepted.');
    EXCEPTION
        WHEN OTHERS THEN
            l_error_code := SQLCODE;
            IF l_error_code <> pfc_config_internal.c_err_pfc_not_found THEN
                RAISE;
            END IF;
    END;

    SAVEPOINT ambiguous_pfc_case;
    UPDATE pfc
    SET payor_guid = c_ui_payor,
        billing_form_code = '837I_5010'
    WHERE pfc_guid = '20000000-0000-0000-0000-0000000000A8';
    BEGIN
        call_current(c_ui_payor, '81');
        RAISE_APPLICATION_ERROR(-20975, 'Ambiguous PFC was accepted.');
    EXCEPTION
        WHEN OTHERS THEN
            l_error_code := SQLCODE;
            IF l_error_code <> c_err_pfc_ambiguous THEN
                RAISE;
            END IF;
    END;
    ROLLBACK TO ambiguous_pfc_case;

    SAVEPOINT missing_source_case;
    UPDATE hcfa_electronic_records
    SET billing_form_code = 'MISSING'
    WHERE electronic_rec_guid = '30000000-0000-0000-0000-00000000D081';
    BEGIN
        call_current(c_ui_payor, '81');
        RAISE_APPLICATION_ERROR(-20976, 'Missing source was accepted.');
    EXCEPTION
        WHEN OTHERS THEN
            l_error_code := SQLCODE;
            IF l_error_code <> c_err_source_missing THEN
                RAISE;
            END IF;
    END;
    ROLLBACK TO missing_source_case;

    SAVEPOINT ambiguous_source_case;
    UPDATE hcfa_electronic_records
    SET billing_form_code = '837I_5010'
    WHERE electronic_rec_guid = '30000000-0000-0000-0000-000000000001';
    BEGIN
        call_current(c_ui_payor, '81');
        RAISE_APPLICATION_ERROR(-20977, 'Ambiguous source was accepted.');
    EXCEPTION
        WHEN OTHERS THEN
            l_error_code := SQLCODE;
            IF l_error_code <> c_err_source_ambiguous THEN
                RAISE;
            END IF;
    END;
    ROLLBACK TO ambiguous_source_case;

    DBMS_OUTPUT.PUT_LINE(
        'PASS: current configuration resolved inherited, override, template, ' ||
        'noncanonical, all Service Facility, and safe failure states.'
    );
END;
/
