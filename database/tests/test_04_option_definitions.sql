WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

DECLARE
    l_option           pfc_option_types.t_option_definition;
    l_sto_requirement  pfc_option_types.t_value_requirement;
    l_hard_requirement pfc_option_types.t_value_requirement;
    l_sto_value        pfc_option_types.t_value_text;
    l_hard_value       pfc_option_types.t_value_text;
    l_conflict_rejected BOOLEAN;
    l_managed_targets  pfc_option_registry.t_managed_targets;
    l_provider_count   PLS_INTEGER := 0;
    l_nm1_count        PLS_INTEGER := 0;
    l_n3_count         PLS_INTEGER := 0;
    l_n4_count         PLS_INTEGER := 0;
    l_value_codes_count PLS_INTEGER := 0;

    PROCEDURE assert_text (
        p_label    IN VARCHAR2,
        p_actual   IN VARCHAR2,
        p_expected IN VARCHAR2
    )
    IS
    BEGIN
        IF (p_actual IS NULL AND p_expected IS NOT NULL)
           OR (p_actual IS NOT NULL AND p_expected IS NULL)
           OR p_actual <> p_expected THEN
            RAISE_APPLICATION_ERROR(-20960, p_label || ': unexpected value.');
        END IF;
    END assert_text;

    PROCEDURE assert_hef (
        p_label         IN VARCHAR2,
        p_requirement   IN pfc_option_types.t_hef_requirement,
        p_field_number  IN VARCHAR2,
        p_sto_action    IN VARCHAR2,
        p_sto_value     IN VARCHAR2,
        p_hard_action   IN VARCHAR2,
        p_hard_value    IN VARCHAR2
    )
    IS
    BEGIN
        assert_text(
            p_label || ' selector attribute',
            p_requirement.selector_terms(1).attribute_code,
            pfc_option_types.c_attr_field_number
        );
        assert_text(
            p_label || ' field number',
            p_requirement.selector_terms(1).expected_value,
            p_field_number
        );
        assert_text(
            p_label || ' STO action',
            p_requirement.attribute_requirements(1).desired_value.action_code,
            p_sto_action
        );
        assert_text(
            p_label || ' STO value',
            p_requirement.attribute_requirements(1).desired_value.value_text,
            p_sto_value
        );
        assert_text(
            p_label || ' hard-code action',
            p_requirement.attribute_requirements(2).desired_value.action_code,
            p_hard_action
        );
        assert_text(
            p_label || ' hard-code value',
            p_requirement.attribute_requirements(2).desired_value.value_text,
            p_hard_value
        );
    END assert_hef;

    PROCEDURE assert_service_option (
        p_option_code   IN VARCHAR2,
        p_nm1_value     IN VARCHAR2,
        p_n3_value      IN VARCHAR2,
        p_n4_value      IN VARCHAR2,
        p_nm1_hef_count IN PLS_INTEGER,
        p_n3_hef_count  IN PLS_INTEGER,
        p_n4_hef_count  IN PLS_INTEGER
    )
    IS
        l_option pfc_option_types.t_option_definition;
    BEGIN
        l_option := pfc_option_registry.get_option(p_option_code);
        IF l_option.targets.COUNT <> 3 THEN
            RAISE_APPLICATION_ERROR(-20961, 'Service Facility must have 3 targets.');
        END IF;

        assert_text('NM1 target code', l_option.targets(1).target_code, 'NM1');
        assert_text(
            'NM1 record type', l_option.targets(1).record_type_code,
            'D2310E2500NM1343'
        );
        assert_text(
            'NM1 HER value',
            l_option.targets(1).her_requirements(1).desired_value.value_text,
            p_nm1_value
        );
        assert_text('N3 target code', l_option.targets(2).target_code, 'N3');
        assert_text(
            'N3 record type', l_option.targets(2).record_type_code,
            'D2310E2650N3346'
        );
        assert_text(
            'N3 HER value',
            l_option.targets(2).her_requirements(1).desired_value.value_text,
            p_n3_value
        );
        assert_text('N4 target code', l_option.targets(3).target_code, 'N4');
        assert_text(
            'N4 record type', l_option.targets(3).record_type_code,
            'D2310E2700N4347'
        );
        assert_text(
            'N4 HER value',
            l_option.targets(3).her_requirements(1).desired_value.value_text,
            p_n4_value
        );

        IF l_option.targets(1).hef_requirements.COUNT <> p_nm1_hef_count
           OR l_option.targets(2).hef_requirements.COUNT <> p_n3_hef_count
           OR l_option.targets(3).hef_requirements.COUNT <> p_n4_hef_count THEN
            RAISE_APPLICATION_ERROR(-20962, 'Service Facility HEF requirements are incomplete.');
        END IF;

        IF p_nm1_hef_count > 0 THEN
            assert_hef(
                'NM1-01', l_option.targets(1).hef_requirements(1), '01',
                'KEEP', NULL, 'SET', '77'
            );
            assert_hef(
                'NM1-02', l_option.targets(1).hef_requirements(2), '02',
                'KEEP', NULL, 'SET', '2'
            );
            assert_hef(
                'NM1-03', l_option.targets(1).hef_requirements(3), '03',
                'SET', 'G_ORGANIZATION_NAME', 'KEEP', NULL
            );
            assert_hef(
                'NM1-09', l_option.targets(1).hef_requirements(4), '09',
                'SET', 'G_FACILITY_NPI', 'KEEP', NULL
            );
        END IF;
        IF p_n3_hef_count > 0 THEN
            assert_hef(
                'N3-01', l_option.targets(2).hef_requirements(1), '01',
                'SET', 'G_CARE_LOCATION_ADDR1', 'KEEP', NULL
            );
            assert_hef(
                'N3-02', l_option.targets(2).hef_requirements(2), '02',
                'SET', 'G_CARE_LOCATION_ADDR2', 'KEEP', NULL
            );
        END IF;
        IF p_n4_hef_count > 0 THEN
            assert_hef(
                'N4-01', l_option.targets(3).hef_requirements(1), '01',
                'SET', 'G_CARE_LOCATION_CITY', 'KEEP', NULL
            );
            assert_hef(
                'N4-02', l_option.targets(3).hef_requirements(2), '02',
                'SET', 'G_CARE_LOCATION_STATE', 'KEEP', NULL
            );
            assert_hef(
                'N4-03', l_option.targets(3).hef_requirements(3), '03',
                'SET', 'G_CARE_LOCATION_ZIP', 'KEEP', NULL
            );
        END IF;
    END assert_service_option;

BEGIN
    l_sto_requirement.action_code := pfc_option_types.c_action_set;
    l_sto_requirement.value_text := 'TEST_PROC';
    l_hard_requirement.action_code := pfc_option_types.c_action_keep;
    l_hard_requirement.value_text := NULL;
    l_sto_value := NULL;
    l_hard_value := 'ABC';
    pfc_option_types.apply_hef_value_pair(
        l_sto_requirement,
        l_hard_requirement,
        l_sto_value,
        l_hard_value
    );
    assert_text('procedure replacement STO', l_sto_value, 'TEST_PROC');
    assert_text('procedure replacement hard code', l_hard_value, NULL);

    l_sto_requirement.action_code := pfc_option_types.c_action_keep;
    l_sto_requirement.value_text := NULL;
    l_hard_requirement.action_code := pfc_option_types.c_action_set;
    l_hard_requirement.value_text := 'ABC';
    l_sto_value := 'TEST_PROC';
    l_hard_value := NULL;
    pfc_option_types.apply_hef_value_pair(
        l_sto_requirement,
        l_hard_requirement,
        l_sto_value,
        l_hard_value
    );
    assert_text('hard-code replacement STO', l_sto_value, NULL);
    assert_text('hard-code replacement value', l_hard_value, 'ABC');

    l_sto_requirement.action_code := pfc_option_types.c_action_set;
    l_sto_requirement.value_text := 'TEST_PROC';
    l_hard_requirement.action_code := pfc_option_types.c_action_clear;
    l_hard_requirement.value_text := NULL;
    l_sto_value := 'OLD_PROC';
    l_hard_value := 'OLD_VALUE';
    pfc_option_types.apply_hef_value_pair(
        l_sto_requirement,
        l_hard_requirement,
        l_sto_value,
        l_hard_value
    );
    assert_text('explicit procedure SET/CLEAR STO', l_sto_value, 'TEST_PROC');
    assert_text('explicit procedure SET/CLEAR hard', l_hard_value, NULL);

    l_sto_requirement.action_code := pfc_option_types.c_action_clear;
    l_sto_requirement.value_text := NULL;
    l_hard_requirement.action_code := pfc_option_types.c_action_set;
    l_hard_requirement.value_text := 'ABC';
    l_sto_value := 'OLD_PROC';
    l_hard_value := 'OLD_VALUE';
    pfc_option_types.apply_hef_value_pair(
        l_sto_requirement,
        l_hard_requirement,
        l_sto_value,
        l_hard_value
    );
    assert_text('explicit hard SET/CLEAR STO', l_sto_value, NULL);
    assert_text('explicit hard SET/CLEAR value', l_hard_value, 'ABC');

    l_sto_requirement.action_code := pfc_option_types.c_action_keep;
    l_sto_requirement.value_text := NULL;
    l_hard_requirement.action_code := pfc_option_types.c_action_keep;
    l_hard_requirement.value_text := NULL;
    l_sto_value := 'KEEP_PROC';
    l_hard_value := 'KEEP_VALUE';
    pfc_option_types.apply_hef_value_pair(
        l_sto_requirement,
        l_hard_requirement,
        l_sto_value,
        l_hard_value
    );
    assert_text('KEEP/KEEP STO', l_sto_value, 'KEEP_PROC');
    assert_text('KEEP/KEEP hard code', l_hard_value, 'KEEP_VALUE');

    l_sto_requirement.action_code := pfc_option_types.c_action_clear;
    l_sto_requirement.value_text := NULL;
    l_hard_requirement.action_code := pfc_option_types.c_action_keep;
    l_hard_requirement.value_text := NULL;
    l_sto_value := 'CLEAR_ME';
    l_hard_value := 'KEEP_ME';
    pfc_option_types.apply_hef_value_pair(
        l_sto_requirement,
        l_hard_requirement,
        l_sto_value,
        l_hard_value
    );
    assert_text('CLEAR-only STO', l_sto_value, NULL);
    assert_text('CLEAR-only paired hard code', l_hard_value, 'KEEP_ME');

    l_sto_requirement.action_code := pfc_option_types.c_action_set;
    l_sto_requirement.value_text := 'TEST_PROC';
    l_hard_requirement.action_code := pfc_option_types.c_action_set;
    l_hard_requirement.value_text := 'ABC';
    l_sto_value := NULL;
    l_hard_value := NULL;
    l_conflict_rejected := FALSE;
    BEGIN
        pfc_option_types.apply_hef_value_pair(
            l_sto_requirement,
            l_hard_requirement,
            l_sto_value,
            l_hard_value
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = pfc_option_types.c_err_invalid_option THEN
                l_conflict_rejected := TRUE;
            ELSE
                RAISE;
            END IF;
    END;
    IF NOT l_conflict_rejected THEN
        RAISE_APPLICATION_ERROR(-20964,
            'Conflicting non-null HEF SET actions were not rejected.');
    END IF;

    l_option := pfc_option_registry.get_option('PROVIDER_TAXONOMY_ON');
    IF l_option.targets.COUNT <> 1 THEN
        RAISE_APPLICATION_ERROR(-20963, 'Provider Taxonomy must have 1 target.');
    END IF;
    assert_text(
        'Provider record type', l_option.targets(1).record_type_code,
        'B2000A0030PRV080'
    );
    assert_text('Provider billing form',
        l_option.targets(1).billing_form_code, '837I_5010');
    assert_text(
        'Provider HEF selector attribute',
        l_option.targets(1).hef_requirements(1).selector_terms(1).attribute_code,
        pfc_option_types.c_attr_field_name
    );
    assert_text(
        'Provider HEF selector value',
        l_option.targets(1).hef_requirements(1).selector_terms(1).expected_value,
        'PRV03'
    );
    assert_text(
        'Provider HEF procedure',
        l_option.targets(1).hef_requirements(1)
            .attribute_requirements(1).desired_value.value_text,
        'G_PROVIDER_TAXONOMY_CODE'
    );
    assert_text(
        'Provider ON HER procedure',
        l_option.targets(1).her_requirements(1).desired_value.value_text,
        'RETURN_1'
    );
    assert_text(
        'Provider hard-coded action',
        l_option.targets(1).hef_requirements(1)
            .attribute_requirements(2).desired_value.action_code,
        'KEEP'
    );

    l_option := pfc_option_registry.get_option('PROVIDER_TAXONOMY_OFF');
    assert_text(
        'Provider OFF HER procedure',
        l_option.targets(1).her_requirements(1).desired_value.value_text,
        'RETURN_0'
    );
    assert_text(
        'Provider OFF HEF procedure',
        l_option.targets(1).hef_requirements(1)
            .attribute_requirements(1).desired_value.value_text,
        'G_PROVIDER_TAXONOMY_CODE'
    );

    assert_service_option(
        'SERVICE_FACILITY_ALWAYS_ADDRESS_YES',
        'RETURN_1', 'RETURN_1', 'RETURN_1', 4, 2, 3
    );
    assert_service_option(
        'SERVICE_FACILITY_ALWAYS_ADDRESS_NO',
        'RETURN_1', 'RETURN_0', 'RETURN_0', 4, 0, 0
    );
    assert_service_option(
        'SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES',
        'G_D2310E2500NM1343_COUNT',
        'G_D2310E2500NM1343_COUNT',
        'G_D2310E2500NM1343_COUNT', 4, 2, 3
    );
    assert_service_option(
        'SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO',
        'G_D2310E2500NM1343_COUNT', 'RETURN_0', 'RETURN_0', 4, 0, 0
    );
    assert_service_option(
        'SERVICE_FACILITY_NEVER',
        'RETURN_0', 'RETURN_0', 'RETURN_0', 0, 0, 0
    );

    pfc_option_registry.get_managed_targets(l_managed_targets);
    IF l_managed_targets.COUNT <> 5 THEN
        RAISE_APPLICATION_ERROR(-20965,
            'Managed targets were not deduplicated across option definitions.');
    END IF;
    FOR i IN 1 .. l_managed_targets.COUNT LOOP
        assert_text('Managed target billing form ' || i,
            l_managed_targets(i).billing_form_code, '837I_5010');
        CASE l_managed_targets(i).record_type_code
            WHEN 'B2000A0030PRV080' THEN l_provider_count := l_provider_count + 1;
            WHEN 'D2310E2500NM1343' THEN l_nm1_count := l_nm1_count + 1;
            WHEN 'D2310E2650N3346' THEN l_n3_count := l_n3_count + 1;
            WHEN 'D2310E2700N4347' THEN l_n4_count := l_n4_count + 1;
            WHEN 'D23002310HI286' THEN
                l_value_codes_count := l_value_codes_count + 1;
            ELSE RAISE_APPLICATION_ERROR(-20966,
                'Unexpected managed target was registered.');
        END CASE;
    END LOOP;
    IF l_provider_count <> 1 OR l_nm1_count <> 1 OR
       l_n3_count <> 1 OR l_n4_count <> 1 OR l_value_codes_count <> 1 THEN
        RAISE_APPLICATION_ERROR(-20967,
            'The authoritative managed target set is incomplete.');
    END IF;

    DBMS_OUTPUT.PUT_LINE(
        'PASS: option definitions and deduplicated managed targets are valid.'
    );
END;
/
