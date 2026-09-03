WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

DECLARE
    c_audit_user CONSTANT VARCHAR2(36) :=
        '90000000-0000-0000-0000-000000000003';

    l_status                  VARCHAR2(20);
    l_summary_option_code     VARCHAR2(100);
    l_display_label           VARCHAR2(200);
    l_summary_payor_guid      payors.payor_guid%TYPE;
    l_summary_plan_guid       pfc.plan_guid%TYPE;
    l_summary_pfc_guid        pfc.pfc_guid%TYPE;
    l_summary_billing_form    pfc.billing_form_code%TYPE;
    l_summary_record_type     hcfa_electronic_records.record_type_code%TYPE;
    l_source_guid             hcfa_electronic_records.electronic_rec_guid%TYPE;
    l_existing_her_count      PLS_INTEGER;
    l_existing_hef_count      PLS_INTEGER;
    l_new_hef_count           PLS_INTEGER;
    l_state_hash              VARCHAR2(64);
    l_change_count            PLS_INTEGER;
    l_delete_hef_count        PLS_INTEGER;
    l_delete_her_count        PLS_INTEGER;
    l_insert_her_count        PLS_INTEGER;
    l_insert_hef_count        PLS_INTEGER;
    l_set_her_count           PLS_INTEGER;
    l_set_hef_count           PLS_INTEGER;
    l_clear_her_count         PLS_INTEGER;
    l_clear_hef_count         PLS_INTEGER;
    l_operation_order         PLS_INTEGER;
    l_operation_code          VARCHAR2(30);
    l_change_target_guid      VARCHAR2(64);
    l_change_field_number     hcfa_electronic_fields.field_number%TYPE;
    l_change_attribute        VARCHAR2(128);
    l_change_old_value        VARCHAR2(4000);
    l_change_new_value        VARCHAR2(4000);
    l_target_guid             hcfa_electronic_records.electronic_rec_guid%TYPE;
    l_text                    VARCHAR2(4000);
    l_text_2                  VARCHAR2(4000);
    l_number                  PLS_INTEGER;
    l_number_2                PLS_INTEGER;
    l_date                    DATE;
    l_before_guid             hcfa_electronic_records.electronic_rec_guid%TYPE;
    l_before_user             hcfa_electronic_records.rec_ent_user%TYPE;
    l_before_date             hcfa_electronic_records.rec_ent_date%TYPE;
    l_preview_hash            VARCHAR2(64);
    l_stale_rejected          BOOLEAN;
    l_action_prv              VARCHAR2(30);
    l_action_nm1              VARCHAR2(30);
    l_action_n3               VARCHAR2(30);
    l_action_n4               VARCHAR2(30);

    PROCEDURE assert_text (
        p_label    IN VARCHAR2,
        p_actual   IN VARCHAR2,
        p_expected IN VARCHAR2
    ) IS
    BEGIN
        IF (p_actual IS NULL AND p_expected IS NOT NULL)
           OR (p_actual IS NOT NULL AND p_expected IS NULL)
           OR (p_actual IS NOT NULL AND p_expected IS NOT NULL
               AND p_actual <> p_expected) THEN
            RAISE_APPLICATION_ERROR(
                -20930,
                p_label || ' expected [' || NVL(p_expected, '<NULL>') ||
                '] but found [' || NVL(p_actual, '<NULL>') || '].'
            );
        END IF;
    END assert_text;

    PROCEDURE assert_number (
        p_label    IN VARCHAR2,
        p_actual   IN NUMBER,
        p_expected IN NUMBER
    ) IS
    BEGIN
        IF (p_actual IS NULL AND p_expected IS NOT NULL)
           OR (p_actual IS NOT NULL AND p_expected IS NULL)
           OR (p_actual IS NOT NULL AND p_expected IS NOT NULL
               AND p_actual <> p_expected) THEN
            RAISE_APPLICATION_ERROR(
                -20931,
                p_label || ' expected ' || NVL(TO_CHAR(p_expected), '<NULL>') ||
                ' but found ' || NVL(TO_CHAR(p_actual), '<NULL>') || '.'
            );
        END IF;
    END assert_number;

    PROCEDURE call_option (
        p_payor_guid   IN payors.payor_guid%TYPE,
        p_option_code  IN VARCHAR2,
        p_mode         IN VARCHAR2,
        p_expected_hash IN VARCHAR2 DEFAULT NULL
    ) IS
        l_summary              SYS_REFCURSOR;
        l_changes              SYS_REFCURSOR;
        l_fetched_dml_count    PLS_INTEGER := 0;
        l_last_order           PLS_INTEGER := 0;
        l_last_phase           PLS_INTEGER := 0;
        l_phase                PLS_INTEGER;
        l_target_action        VARCHAR2(30);
        l_matches_source       VARCHAR2(1);
        l_matches_desired      VARCHAR2(1);
    BEGIN
        l_delete_hef_count := 0;
        l_delete_her_count := 0;
        l_insert_her_count := 0;
        l_insert_hef_count := 0;
        l_set_her_count := 0;
        l_set_hef_count := 0;
        l_clear_her_count := 0;
        l_clear_hef_count := 0;
        l_action_prv := NULL;
        l_action_nm1 := NULL;
        l_action_n3 := NULL;
        l_action_n4 := NULL;

        pfc_apply_option(
            p_payor_guid => p_payor_guid,
            p_plan_guid => NULL,
            p_option_code => p_option_code,
            p_audit_user => c_audit_user,
            p_mode => p_mode,
            p_expected_state_hash => p_expected_hash,
            p_summary => l_summary,
            p_changes => l_changes
        );

        FETCH l_summary INTO
            l_status,
            l_summary_option_code,
            l_display_label,
            l_summary_payor_guid,
            l_summary_plan_guid,
            l_summary_pfc_guid,
            l_summary_billing_form,
            l_summary_record_type,
            l_source_guid,
            l_target_action,
            l_matches_source,
            l_matches_desired,
            l_existing_her_count,
            l_existing_hef_count,
            l_new_hef_count,
            l_state_hash,
            l_change_count;
        IF l_summary%NOTFOUND THEN
            RAISE_APPLICATION_ERROR(-20932, 'Script 3 returned no summary row.');
        END IF;
        CLOSE l_summary;

        LOOP
            FETCH l_changes INTO
                l_operation_order,
                l_operation_code,
                l_change_target_guid,
                l_change_field_number,
                l_change_attribute,
                l_change_old_value,
                l_change_new_value;
            EXIT WHEN l_changes%NOTFOUND;
            IF l_operation_order <= l_last_order THEN
                RAISE_APPLICATION_ERROR(
                    -20938,
                    'Script 3 change operations are not deterministically ordered.'
                );
            END IF;
            l_last_order := l_operation_order;
            CASE l_operation_code
                WHEN 'NO_CHANGE' THEN
                    l_phase := 0;
                    CASE l_change_target_guid
                        WHEN 'PRV' THEN l_action_prv := l_operation_code;
                        WHEN 'NM1' THEN l_action_nm1 := l_operation_code;
                        WHEN 'N3' THEN l_action_n3 := l_operation_code;
                        WHEN 'N4' THEN l_action_n4 := l_operation_code;
                        ELSE RAISE_APPLICATION_ERROR(
                            -20933, 'Unknown target action identifier.');
                    END CASE;
                WHEN 'REMOVE_OVERRIDE' THEN
                    l_phase := 0;
                    CASE l_change_target_guid
                        WHEN 'PRV' THEN l_action_prv := l_operation_code;
                        WHEN 'NM1' THEN l_action_nm1 := l_operation_code;
                        WHEN 'N3' THEN l_action_n3 := l_operation_code;
                        WHEN 'N4' THEN l_action_n4 := l_operation_code;
                        ELSE RAISE_APPLICATION_ERROR(
                            -20933, 'Unknown target action identifier.');
                    END CASE;
                WHEN 'REBUILD_OVERRIDE' THEN
                    l_phase := 0;
                    CASE l_change_target_guid
                        WHEN 'PRV' THEN l_action_prv := l_operation_code;
                        WHEN 'NM1' THEN l_action_nm1 := l_operation_code;
                        WHEN 'N3' THEN l_action_n3 := l_operation_code;
                        WHEN 'N4' THEN l_action_n4 := l_operation_code;
                        ELSE RAISE_APPLICATION_ERROR(
                            -20933, 'Unknown target action identifier.');
                    END CASE;
                WHEN 'DELETE_HEF' THEN
                    l_delete_hef_count := l_delete_hef_count + 1;
                    l_fetched_dml_count := l_fetched_dml_count + 1;
                    l_phase := 1;
                WHEN 'DELETE_HER' THEN
                    l_delete_her_count := l_delete_her_count + 1;
                    l_fetched_dml_count := l_fetched_dml_count + 1;
                    l_phase := 2;
                WHEN 'INSERT_HER' THEN
                    l_insert_her_count := l_insert_her_count + 1;
                    l_fetched_dml_count := l_fetched_dml_count + 1;
                    l_phase := 3;
                WHEN 'INSERT_HEF' THEN
                    l_insert_hef_count := l_insert_hef_count + 1;
                    l_fetched_dml_count := l_fetched_dml_count + 1;
                    l_phase := 4;
                WHEN 'SET_HER_VALUE' THEN
                    l_set_her_count := l_set_her_count + 1;
                    l_phase := 5;
                WHEN 'SET_HEF_VALUE' THEN
                    l_set_hef_count := l_set_hef_count + 1;
                    l_phase := 5;
                WHEN 'CLEAR_HER_VALUE' THEN
                    l_clear_her_count := l_clear_her_count + 1;
                    l_phase := 5;
                WHEN 'CLEAR_HEF_VALUE' THEN
                    l_clear_hef_count := l_clear_hef_count + 1;
                    l_phase := 5;
                ELSE
                    RAISE_APPLICATION_ERROR(
                        -20933,
                        'Script 3 returned an unknown change operation.'
                    );
            END CASE;
            IF l_phase < l_last_phase THEN
                RAISE_APPLICATION_ERROR(
                    -20939,
                    'Script 3 change operations violate rebuild order.'
                );
            END IF;
            l_last_phase := l_phase;
        END LOOP;
        CLOSE l_changes;
        assert_number(
            'summary change count',
            l_fetched_dml_count,
            l_change_count
        );
    END call_option;

    PROCEDURE get_target_her (
        p_payor_guid IN payors.payor_guid%TYPE,
        p_guid       OUT hcfa_electronic_records.electronic_rec_guid%TYPE,
        p_sto_proc   OUT hcfa_electronic_records.sto_proc_name%TYPE,
        p_form       OUT hcfa_electronic_records.form_template_guid%TYPE,
        p_user_form  OUT hcfa_electronic_records.user_form_template_guid%TYPE,
        p_payor_type OUT hcfa_electronic_records.payor_type_guid%TYPE
    ) IS
    BEGIN
        SELECT
            h.electronic_rec_guid,
            h.sto_proc_name,
            h.form_template_guid,
            h.user_form_template_guid,
            h.payor_type_guid
        INTO
            p_guid,
            p_sto_proc,
            p_form,
            p_user_form,
            p_payor_type
        FROM hcfa_electronic_records h
        WHERE h.payor_guid = p_payor_guid
          AND h.billing_form_code = 'UB04'
          AND h.record_type_code = 'B2000A0030PRV080';
    END get_target_her;

BEGIN
    /*
     * UI Demo Payor: fresh inherited OFF/NEVER state with no overrides.
     * Preview the two intended first UI changes without persisting DML.
     */
    SAVEPOINT test_ui_demo_payor;
    call_option(
        '10000000-0000-0000-0000-00000000D001',
        'PROVIDER_TAXONOMY_OFF',
        'PREVIEW'
    );
    assert_text('UI Demo Provider OFF status', l_status, 'NO_CHANGE');
    assert_text('UI Demo Provider OFF action', l_action_prv, 'NO_CHANGE');
    assert_text(
        'UI Demo selected PFC',
        l_summary_pfc_guid,
        '20000000-0000-0000-0000-00000000D001'
    );
    assert_text(
        'UI Demo billing form',
        l_summary_billing_form,
        '837I_5010'
    );

    call_option(
        '10000000-0000-0000-0000-00000000D001',
        'PROVIDER_TAXONOMY_ON',
        'PREVIEW'
    );
    assert_text('UI Demo Provider ON status', l_status, 'PREVIEW');
    assert_text(
        'UI Demo Provider ON action',
        l_action_prv,
        'REBUILD_OVERRIDE'
    );

    call_option(
        '10000000-0000-0000-0000-00000000D001',
        'SERVICE_FACILITY_NEVER',
        'PREVIEW'
    );
    assert_text('UI Demo Service NEVER status', l_status, 'NO_CHANGE');
    assert_text('UI Demo Service NEVER NM1', l_action_nm1, 'NO_CHANGE');
    assert_text('UI Demo Service NEVER N3', l_action_n3, 'NO_CHANGE');
    assert_text('UI Demo Service NEVER N4', l_action_n4, 'NO_CHANGE');

    call_option(
        '10000000-0000-0000-0000-00000000D001',
        'SERVICE_FACILITY_ALWAYS_ADDRESS_YES',
        'PREVIEW'
    );
    assert_text('UI Demo Service ALWAYS/Y status', l_status, 'PREVIEW');
    assert_text(
        'UI Demo Service ALWAYS/Y NM1',
        l_action_nm1,
        'REBUILD_OVERRIDE'
    );
    assert_text(
        'UI Demo Service ALWAYS/Y N3',
        l_action_n3,
        'REBUILD_OVERRIDE'
    );
    assert_text(
        'UI Demo Service ALWAYS/Y N4',
        l_action_n4,
        'REBUILD_OVERRIDE'
    );

    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-00000000D001'
      AND h.billing_form_code = '837I_5010'
      AND h.record_type_code IN (
        'B2000A0030PRV080',
        'D2310E2500NM1343',
        'D2310E2650N3346',
        'D2310E2700N4347'
      );
    assert_number('UI Demo payor override count', l_number, 0);
    ROLLBACK TO test_ui_demo_payor;
    DBMS_OUTPUT.PUT_LINE(
        'PASS: UI Demo Payor inherited OFF/NEVER and previews rebuilds.'
    );

    /* PAYOR_A: preview and canonical apply from the billing-form source. */
    SAVEPOINT test_payor_a;
    SELECT h.carry_forward_ind, h.include_record_data_onclaim
    INTO l_text, l_text_2
    FROM hcfa_electronic_records h
    WHERE h.electronic_rec_guid =
        '30000000-0000-0000-0000-000000000001';
    assert_text('Provider source carry-forward fixture', l_text, 'N');
    assert_text('Provider source include-on-claim fixture', l_text_2, 'N');
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'PROVIDER_TAXONOMY_ON',
        'PREVIEW'
    );
    assert_text('PAYOR_A preview status', l_status, 'PREVIEW');
    assert_number('PAYOR_A existing HERs', l_existing_her_count, 0);
    assert_number('PAYOR_A existing HEFs', l_existing_hef_count, 0);
    assert_number('PAYOR_A new HEFs', l_new_hef_count, 4);
    assert_number('PAYOR_A deleted HER operations', l_delete_her_count, 0);
    assert_number('PAYOR_A inserted HER operations', l_insert_her_count, 1);
    assert_number('PAYOR_A inserted HEF operations', l_insert_hef_count, 4);
    assert_text('PAYOR_A target action', l_action_prv, 'REBUILD_OVERRIDE');
    IF LENGTH(l_state_hash) <> 64 THEN
        RAISE_APPLICATION_ERROR(-20934, 'PAYOR_A preview hash is not SHA256-sized.');
    END IF;
    l_preview_hash := l_state_hash;

    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'PROVIDER_TAXONOMY_ON',
        'APPLY',
        l_preview_hash
    );
    assert_text('PAYOR_A apply status', l_status, 'APPLIED');
    get_target_her(
        '10000000-0000-0000-0000-0000000000A1',
        l_target_guid, l_text, l_text_2, l_before_user, l_before_guid
    );
    assert_text('PAYOR_A HER procedure', l_text, 'RETURN_1');
    assert_text('PAYOR_A form template', l_text_2, NULL);
    SELECT
        h.carry_forward_ind,
        h.include_record_data_onclaim,
        h.max_carry_forward
    INTO l_text, l_text_2, l_number
    FROM hcfa_electronic_records h
    WHERE h.electronic_rec_guid = l_target_guid;
    assert_text('PAYOR_A canonical carry forward', l_text, NULL);
    assert_text('PAYOR_A canonical include on claim', l_text_2, 'Y');
    assert_number('PAYOR_A source max carry forward retained', l_number, 0);
    IF LENGTH(l_target_guid) <> 32
       OR NOT REGEXP_LIKE(l_target_guid, '^[0-9A-F]{32}$') THEN
        RAISE_APPLICATION_ERROR(-20935, 'PAYOR_A received an invalid generated GUID.');
    END IF;
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_fields f
    WHERE f.electronic_rec_guid = l_target_guid;
    assert_number('PAYOR_A cloned HEF count', l_number, 4);
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_fields f
    WHERE f.electronic_rec_guid = l_target_guid
      AND f.field_name = 'PRV03'
      AND f.sto_proc_name = 'G_PROVIDER_TAXONOMY_CODE'
      AND f.hard_coded_data IS NULL;
    assert_number('PAYOR_A PRV03 overlay', l_number, 1);
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    WHERE h.electronic_rec_guid = l_target_guid
      AND h.rec_ent_user = c_audit_user
      AND h.rec_mod_date IS NULL
      AND h.rec_mod_user IS NULL;
    assert_number('PAYOR_A HER audit values', l_number, 1);
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_fields f
    WHERE f.electronic_rec_guid = l_target_guid
      AND f.rec_ent_user = c_audit_user
      AND f.rec_mod_date IS NULL
      AND f.rec_mod_user IS NULL;
    assert_number('PAYOR_A HEF audit values', l_number, 4);
    ROLLBACK TO test_payor_a;
    DBMS_OUTPUT.PUT_LINE('PASS: PAYOR_A preview/apply cloned the complete canonical source.');

    /* PAYOR_B: exact canonical state must remain untouched. */
    SAVEPOINT test_payor_b;
    SELECT h.electronic_rec_guid, h.rec_ent_user, h.rec_ent_date
    INTO l_before_guid, l_before_user, l_before_date
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A2'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code = 'B2000A0030PRV080';
    SELECT
        h.payor_type_guid,
        h.carry_forward_ind,
        h.include_record_data_onclaim
    INTO l_text, l_text_2, l_change_new_value
    FROM hcfa_electronic_records h
    WHERE h.electronic_rec_guid = l_before_guid;
    assert_text('PAYOR_B tolerated NULL payor type fixture', l_text, NULL);
    assert_text('PAYOR_B canonical carry-forward fixture', l_text_2, NULL);
    assert_text('PAYOR_B canonical include-on-claim fixture', l_change_new_value, 'Y');
    call_option(
        '10000000-0000-0000-0000-0000000000A2',
        'PROVIDER_TAXONOMY_ON',
        'PREVIEW'
    );
    assert_text('PAYOR_B preview status', l_status, 'NO_CHANGE');
    assert_number('PAYOR_B preview operations', l_change_count, 0);
    l_preview_hash := l_state_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A2',
        'PROVIDER_TAXONOMY_ON',
        'APPLY',
        l_preview_hash
    );
    assert_text('PAYOR_B apply status', l_status, 'NO_CHANGE');
    SELECT h.electronic_rec_guid, h.rec_ent_user, h.rec_ent_date
    INTO l_target_guid, l_text, l_date
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A2'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code = 'B2000A0030PRV080';
    assert_text('PAYOR_B HER identity', l_target_guid, l_before_guid);
    assert_text('PAYOR_B audit user', l_text, l_before_user);
    IF l_date <> l_before_date THEN
        RAISE_APPLICATION_ERROR(-20936, 'PAYOR_B audit date changed.');
    END IF;

    UPDATE hcfa_electronic_records h
    SET h.carry_forward_ind = 'N'
    WHERE h.electronic_rec_guid = l_before_guid;
    call_option(
        '10000000-0000-0000-0000-0000000000A2',
        'PROVIDER_TAXONOMY_ON',
        'PREVIEW'
    );
    assert_text(
        'PAYOR_B noncanonical carry-forward action',
        l_action_prv,
        'REBUILD_OVERRIDE'
    );

    UPDATE hcfa_electronic_records h
    SET
        h.carry_forward_ind = NULL,
        h.include_record_data_onclaim = 'N'
    WHERE h.electronic_rec_guid = l_before_guid;
    call_option(
        '10000000-0000-0000-0000-0000000000A2',
        'PROVIDER_TAXONOMY_ON',
        'PREVIEW'
    );
    assert_text(
        'PAYOR_B noncanonical include-on-claim action',
        l_action_prv,
        'REBUILD_OVERRIDE'
    );

    UPDATE hcfa_electronic_records h
    SET h.include_record_data_onclaim = 'Y'
    WHERE h.electronic_rec_guid = l_before_guid;

    /* The same ON override is stale when the source and request are both OFF. */
    call_option(
        '10000000-0000-0000-0000-0000000000A2',
        'PROVIDER_TAXONOMY_OFF',
        'PREVIEW'
    );
    assert_text('PAYOR_B OFF target action', l_action_prv, 'REMOVE_OVERRIDE');
    l_preview_hash := l_state_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A2',
        'PROVIDER_TAXONOMY_OFF',
        'APPLY',
        l_preview_hash
    );
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A2'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code = 'B2000A0030PRV080';
    assert_number('PAYOR_B OFF override count', l_number, 0);
    ROLLBACK TO test_payor_b;
    DBMS_OUTPUT.PUT_LINE('PASS: PAYOR_B exact ON was untouched and stale OFF was removed.');

    /* PAYOR_C: source-equivalent ON removes both stale overrides. */
    SAVEPOINT test_payor_c;
    call_option(
        '10000000-0000-0000-0000-0000000000A3',
        'PROVIDER_TAXONOMY_ON',
        'PREVIEW'
    );
    assert_text('PAYOR_C preview status', l_status, 'PREVIEW');
    assert_text(
        'PAYOR_C source', l_source_guid,
        '30000000-0000-0000-0000-0000000000F1'
    );
    assert_number('PAYOR_C stale HER count', l_existing_her_count, 2);
    assert_number('PAYOR_C stale HEF count', l_existing_hef_count, 8);
    assert_number('PAYOR_C DELETE_HEF operations', l_delete_hef_count, 8);
    assert_number('PAYOR_C DELETE_HER operations', l_delete_her_count, 2);
    assert_number('PAYOR_C INSERT_HER operations', l_insert_her_count, 0);
    assert_text('PAYOR_C target action', l_action_prv, 'REMOVE_OVERRIDE');
    l_preview_hash := l_state_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A3',
        'PROVIDER_TAXONOMY_ON',
        'APPLY',
        l_preview_hash
    );
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A3'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code = 'B2000A0030PRV080';
    assert_number('PAYOR_C stale HERs remaining', l_number, 0);
    ROLLBACK TO test_payor_c;
    DBMS_OUTPUT.PUT_LINE('PASS: PAYOR_C removed duplicate source-equivalent overrides.');

    /* PAYOR_D: incorrect managed HEF forces a rebuild. */
    SAVEPOINT test_payor_d;
    call_option(
        '10000000-0000-0000-0000-0000000000A4',
        'PROVIDER_TAXONOMY_ON',
        'PREVIEW'
    );
    assert_text('PAYOR_D preview status', l_status, 'PREVIEW');
    l_preview_hash := l_state_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A4',
        'PROVIDER_TAXONOMY_ON',
        'APPLY',
        l_preview_hash
    );
    get_target_her(
        '10000000-0000-0000-0000-0000000000A4',
        l_target_guid, l_text, l_text_2, l_before_user, l_before_guid
    );
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_fields f
    WHERE f.electronic_rec_guid = l_target_guid
      AND f.field_name = 'PRV03'
      AND f.sto_proc_name = 'G_PROVIDER_TAXONOMY_CODE'
      AND f.hard_coded_data IS NULL;
    assert_number('PAYOR_D corrected PRV03', l_number, 1);
    call_option(
        '10000000-0000-0000-0000-0000000000A4',
        'PROVIDER_TAXONOMY_ON',
        'PREVIEW'
    );
    assert_text('PAYOR_D canonical re-preview', l_status, 'NO_CHANGE');
    assert_text('PAYOR_D canonical action', l_action_prv, 'NO_CHANGE');
    ROLLBACK TO test_payor_d;
    DBMS_OUTPUT.PUT_LINE('PASS: PAYOR_D incorrect PRV03 forced a canonical rebuild.');

    /* OFF/OFF with no override is canonical without DML. */
    SAVEPOINT test_option_off;
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'PROVIDER_TAXONOMY_OFF',
        'PREVIEW'
    );
    assert_text('OFF preview status', l_status, 'NO_CHANGE');
    assert_text('OFF target action', l_action_prv, 'NO_CHANGE');
    assert_number('OFF preview DML operations', l_change_count, 0);
    l_preview_hash := l_state_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'PROVIDER_TAXONOMY_OFF',
        'APPLY',
        l_preview_hash
    );
    assert_text('OFF apply status', l_status, 'NO_CHANGE');
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A1'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code = 'B2000A0030PRV080';
    assert_number('OFF payor override count', l_number, 0);
    ROLLBACK TO test_option_off;
    DBMS_OUTPUT.PUT_LINE('PASS: source OFF/request OFF remained canonical with zero overrides.');

    /* PAYOR_E: source form template is retained, with NULL user template. */
    SAVEPOINT test_payor_e;
    call_option(
        '10000000-0000-0000-0000-0000000000A5',
        'PROVIDER_TAXONOMY_OFF',
        'PREVIEW'
    );
    assert_text(
        'PAYOR_E source', l_source_guid,
        '30000000-0000-0000-0000-0000000000E1'
    );
    l_preview_hash := l_state_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A5',
        'PROVIDER_TAXONOMY_OFF',
        'APPLY',
        l_preview_hash
    );
    get_target_her(
        '10000000-0000-0000-0000-0000000000A5',
        l_target_guid, l_text, l_text_2, l_before_user, l_before_guid
    );
    assert_text('PAYOR_E HER procedure', l_text, 'RETURN_0');
    assert_text(
        'PAYOR_E form template', l_text_2,
        '40000000-0000-0000-0000-0000000000E1'
    );
    assert_text('PAYOR_E user template', l_before_user, NULL);
    SELECT h.mandatory_ind INTO l_text
    FROM hcfa_electronic_records h
    WHERE h.electronic_rec_guid = l_target_guid;
    assert_text('Provider OFF mandatory invariant', l_text, 'N');
    ROLLBACK TO test_payor_e;
    DBMS_OUTPUT.PUT_LINE('PASS: PAYOR_E retained exact source template scope.');

    /* PAYOR_F: both source template values are retained. */
    SAVEPOINT test_payor_f;
    call_option(
        '10000000-0000-0000-0000-0000000000A6',
        'PROVIDER_TAXONOMY_OFF',
        'PREVIEW'
    );
    assert_text(
        'PAYOR_F source', l_source_guid,
        '30000000-0000-0000-0000-0000000000F1'
    );
    l_preview_hash := l_state_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A6',
        'PROVIDER_TAXONOMY_OFF',
        'APPLY',
        l_preview_hash
    );
    get_target_her(
        '10000000-0000-0000-0000-0000000000A6',
        l_target_guid, l_text, l_text_2, l_before_user, l_before_guid
    );
    assert_text('PAYOR_F HER procedure', l_text, 'RETURN_0');
    assert_text(
        'PAYOR_F form template', l_text_2,
        '40000000-0000-0000-0000-0000000000F1'
    );
    assert_text(
        'PAYOR_F user template', l_before_user,
        '50000000-0000-0000-0000-0000000000F1'
    );
    ROLLBACK TO test_payor_f;
    DBMS_OUTPUT.PUT_LINE('PASS: PAYOR_F retained both exact source template values.');

    /* A hard-coded source PRV03 must be replaced by the ON procedure. */
    SAVEPOINT test_provider_source_replacement;
    UPDATE hcfa_electronic_fields f
    SET
        f.sto_proc_name = NULL,
        f.hard_coded_data = 'SYNTHETIC_SOURCE_HARD_CODED_TAXONOMY'
    WHERE f.electronic_rec_guid =
            '30000000-0000-0000-0000-0000000000F1'
      AND f.field_number = '03'
      AND f.field_name = 'PRV03';
    call_option(
        '10000000-0000-0000-0000-0000000000A6',
        'PROVIDER_TAXONOMY_ON',
        'PREVIEW'
    );
    assert_text(
        'hard-coded source Provider action',
        l_action_prv,
        'REBUILD_OVERRIDE'
    );
    l_preview_hash := l_state_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A6',
        'PROVIDER_TAXONOMY_ON',
        'APPLY',
        l_preview_hash
    );
    get_target_her(
        '10000000-0000-0000-0000-0000000000A6',
        l_target_guid, l_text, l_text_2, l_before_user, l_before_guid
    );
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_fields f
    WHERE f.electronic_rec_guid = l_target_guid
      AND f.field_number = '03'
      AND f.field_name = 'PRV03'
      AND f.sto_proc_name = 'G_PROVIDER_TAXONOMY_CODE'
      AND f.hard_coded_data IS NULL;
    assert_number('hard-coded source Provider replacement', l_number, 1);
    call_option(
        '10000000-0000-0000-0000-0000000000A6',
        'PROVIDER_TAXONOMY_ON',
        'PREVIEW'
    );
    assert_text('hard-coded source re-preview', l_status, 'NO_CHANGE');
    assert_text('hard-coded source canonical action', l_action_prv, 'NO_CHANGE');
    ROLLBACK TO test_provider_source_replacement;
    DBMS_OUTPUT.PUT_LINE(
        'PASS: hard-coded Provider source was replaced and re-previewed canonical.'
    );

    /* PAYOR_H: exact payor-type source and authoritative PAYORS value. */
    SAVEPOINT test_payor_h;
    call_option(
        '10000000-0000-0000-0000-0000000000A8',
        'PROVIDER_TAXONOMY_OFF',
        'PREVIEW'
    );
    assert_text(
        'PAYOR_H exact-type source', l_source_guid,
        '30000000-0000-0000-0000-0000000000A8'
    );
    l_preview_hash := l_state_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A8',
        'PROVIDER_TAXONOMY_OFF',
        'APPLY',
        l_preview_hash
    );
    get_target_her(
        '10000000-0000-0000-0000-0000000000A8',
        l_target_guid, l_text, l_text_2, l_before_user, l_before_guid
    );
    assert_text(
        'PAYOR_H authoritative payor type', l_before_guid,
        '11000000-0000-0000-0000-000000000002'
    );
    ROLLBACK TO test_payor_h;
    DBMS_OUTPUT.PUT_LINE('PASS: PAYOR_H used the exact-type source and PAYORS type.');

    /* Stale preview: a relevant external change invalidates the old hash. */
    SAVEPOINT test_stale_preview;
    call_option(
        '10000000-0000-0000-0000-0000000000A4',
        'PROVIDER_TAXONOMY_ON',
        'PREVIEW'
    );
    l_preview_hash := l_state_hash;
    UPDATE hcfa_electronic_fields f
    SET f.hard_coded_data = 'SYNTHETIC_STALE_PREVIEW_CHANGE'
    WHERE f.electronic_rec_guid =
        '30000000-0000-0000-0000-0000000000D1'
      AND f.field_number = '02';

    l_stale_rejected := FALSE;
    BEGIN
        call_option(
            '10000000-0000-0000-0000-0000000000A4',
            'PROVIDER_TAXONOMY_ON',
            'APPLY',
            l_preview_hash
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20036 THEN
                l_stale_rejected := TRUE;
            ELSE
                RAISE;
            END IF;
    END;
    IF NOT l_stale_rejected THEN
        RAISE_APPLICATION_ERROR(-20937, 'Stale preview was not rejected.');
    END IF;

    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_fields f
    WHERE f.electronic_rec_guid =
        '30000000-0000-0000-0000-0000000000D1'
      AND f.field_number = '02'
      AND f.hard_coded_data = 'SYNTHETIC_STALE_PREVIEW_CHANGE';
    assert_number('stale-preview caller change retained', l_number, 1);
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A4'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code = 'B2000A0030PRV080';
    assert_number('stale-preview HER count', l_number, 1);
    ROLLBACK TO test_stale_preview;
    DBMS_OUTPUT.PUT_LINE('PASS: stale preview was rejected without Script 3 DML.');

    /* Always + address creates all three targets from their complete sources. */
    SAVEPOINT test_service_always_yes;
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    WHERE h.electronic_rec_guid IN (
        '31000000-0000-0000-0000-000000000001',
        '31000000-0000-0000-0000-000000000002',
        '31000000-0000-0000-0000-000000000003'
    )
      AND h.carry_forward_ind = 'N'
      AND h.include_record_data_onclaim = 'N';
    assert_number('Service source payor-metadata fixture count', l_number, 3);
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'SERVICE_FACILITY_ALWAYS_ADDRESS_YES',
        'PREVIEW'
    );
    assert_text('always/yes preview status', l_status, 'PREVIEW');
    assert_text('always/yes summary record type', l_summary_record_type, NULL);
    assert_text('always/yes summary source', l_source_guid, NULL);
    assert_text('always/yes NM1 action', l_action_nm1, 'REBUILD_OVERRIDE');
    assert_text('always/yes N3 action', l_action_n3, 'REBUILD_OVERRIDE');
    assert_text('always/yes N4 action', l_action_n4, 'REBUILD_OVERRIDE');
    assert_number('always/yes new HEFs', l_new_hef_count, 10);
    assert_number('always/yes inserted HER operations', l_insert_her_count, 3);
    assert_number('always/yes inserted HEF operations', l_insert_hef_count, 10);
    assert_number('always/yes SET HEF operations', l_set_hef_count, 9);
    assert_number('always/yes paired CLEAR operations', l_clear_hef_count, 9);
    l_preview_hash := l_state_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'SERVICE_FACILITY_ALWAYS_ADDRESS_YES',
        'APPLY',
        l_preview_hash
    );
    assert_text('always/yes apply status', l_status, 'APPLIED');
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A1'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code IN (
        'D2310E2500NM1343', 'D2310E2650N3346', 'D2310E2700N4347'
      );
    assert_number('always/yes HER count', l_number, 3);
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = h.electronic_rec_guid
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A1'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code IN (
        'D2310E2500NM1343', 'D2310E2650N3346', 'D2310E2700N4347'
      );
    assert_number('always/yes complete cloned HEF count', l_number, 10);
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A1'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code IN (
        'D2310E2500NM1343', 'D2310E2650N3346', 'D2310E2700N4347'
      )
      AND h.sto_proc_name = 'RETURN_1';
    assert_number('always/yes HER values', l_number, 3);
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A1'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code IN (
        'D2310E2500NM1343', 'D2310E2650N3346', 'D2310E2700N4347'
      )
      AND h.carry_forward_ind IS NULL
      AND h.include_record_data_onclaim = 'Y'
      AND h.max_carry_forward = 0;
    assert_number('always/yes canonical payor HER metadata', l_number, 3);
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = h.electronic_rec_guid
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A1'
      AND h.record_type_code = 'D2310E2500NM1343'
      AND (
        (f.field_number = '01'
         AND f.sto_proc_name IS NULL
         AND f.hard_coded_data = '77')
        OR
        (f.field_number = '03'
         AND f.sto_proc_name = 'G_ORGANIZATION_NAME'
         AND f.hard_coded_data IS NULL)
      );
    assert_number('always/yes paired replacement overlays', l_number, 2);
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    JOIN hcfa_electronic_fields f
      ON f.electronic_rec_guid = h.electronic_rec_guid
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A1'
      AND h.record_type_code = 'D2310E2500NM1343'
      AND f.field_number = '10'
      AND f.sto_proc_name = 'G_SYNTHETIC_UNMANAGED'
      AND f.hard_coded_data = 'KEEP_ME';
    assert_number('always/yes unmanaged HEF preserved', l_number, 1);

    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'SERVICE_FACILITY_ALWAYS_ADDRESS_YES',
        'PREVIEW'
    );
    assert_text('existing always/yes status', l_status, 'NO_CHANGE');
    assert_text('existing always/yes NM1 action', l_action_nm1, 'NO_CHANGE');
    assert_text('existing always/yes N3 action', l_action_n3, 'NO_CHANGE');
    assert_text('existing always/yes N4 action', l_action_n4, 'NO_CHANGE');

    /* Applying NEVER removes all active overrides instead of cloning OFF rows. */
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'SERVICE_FACILITY_NEVER',
        'PREVIEW'
    );
    assert_text('never stale NM1 action', l_action_nm1, 'REMOVE_OVERRIDE');
    assert_text('never stale N3 action', l_action_n3, 'REMOVE_OVERRIDE');
    assert_text('never stale N4 action', l_action_n4, 'REMOVE_OVERRIDE');
    l_preview_hash := l_state_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'SERVICE_FACILITY_NEVER',
        'APPLY',
        l_preview_hash
    );
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A1'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code IN (
        'D2310E2500NM1343', 'D2310E2650N3346', 'D2310E2700N4347'
      );
    assert_number('never removed all overrides', l_number, 0);
    ROLLBACK TO test_service_always_yes;
    DBMS_OUTPUT.PUT_LINE('PASS: Always/address-yes cloned all targets and Never removed them.');

    /* Always + no address only requires an NM1 override. */
    SAVEPOINT test_service_always_no;
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'SERVICE_FACILITY_ALWAYS_ADDRESS_NO',
        'PREVIEW'
    );
    assert_text('always/no NM1 action', l_action_nm1, 'REBUILD_OVERRIDE');
    assert_text('always/no N3 action', l_action_n3, 'NO_CHANGE');
    assert_text('always/no N4 action', l_action_n4, 'NO_CHANGE');
    assert_number('always/no new HEFs', l_new_hef_count, 5);
    l_preview_hash := l_state_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'SERVICE_FACILITY_ALWAYS_ADDRESS_NO',
        'APPLY',
        l_preview_hash
    );
    SELECT COUNT(*), NVL(SUM((
        SELECT COUNT(*) FROM hcfa_electronic_fields f
        WHERE f.electronic_rec_guid = h.electronic_rec_guid
    )), 0)
    INTO l_number, l_number_2
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A1'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code IN (
        'D2310E2500NM1343', 'D2310E2650N3346', 'D2310E2700N4347'
      );
    assert_number('always/no HER count', l_number, 1);
    assert_number('always/no HEF count', l_number_2, 5);
    ROLLBACK TO test_service_always_no;
    DBMS_OUTPUT.PUT_LINE('PASS: Always/address-no left OFF address targets override-free.');

    /* Conditional + address manages all three targets with conditional HERs. */
    SAVEPOINT test_service_conditional_yes;
    UPDATE hcfa_electronic_records h
    SET h.mandatory_ind = 'Y'
    WHERE h.electronic_rec_guid IN (
        '31000000-0000-0000-0000-000000000001',
        '31000000-0000-0000-0000-000000000002',
        '31000000-0000-0000-0000-000000000003'
    );
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES',
        'PREVIEW'
    );
    assert_text('conditional/yes NM1 action', l_action_nm1, 'REBUILD_OVERRIDE');
    assert_text('conditional/yes N3 action', l_action_n3, 'REBUILD_OVERRIDE');
    assert_text('conditional/yes N4 action', l_action_n4, 'REBUILD_OVERRIDE');
    l_preview_hash := l_state_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES',
        'APPLY',
        l_preview_hash
    );
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A1'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code IN (
        'D2310E2500NM1343', 'D2310E2650N3346', 'D2310E2700N4347'
      )
      AND h.sto_proc_name = 'G_D2310E2500NM1343_COUNT'
      AND h.mandatory_ind = 'N';
    assert_number('conditional/yes HER values', l_number, 3);
    ROLLBACK TO test_service_conditional_yes;
    DBMS_OUTPUT.PUT_LINE('PASS: Conditional/address-yes applied all conditional targets.');

    /* Conditional + no address only requires the conditional NM1 override. */
    SAVEPOINT test_service_conditional_no;
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO',
        'PREVIEW'
    );
    assert_text('conditional/no NM1 action', l_action_nm1, 'REBUILD_OVERRIDE');
    assert_text('conditional/no N3 action', l_action_n3, 'NO_CHANGE');
    assert_text('conditional/no N4 action', l_action_n4, 'NO_CHANGE');
    l_preview_hash := l_state_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO',
        'APPLY',
        l_preview_hash
    );
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A1'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code = 'D2310E2500NM1343'
      AND h.sto_proc_name = 'G_D2310E2500NM1343_COUNT';
    assert_number('conditional/no NM1 value', l_number, 1);
    ROLLBACK TO test_service_conditional_no;
    DBMS_OUTPUT.PUT_LINE('PASS: Conditional/address-no left OFF address targets override-free.');

    /* Fresh NEVER is already canonical against the three OFF sources. */
    SAVEPOINT test_service_never;
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'SERVICE_FACILITY_NEVER',
        'PREVIEW'
    );
    assert_text('fresh never status', l_status, 'NO_CHANGE');
    assert_text('fresh never NM1 action', l_action_nm1, 'NO_CHANGE');
    assert_text('fresh never N3 action', l_action_n3, 'NO_CHANGE');
    assert_text('fresh never N4 action', l_action_n4, 'NO_CHANGE');
    assert_number('fresh never DML operations', l_change_count, 0);
    ROLLBACK TO test_service_never;
    DBMS_OUTPUT.PUT_LINE('PASS: Never was canonical with zero Service Facility overrides.');

    /* One relevant change in N4 invalidates the shared three-target hash. */
    SAVEPOINT test_service_stale_hash;
    call_option(
        '10000000-0000-0000-0000-0000000000A1',
        'SERVICE_FACILITY_ALWAYS_ADDRESS_YES',
        'PREVIEW'
    );
    l_preview_hash := l_state_hash;
    UPDATE hcfa_electronic_fields f
    SET f.hard_coded_data = 'SYNTHETIC_SERVICE_STALE_HASH'
    WHERE f.electronic_rec_guid =
        '31000000-0000-0000-0000-000000000003'
      AND f.field_number = '01';
    l_stale_rejected := FALSE;
    BEGIN
        call_option(
            '10000000-0000-0000-0000-0000000000A1',
            'SERVICE_FACILITY_ALWAYS_ADDRESS_YES',
            'APPLY',
            l_preview_hash
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20036 THEN
                l_stale_rejected := TRUE;
            ELSE
                RAISE;
            END IF;
    END;
    IF NOT l_stale_rejected THEN
        RAISE_APPLICATION_ERROR(-20937,
            'The multi-target stale preview was not rejected.');
    END IF;
    SELECT COUNT(*)
    INTO l_number
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A1'
      AND h.billing_form_code = 'UB04'
      AND h.record_type_code IN (
        'D2310E2500NM1343', 'D2310E2650N3346', 'D2310E2700N4347'
      );
    assert_number('service stale-hash override count', l_number, 0);
    ROLLBACK TO test_service_stale_hash;
    DBMS_OUTPUT.PUT_LINE('PASS: one N4 change invalidated the shared target-state hash.');

    /* Inject an N4 insert failure after NM1/N3 inserts and prove full rollback. */
    BEGIN
        EXECUTE IMMEDIATE q'~
            ALTER TABLE hcfa_electronic_records ADD CONSTRAINT
                pfc_test_fail_service_n4 CHECK (
                    record_type_code <> 'D2310E2700N4347'
                    OR rec_ent_user <>
                        '90000000-0000-0000-0000-000000000003'
                )
        ~';
        BEGIN
            SAVEPOINT test_service_atomic_rollback;
            call_option(
                '10000000-0000-0000-0000-0000000000A1',
                'SERVICE_FACILITY_ALWAYS_ADDRESS_YES',
                'PREVIEW'
            );
            l_preview_hash := l_state_hash;
            l_stale_rejected := FALSE;
            BEGIN
                call_option(
                    '10000000-0000-0000-0000-0000000000A1',
                    'SERVICE_FACILITY_ALWAYS_ADDRESS_YES',
                    'APPLY',
                    l_preview_hash
                );
            EXCEPTION
                WHEN OTHERS THEN
                    IF SQLCODE = -20040 THEN
                        l_stale_rejected := TRUE;
                    ELSE
                        RAISE;
                    END IF;
            END;
            IF NOT l_stale_rejected THEN
                RAISE_APPLICATION_ERROR(-20937,
                    'The injected N4 failure was not reported safely.');
            END IF;
            SELECT COUNT(*)
            INTO l_number
            FROM hcfa_electronic_records h
            WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A1'
              AND h.billing_form_code = 'UB04'
              AND h.record_type_code IN (
                'D2310E2500NM1343', 'D2310E2650N3346', 'D2310E2700N4347'
              );
            assert_number('atomic rollback HER count', l_number, 0);
            ROLLBACK TO test_service_atomic_rollback;
        EXCEPTION
            WHEN OTHERS THEN
                EXECUTE IMMEDIATE q'~
                    ALTER TABLE hcfa_electronic_records
                    DROP CONSTRAINT pfc_test_fail_service_n4
                ~';
                RAISE;
        END;
        EXECUTE IMMEDIATE q'~
            ALTER TABLE hcfa_electronic_records
            DROP CONSTRAINT pfc_test_fail_service_n4
        ~';
    END;
    DBMS_OUTPUT.PUT_LINE('PASS: injected N4 failure rolled back NM1/N3/N4 atomically.');

    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('PASS: all Script 3 tests passed and were rolled back.');
END;
/
