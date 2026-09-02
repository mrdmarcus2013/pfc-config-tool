WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

DECLARE
    c_payor CONSTANT VARCHAR2(36) := '10000000-0000-0000-0000-00000000D002';
    c_hospice_payor CONSTANT VARCHAR2(36) := '10000000-0000-0000-0000-00000000D001';
    c_target CONSTANT VARCHAR2(20) := 'D23002310HI286';
    c_audit CONSTANT VARCHAR2(36) := '90000000-0000-0000-0000-000000000003';
    l_status VARCHAR2(40); l_lob VARCHAR2(20); l_default VARCHAR2(1);
    l_cbsa VARCHAR2(1); l_fips VARCHAR2(1); l_care VARCHAR2(1);
    l_patient VARCHAR2(1); l_days VARCHAR2(1); l_canonical VARCHAR2(40);
    l_display VARCHAR2(200); l_pfc VARCHAR2(36); l_form VARCHAR2(10);
    l_source VARCHAR2(36); l_her_count NUMBER; l_hef_count NUMBER;
    l_hash VARCHAR2(64); l_hash2 VARCHAR2(64); l_count NUMBER;
    l_failed BOOLEAN;

    PROCEDURE fail(p_text VARCHAR2) IS BEGIN RAISE_APPLICATION_ERROR(-20985, p_text); END;
    PROCEDURE assert_text(p_label VARCHAR2, p_actual VARCHAR2, p_expected VARCHAR2) IS
    BEGIN
        IF (p_actual IS NULL AND p_expected IS NOT NULL)
           OR (p_actual IS NOT NULL AND p_expected IS NULL)
           OR p_actual <> p_expected THEN
            fail(p_label || ' mismatch.');
        END IF;
    END;
    PROCEDURE assert_number(p_label VARCHAR2, p_actual NUMBER, p_expected NUMBER) IS
    BEGIN IF p_actual <> p_expected THEN fail(p_label || ' mismatch.'); END IF; END;

    PROCEDURE get_current(p_payor VARCHAR2) IS
        l_result SYS_REFCURSOR;
    BEGIN
        pfc_value_codes_api.current_configuration(p_payor, NULL, l_result);
        FETCH l_result INTO l_status, l_lob, l_default, l_cbsa, l_fips,
            l_care, l_patient, l_days, l_canonical, l_display, l_pfc,
            l_form, l_source, l_her_count, l_hef_count, l_hash;
        CLOSE l_result;
    END;

    PROCEDURE change_config(
        p_payor VARCHAR2, p_mode VARCHAR2, p_expected VARCHAR2,
        p_cbsa VARCHAR2, p_fips VARCHAR2, p_care VARCHAR2,
        p_patient VARCHAR2, p_days VARCHAR2
    ) IS
        l_summary SYS_REFCURSOR; l_changes SYS_REFCURSOR;
        l_option VARCHAR2(100); l_payor VARCHAR2(36); l_plan VARCHAR2(36);
        l_record VARCHAR2(20); l_action VARCHAR2(30); l_ms VARCHAR2(1);
        l_md VARCHAR2(1); l_new NUMBER; l_change_count NUMBER;
    BEGIN
        IF p_mode = 'PREVIEW' THEN
            pfc_value_codes_api.preview_configuration(p_payor, NULL, p_cbsa,
                p_fips, p_care, p_patient, p_days, c_audit,
                l_summary, l_changes);
        ELSE
            pfc_value_codes_api.apply_configuration(p_payor, NULL, p_cbsa,
                p_fips, p_care, p_patient, p_days, c_audit, p_expected,
                l_summary, l_changes);
        END IF;
        FETCH l_summary INTO l_status, l_option, l_display, l_payor, l_plan,
            l_pfc, l_form, l_record, l_source, l_action, l_ms, l_md,
            l_her_count, l_hef_count, l_new, l_hash, l_change_count;
        CLOSE l_summary; CLOSE l_changes;
    END;
BEGIN
    SAVEPOINT value_codes_test;
    INSERT INTO pfc_config_payor_context (
        payor_guid, line_of_business, rec_ent_date, rec_ent_user
    ) VALUES (c_hospice_payor, 'HOSPICE', SYSDATE, c_audit);

    get_current(c_payor);
    assert_text('Home Health inherited current', l_default, 'Y');
    assert_text('Home Health inherited summary', l_display, 'Default');
    assert_number('Home Health starts without override', l_her_count, 0);

    change_config(c_payor, 'PREVIEW', NULL, 'Y', 'N', 'N', 'N', 'N');
    assert_text('CBSA preview', l_status, 'PREVIEW');
    l_hash2 := l_hash;
    change_config(c_payor, 'APPLY', l_hash2, 'Y', 'N', 'N', 'N', 'N');
    assert_text('CBSA apply', l_status, 'APPLIED');
    get_current(c_payor);
    assert_text('CBSA current is explicit', l_default, 'N');
    assert_text('CBSA current selection', l_cbsa, 'Y');
    assert_text('CBSA current FIPS', l_fips, 'N');

    SELECT COUNT(*) INTO l_count
    FROM hcfa_electronic_fields f
    JOIN hcfa_electronic_records h
      ON h.electronic_rec_guid = f.electronic_rec_guid
    WHERE h.payor_guid = c_payor AND h.record_type_code = c_target;
    assert_number('Complete source HEFs cloned', l_count, 5);
    SELECT COUNT(*) INTO l_count
    FROM hcfa_electronic_fields f
    JOIN hcfa_electronic_records h ON h.electronic_rec_guid = f.electronic_rec_guid
    WHERE h.payor_guid = c_payor AND h.record_type_code = c_target
      AND f.field_number = '030' AND f.sto_proc_name = 'SYN_KEEP_UNMANAGED'
      AND f.hard_coded_data = 'KEEP_UNMANAGED';
    assert_number('Unmanaged paired HEF retained', l_count, 1);

    change_config(c_payor, 'PREVIEW', NULL, 'N', 'N', 'N', 'N', 'N');
    assert_text('Default previews override removal', l_status, 'PREVIEW');
    l_hash2 := l_hash;
    change_config(c_payor, 'APPLY', l_hash2, 'N', 'N', 'N', 'N', 'N');
    get_current(c_payor);
    assert_text('Default after removal', l_default, 'Y');
    assert_number('Default removed override', l_her_count, 0);

    change_config(c_payor, 'PREVIEW', NULL, 'N', 'N', 'N', 'N', 'N');
    assert_text('Default never creates override', l_status, 'NO_CHANGE');
    l_hash2 := l_hash;
    change_config(c_payor, 'PREVIEW', NULL, 'Y', 'Y', 'N', 'N', 'N');
    IF l_hash = l_hash2 THEN fail('Structured selection did not change hash.'); END IF;

    SAVEPOINT explicit_source;
    UPDATE hcfa_electronic_records SET sto_proc_name = 'RETURN_1'
    WHERE electronic_rec_guid = l_source;
    UPDATE hcfa_electronic_fields SET sto_proc_name = NULL,
        hard_coded_data = '61' WHERE electronic_rec_guid = l_source
        AND field_number = '012';
    UPDATE hcfa_electronic_fields SET sto_proc_name = 'GET_PAT_CBSA_CODE',
        hard_coded_data = NULL WHERE electronic_rec_guid = l_source
        AND field_number = '015';
    get_current(c_payor);
    assert_text('Recipe-like inherited source still displays Default', l_default, 'Y');
    change_config(c_payor, 'PREVIEW', NULL, 'Y', 'N', 'N', 'N', 'N');
    assert_text('Explicit choice equal to source needs no override', l_status, 'NO_CHANGE');
    ROLLBACK TO explicit_source;

    change_config(c_payor, 'PREVIEW', NULL, 'N', 'N', 'N', 'N', 'N');
    l_hash2 := l_hash;
    UPDATE pfc_config_payor_context SET line_of_business = 'HOSPICE'
    WHERE payor_guid = c_payor;
    l_failed := FALSE;
    BEGIN
        change_config(c_payor, 'APPLY', l_hash2, 'N', 'N', 'N', 'N', 'N');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE = -20036 THEN l_failed := TRUE; ELSE RAISE; END IF;
    END;
    IF NOT l_failed THEN fail('LOB change did not invalidate preview hash.'); END IF;
    UPDATE pfc_config_payor_context SET line_of_business = 'HOME_HEALTH'
    WHERE payor_guid = c_payor;

    get_current(c_hospice_payor);
    assert_text('Hospice inherited current', l_default, 'Y');

    change_config(c_hospice_payor, 'PREVIEW', NULL, 'N', 'N', 'N', 'Y', 'N');
    assert_text('Hospice patient-only preview', l_status, 'PREVIEW');
    l_hash2 := l_hash;
    change_config(c_hospice_payor, 'APPLY', l_hash2, 'N', 'N', 'N', 'Y', 'N');
    assert_text('Hospice patient-only apply', l_status, 'APPLIED');
    get_current(c_hospice_payor);
    assert_text('Hospice patient-only current is explicit', l_default, 'N');
    assert_text('Hospice patient-only current selection', l_patient, 'Y');
    assert_text('Hospice patient-only leaves days off', l_days, 'N');
    assert_text('Hospice patient-only leaves care off', l_care, 'N');

    change_config(c_hospice_payor, 'PREVIEW', NULL, 'N', 'N', 'N', 'Y', 'Y');
    assert_text('Hospice patient and days preview', l_status, 'PREVIEW');
    l_hash2 := l_hash;
    change_config(c_hospice_payor, 'APPLY', l_hash2, 'N', 'N', 'N', 'Y', 'Y');
    assert_text('Hospice patient and days apply', l_status, 'APPLIED');
    get_current(c_hospice_payor);
    assert_text('Hospice patient and days current patient', l_patient, 'Y');
    assert_text('Hospice patient and days current days', l_days, 'Y');

    FOR with_days IN 0 .. 1 LOOP
        l_failed := FALSE;
        BEGIN
            change_config(c_hospice_payor, 'PREVIEW', NULL, 'N', 'N', 'Y', 'Y',
                CASE WHEN with_days = 1 THEN 'Y' ELSE 'N' END);
        EXCEPTION WHEN OTHERS THEN
            IF SQLCODE = pfc_value_codes.c_err_invalid_selection THEN
                l_failed := TRUE;
            ELSE
                RAISE;
            END IF;
        END;
        IF NOT l_failed THEN
            fail('Care-location and patient-entered conflict was accepted.');
        END IF;
    END LOOP;

    change_config(c_hospice_payor, 'PREVIEW', NULL, 'N', 'N', 'N', 'N', 'Y');
    l_hash2 := l_hash;
    change_config(c_hospice_payor, 'APPLY', l_hash2, 'N', 'N', 'N', 'N', 'Y');
    get_current(c_hospice_payor);
    assert_text('Hospice current explicit', l_default, 'N');
    assert_text('Hospice days current', l_days, 'Y');
    assert_text('Hospice patient current', l_patient, 'N');

    ROLLBACK TO value_codes_test;
    SELECT COUNT(*) INTO l_count FROM hcfa_electronic_records
    WHERE payor_guid IN (c_payor, c_hospice_payor)
      AND record_type_code = c_target;
    assert_number('Value Codes procedures do not commit', l_count, 0);
    DBMS_OUTPUT.PUT_LINE('PASS: Value Codes structured current/preview/apply uses source-derived DEFAULT, complete cloning, private recipes, hashes, and caller-owned transactions.');
    ROLLBACK;
END;
/
