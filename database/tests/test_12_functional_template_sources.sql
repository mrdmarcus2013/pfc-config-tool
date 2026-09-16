WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

DECLARE
    l_owners VARCHAR2(4000);
    c_audit CONSTANT VARCHAR2(36) :=
        '90000000-0000-0000-0000-000000000003';

    PROCEDURE fail(p_message IN VARCHAR2) IS
    BEGIN
        RAISE_APPLICATION_ERROR(-20959, p_message);
    END;

    PROCEDURE assert_text(
        p_label    IN VARCHAR2,
        p_actual   IN VARCHAR2,
        p_expected IN VARCHAR2
    ) IS
    BEGIN
        IF (p_actual IS NULL AND p_expected IS NOT NULL)
           OR (p_actual IS NOT NULL AND p_expected IS NULL)
           OR (p_actual IS NOT NULL AND p_expected IS NOT NULL
               AND p_actual <> p_expected) THEN
            fail(p_label || ': expected [' || NVL(p_expected, '<NULL>') ||
                '], got [' || NVL(p_actual, '<NULL>') || '].');
        END IF;
    END;

    PROCEDURE assert_current(
        p_label           IN VARCHAR2,
        p_payor_guid      IN VARCHAR2,
        p_plan_guid       IN VARCHAR2,
        p_field_number    IN VARCHAR2,
        p_expected_option IN VARCHAR2
    ) IS
        l_result SYS_REFCURSOR;
        l_status VARCHAR2(20);
        l_field VARCHAR2(10);
        l_capability VARCHAR2(40);
        l_option VARCHAR2(100);
        l_mode VARCHAR2(20);
        l_address VARCHAR2(1);
        l_enabled VARCHAR2(1);
        l_taxonomy_code VARCHAR2(10);
        l_pfc VARCHAR2(36);
        l_canonical VARCHAR2(1);
    BEGIN
        pfc_get_current_config(
            p_payor_guid, p_plan_guid, p_field_number, l_result
        );
        FETCH l_result INTO l_status, l_field, l_capability, l_option,
            l_mode, l_address, l_enabled, l_taxonomy_code, l_pfc, l_canonical, l_owners;
        IF l_result%NOTFOUND THEN
            CLOSE l_result;
            fail(p_label || ': current resolver returned no row.');
        END IF;
        CLOSE l_result;
        assert_text(p_label || ' status', l_status, 'RESOLVED');
        assert_text(p_label || ' option', l_option, p_expected_option);
        IF p_field_number = '81' THEN
            assert_text(p_label || ' canonical', l_canonical, 'Y');
        END IF;
    END;

    PROCEDURE assert_value_no_change(
        p_label           IN VARCHAR2,
        p_payor_guid      IN VARCHAR2,
        p_plan_guid       IN VARCHAR2,
        p_cbsa            IN VARCHAR2,
        p_fips            IN VARCHAR2,
        p_care            IN VARCHAR2,
        p_patient         IN VARCHAR2,
        p_days            IN VARCHAR2,
        p_expected_source IN VARCHAR2
    ) IS
        l_summary SYS_REFCURSOR;
        l_changes SYS_REFCURSOR;
        l_status VARCHAR2(20);
        l_option VARCHAR2(100);
        l_display VARCHAR2(200);
        l_payor VARCHAR2(36);
        l_plan VARCHAR2(36);
        l_pfc VARCHAR2(36);
        l_form VARCHAR2(10);
        l_record VARCHAR2(20);
        l_source VARCHAR2(36);
        l_action VARCHAR2(30);
        l_matches_source VARCHAR2(1);
        l_matches_desired VARCHAR2(1);
        l_her_count NUMBER;
        l_hef_count NUMBER;
        l_new_hef_count NUMBER;
        l_hash VARCHAR2(64);
        l_change_count NUMBER;
    BEGIN
        pfc_value_codes_api.preview_configuration(
            p_payor_guid, p_plan_guid, p_cbsa, p_fips, p_care,
            p_patient, p_days, c_audit, l_summary, l_changes
        );
        FETCH l_summary INTO l_status, l_option, l_display, l_payor,
            l_plan, l_pfc, l_form, l_record, l_source, l_action,
            l_matches_source, l_matches_desired, l_her_count,
            l_hef_count, l_new_hef_count, l_hash, l_change_count;
        CLOSE l_summary;
        CLOSE l_changes;
        assert_text(p_label || ' preview', l_status, 'NO_CHANGE');
        assert_text(p_label || ' source', l_source, p_expected_source);
    END;

    PROCEDURE assert_remarks_no_change(
        p_label           IN VARCHAR2,
        p_payor_guid      IN VARCHAR2,
        p_plan_guid       IN VARCHAR2,
        p_mode            IN VARCHAR2,
        p_text            IN VARCHAR2,
        p_expected_source IN VARCHAR2
    ) IS
        l_summary SYS_REFCURSOR;
        l_changes SYS_REFCURSOR;
        l_status VARCHAR2(20);
        l_option VARCHAR2(100);
        l_display VARCHAR2(200);
        l_payor VARCHAR2(36);
        l_plan VARCHAR2(36);
        l_pfc VARCHAR2(36);
        l_form VARCHAR2(10);
        l_record VARCHAR2(20);
        l_source VARCHAR2(36);
        l_action VARCHAR2(30);
        l_matches_source VARCHAR2(1);
        l_matches_desired VARCHAR2(1);
        l_her_count NUMBER;
        l_hef_count NUMBER;
        l_new_hef_count NUMBER;
        l_hash VARCHAR2(64);
        l_change_count NUMBER;
    BEGIN
        pfc_remarks_api.preview_configuration(
            p_payor_guid, p_plan_guid, p_mode, p_text, c_audit,
            l_summary, l_changes
        );
        FETCH l_summary INTO l_status, l_option, l_display, l_payor,
            l_plan, l_pfc, l_form, l_record, l_source, l_action,
            l_matches_source, l_matches_desired, l_her_count,
            l_hef_count, l_new_hef_count, l_hash, l_change_count;
        CLOSE l_summary;
        CLOSE l_changes;
        assert_text(p_label || ' preview', l_status, 'NO_CHANGE');
        assert_text(p_label || ' source', l_source, p_expected_source);
    END;
BEGIN
    /* Shared form template A100. */
    assert_current('Form A100 Provider',
        '10000000-0000-0000-0000-00000000B102',
        '60000000-0000-0000-0000-00000000B102', '81',
        'PROVIDER_TAXONOMY_ON');
    assert_current('Form A100 Service Facility',
        '10000000-0000-0000-0000-00000000B102',
        '60000000-0000-0000-0000-00000000B102', '77',
        'SERVICE_FACILITY_ALWAYS_ADDRESS_YES');
    assert_value_no_change('Form A100 Value Codes',
        '10000000-0000-0000-0000-00000000B102',
        '60000000-0000-0000-0000-00000000B102',
        'Y', 'N', 'N', 'N', 'N',
        '32000000-0000-0000-0000-A10000000001');
    assert_remarks_no_change('Form A100 Remarks',
        '10000000-0000-0000-0000-00000000B102',
        '60000000-0000-0000-0000-00000000B102',
        'CUSTOM', 'Form A100 template remark',
        '33000000-0000-0000-0000-A10000000001');

    /* Shared form template A200. */
    assert_current('Form A200 Provider',
        '10000000-0000-0000-0000-00000000B107',
        '60000000-0000-0000-0000-00000000B107', '81',
        'PROVIDER_TAXONOMY_OFF');
    assert_current('Form A200 Service Facility',
        '10000000-0000-0000-0000-00000000B107',
        '60000000-0000-0000-0000-00000000B107', '77',
        'SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO');
    assert_value_no_change('Form A200 Value Codes',
        '10000000-0000-0000-0000-00000000B107',
        '60000000-0000-0000-0000-00000000B107',
        'N', 'N', 'Y', 'N', 'Y',
        '32000000-0000-0000-0000-A20000000001');
    assert_remarks_no_change('Form A200 Remarks',
        '10000000-0000-0000-0000-00000000B107',
        '60000000-0000-0000-0000-00000000B107',
        'CUSTOM', 'Form A200 template remark',
        '33000000-0000-0000-0000-A20000000001');

    /* Shared user template B100 outranks any form template. */
    assert_current('User B100 Provider',
        '10000000-0000-0000-0000-00000000B104',
        '60000000-0000-0000-0000-00000000B104', '81',
        'PROVIDER_TAXONOMY_OFF');
    assert_current('User B100 Service Facility',
        '10000000-0000-0000-0000-00000000B104',
        '60000000-0000-0000-0000-00000000B104', '77',
        'SERVICE_FACILITY_ALWAYS_ADDRESS_NO');
    assert_value_no_change('User B100 Value Codes',
        '10000000-0000-0000-0000-00000000B104',
        '60000000-0000-0000-0000-00000000B104',
        'Y', 'Y', 'N', 'N', 'N',
        '32000000-0000-0000-0000-B10000000001');
    assert_remarks_no_change('User B100 Remarks',
        '10000000-0000-0000-0000-00000000B104',
        '60000000-0000-0000-0000-00000000B104',
        'CUSTOM', 'User B100 template remark',
        '33000000-0000-0000-0000-B10000000001');

    assert_current('User B200 Provider',
        '10000000-0000-0000-0000-00000000B108',
        '60000000-0000-0000-0000-00000000B108', '81',
        'PROVIDER_TAXONOMY_ON');
    assert_current('User B200 Service Facility',
        '10000000-0000-0000-0000-00000000B108',
        '60000000-0000-0000-0000-00000000B108', '77',
        'SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES');
    assert_value_no_change('User B200 Value Codes',
        '10000000-0000-0000-0000-00000000B108',
        '60000000-0000-0000-0000-00000000B108',
        'N', 'N', 'N', 'Y', 'Y',
        '32000000-0000-0000-0000-B20000000001');
    assert_remarks_no_change('User B200 Remarks',
        '10000000-0000-0000-0000-00000000B108',
        '60000000-0000-0000-0000-00000000B108',
        'CUSTOM', 'User B200 template remark',
        '33000000-0000-0000-0000-B20000000001');

    assert_current('User B300 Provider',
        '10000000-0000-0000-0000-00000000B109',
        '60000000-0000-0000-0000-00000000B109', '81',
        'PROVIDER_TAXONOMY_ON');
    assert_current('User B300 Service Facility',
        '10000000-0000-0000-0000-00000000B109',
        '60000000-0000-0000-0000-00000000B109', '77',
        'SERVICE_FACILITY_NEVER');
    assert_value_no_change('User B300 Value Codes',
        '10000000-0000-0000-0000-00000000B109',
        '60000000-0000-0000-0000-00000000B109',
        'N', 'N', 'N', 'N', 'Y',
        '32000000-0000-0000-0000-B30000000001');
    assert_remarks_no_change('User B300 Remarks',
        '10000000-0000-0000-0000-00000000B109',
        '60000000-0000-0000-0000-00000000B109',
        'DEFAULT', NULL,
        '33000000-0000-0000-0000-B30000000001');

    DBMS_OUTPUT.PUT_LINE(
        'PASS: functional form and user template sources resolve supported configurations.'
    );
END;
/
