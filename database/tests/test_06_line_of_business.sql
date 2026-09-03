WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

DECLARE
    c_payor_defined CONSTANT VARCHAR2(36) :=
        '10000000-0000-0000-0000-00000000D002';
    c_payor_undefined CONSTANT VARCHAR2(36) :=
        '10000000-0000-0000-0000-00000000D001';
    c_payor_hospice CONSTANT VARCHAR2(36) :=
        '10000000-0000-0000-0000-0000000000A8';
    c_audit CONSTANT VARCHAR2(36) :=
        '90000000-0000-0000-0000-000000000003';
    c_unmanaged_type CONSTANT VARCHAR2(20) := 'SYNTHETIC_UNMANAGED';

    l_summary SYS_REFCURSOR;
    l_targets SYS_REFCURSOR;
    l_result SYS_REFCURSOR;
    l_status VARCHAR2(30);
    l_changes VARCHAR2(1);
    l_current VARCHAR2(20);
    l_requested VARCHAR2(20);
    l_target_count NUMBER;
    l_affected NUMBER;
    l_hers NUMBER;
    l_hefs NUMBER;
    l_hash VARCHAR2(64);
    l_hash_2 VARCHAR2(64);
    l_number NUMBER;
    l_entry_date DATE;
    l_entry_user VARCHAR2(36);
    l_failed BOOLEAN;
    l_vc_text VARCHAR2(200);
    l_vc_guid VARCHAR2(36);
    l_vc_form VARCHAR2(10);
    l_vc_source VARCHAR2(36);
    l_vc_state VARCHAR2(64);
    l_vc_default VARCHAR2(1);

    PROCEDURE assert_text(p_label VARCHAR2, p_actual VARCHAR2, p_expected VARCHAR2) IS
    BEGIN
        IF (p_actual IS NULL AND p_expected IS NOT NULL) OR
           (p_actual IS NOT NULL AND p_expected IS NULL) OR
           p_actual <> p_expected THEN
            RAISE_APPLICATION_ERROR(-20970, p_label || ': unexpected value.');
        END IF;
    END;

    PROCEDURE assert_number(p_label VARCHAR2, p_actual NUMBER, p_expected NUMBER) IS
    BEGIN
        IF p_actual <> p_expected THEN
            RAISE_APPLICATION_ERROR(-20971, p_label || ': expected ' ||
                p_expected || ', got ' || p_actual || '.');
        END IF;
    END;

    PROCEDURE fetch_summary IS
    BEGIN
        FETCH l_summary INTO l_status, l_changes, l_current, l_requested,
            l_target_count, l_affected, l_hers, l_hefs, l_hash;
        CLOSE l_summary;
    END;

    PROCEDURE clone_target(
        p_source_guid VARCHAR2,
        p_new_guid VARCHAR2,
        p_payor_guid VARCHAR2,
        p_plan_guid VARCHAR2,
        p_record_type VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        INSERT INTO hcfa_electronic_records (
            electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
            record_name, record_type_code, record_size, mandatory_ind,
            req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
            type_of_bill, detail_ind, max_number, invoice_ind,
            form_template_guid, carry_forward_ind, max_carry_forward,
            sto_proc_name, user_form_template_guid, notes, rec_ent_date,
            rec_ent_user, rec_mod_date, rec_mod_user, include_record_data_onclaim
        ) SELECT
            p_new_guid, h.loop_id, h.contiguity_ind, h.billing_form_code,
            'Synthetic LOB reset fixture',
            NVL(p_record_type, h.record_type_code), h.record_size,
            h.mandatory_ind, h.req_for_claim_ind, h.payor_type_guid,
            p_payor_guid, p_plan_guid, h.type_of_bill, h.detail_ind,
            h.max_number, h.invoice_ind, h.form_template_guid,
            h.carry_forward_ind, h.max_carry_forward, h.sto_proc_name,
            h.user_form_template_guid, 'Synthetic LOB reset fixture',
            SYSDATE, c_audit, NULL, NULL, h.include_record_data_onclaim
        FROM hcfa_electronic_records h
        WHERE h.electronic_rec_guid = p_source_guid;

        INSERT INTO hcfa_electronic_fields (
            field_number, electronic_rec_guid, field_name, record_type_code,
            sto_proc_name, pic, field_spec, position_from, position_thru,
            field_name_desc, mandatory_ind, must_fit_length_ind, order_num,
            repeats, detail_ind, occurs_next, hard_coded_data, field_format,
            caps_ind, required_subelement_ind, rec_ent_date, rec_ent_user,
            rec_mod_date, rec_mod_user, include_data_onclaim
        ) SELECT
            f.field_number, p_new_guid, f.field_name,
            NVL(p_record_type, f.record_type_code), f.sto_proc_name, f.pic,
            f.field_spec, f.position_from, f.position_thru, f.field_name_desc,
            f.mandatory_ind, f.must_fit_length_ind, f.order_num, f.repeats,
            f.detail_ind, f.occurs_next, f.hard_coded_data, f.field_format,
            f.caps_ind, f.required_subelement_ind, SYSDATE, c_audit,
            NULL, NULL, f.include_data_onclaim
        FROM hcfa_electronic_fields f
        WHERE f.electronic_rec_guid = p_source_guid;
    END;

    PROCEDURE preview(p_requested VARCHAR2) IS
    BEGIN
        pfc_line_of_business.preview_change(
            c_payor_defined, p_requested, l_summary, l_targets);
        fetch_summary;
        CLOSE l_targets;
    END;
BEGIN
    /* Current is payor-only and represents undefined and both valid values. */
    pfc_line_of_business.get_current(c_payor_undefined, l_result);
    FETCH l_result INTO l_status, l_current; CLOSE l_result;
    assert_text('Undefined current status', l_status, 'UNDEFINED');
    assert_text('Undefined current LOB', l_current, NULL);

    pfc_line_of_business.get_current(c_payor_defined, l_result);
    FETCH l_result INTO l_status, l_current; CLOSE l_result;
    assert_text('Home Health current status', l_status, 'DEFINED');
    assert_text('Home Health current LOB', l_current, 'HOME_HEALTH');

    pfc_line_of_business.get_current(c_payor_hospice, l_result);
    FETCH l_result INTO l_status, l_current; CLOSE l_result;
    assert_text('Hospice current LOB', l_current, 'HOSPICE');

    /* Initial assignment preserves existing customization and never commits. */
    SAVEPOINT initial_home;
    clone_target('30000000-0000-0000-0000-00000000D081',
        '61000000-0000-0000-0000-000000000001', c_payor_undefined, NULL);
    pfc_line_of_business.save_initial(
        c_payor_undefined, 'HOME_HEALTH', c_audit, l_result);
    FETCH l_result INTO l_status, l_current; CLOSE l_result;
    assert_text('Initial save status', l_status, 'SAVED');
    SELECT COUNT(*) INTO l_number FROM hcfa_electronic_records
    WHERE electronic_rec_guid = '61000000-0000-0000-0000-000000000001';
    assert_number('Initial save preserved override', l_number, 1);
    l_failed := FALSE;
    BEGIN
        pfc_line_of_business.save_initial(
            c_payor_undefined, 'HOSPICE', c_audit, l_result);
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE = pfc_line_of_business.c_err_lob_already_saved THEN
            l_failed := TRUE; ELSE RAISE; END IF;
    END;
    IF NOT l_failed THEN RAISE_APPLICATION_ERROR(-20972,
        'Duplicate initial save was not rejected.'); END IF;
    ROLLBACK TO initial_home;
    SELECT COUNT(*) INTO l_number FROM pfc_config_payor_context
    WHERE payor_guid = c_payor_undefined;
    assert_number('Initial save had no internal commit', l_number, 0);

    SAVEPOINT initial_hospice;
    pfc_line_of_business.save_initial(
        c_payor_undefined, 'HOSPICE', c_audit, l_result);
    CLOSE l_result;
    ROLLBACK TO initial_hospice;
    l_failed := FALSE;
    BEGIN
        pfc_line_of_business.save_initial(
            c_payor_undefined, 'INVALID', c_audit, l_result);
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE = pfc_line_of_business.c_err_invalid_lob THEN
            l_failed := TRUE; ELSE RAISE; END IF;
    END;
    IF NOT l_failed THEN RAISE_APPLICATION_ERROR(-20973,
        'Invalid Line of Business was not rejected.'); END IF;

    /* Six managed target scopes span NULL, current, other, and stale plans. */
    SAVEPOINT reset_scope;
    clone_target('30000000-0000-0000-0000-00000000D081',
        '62000000-0000-0000-0000-000000000001', c_payor_defined, NULL);
    clone_target('31000000-0000-0000-0000-00000000D771',
        '62000000-0000-0000-0000-000000000002', c_payor_defined, 'PLAN-ONE');
    clone_target('31000000-0000-0000-0000-00000000D772',
        '62000000-0000-0000-0000-000000000003', c_payor_defined, 'PLAN-TWO');
    clone_target('31000000-0000-0000-0000-00000000D773',
        '62000000-0000-0000-0000-000000000004', c_payor_defined, 'STALE-PLAN');
    clone_target('32000000-0000-0000-0000-000000000001',
        '62000000-0000-0000-0000-000000000005', c_payor_defined, 'OTHER-PLAN');
    clone_target('33000000-0000-0000-0000-000000000001',
        '62000000-0000-0000-0000-000000000006', c_payor_defined, 'STALE-PLAN');
    clone_target('30000000-0000-0000-0000-00000000D081',
        '62000000-0000-0000-0000-000000000099', c_payor_defined, 'STALE-PLAN',
        c_unmanaged_type);

    SELECT rec_ent_date, rec_ent_user INTO l_entry_date, l_entry_user
    FROM pfc_config_payor_context WHERE payor_guid = c_payor_defined;
    preview('HOSPICE');
    assert_text('Change preview status', l_status, 'CHANGES_REQUIRED');
    assert_text('Change preview current', l_current, 'HOME_HEALTH');
    assert_text('Change preview requested', l_requested, 'HOSPICE');
    assert_number('All managed targets enumerated', l_target_count, 6);
    assert_number('All managed target scopes affected', l_affected, 6);
    assert_number('All plan HERs counted', l_hers, 6);
    IF l_hefs < 11 THEN RAISE_APPLICATION_ERROR(-20974,
        'Managed HEF count is incomplete.'); END IF;
    IF LENGTH(l_hash) <> 64 THEN RAISE_APPLICATION_ERROR(-20975,
        'LOB preview hash is not SHA-256 sized.'); END IF;
    l_hash_2 := l_hash;
    preview('HOSPICE');
    assert_text('Deterministic preview hash', l_hash, l_hash_2);
    preview('HOME_HEALTH');
    assert_text('Same LOB preview', l_status, 'NO_CHANGE');

    preview('HOSPICE');
    l_hash_2 := l_hash;
    pfc_line_of_business.apply_change(
        c_payor_defined, 'HOSPICE', l_hash_2, c_audit, l_summary, l_targets);
    fetch_summary; CLOSE l_targets;
    assert_text('LOB apply status', l_status, 'APPLIED');
    SELECT COUNT(*) INTO l_number FROM hcfa_electronic_records h
    WHERE h.payor_guid = c_payor_defined
      AND h.electronic_rec_guid IN (
        '62000000-0000-0000-0000-000000000001',
        '62000000-0000-0000-0000-000000000002',
        '62000000-0000-0000-0000-000000000003',
        '62000000-0000-0000-0000-000000000004',
        '62000000-0000-0000-0000-000000000005',
        '62000000-0000-0000-0000-000000000006');
    assert_number('All-plan managed HER reset', l_number, 0);
    SELECT COUNT(*) INTO l_number FROM hcfa_electronic_fields f
    WHERE f.electronic_rec_guid IN (
        '62000000-0000-0000-0000-000000000001',
        '62000000-0000-0000-0000-000000000002',
        '62000000-0000-0000-0000-000000000003',
        '62000000-0000-0000-0000-000000000004',
        '62000000-0000-0000-0000-000000000005',
        '62000000-0000-0000-0000-000000000006');
    assert_number('All managed HEFs reset', l_number, 0);
    SELECT COUNT(*) INTO l_number FROM hcfa_electronic_records
    WHERE electronic_rec_guid = '62000000-0000-0000-0000-000000000099';
    assert_number('Unmanaged HER survives', l_number, 1);
    SELECT COUNT(*) INTO l_number FROM hcfa_electronic_fields
    WHERE electronic_rec_guid = '62000000-0000-0000-0000-000000000099';
    IF l_number = 0 THEN RAISE_APPLICATION_ERROR(-20976,
        'Unmanaged HEFs were deleted.'); END IF;
    SELECT COUNT(*) INTO l_number FROM pfc_config_payor_context c
    WHERE c.payor_guid = c_payor_defined AND c.line_of_business = 'HOSPICE'
      AND c.rec_ent_date = l_entry_date AND c.rec_ent_user = l_entry_user
      AND c.rec_mod_date IS NOT NULL AND c.rec_mod_user = c_audit;
    assert_number('LOB and audit update verified', l_number, 1);
    pfc_value_codes_api.current_configuration(
        c_payor_defined, NULL, l_result);
    FETCH l_result INTO l_status, l_current, l_vc_default,
        l_changes, l_changes, l_changes, l_changes, l_changes,
        l_requested, l_vc_text, l_vc_guid, l_vc_form, l_vc_source,
        l_hers, l_hefs, l_vc_state;
    CLOSE l_result;
    assert_text('Value Codes is Default after LOB reset', l_vc_default, 'Y');
    ROLLBACK TO reset_scope;

    /* A changed managed row makes the destructive preview stale before DML. */
    SAVEPOINT stale_scope;
    clone_target('30000000-0000-0000-0000-00000000D081',
        '63000000-0000-0000-0000-000000000001', c_payor_defined, NULL);
    preview('HOSPICE'); l_hash_2 := l_hash;
    UPDATE hcfa_electronic_records SET notes = 'Synthetic concurrent change'
    WHERE electronic_rec_guid = '63000000-0000-0000-0000-000000000001';
    l_failed := FALSE;
    BEGIN
        pfc_line_of_business.apply_change(c_payor_defined, 'HOSPICE',
            l_hash_2, c_audit, l_summary, l_targets);
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE = pfc_line_of_business.c_err_stale_preview THEN
            l_failed := TRUE; ELSE RAISE; END IF;
    END;
    IF NOT l_failed THEN RAISE_APPLICATION_ERROR(-20977,
        'Stale destructive preview was not rejected.'); END IF;
    SELECT COUNT(*) INTO l_number FROM pfc_config_payor_context
    WHERE payor_guid = c_payor_defined AND line_of_business = 'HOME_HEALTH';
    assert_number('Stale apply preserved old LOB', l_number, 1);
    SELECT COUNT(*) INTO l_number FROM hcfa_electronic_records
    WHERE electronic_rec_guid = '63000000-0000-0000-0000-000000000001';
    assert_number('Stale apply preserved managed HER', l_number, 1);
    ROLLBACK TO stale_scope;

    DBMS_OUTPUT.PUT_LINE('PASS: payor-level LOB save, preview, atomic reset, stale protection, and unmanaged safety are valid.');
    ROLLBACK;
END;
/
