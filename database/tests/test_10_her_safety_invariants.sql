WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

DECLARE
    l_her hcfa_electronic_records%ROWTYPE;
    l_status VARCHAR2(20);
    l_target_action VARCHAR2(30);
    l_hash VARCHAR2(64);
    l_hash_n VARCHAR2(64);
    l_hash_y VARCHAR2(64);
    l_count PLS_INTEGER;
    l_value_codes_option pfc_option_types.t_option_code;
    l_none pfc_value_codes.t_selections := pfc_value_codes.no_selections;

    PROCEDURE assert_boolean(
        p_label IN VARCHAR2,
        p_actual IN BOOLEAN,
        p_expected IN BOOLEAN
    ) IS
    BEGIN
        IF p_actual IS NULL
           OR (p_actual AND NOT p_expected)
           OR (NOT p_actual AND p_expected) THEN
            RAISE_APPLICATION_ERROR(-20990, p_label || ' failed.');
        END IF;
    END;

    PROCEDURE run_option(
        p_option_code IN VARCHAR2,
        p_mode IN VARCHAR2,
        p_expected_hash IN VARCHAR2 DEFAULT NULL
    ) IS
        l_summary SYS_REFCURSOR;
        l_changes SYS_REFCURSOR;
        l_option_code VARCHAR2(100); l_label VARCHAR2(200);
        l_payor VARCHAR2(36); l_plan VARCHAR2(36); l_pfc VARCHAR2(36);
        l_form VARCHAR2(10); l_record VARCHAR2(20); l_source VARCHAR2(36);
        l_source_match VARCHAR2(1); l_desired_match VARCHAR2(1);
        l_her_count NUMBER; l_hef_count NUMBER; l_new_hefs NUMBER;
        l_change_count NUMBER;
    BEGIN
        pfc_apply_option(
            '10000000-0000-0000-0000-00000000D002', NULL,
            p_option_code, 'SAFETY_TEST', p_mode, p_expected_hash,
            l_summary, l_changes
        );
        CLOSE l_changes;
        FETCH l_summary INTO l_status, l_option_code, l_label, l_payor,
            l_plan, l_pfc, l_form, l_record, l_source, l_target_action,
            l_source_match, l_desired_match, l_her_count, l_hef_count,
            l_new_hefs, l_hash, l_change_count;
        CLOSE l_summary;
    END;

    PROCEDURE assert_normalized(
        p_label IN VARCHAR2,
        p_sto_proc_name IN VARCHAR2,
        p_source_mandatory IN VARCHAR2,
        p_expected_mandatory IN VARCHAR2
    ) IS
    BEGIN
        l_her.sto_proc_name := p_sto_proc_name;
        l_her.mandatory_ind := p_source_mandatory;
        pfc_config_internal.apply_her_safety_invariants(l_her);
        IF l_her.mandatory_ind <> p_expected_mandatory THEN
            RAISE_APPLICATION_ERROR(-20991,
                p_label || ' expected ' || p_expected_mandatory ||
                ' but found ' || NVL(l_her.mandatory_ind, '<NULL>') || '.');
        END IF;
    END;
BEGIN
    assert_boolean('RETURN_1/Y is safe',
        pfc_config_internal.her_satisfies_safety_invariants('RETURN_1', 'Y'),
        TRUE);
    assert_boolean('RETURN_1/N is safe',
        pfc_config_internal.her_satisfies_safety_invariants('RETURN_1', 'N'),
        TRUE);
    assert_boolean('RETURN_0/Y is unsafe',
        pfc_config_internal.her_satisfies_safety_invariants('RETURN_0', 'Y'),
        FALSE);
    assert_boolean('conditional/Y is unsafe',
        pfc_config_internal.her_satisfies_safety_invariants(
            'G_SYNTHETIC_CONDITIONAL_COUNT', 'Y'), FALSE);
    assert_boolean('NULL/Y is unsafe',
        pfc_config_internal.her_satisfies_safety_invariants(NULL, 'Y'), FALSE);

    assert_normalized('RETURN_1 preserves Y', 'RETURN_1', 'Y', 'Y');
    assert_normalized('RETURN_1 preserves N', 'RETURN_1', 'N', 'N');
    assert_normalized('RETURN_0 converts Y', 'RETURN_0', 'Y', 'N');
    assert_normalized('RETURN_0 preserves N', 'RETURN_0', 'N', 'N');
    assert_normalized('conditional converts Y',
        'G_SYNTHETIC_CONDITIONAL_COUNT', 'Y', 'N');
    assert_normalized('conditional preserves N',
        'G_SYNTHETIC_CONDITIONAL_COUNT', 'N', 'N');
    assert_normalized('NULL converts Y', NULL, 'Y', 'N');

    /* Hashing and explicit repair use the normalized mandatory value. */
    SAVEPOINT explicit_repair;
    run_option('PROVIDER_TAXONOMY_OFF', 'PREVIEW');
    l_hash_n := l_hash;
    UPDATE hcfa_electronic_records
    SET mandatory_ind = 'Y'
    WHERE electronic_rec_guid = '30000000-0000-0000-0000-00000000D081';
    run_option('PROVIDER_TAXONOMY_OFF', 'PREVIEW');
    l_hash_y := l_hash;
    IF l_hash_n = l_hash_y THEN
        RAISE_APPLICATION_ERROR(-20992,
            'The state hash did not change with source MANDATORY_IND.');
    END IF;
    IF l_target_action <> 'REBUILD_OVERRIDE' THEN
        RAISE_APPLICATION_ERROR(-20993,
            'Unsafe source explicit repair did not request a rebuild.');
    END IF;
    run_option('PROVIDER_TAXONOMY_OFF', 'APPLY', l_hash_y);
    SELECT COUNT(*) INTO l_count
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-00000000D002'
      AND h.record_type_code = 'B2000A0030PRV080'
      AND h.sto_proc_name = 'RETURN_0'
      AND h.mandatory_ind = 'N';
    IF l_count <> 1 THEN
        RAISE_APPLICATION_ERROR(-20994,
            'Explicit repair did not persist RETURN_0 with MANDATORY_IND=N.');
    END IF;
    UPDATE hcfa_electronic_records
    SET mandatory_ind = 'Y'
    WHERE payor_guid = '10000000-0000-0000-0000-00000000D002'
      AND record_type_code = 'B2000A0030PRV080';
    run_option('PROVIDER_TAXONOMY_OFF', 'PREVIEW');
    IF l_target_action <> 'REBUILD_OVERRIDE' THEN
        RAISE_APPLICATION_ERROR(-20995,
            'Unsafe current override was incorrectly accepted as canonical.');
    END IF;
    ROLLBACK TO explicit_repair;

    /* Default is exact inheritance and rejects unsafe conditional/off sources. */
    SAVEPOINT default_source_safety;
    l_value_codes_option := pfc_value_codes.private_option_code(
        pfc_value_codes.c_home_health, l_none);
    run_option(l_value_codes_option, 'PREVIEW');
    UPDATE hcfa_electronic_records
    SET mandatory_ind = 'Y'
    WHERE electronic_rec_guid = '32000000-0000-0000-0000-000000000001';
    BEGIN
        run_option(l_value_codes_option, 'PREVIEW');
        RAISE_APPLICATION_ERROR(-20996,
            'Unsafe conditional Default source was not blocked.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE <> pfc_config_internal.c_err_unsafe_source THEN RAISE; END IF;
    END;
    UPDATE hcfa_electronic_records
    SET sto_proc_name = 'RETURN_0'
    WHERE electronic_rec_guid = '32000000-0000-0000-0000-000000000001';
    BEGIN
        run_option(l_value_codes_option, 'PREVIEW');
        RAISE_APPLICATION_ERROR(-20997,
            'Unsafe RETURN_0 Default source was not blocked.');
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE <> pfc_config_internal.c_err_unsafe_source THEN RAISE; END IF;
    END;
    UPDATE hcfa_electronic_records
    SET sto_proc_name = 'RETURN_1', mandatory_ind = 'Y'
    WHERE electronic_rec_guid = '32000000-0000-0000-0000-000000000001';
    run_option(l_value_codes_option, 'PREVIEW');
    UPDATE hcfa_electronic_records
    SET mandatory_ind = 'N'
    WHERE electronic_rec_guid = '32000000-0000-0000-0000-000000000001';
    run_option(l_value_codes_option, 'PREVIEW');
    SELECT COUNT(*) INTO l_count FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-00000000D002'
      AND h.record_type_code = 'D23002310HI286';
    IF l_count <> 0 THEN
        RAISE_APPLICATION_ERROR(-20998,
            'Default source validation created an unexpected repair override.');
    END IF;
    ROLLBACK TO default_source_safety;

    DBMS_OUTPUT.PUT_LINE(
        'PASS: global HER safety normalization, hashing, explicit repair, and Default blocking are valid.');
END;
/
