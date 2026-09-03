WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

DECLARE
    c_payor CONSTANT VARCHAR2(36) :=
        '10000000-0000-0000-0000-00000000D002';
    c_target CONSTANT VARCHAR2(20) := 'D23001900NTE182';
    c_source CONSTANT VARCHAR2(36) :=
        '33000000-0000-0000-0000-000000000001';
    c_audit CONSTANT VARCHAR2(36) :=
        '90000000-0000-0000-0000-000000000003';
    c_text CONSTANT VARCHAR2(100) := 'Test custom remark';
    c_updated CONSTANT VARCHAR2(100) := 'Updated custom remark';

    l_status VARCHAR2(40);
    l_lob VARCHAR2(20);
    l_remarks_mode VARCHAR2(10);
    l_custom_remark VARCHAR2(128);
    l_canonical VARCHAR2(40);
    l_display VARCHAR2(200);
    l_pfc VARCHAR2(36);
    l_form VARCHAR2(10);
    l_source VARCHAR2(36);
    l_action VARCHAR2(30);
    l_her_count NUMBER;
    l_hef_count NUMBER;
    l_source_hef_count NUMBER;
    l_hash VARCHAR2(64);
    l_hash2 VARCHAR2(64);
    l_count NUMBER;
    l_failed BOOLEAN;

    PROCEDURE fail(p_text VARCHAR2) IS
    BEGIN
        RAISE_APPLICATION_ERROR(-20986, p_text);
    END;

    PROCEDURE assert_text(
        p_label VARCHAR2, p_actual VARCHAR2, p_expected VARCHAR2
    ) IS
    BEGIN
        IF (p_actual IS NULL AND p_expected IS NOT NULL)
           OR (p_actual IS NOT NULL AND p_expected IS NULL)
           OR p_actual <> p_expected THEN
            fail(p_label || ' mismatch.');
        END IF;
    END;

    PROCEDURE assert_number(
        p_label VARCHAR2, p_actual NUMBER, p_expected NUMBER
    ) IS
    BEGIN
        IF p_actual <> p_expected THEN
            fail(p_label || ' mismatch.');
        END IF;
    END;

    PROCEDURE get_current IS
        l_result SYS_REFCURSOR;
    BEGIN
        pfc_remarks_api.current_configuration(c_payor, NULL, l_result);
        FETCH l_result INTO l_status, l_lob, l_remarks_mode,
            l_custom_remark, l_canonical, l_display, l_pfc, l_form,
            l_source, l_action, l_her_count, l_hef_count,
            l_source_hef_count, l_hash;
        CLOSE l_result;
    END;

    PROCEDURE change_config(
        p_operation VARCHAR2,
        p_mode VARCHAR2,
        p_custom_remark VARCHAR2,
        p_expected_hash VARCHAR2
    ) IS
        l_summary SYS_REFCURSOR;
        l_changes SYS_REFCURSOR;
        l_option VARCHAR2(100);
        l_payor VARCHAR2(36);
        l_plan VARCHAR2(36);
        l_record VARCHAR2(20);
        l_matches_source VARCHAR2(1);
        l_matches_desired VARCHAR2(1);
        l_new_hefs NUMBER;
        l_change_count NUMBER;
    BEGIN
        IF p_operation = 'PREVIEW' THEN
            pfc_remarks_api.preview_configuration(
                c_payor, NULL, p_mode, p_custom_remark, c_audit,
                l_summary, l_changes);
        ELSE
            pfc_remarks_api.apply_configuration(
                c_payor, NULL, p_mode, p_custom_remark, c_audit,
                p_expected_hash, l_summary, l_changes);
        END IF;
        FETCH l_summary INTO l_status, l_option, l_display, l_payor,
            l_plan, l_pfc, l_form, l_record, l_source, l_action,
            l_matches_source, l_matches_desired, l_her_count,
            l_hef_count, l_new_hefs, l_hash, l_change_count;
        CLOSE l_summary;
        CLOSE l_changes;
    END;

    PROCEDURE expect_prepare_error(
        p_mode VARCHAR2,
        p_text VARCHAR2,
        p_code PLS_INTEGER
    ) IS
        l_option pfc_option_types.t_option_code;
    BEGIN
        l_failed := FALSE;
        BEGIN
            l_option := pfc_remarks.prepare_private_option(
                'HOME_HEALTH', p_mode, p_text);
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE = p_code THEN
                    l_failed := TRUE;
                ELSE
                    RAISE;
                END IF;
        END;
        IF NOT l_failed THEN
            fail('Expected Remarks validation error was not raised.');
        END IF;
    END;
BEGIN
    SAVEPOINT remarks_test;

    DELETE FROM hcfa_electronic_fields f
    WHERE EXISTS (
        SELECT 1 FROM hcfa_electronic_records h
        WHERE h.electronic_rec_guid = f.electronic_rec_guid
          AND h.payor_guid = c_payor
          AND h.billing_form_code = '837I_5010'
          AND h.record_type_code = c_target
    );
    DELETE FROM hcfa_electronic_records h
    WHERE h.payor_guid = c_payor
      AND h.billing_form_code = '837I_5010'
      AND h.record_type_code = c_target;
    UPDATE pfc_config_payor_context
    SET line_of_business = 'HOME_HEALTH'
    WHERE payor_guid = c_payor;

    expect_prepare_error('CUSTOM', NULL,
        pfc_remarks.c_err_custom_required);
    expect_prepare_error('CUSTOM', '   ',
        pfc_remarks.c_err_custom_required);
    expect_prepare_error('CUSTOM', RPAD('X', 101, 'X'),
        pfc_remarks.c_err_custom_too_long);
    expect_prepare_error('DEFAULT', 'must reject',
        pfc_remarks.c_err_invalid_mode);
    l_display := pfc_remarks.prepare_private_option(
        'HOME_HEALTH', 'CUSTOM', RPAD('X', 100, 'X'));

    get_current;
    assert_text('Inherited mode', l_remarks_mode, 'DEFAULT');
    assert_text('Inherited custom text', l_custom_remark, NULL);
    assert_text('Inherited source', l_source, c_source);
    assert_number('Inherited override count', l_her_count, 0);
    assert_number('Complete source HEF count', l_source_hef_count, 4);

    SAVEPOINT unsafe_remarks_source;
    UPDATE hcfa_electronic_records SET mandatory_ind = 'Y'
    WHERE electronic_rec_guid = c_source;
    l_failed := FALSE;
    BEGIN
        change_config('PREVIEW', 'DEFAULT', NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE = pfc_config_internal.c_err_unsafe_source THEN
            l_failed := TRUE;
        ELSE RAISE;
        END IF;
    END;
    IF NOT l_failed THEN fail('Unsafe Remarks Default source was accepted.'); END IF;
    change_config('PREVIEW', 'CUSTOM', c_text, NULL);
    l_hash2 := l_hash;
    change_config('APPLY', 'CUSTOM', c_text, l_hash2);
    SELECT COUNT(*) INTO l_count
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = c_payor AND h.record_type_code = c_target
      AND h.sto_proc_name = 'RETURN_1' AND h.mandatory_ind = 'Y';
    assert_number('Remarks RETURN_1 preserves source mandatory', l_count, 1);
    ROLLBACK TO unsafe_remarks_source;

    change_config('PREVIEW', 'CUSTOM', c_text, NULL);
    assert_text('Custom Preview status', l_status, 'PREVIEW');
    assert_text('Custom Preview action', l_action, 'REBUILD_OVERRIDE');
    l_hash2 := l_hash;
    change_config('PREVIEW', 'CUSTOM', c_updated, NULL);
    IF l_hash = l_hash2 THEN
        fail('Changing custom text did not change the Preview hash.');
    END IF;
    change_config('PREVIEW', 'DEFAULT', NULL, NULL);
    IF l_hash = l_hash2 THEN
        fail('Changing mode did not change the Preview hash.');
    END IF;

    change_config('APPLY', 'CUSTOM', c_text, l_hash2);
    assert_text('Custom Apply status', l_status, 'APPLIED');
    get_current;
    assert_text('Custom current mode', l_remarks_mode, 'CUSTOM');
    assert_text('Custom current exact text', l_custom_remark, c_text);
    assert_text('Custom current canonical status', l_canonical,
        'CANONICAL_OVERRIDE');

    SELECT COUNT(*) INTO l_count
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = c_payor
      AND h.billing_form_code = '837I_5010'
      AND h.record_type_code = c_target
      AND h.plan_guid IS NULL
      AND h.payor_type_guid =
          '11000000-0000-0000-0000-000000000001'
      AND h.carry_forward_ind IS NULL
      AND h.include_record_data_onclaim = 'Y'
      AND h.sto_proc_name = 'RETURN_1';
    assert_number('Canonical custom HER', l_count, 1);

    SELECT COUNT(*) INTO l_count
    FROM hcfa_electronic_fields f
    JOIN hcfa_electronic_records h
      ON h.electronic_rec_guid = f.electronic_rec_guid
    WHERE h.payor_guid = c_payor AND h.record_type_code = c_target;
    assert_number('Complete source HEFs cloned', l_count, 4);

    SELECT COUNT(*) INTO l_count
    FROM hcfa_electronic_fields f
    JOIN hcfa_electronic_records h
      ON h.electronic_rec_guid = f.electronic_rec_guid
    WHERE h.payor_guid = c_payor AND h.record_type_code = c_target
      AND ((f.field_number = '00' AND f.field_name = 'NTE00'
            AND f.sto_proc_name IS NULL AND f.hard_coded_data = 'NTE')
        OR (f.field_number = '01' AND f.field_name = 'NTE01'
            AND f.sto_proc_name IS NULL AND f.hard_coded_data = 'ADD')
        OR (f.field_number = '02' AND f.field_name = 'NTE02'
            AND f.sto_proc_name IS NULL AND f.hard_coded_data = c_text));
    assert_number('Managed Remarks overlays', l_count, 3);

    SELECT COUNT(*) INTO l_count
    FROM hcfa_electronic_fields f
    JOIN hcfa_electronic_records h
      ON h.electronic_rec_guid = f.electronic_rec_guid
    WHERE h.payor_guid = c_payor AND h.record_type_code = c_target
      AND f.field_number = '03' AND f.field_name = 'NTE03'
      AND f.sto_proc_name = 'SYN_KEEP_UNMANAGED_NTE'
      AND f.hard_coded_data = 'KEEP_NTE03';
    assert_number('Unmanaged paired HEF retained exactly', l_count, 1);

    change_config('PREVIEW', 'CUSTOM', c_text, NULL);
    assert_text('Same custom Preview', l_status, 'NO_CHANGE');

    change_config('PREVIEW', 'CUSTOM', c_updated, NULL);
    l_hash2 := l_hash;
    SAVEPOINT stale_source;
    UPDATE hcfa_electronic_records
    SET notes = 'Synthetic state hash mutation'
    WHERE electronic_rec_guid = c_source;
    l_failed := FALSE;
    BEGIN
        change_config('APPLY', 'CUSTOM', c_updated, l_hash2);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20036 THEN
                l_failed := TRUE;
            ELSE
                RAISE;
            END IF;
    END;
    IF NOT l_failed THEN
        fail('A stale Remarks Preview was accepted.');
    END IF;
    ROLLBACK TO stale_source;

    change_config('PREVIEW', 'DEFAULT', NULL, NULL);
    assert_text('Default removes override', l_action, 'REMOVE_OVERRIDE');
    l_hash2 := l_hash;
    change_config('APPLY', 'DEFAULT', NULL, l_hash2);
    get_current;
    assert_text('Default after removal', l_remarks_mode, 'DEFAULT');
    assert_number('Default removed override', l_her_count, 0);
    change_config('PREVIEW', 'DEFAULT', NULL, NULL);
    assert_text('Default never creates override', l_status, 'NO_CHANGE');

    SAVEPOINT custom_source;
    UPDATE hcfa_electronic_records SET sto_proc_name = 'RETURN_1'
    WHERE electronic_rec_guid = c_source;
    UPDATE hcfa_electronic_fields
    SET sto_proc_name = NULL,
        hard_coded_data = CASE field_number
            WHEN '00' THEN 'NTE'
            WHEN '01' THEN 'ADD'
            WHEN '02' THEN c_text
        END
    WHERE electronic_rec_guid = c_source
      AND field_number IN ('00', '01', '02');
    get_current;
    assert_text('Custom-looking inherited source remains Default',
        l_remarks_mode, 'DEFAULT');
    change_config('PREVIEW', 'CUSTOM', c_text, NULL);
    assert_text('Custom equal to source needs no override',
        l_status, 'NO_CHANGE');
    ROLLBACK TO custom_source;

    change_config('PREVIEW', 'DEFAULT', NULL, NULL);
    l_hash2 := l_hash;
    UPDATE pfc_config_payor_context SET line_of_business = 'HOSPICE'
    WHERE payor_guid = c_payor;
    change_config('PREVIEW', 'DEFAULT', NULL, NULL);
    IF l_hash = l_hash2 THEN
        fail('Changing LOB did not change the Remarks Preview hash.');
    END IF;
    UPDATE pfc_config_payor_context SET line_of_business = 'HOME_HEALTH'
    WHERE payor_guid = c_payor;

    change_config('PREVIEW', 'CUSTOM', c_text, NULL);
    l_hash2 := l_hash;
    change_config('APPLY', 'CUSTOM', c_text, l_hash2);
    UPDATE hcfa_electronic_records SET mandatory_ind = 'Y'
    WHERE electronic_rec_guid = c_source;
    DECLARE
        l_lob_summary SYS_REFCURSOR;
        l_targets SYS_REFCURSOR;
        l_lob_status VARCHAR2(20);
        l_changes_required VARCHAR2(1);
        l_current_lob VARCHAR2(20);
        l_requested_lob VARCHAR2(20);
        l_target_count NUMBER;
        l_affected NUMBER;
        l_hers NUMBER;
        l_hefs NUMBER;
        l_lob_hash VARCHAR2(64);
    BEGIN
        pfc_line_of_business.preview_change(
            c_payor, 'HOSPICE', l_lob_summary, l_targets);
        FETCH l_lob_summary INTO l_lob_status, l_changes_required,
            l_current_lob, l_requested_lob, l_target_count, l_affected,
            l_hers, l_hefs, l_lob_hash;
        CLOSE l_lob_summary;
        CLOSE l_targets;
        assert_number('LOB reset shared managed target count',
            l_target_count, 6);
        pfc_line_of_business.apply_change(
            c_payor, 'HOSPICE', l_lob_hash, c_audit,
            l_lob_summary, l_targets);
        CLOSE l_lob_summary;
        CLOSE l_targets;
    END;
    l_failed := FALSE;
    BEGIN
        get_current;
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE = pfc_config_internal.c_err_unsafe_source THEN
            l_failed := TRUE;
        ELSE RAISE;
        END IF;
    END;
    IF NOT l_failed THEN
        fail('LOB reset exposed an unsafe inherited Remarks Default.');
    END IF;
    SELECT COUNT(*) INTO l_count FROM hcfa_electronic_records h
    WHERE h.payor_guid = c_payor AND h.record_type_code = c_target;
    assert_number('LOB reset does not create repair override', l_count, 0);
    UPDATE hcfa_electronic_records SET mandatory_ind = 'N'
    WHERE electronic_rec_guid = c_source;
    get_current;
    assert_text('LOB reset restores inherited Default',
        l_remarks_mode, 'DEFAULT');
    assert_text('LOB reset changed context', l_lob, 'HOSPICE');

    ROLLBACK TO remarks_test;
    SELECT COUNT(*) INTO l_count
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = c_payor AND h.record_type_code = c_target;
    assert_number('Remarks procedures do not commit', l_count, 0);
    DBMS_OUTPUT.PUT_LINE(
        'PASS: Remarks uses source-derived DEFAULT, dynamic custom text, ' ||
        'complete cloning, stale hashes, LOB reset, and caller transactions.');
    ROLLBACK;
END;
/
