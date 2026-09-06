WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

DECLARE
    c_home_health_payor CONSTANT VARCHAR2(36) :=
        '10000000-0000-0000-0000-0000000000A1';
    c_hospice_payor CONSTANT VARCHAR2(36) :=
        '10000000-0000-0000-0000-0000000000A8';
    c_source_guid CONSTANT VARCHAR2(36) :=
        '32000000-0000-0000-0000-000000000001';
    c_target CONSTANT VARCHAR2(20) := 'D23002310HI286';

    l_source pfc_value_codes.t_configuration_state;
    l_desired pfc_value_codes.t_configuration_state;
    l_dirty_source pfc_value_codes.t_configuration_state;
    l_selections pfc_value_codes.t_selections;
    l_recipe pfc_option_types.t_option_definition;
    l_lob VARCHAR2(20);
    l_status VARCHAR2(50);
    l_count PLS_INTEGER;
    l_failed BOOLEAN;

    PROCEDURE fail(p_message VARCHAR2) IS
    BEGIN
        RAISE_APPLICATION_ERROR(-20980, p_message);
    END;

    PROCEDURE assert_text(
        p_label VARCHAR2, p_actual VARCHAR2, p_expected VARCHAR2
    ) IS
    BEGIN
        IF (p_actual IS NULL AND p_expected IS NOT NULL)
           OR (p_actual IS NOT NULL AND p_expected IS NULL)
           OR p_actual <> p_expected THEN
            fail(p_label || ': unexpected value.');
        END IF;
    END;

    PROCEDURE assert_number(
        p_label VARCHAR2, p_actual NUMBER, p_expected NUMBER
    ) IS
    BEGIN
        IF p_actual <> p_expected THEN
            fail(p_label || ': expected ' || p_expected || ', got ' || p_actual || '.');
        END IF;
    END;

    PROCEDURE assert_hef(
        p_label VARCHAR2,
        p_state pfc_value_codes.t_configuration_state,
        p_field_number VARCHAR2,
        p_sto_proc_name VARCHAR2,
        p_hard_coded_data VARCHAR2
    ) IS
        l_index PLS_INTEGER;
        l_matches PLS_INTEGER := 0;
    BEGIN
        l_index := p_state.hefs.FIRST;
        WHILE l_index IS NOT NULL LOOP
            IF p_state.hefs(l_index).field_number = p_field_number THEN
                l_matches := l_matches + 1;
                assert_text(p_label || ' STO procedure',
                    p_state.hefs(l_index).sto_proc_name, p_sto_proc_name);
                assert_text(p_label || ' hard-coded data',
                    p_state.hefs(l_index).hard_coded_data, p_hard_coded_data);
            END IF;
            l_index := p_state.hefs.NEXT(l_index);
        END LOOP;
        assert_number(p_label || ' selector count', l_matches, 1);
    END;

    PROCEDURE assert_recipe(
        p_label VARCHAR2,
        p_lob VARCHAR2,
        p_selections pfc_value_codes.t_selections,
        p_expected_recipe VARCHAR2
    ) IS
        l_local pfc_value_codes.t_configuration_state;
    BEGIN
        l_local := pfc_value_codes.build_desired_state(
            p_lob, p_selections, l_source);
        IF p_expected_recipe = pfc_value_codes.c_recipe_default THEN
            assert_number(p_label || ' canonical inherited override count',
                pfc_value_codes.canonical_override_count(l_source, l_local), 0);
        ELSE
            assert_text(p_label || ' recognition',
                pfc_value_codes.recognize_state(p_lob, l_local), p_expected_recipe);
            assert_number(p_label || ' canonical differing override count',
                pfc_value_codes.canonical_override_count(l_source, l_local), 1);
        END IF;
    END;

    PROCEDURE clone_source_her(p_guid VARCHAR2) IS
    BEGIN
        INSERT INTO hcfa_electronic_records (
            electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
            record_name, record_type_code, record_size, mandatory_ind,
            req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
            type_of_bill, detail_ind, max_number, invoice_ind,
            form_template_guid, carry_forward_ind, max_carry_forward,
            sto_proc_name, user_form_template_guid, notes,
            rec_ent_date, rec_ent_user, include_record_data_onclaim
        ) SELECT
            p_guid, h.loop_id, h.contiguity_ind, h.billing_form_code,
            'Synthetic duplicate Value Codes override', h.record_type_code,
            h.record_size, h.mandatory_ind, h.req_for_claim_ind,
            '11000000-0000-0000-0000-000000000001', c_home_health_payor,
            NULL, NULL, h.detail_ind, h.max_number, h.invoice_ind,
            h.form_template_guid, h.carry_forward_ind, h.max_carry_forward,
            h.sto_proc_name, h.user_form_template_guid,
            'Synthetic duplicate stale payor HER', SYSDATE,
            '90000000-0000-0000-0000-000000000001',
            h.include_record_data_onclaim
        FROM hcfa_electronic_records h
        WHERE h.electronic_rec_guid = c_source_guid;
    END;
BEGIN
    SELECT line_of_business INTO l_lob
    FROM pfc_config_payor_context
    WHERE payor_guid = c_home_health_payor;
    assert_text('Synthetic Home Health saved LOB', l_lob, 'HOME_HEALTH');
    SELECT line_of_business INTO l_lob
    FROM pfc_config_payor_context
    WHERE payor_guid = c_hospice_payor;
    assert_text('Synthetic Hospice saved LOB', l_lob, 'HOSPICE');

    SELECT h.sto_proc_name INTO l_source.her_sto_proc_name
    FROM hcfa_electronic_records h
    WHERE h.electronic_rec_guid = c_source_guid
      AND h.record_type_code = c_target;
    FOR row_value IN (
        SELECT field_number, field_name, sto_proc_name, hard_coded_data
        FROM hcfa_electronic_fields
        WHERE electronic_rec_guid = c_source_guid
        ORDER BY order_num
    ) LOOP
        l_count := l_source.hefs.COUNT + 1;
        l_source.hefs(l_count).field_number := row_value.field_number;
        l_source.hefs(l_count).field_name := row_value.field_name;
        l_source.hefs(l_count).sto_proc_name := row_value.sto_proc_name;
        l_source.hefs(l_count).hard_coded_data := row_value.hard_coded_data;
    END LOOP;
    assert_number('Complete synthetic source HEF count', l_source.hefs.COUNT, 5);

    /* DEFAULT is the complete source, including unusual managed values. */
    l_dirty_source := l_source;
    l_dirty_source.hefs(3).sto_proc_name := NULL;
    l_dirty_source.hefs(3).hard_coded_data := 'SYNTHETIC_DIRTY_VALUE';
    l_selections := pfc_value_codes.no_selections();
    l_desired := pfc_value_codes.build_desired_state(
        'HOME_HEALTH', l_selections, l_dirty_source);
    assert_hef('Default retains inherited managed pair', l_desired, '022',
        NULL, 'SYNTHETIC_DIRTY_VALUE');

    l_selections := pfc_value_codes.no_selections();
    assert_recipe('Home Health default', 'HOME_HEALTH', l_selections, 'DEFAULT');
    l_selections.cbsa := 'Y';
    assert_recipe('Home Health CBSA', 'HOME_HEALTH', l_selections,
        'HOME_HEALTH_CBSA');
    l_desired := pfc_value_codes.build_desired_state(
        'HOME_HEALTH', l_selections, l_source);
    assert_hef('CBSA code', l_desired, '012', NULL, '61');
    assert_hef('CBSA amount', l_desired, '015', 'GET_PAT_CBSA_CODE', NULL);
    assert_hef('CBSA generic second code', l_desired, '022', 'GET_VAL_CODE', NULL);
    assert_hef('CBSA generic second amount', l_desired, '025', 'GET_VAL_CODE_AMT', NULL);
    assert_hef('Unmanaged source retained', l_desired, '030',
        'SYN_KEEP_UNMANAGED', 'KEEP_UNMANAGED');
    assert_number('Complete desired HEF set retained', l_desired.hefs.COUNT, 5);

    l_selections.fips := 'Y';
    assert_recipe('Home Health CBSA and FIPS', 'HOME_HEALTH', l_selections,
        'HOME_HEALTH_CBSA_FIPS');
    l_desired := pfc_value_codes.build_desired_state(
        'HOME_HEALTH', l_selections, l_source);
    assert_hef('FIPS code', l_desired, '022', 'GET_FIPS_CODE', NULL);
    assert_hef('FIPS value', l_desired, '025', 'GET_FIPS_CODE_VALUE', NULL);

    l_selections := pfc_value_codes.no_selections();
    l_selections.fips := 'Y';
    l_failed := FALSE;
    BEGIN
        l_recipe := pfc_value_codes.get_recipe('HOME_HEALTH', l_selections);
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE = pfc_value_codes.c_err_invalid_selection THEN
            l_failed := TRUE;
        ELSE RAISE; END IF;
    END;
    IF NOT l_failed THEN fail('FIPS without CBSA was not rejected.'); END IF;

    l_selections := pfc_value_codes.no_selections();
    assert_recipe('Hospice default', 'HOSPICE', l_selections, 'DEFAULT');
    l_selections.care_location_value_code := 'Y';
    assert_recipe('Hospice care location', 'HOSPICE', l_selections,
        'HOSPICE_61_G8');
    l_desired := pfc_value_codes.build_desired_state(
        'HOSPICE', l_selections, l_source);
    assert_hef('Care-location code', l_desired, '012', 'GET_CARE_LOC_CODE', NULL);
    assert_hef('Care-location value', l_desired, '015',
        'GET_CARE_LOC_VAL_CODE', NULL);

    l_selections.covered_days_value_code := 'Y';
    assert_recipe('Hospice care location and days', 'HOSPICE', l_selections,
        'HOSPICE_61_G8_VC80_DAYS');
    l_desired := pfc_value_codes.build_desired_state(
        'HOSPICE', l_selections, l_source);
    assert_hef('Care-location and days code', l_desired, '012', 'GET_CARE_LOC_CODE', NULL);
    assert_hef('Care-location and days amount', l_desired, '015', 'GET_CARE_LOC_VAL_CODE', NULL);
    assert_hef('Care-location and days 80', l_desired, '022', NULL, '80');
    assert_hef('Covered days value', l_desired, '025',
        'GET_DISTINCT_COVERED_DAYS', NULL);

    l_selections := pfc_value_codes.no_selections();
    l_selections.patient_entered_value_code := 'Y';
    assert_recipe('Hospice patient-entered only', 'HOSPICE', l_selections,
        'HOSPICE_PATIENT_VALUE');
    l_desired := pfc_value_codes.build_desired_state(
        'HOSPICE', l_selections, l_source);
    assert_hef('Patient-only first code', l_desired, '012',
        'GET_VAL_CODE', NULL);
    assert_hef('Patient-only first amount', l_desired, '015',
        'GET_VAL_CODE_AMT', NULL);
    assert_hef('Patient-only second code', l_desired, '022',
        'GET_VAL_CODE', NULL);
    assert_hef('Patient-only second amount', l_desired, '025',
        'GET_VAL_CODE_AMT', NULL);

    l_selections.covered_days_value_code := 'Y';
    assert_recipe('Hospice patient-entered and days', 'HOSPICE', l_selections,
        'HOSPICE_PATIENT_VALUE_VC80_DAYS');

    l_selections := pfc_value_codes.no_selections();
    l_selections.covered_days_value_code := 'Y';
    assert_recipe('Hospice days only', 'HOSPICE', l_selections,
        'HOSPICE_VC80_DAYS');
    l_desired := pfc_value_codes.build_desired_state(
        'HOSPICE', l_selections, l_source);
    assert_hef('Days-only 80', l_desired, '012', NULL, '80');
    assert_hef('Days-only amount', l_desired, '015',
        'GET_DISTINCT_COVERED_DAYS', NULL);
    assert_hef('Days-only retained generic code', l_desired, '022',
        'GET_VAL_CODE', NULL);

    /* Both care-location/patient-entered conflicts fail regardless of VC80. */
    FOR unsupported IN 1 .. 2 LOOP
        l_selections := pfc_value_codes.no_selections();
        IF unsupported = 1 THEN
            l_selections.care_location_value_code := 'Y';
            l_selections.patient_entered_value_code := 'Y';
        ELSE
            l_selections.care_location_value_code := 'Y';
            l_selections.patient_entered_value_code := 'Y';
            l_selections.covered_days_value_code := 'Y';
        END IF;
        l_failed := FALSE;
        BEGIN
            l_recipe := pfc_value_codes.get_recipe('HOSPICE', l_selections);
        EXCEPTION WHEN OTHERS THEN
            IF SQLCODE = pfc_value_codes.c_err_invalid_selection THEN
                l_failed := TRUE;
            ELSE RAISE; END IF;
        END;
        IF NOT l_failed THEN fail('Conflicting Hospice combination was accepted.'); END IF;
    END LOOP;

    l_selections := pfc_value_codes.no_selections();
    l_selections.care_location_value_code := 'Y';
    l_failed := FALSE;
    BEGIN
        l_recipe := pfc_value_codes.get_recipe('HOME_HEALTH', l_selections);
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE = pfc_value_codes.c_err_invalid_selection THEN
            l_failed := TRUE;
        ELSE RAISE; END IF;
    END;
    IF NOT l_failed THEN fail('Home Health accepted a Hospice capability.'); END IF;

    l_selections := pfc_value_codes.no_selections();
    l_selections.cbsa := 'Y';
    l_failed := FALSE;
    BEGIN
        l_recipe := pfc_value_codes.get_recipe('HOSPICE', l_selections);
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE = pfc_value_codes.c_err_invalid_selection THEN
            l_failed := TRUE;
        ELSE RAISE; END IF;
    END;
    IF NOT l_failed THEN fail('Hospice accepted a Home Health capability.'); END IF;

    l_failed := FALSE;
    BEGIN
        l_recipe := pfc_value_codes.get_recipe(NULL, l_selections);
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE = pfc_value_codes.c_err_lob_required THEN
            l_failed := TRUE;
        ELSE RAISE; END IF;
    END;
    IF NOT l_failed THEN fail('Undefined Line of Business was not blocked.'); END IF;

    /* A mixed effective state is diagnostic-only and is never guessed. */
    l_selections := pfc_value_codes.no_selections();
    l_desired := pfc_value_codes.build_desired_state(
        'HOME_HEALTH', l_selections, l_source);
    l_desired.hefs(4).sto_proc_name := 'MIXED_UNREGISTERED_PROC';
    assert_text('Mixed current state',
        pfc_value_codes.recognize_state('HOME_HEALTH', l_desired),
        'UNRECOGNIZED');
    l_desired.hefs(6) := l_desired.hefs(1);
    assert_text('Duplicate managed current HEF',
        pfc_value_codes.recognize_state('HOME_HEALTH', l_desired),
        'UNRECOGNIZED');

    /* Duplicate stale payor HER fixture is explicitly blocked by policy. */
    SAVEPOINT duplicate_payor_scope;
    clone_source_her('65000000-0000-0000-0000-000000000001');
    clone_source_her('65000000-0000-0000-0000-000000000002');
    SELECT COUNT(*) INTO l_count
    FROM hcfa_electronic_records
    WHERE payor_guid = c_home_health_payor
      AND billing_form_code = '837I_5010'
      AND record_type_code = c_target;
    assert_number('Duplicate stale payor HER fixture', l_count, 2);
    l_status := pfc_value_codes.current_effective_status(
        'RESOLVED', l_count, 'DEFAULT');
    assert_text('Duplicate stale payor HER status', l_status,
        'BLOCKED_DUPLICATE_PAYOR_HER');
    ROLLBACK TO duplicate_payor_scope;

    DBMS_OUTPUT.PUT_LINE(
        'PASS: Value Codes recipes, structured validation, desired-state construction, current recognition, and synthetic safety fixtures are valid.'
    );
    ROLLBACK;
END;
/
