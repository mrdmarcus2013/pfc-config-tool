CREATE OR REPLACE PACKAGE BODY pfc_option_registry AS
    PROCEDURE get_registered_options (
        p_options OUT t_option_definitions
    )
    IS
    BEGIN
        p_options.DELETE;
        p_options(1) := pfc_opt_provider_taxonomy_on();
        p_options(2) := pfc_opt_provider_taxonomy_off();
        p_options(3) := pfc_opt_service_facility(
            'SERVICE_FACILITY_ALWAYS_ADDRESS_YES');
        p_options(4) := pfc_opt_service_facility(
            'SERVICE_FACILITY_ALWAYS_ADDRESS_NO');
        p_options(5) := pfc_opt_service_facility(
            'SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES');
        p_options(6) := pfc_opt_service_facility(
            'SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO');
        p_options(7) := pfc_opt_service_facility('SERVICE_FACILITY_NEVER');
    END get_registered_options;

    FUNCTION get_option (
        p_option_code IN pfc_option_types.t_option_code
    ) RETURN pfc_option_types.t_option_definition
    IS
        l_option_code pfc_option_types.t_option_code;
        l_options     t_option_definitions;
        l_index       PLS_INTEGER;
    BEGIN
        l_option_code := UPPER(TRIM(p_option_code));
        get_registered_options(l_options);
        l_index := l_options.FIRST;
        WHILE l_index IS NOT NULL LOOP
            IF l_options(l_index).option_code = l_option_code THEN
                RETURN l_options(l_index);
            END IF;
            l_index := l_options.NEXT(l_index);
        END LOOP;
        RAISE_APPLICATION_ERROR(
            c_err_unknown_option,
            'Unknown PFC option code.'
        );
    END get_option;

    PROCEDURE get_managed_targets (
        p_targets OUT t_managed_targets
    )
    IS
        TYPE t_seen_map IS TABLE OF BOOLEAN INDEX BY VARCHAR2(128);
        l_options      t_option_definitions;
        l_seen         t_seen_map;
        l_option_index PLS_INTEGER;
        l_target_index PLS_INTEGER;
        l_key          VARCHAR2(128);
        l_count        PLS_INTEGER := 0;
    BEGIN
        p_targets.DELETE;
        get_registered_options(l_options);
        l_option_index := l_options.FIRST;
        WHILE l_option_index IS NOT NULL LOOP
            l_target_index := l_options(l_option_index).targets.FIRST;
            WHILE l_target_index IS NOT NULL LOOP
                l_key := l_options(l_option_index).targets(l_target_index)
                    .billing_form_code || '|' ||
                    l_options(l_option_index).targets(l_target_index)
                    .record_type_code;
                IF NOT l_seen.EXISTS(l_key) THEN
                    l_count := l_count + 1;
                    p_targets(l_count).billing_form_code :=
                        l_options(l_option_index).targets(l_target_index)
                        .billing_form_code;
                    p_targets(l_count).record_type_code :=
                        l_options(l_option_index).targets(l_target_index)
                        .record_type_code;
                    l_seen(l_key) := TRUE;
                END IF;
                l_target_index := l_options(l_option_index).targets.NEXT(
                    l_target_index);
            END LOOP;
            l_option_index := l_options.NEXT(l_option_index);
        END LOOP;
    END get_managed_targets;
END pfc_option_registry;
/
