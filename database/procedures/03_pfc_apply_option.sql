/*
 * Generic preview/apply engine for the synthetic Oracle POC schema.
 *
 * Each explicit option target is evaluated independently against its
 * authoritative non-payor source.  An equivalent requested configuration is
 * represented by no payor override; a differing configuration is represented
 * by exactly one complete payor override.  Multi-target options share one
 * state hash and one savepoint so APPLY is atomic across every target.
 */
CREATE OR REPLACE PROCEDURE pfc_apply_option (
    p_payor_guid          IN pfc.payor_guid%TYPE,
    p_plan_guid           IN pfc.plan_guid%TYPE DEFAULT NULL,
    p_option_code         IN pfc_option_types.t_option_code,
    p_audit_user          IN hcfa_electronic_records.rec_ent_user%TYPE,
    p_mode                IN VARCHAR2,
    p_expected_state_hash IN VARCHAR2 DEFAULT NULL,
    p_summary             OUT SYS_REFCURSOR,
    p_changes             OUT SYS_REFCURSOR,
    p_taxonomy_code       IN VARCHAR2 DEFAULT NULL
)
AUTHID DEFINER
IS
    c_err_invalid_mode          CONSTANT PLS_INTEGER := -20030;
    c_err_missing_audit_user    CONSTANT PLS_INTEGER := -20031;
    c_err_invalid_option        CONSTANT PLS_INTEGER := -20032;
    c_err_expected_hash_missing CONSTANT PLS_INTEGER := -20035;
    c_err_stale_preview         CONSTANT PLS_INTEGER := -20036;
    c_err_hef_target_missing    CONSTANT PLS_INTEGER := -20037;
    c_err_hef_target_ambiguous  CONSTANT PLS_INTEGER := -20038;
    c_err_verification          CONSTANT PLS_INTEGER := -20039;
    c_err_unexpected_state      CONSTANT PLS_INTEGER := -20040;

    c_mode_preview CONSTANT VARCHAR2(7) := 'PREVIEW';
    c_mode_apply   CONSTANT VARCHAR2(5) := 'APPLY';

    c_target_no_change       CONSTANT VARCHAR2(30) := 'NO_CHANGE';
    c_target_remove_override CONSTANT VARCHAR2(30) := 'REMOVE_OVERRIDE';
    c_target_rebuild_override CONSTANT VARCHAR2(30) := 'REBUILD_OVERRIDE';

    TYPE t_hef_rows IS TABLE OF hcfa_electronic_fields%ROWTYPE
        INDEX BY PLS_INTEGER;
    TYPE t_text_rows IS TABLE OF VARCHAR2(32767)
        INDEX BY PLS_INTEGER;
    TYPE t_seen_map IS TABLE OF BOOLEAN
        INDEX BY VARCHAR2(256);

    TYPE t_target_state IS RECORD (
        option_index       PLS_INTEGER,
        target_code        pfc_option_types.t_target_code,
        record_type_code   hcfa_electronic_records.record_type_code%TYPE,
        source_guid        hcfa_electronic_records.electronic_rec_guid%TYPE,
        source_her         hcfa_electronic_records%ROWTYPE,
        source_hefs        t_hef_rows,
        overlay_her        hcfa_electronic_records%ROWTYPE,
        overlay_hefs       t_hef_rows,
        desired_her        hcfa_electronic_records%ROWTYPE,
        desired_hefs       t_hef_rows,
        current_her        hcfa_electronic_records%ROWTYPE,
        current_hefs       t_hef_rows,
        existing_her_count PLS_INTEGER,
        existing_hef_count PLS_INTEGER,
        desired_differs    BOOLEAN,
        current_matches_source BOOLEAN,
        current_matches_desired BOOLEAN,
        target_action      VARCHAR2(30),
        new_guid           hcfa_electronic_records.electronic_rec_guid%TYPE
    );
    TYPE t_target_states IS TABLE OF t_target_state INDEX BY PLS_INTEGER;

    TYPE t_change IS RECORD (
        operation_order            PLS_INTEGER,
        operation_code             VARCHAR2(30),
        target_electronic_rec_guid VARCHAR2(64),
        field_number               hcfa_electronic_fields.field_number%TYPE,
        attribute_code             pfc_option_types.t_attribute_code,
        old_value                  VARCHAR2(4000),
        new_value                  VARCHAR2(4000)
    );
    TYPE t_changes IS TABLE OF t_change INDEX BY PLS_INTEGER;

    l_mode                 VARCHAR2(7);
    l_audit_user           hcfa_electronic_records.rec_ent_user%TYPE;
    l_option               pfc_option_types.t_option_definition;
    l_targets              t_target_states;
    l_pfc_guid             pfc.pfc_guid%TYPE;
    l_resolved_payor_guid  pfc.payor_guid%TYPE;
    l_resolved_plan_guid   pfc.plan_guid%TYPE;
    l_payor_type_guid      payors.payor_type_guid%TYPE;
    l_billing_form_code    pfc.billing_form_code%TYPE;
    l_form_template_guid   pfc.form_template_guid%TYPE;
    l_user_template_guid   pfc.user_form_template_guid%TYPE;
    l_cpd_start_date       pfc.cpd_start_date%TYPE;
    l_cpd_end_date         pfc.cpd_end_date%TYPE;
    l_context_set          BOOLEAN := FALSE;
    l_state_serial         VARCHAR2(32767);
    l_state_hash           VARCHAR2(64);
    l_changes              t_changes;
    l_changes_sql          VARCHAR2(32767);
    l_change_count         PLS_INTEGER := 0;
    l_existing_her_count   PLS_INTEGER := 0;
    l_existing_hef_count   PLS_INTEGER := 0;
    l_new_hef_count        PLS_INTEGER := 0;
    l_savepoint_set        BOOLEAN := FALSE;
    l_error_code           PLS_INTEGER;
    l_result_status        VARCHAR2(20);
    l_output_record_type   hcfa_electronic_records.record_type_code%TYPE;
    l_output_source_guid   hcfa_electronic_records.electronic_rec_guid%TYPE;
    l_output_target_action VARCHAR2(30);
    l_output_current_matches_source VARCHAR2(1);
    l_output_current_matches_desired VARCHAR2(1);

    FUNCTION values_equal (
        p_left IN VARCHAR2,
        p_right IN VARCHAR2
    ) RETURN BOOLEAN
    IS
    BEGIN
        RETURN (p_left = p_right) OR (p_left IS NULL AND p_right IS NULL);
    END values_equal;

    FUNCTION encoded_value (p_value IN VARCHAR2) RETURN VARCHAR2
    IS
    BEGIN
        IF p_value IS NULL THEN
            RETURN '-1:';
        END IF;
        RETURN TO_CHAR(LENGTH(p_value)) || ':' || p_value;
    END encoded_value;

    FUNCTION encoded_number (p_value IN NUMBER) RETURN VARCHAR2
    IS
    BEGIN
        IF p_value IS NULL THEN
            RETURN encoded_value(NULL);
        END IF;
        RETURN encoded_value(
            TO_CHAR(p_value, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''')
        );
    END encoded_number;

    FUNCTION encoded_date (p_value IN DATE) RETURN VARCHAR2
    IS
    BEGIN
        IF p_value IS NULL THEN
            RETURN encoded_value(NULL);
        END IF;
        RETURN encoded_value(TO_CHAR(p_value, 'YYYYMMDDHH24MISS'));
    END encoded_date;

    FUNCTION her_business_serial (
        p_row IN hcfa_electronic_records%ROWTYPE
    ) RETURN VARCHAR2
    IS
    BEGIN
        RETURN
            encoded_value(p_row.loop_id) ||
            encoded_value(p_row.contiguity_ind) ||
            encoded_value(p_row.billing_form_code) ||
            encoded_value(p_row.record_name) ||
            encoded_value(p_row.record_type_code) ||
            encoded_number(p_row.record_size) ||
            encoded_value(p_row.mandatory_ind) ||
            encoded_value(p_row.req_for_claim_ind) ||
            encoded_value(p_row.payor_type_guid) ||
            encoded_value(p_row.payor_guid) ||
            encoded_value(p_row.plan_guid) ||
            encoded_value(p_row.type_of_bill) ||
            encoded_value(p_row.detail_ind) ||
            encoded_value(p_row.max_number) ||
            encoded_value(p_row.invoice_ind) ||
            encoded_value(p_row.form_template_guid) ||
            encoded_value(p_row.carry_forward_ind) ||
            encoded_number(p_row.max_carry_forward) ||
            encoded_value(p_row.sto_proc_name) ||
            encoded_value(p_row.user_form_template_guid) ||
            encoded_value(p_row.notes) ||
            encoded_value(p_row.include_record_data_onclaim);
    END her_business_serial;

    FUNCTION her_functional_serial (
        p_row IN hcfa_electronic_records%ROWTYPE
    ) RETURN VARCHAR2
    IS
    BEGIN
        /* Scope, identity, template and audit metadata do not alter behavior. */
        RETURN
            encoded_value(p_row.loop_id) ||
            encoded_value(p_row.contiguity_ind) ||
            encoded_value(p_row.billing_form_code) ||
            encoded_value(p_row.record_type_code) ||
            encoded_number(p_row.record_size) ||
            encoded_value(p_row.mandatory_ind) ||
            encoded_value(p_row.req_for_claim_ind) ||
            encoded_value(p_row.type_of_bill) ||
            encoded_value(p_row.detail_ind) ||
            encoded_value(p_row.max_number) ||
            encoded_value(p_row.invoice_ind) ||
            encoded_number(p_row.max_carry_forward) ||
            encoded_value(p_row.sto_proc_name);
    END her_functional_serial;

    FUNCTION hef_business_serial (
        p_row IN hcfa_electronic_fields%ROWTYPE
    ) RETURN VARCHAR2
    IS
    BEGIN
        RETURN
            encoded_value(p_row.field_number) ||
            encoded_value(p_row.field_name) ||
            encoded_value(p_row.record_type_code) ||
            encoded_value(p_row.sto_proc_name) ||
            encoded_value(p_row.pic) ||
            encoded_value(p_row.field_spec) ||
            encoded_number(p_row.position_from) ||
            encoded_number(p_row.position_thru) ||
            encoded_value(p_row.field_name_desc) ||
            encoded_value(p_row.mandatory_ind) ||
            encoded_value(p_row.must_fit_length_ind) ||
            encoded_number(p_row.order_num) ||
            encoded_number(p_row.repeats) ||
            encoded_value(p_row.detail_ind) ||
            encoded_value(p_row.occurs_next) ||
            encoded_value(p_row.hard_coded_data) ||
            encoded_value(p_row.field_format) ||
            encoded_value(p_row.caps_ind) ||
            encoded_value(p_row.required_subelement_ind) ||
            encoded_value(p_row.include_data_onclaim);
    END hef_business_serial;

    PROCEDURE sort_text_rows (p_values IN OUT NOCOPY t_text_rows)
    IS
        l_key VARCHAR2(32767);
        l_j   PLS_INTEGER;
    BEGIN
        IF p_values.COUNT < 2 THEN
            RETURN;
        END IF;
        FOR i IN 2 .. p_values.COUNT LOOP
            l_key := p_values(i);
            l_j := i - 1;
            WHILE l_j >= 1 AND p_values(l_j) > l_key LOOP
                p_values(l_j + 1) := p_values(l_j);
                l_j := l_j - 1;
            END LOOP;
            p_values(l_j + 1) := l_key;
        END LOOP;
    END sort_text_rows;

    FUNCTION hef_sets_equal (
        p_left  IN t_hef_rows,
        p_right IN t_hef_rows
    ) RETURN BOOLEAN
    IS
        l_left_rows  t_text_rows;
        l_right_rows t_text_rows;
        l_index      PLS_INTEGER;
    BEGIN
        IF p_left.COUNT <> p_right.COUNT THEN
            RETURN FALSE;
        END IF;
        l_index := p_left.FIRST;
        WHILE l_index IS NOT NULL LOOP
            l_left_rows(l_left_rows.COUNT + 1) :=
                hef_business_serial(p_left(l_index));
            l_index := p_left.NEXT(l_index);
        END LOOP;
        l_index := p_right.FIRST;
        WHILE l_index IS NOT NULL LOOP
            l_right_rows(l_right_rows.COUNT + 1) :=
                hef_business_serial(p_right(l_index));
            l_index := p_right.NEXT(l_index);
        END LOOP;
        sort_text_rows(l_left_rows);
        sort_text_rows(l_right_rows);
        IF l_left_rows.COUNT > 0 THEN
            FOR i IN 1 .. l_left_rows.COUNT LOOP
                IF l_left_rows(i) <> l_right_rows(i) THEN
                    RETURN FALSE;
                END IF;
            END LOOP;
        END IF;
        RETURN TRUE;
    END hef_sets_equal;

    FUNCTION configurations_equal (
        p_left_her   IN hcfa_electronic_records%ROWTYPE,
        p_left_hefs  IN t_hef_rows,
        p_right_her  IN hcfa_electronic_records%ROWTYPE,
        p_right_hefs IN t_hef_rows
    ) RETURN BOOLEAN
    IS
    BEGIN
        RETURN her_business_serial(p_left_her) = her_business_serial(p_right_her)
           AND hef_sets_equal(p_left_hefs, p_right_hefs);
    END configurations_equal;

    FUNCTION functional_configurations_equal (
        p_left_her   IN hcfa_electronic_records%ROWTYPE,
        p_left_hefs  IN t_hef_rows,
        p_right_her  IN hcfa_electronic_records%ROWTYPE,
        p_right_hefs IN t_hef_rows
    ) RETURN BOOLEAN
    IS
    BEGIN
        RETURN her_functional_serial(p_left_her) =
               her_functional_serial(p_right_her)
           AND hef_sets_equal(p_left_hefs, p_right_hefs);
    END functional_configurations_equal;

    FUNCTION payor_configurations_equal (
        p_current_her  IN hcfa_electronic_records%ROWTYPE,
        p_current_hefs IN t_hef_rows,
        p_desired_her  IN hcfa_electronic_records%ROWTYPE,
        p_desired_hefs IN t_hef_rows
    ) RETURN BOOLEAN
    IS
        l_current_her hcfa_electronic_records%ROWTYPE;
        l_desired_her hcfa_electronic_records%ROWTYPE;
    BEGIN
        IF p_current_her.payor_type_guid IS NOT NULL
           AND encoded_value(p_current_her.payor_type_guid) <>
               encoded_value(p_desired_her.payor_type_guid) THEN
            RETURN FALSE;
        END IF;

        /* A legacy NULL payor type is tolerated for an otherwise exact row. */
        l_current_her := p_current_her;
        l_desired_her := p_desired_her;
        l_current_her.payor_type_guid := NULL;
        l_desired_her.payor_type_guid := NULL;
        RETURN configurations_equal(
            l_current_her,
            p_current_hefs,
            l_desired_her,
            p_desired_hefs
        );
    END payor_configurations_equal;

    PROCEDURE append_state (p_value IN VARCHAR2)
    IS
        l_piece VARCHAR2(32767) := encoded_value(p_value);
    BEGIN
        IF NVL(LENGTH(l_state_serial), 0) + LENGTH(l_piece) > 32767 THEN
            RAISE_APPLICATION_ERROR(
                c_err_unexpected_state,
                'The POC state serialization exceeds its supported size.'
            );
        END IF;
        l_state_serial := l_state_serial || l_piece;
    END append_state;

    PROCEDURE append_hef_set (p_rows IN t_hef_rows)
    IS
        l_serials t_text_rows;
        l_index   PLS_INTEGER;
    BEGIN
        l_index := p_rows.FIRST;
        WHILE l_index IS NOT NULL LOOP
            l_serials(l_serials.COUNT + 1) :=
                hef_business_serial(p_rows(l_index));
            l_index := p_rows.NEXT(l_index);
        END LOOP;
        sort_text_rows(l_serials);
        append_state(TO_CHAR(l_serials.COUNT));
        IF l_serials.COUNT > 0 THEN
            FOR i IN 1 .. l_serials.COUNT LOOP
                append_state(l_serials(i));
            END LOOP;
        END IF;
    END append_hef_set;

    PROCEDURE validate_value_requirement (
        p_action_code IN pfc_option_types.t_action_code,
        p_value_text  IN pfc_option_types.t_value_text,
        p_max_length  IN PLS_INTEGER
    )
    IS
        l_action pfc_option_types.t_action_code := UPPER(TRIM(p_action_code));
    BEGIN
        IF l_action IS NULL OR l_action NOT IN (
            pfc_option_types.c_action_keep,
            pfc_option_types.c_action_set,
            pfc_option_types.c_action_clear
        ) THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_option,
                'The option definition contains an invalid action.');
        END IF;
        IF l_action = pfc_option_types.c_action_set AND p_value_text IS NULL THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_option,
                'SET requirements must provide a value.');
        END IF;
        IF l_action IN (
            pfc_option_types.c_action_keep,
            pfc_option_types.c_action_clear
        ) AND p_value_text IS NOT NULL THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_option,
                'KEEP and CLEAR requirements cannot provide a value.');
        END IF;
        IF p_value_text IS NOT NULL AND LENGTH(p_value_text) > p_max_length THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_option,
                'An option value exceeds the target attribute length.');
        END IF;
    END validate_value_requirement;

    PROCEDURE validate_target_definition (p_target_index IN PLS_INTEGER)
    IS
        l_index            PLS_INTEGER;
        l_inner_index      PLS_INTEGER;
        l_seen             t_seen_map;
        l_attribute        pfc_option_types.t_attribute_code;
        l_sto_requirement  pfc_option_types.t_value_requirement;
        l_hard_requirement pfc_option_types.t_value_requirement;
        l_test_sto         pfc_option_types.t_value_text;
        l_test_hard        pfc_option_types.t_value_text;
    BEGIN
        IF l_option.targets(p_target_index).target_code IS NULL
           OR l_option.targets(p_target_index).billing_form_code IS NULL
           OR l_option.targets(p_target_index).record_type_code IS NULL THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_option,
                'An option target is incomplete.');
        END IF;

        l_index := l_option.targets(p_target_index).her_requirements.FIRST;
        WHILE l_index IS NOT NULL LOOP
            l_attribute := UPPER(TRIM(l_option.targets(p_target_index)
                .her_requirements(l_index).attribute_code));
            IF l_attribute IS NULL
               OR l_attribute <> pfc_option_types.c_attr_sto_proc_name
               OR l_seen.EXISTS(l_attribute) THEN
                RAISE_APPLICATION_ERROR(c_err_invalid_option,
                    'The option contains an unsupported or duplicate HER requirement.');
            END IF;
            l_seen(l_attribute) := TRUE;
            validate_value_requirement(
                l_option.targets(p_target_index).her_requirements(l_index)
                    .desired_value.action_code,
                l_option.targets(p_target_index).her_requirements(l_index)
                    .desired_value.value_text,
                30
            );
            l_index := l_option.targets(p_target_index).her_requirements.NEXT(l_index);
        END LOOP;

        l_index := l_option.targets(p_target_index).hef_requirements.FIRST;
        WHILE l_index IS NOT NULL LOOP
            IF l_option.targets(p_target_index).hef_requirements(l_index)
                    .selector_terms.COUNT = 0
               OR l_option.targets(p_target_index).hef_requirements(l_index)
                    .attribute_requirements.COUNT = 0 THEN
                RAISE_APPLICATION_ERROR(c_err_invalid_option,
                    'A HEF requirement is incomplete.');
            END IF;

            l_seen.DELETE;
            l_inner_index := l_option.targets(p_target_index)
                .hef_requirements(l_index).selector_terms.FIRST;
            WHILE l_inner_index IS NOT NULL LOOP
                l_attribute := UPPER(TRIM(l_option.targets(p_target_index)
                    .hef_requirements(l_index).selector_terms(l_inner_index)
                    .attribute_code));
                IF l_attribute IS NULL OR l_attribute NOT IN (
                    pfc_option_types.c_attr_field_number,
                    pfc_option_types.c_attr_field_name,
                    pfc_option_types.c_attr_sto_proc_name,
                    pfc_option_types.c_attr_hard_coded_data
                ) OR l_seen.EXISTS(l_attribute) THEN
                    RAISE_APPLICATION_ERROR(c_err_invalid_option,
                        'A HEF selector is unsupported or repeats an attribute.');
                END IF;
                l_seen(l_attribute) := TRUE;
                l_inner_index := l_option.targets(p_target_index)
                    .hef_requirements(l_index).selector_terms.NEXT(l_inner_index);
            END LOOP;

            l_seen.DELETE;
            l_sto_requirement.action_code := pfc_option_types.c_action_keep;
            l_sto_requirement.value_text := NULL;
            l_hard_requirement.action_code := pfc_option_types.c_action_keep;
            l_hard_requirement.value_text := NULL;
            l_inner_index := l_option.targets(p_target_index)
                .hef_requirements(l_index).attribute_requirements.FIRST;
            WHILE l_inner_index IS NOT NULL LOOP
                l_attribute := UPPER(TRIM(l_option.targets(p_target_index)
                    .hef_requirements(l_index)
                    .attribute_requirements(l_inner_index).attribute_code));
                IF l_attribute IS NULL OR l_attribute NOT IN (
                    pfc_option_types.c_attr_sto_proc_name,
                    pfc_option_types.c_attr_hard_coded_data
                ) OR l_seen.EXISTS(l_attribute) THEN
                    RAISE_APPLICATION_ERROR(c_err_invalid_option,
                        'A HEF requirement is unsupported or repeats an attribute.');
                END IF;
                l_seen(l_attribute) := TRUE;
                validate_value_requirement(
                    l_option.targets(p_target_index).hef_requirements(l_index)
                        .attribute_requirements(l_inner_index)
                        .desired_value.action_code,
                    l_option.targets(p_target_index).hef_requirements(l_index)
                        .attribute_requirements(l_inner_index)
                        .desired_value.value_text,
                    CASE WHEN l_attribute = pfc_option_types.c_attr_sto_proc_name
                        THEN 30 ELSE 128 END
                );
                IF l_attribute = pfc_option_types.c_attr_sto_proc_name THEN
                    l_sto_requirement := l_option.targets(p_target_index)
                        .hef_requirements(l_index)
                        .attribute_requirements(l_inner_index).desired_value;
                ELSE
                    l_hard_requirement := l_option.targets(p_target_index)
                        .hef_requirements(l_index)
                        .attribute_requirements(l_inner_index).desired_value;
                END IF;
                l_inner_index := l_option.targets(p_target_index)
                    .hef_requirements(l_index)
                    .attribute_requirements.NEXT(l_inner_index);
            END LOOP;
            l_test_sto := NULL;
            l_test_hard := NULL;
            pfc_option_types.apply_hef_value_pair(
                l_sto_requirement,
                l_hard_requirement,
                l_test_sto,
                l_test_hard
            );
            l_index := l_option.targets(p_target_index).hef_requirements.NEXT(l_index);
        END LOOP;
    END validate_target_definition;

    PROCEDURE validate_option_definition
    IS
        l_index PLS_INTEGER;
        l_seen  t_seen_map;
    BEGIN
        IF l_option.inherit_source_ind IS NULL
           OR l_option.inherit_source_ind NOT IN ('Y', 'N') THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_option,
                'The option definition has an invalid inheritance indicator.');
        END IF;
        IF l_option.option_code IS NULL
           OR l_option.display_label IS NULL
           OR l_option.phys_form_field_num IS NULL
           OR l_option.targets.COUNT = 0 THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_option,
                'The option definition is incomplete.');
        END IF;
        IF l_option.inherit_source_ind = 'Y' THEN
            l_index := l_option.targets.FIRST;
            WHILE l_index IS NOT NULL LOOP
                IF l_option.targets(l_index).her_requirements.COUNT <> 0
                   OR l_option.targets(l_index).hef_requirements.COUNT <> 0 THEN
                    RAISE_APPLICATION_ERROR(c_err_invalid_option,
                        'An inherited option cannot contain desired-state overlays.');
                END IF;
                l_index := l_option.targets.NEXT(l_index);
            END LOOP;
        END IF;
        l_index := l_option.targets.FIRST;
        WHILE l_index IS NOT NULL LOOP
            validate_target_definition(l_index);
            IF l_seen.EXISTS('CODE|' || l_option.targets(l_index).target_code)
               OR l_seen.EXISTS('RECORD|' ||
                    l_option.targets(l_index).record_type_code) THEN
                RAISE_APPLICATION_ERROR(c_err_invalid_option,
                    'The option contains a duplicate target.');
            END IF;
            l_seen('CODE|' || l_option.targets(l_index).target_code) := TRUE;
            l_seen('RECORD|' || l_option.targets(l_index).record_type_code) := TRUE;
            l_index := l_option.targets.NEXT(l_index);
        END LOOP;
    END validate_option_definition;

    FUNCTION hef_matches_requirement (
        p_target_index      IN PLS_INTEGER,
        p_hef               IN hcfa_electronic_fields%ROWTYPE,
        p_requirement_index IN PLS_INTEGER
    ) RETURN BOOLEAN
    IS
        l_index     PLS_INTEGER;
        l_attribute pfc_option_types.t_attribute_code;
        l_actual    VARCHAR2(32767);
        l_expected  VARCHAR2(32767);
    BEGIN
        l_index := l_option.targets(p_target_index)
            .hef_requirements(p_requirement_index).selector_terms.FIRST;
        WHILE l_index IS NOT NULL LOOP
            l_attribute := UPPER(TRIM(l_option.targets(p_target_index)
                .hef_requirements(p_requirement_index).selector_terms(l_index)
                .attribute_code));
            l_expected := l_option.targets(p_target_index)
                .hef_requirements(p_requirement_index).selector_terms(l_index)
                .expected_value;
            CASE l_attribute
                WHEN pfc_option_types.c_attr_field_number THEN
                    l_actual := p_hef.field_number;
                WHEN pfc_option_types.c_attr_field_name THEN
                    l_actual := p_hef.field_name;
                WHEN pfc_option_types.c_attr_sto_proc_name THEN
                    l_actual := p_hef.sto_proc_name;
                WHEN pfc_option_types.c_attr_hard_coded_data THEN
                    l_actual := p_hef.hard_coded_data;
                ELSE
                    RAISE_APPLICATION_ERROR(c_err_invalid_option,
                        'A HEF selector attribute is unsupported.');
            END CASE;
            IF NOT values_equal(l_actual, l_expected) THEN
                RETURN FALSE;
            END IF;
            l_index := l_option.targets(p_target_index)
                .hef_requirements(p_requirement_index).selector_terms.NEXT(l_index);
        END LOOP;
        RETURN TRUE;
    END hef_matches_requirement;

    PROCEDURE set_context (
        p_row_pfc_guid           IN pfc.pfc_guid%TYPE,
        p_row_payor_guid         IN pfc.payor_guid%TYPE,
        p_row_plan_guid          IN pfc.plan_guid%TYPE,
        p_row_payor_type_guid    IN payors.payor_type_guid%TYPE,
        p_row_billing_form_code  IN pfc.billing_form_code%TYPE,
        p_row_form_template_guid IN pfc.form_template_guid%TYPE,
        p_row_user_template_guid IN pfc.user_form_template_guid%TYPE,
        p_row_cpd_start_date     IN pfc.cpd_start_date%TYPE,
        p_row_cpd_end_date       IN pfc.cpd_end_date%TYPE
    )
    IS
    BEGIN
        IF NOT l_context_set THEN
            l_pfc_guid := p_row_pfc_guid;
            l_resolved_payor_guid := p_row_payor_guid;
            l_resolved_plan_guid := p_row_plan_guid;
            l_payor_type_guid := p_row_payor_type_guid;
            l_billing_form_code := p_row_billing_form_code;
            l_form_template_guid := p_row_form_template_guid;
            l_user_template_guid := p_row_user_template_guid;
            l_cpd_start_date := p_row_cpd_start_date;
            l_cpd_end_date := p_row_cpd_end_date;
            l_context_set := TRUE;
        ELSIF NOT values_equal(l_pfc_guid, p_row_pfc_guid)
           OR NOT values_equal(l_resolved_payor_guid, p_row_payor_guid)
           OR NOT values_equal(l_resolved_plan_guid, p_row_plan_guid)
           OR NOT values_equal(l_payor_type_guid, p_row_payor_type_guid)
           OR NOT values_equal(l_billing_form_code, p_row_billing_form_code)
           OR NOT values_equal(l_form_template_guid, p_row_form_template_guid)
           OR NOT values_equal(l_user_template_guid, p_row_user_template_guid)
           OR NVL(l_cpd_start_date, DATE '1000-01-01') <>
                NVL(p_row_cpd_start_date, DATE '1000-01-01')
           OR NVL(l_cpd_end_date, DATE '1000-01-01') <>
                NVL(p_row_cpd_end_date, DATE '1000-01-01') THEN
            RAISE_APPLICATION_ERROR(c_err_unexpected_state,
                'Script 2 returned inconsistent PFC context across targets.');
        END IF;
    END set_context;

    PROCEDURE resolve_source (
        p_target_index IN PLS_INTEGER,
        p_source_guid  OUT hcfa_electronic_records.electronic_rec_guid%TYPE
    )
    IS
        l_results SYS_REFCURSOR;
        l_row pfc_config_internal.t_resolved_her_hef_row;
        l_row_count PLS_INTEGER := 0;
    BEGIN
        p_source_guid := NULL;
        pfc_resolve_her_hef(
            p_payor_guid => p_payor_guid,
            p_plan_guid => p_plan_guid,
            p_record_type_code =>
                l_option.targets(p_target_index).record_type_code,
            p_results => l_results
        );
        LOOP
            FETCH l_results INTO l_row;
            EXIT WHEN l_results%NOTFOUND;
            l_row_count := l_row_count + 1;
            set_context(
                l_row.pfc_guid, l_row.payor_guid, l_row.plan_guid,
                l_row.payor_type_guid, l_row.billing_form_code,
                l_row.form_template_guid, l_row.user_form_template_guid,
                l_row.cpd_start_date, l_row.cpd_end_date
            );
            IF l_row.is_clone_source = 'Y' THEN
                IF p_source_guid IS NULL THEN
                    p_source_guid := l_row.electronic_rec_guid;
                ELSIF p_source_guid <> l_row.electronic_rec_guid THEN
                    RAISE_APPLICATION_ERROR(c_err_unexpected_state,
                        'Script 2 returned inconsistent clone-source rows.');
                END IF;
            END IF;
        END LOOP;
        CLOSE l_results;
        IF l_row_count = 0 OR p_source_guid IS NULL THEN
            RAISE_APPLICATION_ERROR(c_err_unexpected_state,
                'Script 2 did not return a resolved clone source.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF l_results%ISOPEN THEN
                CLOSE l_results;
            END IF;
            RAISE;
    END resolve_source;

    PROCEDURE apply_overlay (p_state_index IN PLS_INTEGER)
    IS
        l_target_index      PLS_INTEGER := l_targets(p_state_index).option_index;
        l_requirement_index PLS_INTEGER;
        l_attribute_index   PLS_INTEGER;
        l_hef_index         PLS_INTEGER;
        l_match_index       PLS_INTEGER;
        l_match_count       PLS_INTEGER;
        l_attribute         pfc_option_types.t_attribute_code;
        l_action            pfc_option_types.t_action_code;
        l_value             pfc_option_types.t_value_text;
        l_seen              t_seen_map;
        l_key               VARCHAR2(256);
        l_sto_requirement   pfc_option_types.t_value_requirement;
        l_hard_requirement  pfc_option_types.t_value_requirement;
        l_sto_value         pfc_option_types.t_value_text;
        l_hard_value        pfc_option_types.t_value_text;
    BEGIN
        l_targets(p_state_index).overlay_her :=
            l_targets(p_state_index).source_her;
        l_targets(p_state_index).overlay_hefs :=
            l_targets(p_state_index).source_hefs;

        l_requirement_index := l_option.targets(l_target_index)
            .her_requirements.FIRST;
        WHILE l_requirement_index IS NOT NULL LOOP
            l_attribute := UPPER(TRIM(l_option.targets(l_target_index)
                .her_requirements(l_requirement_index).attribute_code));
            l_action := UPPER(TRIM(l_option.targets(l_target_index)
                .her_requirements(l_requirement_index).desired_value.action_code));
            l_value := l_option.targets(l_target_index)
                .her_requirements(l_requirement_index).desired_value.value_text;
            IF l_attribute <> pfc_option_types.c_attr_sto_proc_name THEN
                RAISE_APPLICATION_ERROR(c_err_invalid_option,
                    'A HER requirement attribute is unsupported.');
            ELSIF l_action = pfc_option_types.c_action_set THEN
                l_targets(p_state_index).overlay_her.sto_proc_name := l_value;
            ELSIF l_action = pfc_option_types.c_action_clear THEN
                l_targets(p_state_index).overlay_her.sto_proc_name := NULL;
            END IF;
            l_requirement_index := l_option.targets(l_target_index)
                .her_requirements.NEXT(l_requirement_index);
        END LOOP;

        l_requirement_index := l_option.targets(l_target_index)
            .hef_requirements.FIRST;
        WHILE l_requirement_index IS NOT NULL LOOP
            l_match_index := NULL;
            l_match_count := 0;
            l_hef_index := l_targets(p_state_index).source_hefs.FIRST;
            WHILE l_hef_index IS NOT NULL LOOP
                IF hef_matches_requirement(
                    l_target_index,
                    l_targets(p_state_index).source_hefs(l_hef_index),
                    l_requirement_index
                ) THEN
                    l_match_index := l_hef_index;
                    l_match_count := l_match_count + 1;
                END IF;
                l_hef_index := l_targets(p_state_index).source_hefs.NEXT(l_hef_index);
            END LOOP;
            IF l_match_count = 0 THEN
                RAISE_APPLICATION_ERROR(c_err_hef_target_missing,
                    'A required HEF option target was not found.');
            ELSIF l_match_count > 1 THEN
                RAISE_APPLICATION_ERROR(c_err_hef_target_ambiguous,
                    'A HEF option target matched multiple source fields.');
            END IF;

            l_sto_requirement.action_code := pfc_option_types.c_action_keep;
            l_sto_requirement.value_text := NULL;
            l_hard_requirement.action_code := pfc_option_types.c_action_keep;
            l_hard_requirement.value_text := NULL;
            l_attribute_index := l_option.targets(l_target_index)
                .hef_requirements(l_requirement_index)
                .attribute_requirements.FIRST;
            WHILE l_attribute_index IS NOT NULL LOOP
                l_attribute := UPPER(TRIM(l_option.targets(l_target_index)
                    .hef_requirements(l_requirement_index)
                    .attribute_requirements(l_attribute_index).attribute_code));
                l_action := UPPER(TRIM(l_option.targets(l_target_index)
                    .hef_requirements(l_requirement_index)
                    .attribute_requirements(l_attribute_index)
                    .desired_value.action_code));
                l_value := l_option.targets(l_target_index)
                    .hef_requirements(l_requirement_index)
                    .attribute_requirements(l_attribute_index)
                    .desired_value.value_text;
                l_key := TO_CHAR(l_match_index) || '|' || l_attribute;
                IF l_seen.EXISTS(l_key) THEN
                    RAISE_APPLICATION_ERROR(c_err_invalid_option,
                        'Multiple requirements manage the same HEF attribute.');
                END IF;
                l_seen(l_key) := TRUE;
                IF l_attribute = pfc_option_types.c_attr_sto_proc_name THEN
                    l_sto_requirement := l_option.targets(l_target_index)
                        .hef_requirements(l_requirement_index)
                        .attribute_requirements(l_attribute_index).desired_value;
                ELSIF l_attribute = pfc_option_types.c_attr_hard_coded_data THEN
                    l_hard_requirement := l_option.targets(l_target_index)
                        .hef_requirements(l_requirement_index)
                        .attribute_requirements(l_attribute_index).desired_value;
                ELSE
                    RAISE_APPLICATION_ERROR(c_err_invalid_option,
                        'A HEF requirement attribute is unsupported.');
                END IF;
                l_attribute_index := l_option.targets(l_target_index)
                    .hef_requirements(l_requirement_index)
                    .attribute_requirements.NEXT(l_attribute_index);
            END LOOP;

            IF UPPER(TRIM(l_sto_requirement.action_code)) =
                    pfc_option_types.c_action_set
               AND l_sto_requirement.value_text IS NOT NULL THEN
                IF l_seen.EXISTS(
                    'NON_NULL_SET|' || TO_CHAR(l_match_index) || '|HARD'
                ) THEN
                    RAISE_APPLICATION_ERROR(c_err_invalid_option,
                        'A managed HEF cannot SET STO_PROC_NAME and ' ||
                        'HARD_CODED_DATA to non-null values together.');
                END IF;
                l_seen('NON_NULL_SET|' || TO_CHAR(l_match_index) || '|STO') :=
                    TRUE;
            END IF;
            IF UPPER(TRIM(l_hard_requirement.action_code)) =
                    pfc_option_types.c_action_set
               AND l_hard_requirement.value_text IS NOT NULL THEN
                IF l_seen.EXISTS(
                    'NON_NULL_SET|' || TO_CHAR(l_match_index) || '|STO'
                ) THEN
                    RAISE_APPLICATION_ERROR(c_err_invalid_option,
                        'A managed HEF cannot SET STO_PROC_NAME and ' ||
                        'HARD_CODED_DATA to non-null values together.');
                END IF;
                l_seen('NON_NULL_SET|' || TO_CHAR(l_match_index) || '|HARD') :=
                    TRUE;
            END IF;

            l_sto_value := l_targets(p_state_index)
                .overlay_hefs(l_match_index).sto_proc_name;
            l_hard_value := l_targets(p_state_index)
                .overlay_hefs(l_match_index).hard_coded_data;
            pfc_option_types.apply_hef_value_pair(
                l_sto_requirement,
                l_hard_requirement,
                l_sto_value,
                l_hard_value
            );
            l_targets(p_state_index).overlay_hefs(l_match_index)
                .sto_proc_name := l_sto_value;
            l_targets(p_state_index).overlay_hefs(l_match_index)
                .hard_coded_data := l_hard_value;
            l_requirement_index := l_option.targets(l_target_index)
                .hef_requirements.NEXT(l_requirement_index);
        END LOOP;
    END apply_overlay;

    PROCEDURE make_payor_desired (p_state_index IN PLS_INTEGER)
    IS
        l_hef_index PLS_INTEGER;
    BEGIN
        l_targets(p_state_index).desired_her :=
            l_targets(p_state_index).overlay_her;
        l_targets(p_state_index).desired_her.electronic_rec_guid := NULL;
        l_targets(p_state_index).desired_her.payor_guid := l_resolved_payor_guid;
        l_targets(p_state_index).desired_her.plan_guid := l_resolved_plan_guid;
        l_targets(p_state_index).desired_her.payor_type_guid := l_payor_type_guid;
        l_targets(p_state_index).desired_her.carry_forward_ind := NULL;
        l_targets(p_state_index).desired_her.include_record_data_onclaim := 'Y';
        l_targets(p_state_index).desired_her.rec_ent_date := NULL;
        l_targets(p_state_index).desired_her.rec_ent_user := NULL;
        l_targets(p_state_index).desired_her.rec_mod_date := NULL;
        l_targets(p_state_index).desired_her.rec_mod_user := NULL;

        l_targets(p_state_index).desired_hefs :=
            l_targets(p_state_index).overlay_hefs;
        l_hef_index := l_targets(p_state_index).desired_hefs.FIRST;
        WHILE l_hef_index IS NOT NULL LOOP
            l_targets(p_state_index).desired_hefs(l_hef_index)
                .electronic_rec_guid := NULL;
            l_targets(p_state_index).desired_hefs(l_hef_index).rec_ent_date := NULL;
            l_targets(p_state_index).desired_hefs(l_hef_index).rec_ent_user := NULL;
            l_targets(p_state_index).desired_hefs(l_hef_index).rec_mod_date := NULL;
            l_targets(p_state_index).desired_hefs(l_hef_index).rec_mod_user := NULL;
            l_hef_index := l_targets(p_state_index).desired_hefs.NEXT(l_hef_index);
        END LOOP;
    END make_payor_desired;

    PROCEDURE resolve_target (
        p_state_index IN PLS_INTEGER,
        p_option_index IN PLS_INTEGER
    )
    IS
    BEGIN
        l_targets(p_state_index).option_index := p_option_index;
        l_targets(p_state_index).target_code :=
            l_option.targets(p_option_index).target_code;
        l_targets(p_state_index).record_type_code :=
            l_option.targets(p_option_index).record_type_code;
        resolve_source(p_option_index, l_targets(p_state_index).source_guid);

        SELECT * INTO l_targets(p_state_index).source_her
        FROM hcfa_electronic_records h
        WHERE h.electronic_rec_guid = l_targets(p_state_index).source_guid;

        SELECT * BULK COLLECT INTO l_targets(p_state_index).source_hefs
        FROM hcfa_electronic_fields f
        WHERE f.electronic_rec_guid = l_targets(p_state_index).source_guid;

        apply_overlay(p_state_index);
        IF l_option.inherit_source_ind = 'Y' THEN
            pfc_config_internal.assert_inherited_her_safe(
                l_targets(p_state_index).source_her
            );
        ELSE
            pfc_config_internal.apply_her_safety_invariants(
                l_targets(p_state_index).overlay_her
            );
        END IF;
        l_targets(p_state_index).desired_differs := NOT configurations_equal(
            l_targets(p_state_index).source_her,
            l_targets(p_state_index).source_hefs,
            l_targets(p_state_index).overlay_her,
            l_targets(p_state_index).overlay_hefs
        );
        make_payor_desired(p_state_index);

        SELECT COUNT(*), NVL(SUM((
            SELECT COUNT(*)
            FROM hcfa_electronic_fields f
            WHERE f.electronic_rec_guid = h.electronic_rec_guid
        )), 0)
        INTO l_targets(p_state_index).existing_her_count,
             l_targets(p_state_index).existing_hef_count
        FROM hcfa_electronic_records h
        WHERE h.payor_guid = l_resolved_payor_guid
                  AND (h.plan_guid = l_resolved_plan_guid OR (h.plan_guid IS NULL AND l_resolved_plan_guid IS NULL))
          AND h.billing_form_code = l_billing_form_code
          AND h.record_type_code = l_targets(p_state_index).record_type_code;

        l_targets(p_state_index).current_hefs.DELETE;
        IF l_targets(p_state_index).existing_her_count = 1 THEN
            SELECT * INTO l_targets(p_state_index).current_her
            FROM hcfa_electronic_records h
            WHERE h.payor_guid = l_resolved_payor_guid
                  AND (h.plan_guid = l_resolved_plan_guid OR (h.plan_guid IS NULL AND l_resolved_plan_guid IS NULL))
              AND h.billing_form_code = l_billing_form_code
              AND h.record_type_code = l_targets(p_state_index).record_type_code;
            SELECT * BULK COLLECT INTO l_targets(p_state_index).current_hefs
            FROM hcfa_electronic_fields f
            WHERE f.electronic_rec_guid =
                l_targets(p_state_index).current_her.electronic_rec_guid;
            l_targets(p_state_index).current_matches_source :=
                functional_configurations_equal(
                    l_targets(p_state_index).current_her,
                    l_targets(p_state_index).current_hefs,
                    l_targets(p_state_index).source_her,
                    l_targets(p_state_index).source_hefs
                );
            l_targets(p_state_index).current_matches_desired :=
                functional_configurations_equal(
                    l_targets(p_state_index).current_her,
                    l_targets(p_state_index).current_hefs,
                    l_targets(p_state_index).overlay_her,
                    l_targets(p_state_index).overlay_hefs
                );
        END IF;

        IF NOT l_targets(p_state_index).desired_differs THEN
            IF l_targets(p_state_index).existing_her_count = 0 THEN
                l_targets(p_state_index).target_action := c_target_no_change;
            ELSE
                l_targets(p_state_index).target_action := c_target_remove_override;
            END IF;
        ELSIF l_targets(p_state_index).existing_her_count = 1
           AND payor_configurations_equal(
                l_targets(p_state_index).current_her,
                l_targets(p_state_index).current_hefs,
                l_targets(p_state_index).desired_her,
                l_targets(p_state_index).desired_hefs
           ) THEN
            l_targets(p_state_index).target_action := c_target_no_change;
        ELSE
            l_targets(p_state_index).target_action := c_target_rebuild_override;
        END IF;
    END resolve_target;

    PROCEDURE resolve_all_targets
    IS
        l_option_index PLS_INTEGER;
        l_state_index  PLS_INTEGER := 0;
    BEGIN
        l_targets.DELETE;
        l_context_set := FALSE;
        l_existing_her_count := 0;
        l_existing_hef_count := 0;
        l_new_hef_count := 0;
        l_option_index := l_option.targets.FIRST;
        WHILE l_option_index IS NOT NULL LOOP
            l_state_index := l_state_index + 1;
            resolve_target(l_state_index, l_option_index);
            l_existing_her_count := l_existing_her_count +
                l_targets(l_state_index).existing_her_count;
            l_existing_hef_count := l_existing_hef_count +
                l_targets(l_state_index).existing_hef_count;
            IF l_targets(l_state_index).target_action =
                    c_target_rebuild_override THEN
                l_new_hef_count := l_new_hef_count +
                    l_targets(l_state_index).desired_hefs.COUNT;
            END IF;
            l_option_index := l_option.targets.NEXT(l_option_index);
        END LOOP;
    END resolve_all_targets;

    PROCEDURE compute_state_hash
    IS
        l_pfc_entry_date pfc.rec_ent_date%TYPE;
        l_temp_her  hcfa_electronic_records%ROWTYPE;
        l_temp_hefs t_hef_rows;
    BEGIN
        l_state_serial := NULL;
        append_state('PFC_APPLY_OPTION_STATE_V4_PLAN');
        SELECT rec_ent_date INTO l_pfc_entry_date FROM pfc WHERE pfc_guid = l_pfc_guid;
        append_state(encoded_date(l_pfc_entry_date));
        append_state(l_option.option_code);
        append_state(l_option.display_label);
        append_state(l_option.phys_form_field_num);
        append_state(l_option.inherit_source_ind);
        append_state(l_pfc_guid);
        append_state(l_resolved_payor_guid);
        append_state(l_resolved_plan_guid);
        append_state(l_payor_type_guid);
        append_state(l_billing_form_code);
        append_state(l_form_template_guid);
        append_state(l_user_template_guid);
        append_state(encoded_date(l_cpd_start_date));
        append_state(encoded_date(l_cpd_end_date));

        FOR i IN 1 .. l_targets.COUNT LOOP
            append_state(l_targets(i).target_code);
            append_state(l_option.targets(l_targets(i).option_index)
                .billing_form_code);
            append_state(l_targets(i).record_type_code);
            append_state(l_targets(i).target_action);
            append_state(l_targets(i).source_guid);
            append_state(her_business_serial(l_targets(i).source_her));
            append_hef_set(l_targets(i).source_hefs);
            append_state(her_business_serial(l_targets(i).overlay_her));
            append_hef_set(l_targets(i).overlay_hefs);

            FOR target_her IN (
                SELECT h.electronic_rec_guid
                FROM hcfa_electronic_records h
                WHERE h.payor_guid = l_resolved_payor_guid
                  AND (h.plan_guid = l_resolved_plan_guid OR (h.plan_guid IS NULL AND l_resolved_plan_guid IS NULL))
                  AND h.billing_form_code = l_billing_form_code
                  AND h.record_type_code = l_targets(i).record_type_code
                ORDER BY h.electronic_rec_guid
            ) LOOP
                SELECT * INTO l_temp_her
                FROM hcfa_electronic_records h
                WHERE h.electronic_rec_guid = target_her.electronic_rec_guid;
                append_state(target_her.electronic_rec_guid);
                append_state(her_business_serial(l_temp_her));
                l_temp_hefs.DELETE;
                SELECT * BULK COLLECT INTO l_temp_hefs
                FROM hcfa_electronic_fields f
                WHERE f.electronic_rec_guid = target_her.electronic_rec_guid;
                append_hef_set(l_temp_hefs);
            END LOOP;
        END LOOP;
        SELECT STANDARD_HASH(l_state_serial, 'SHA256')
        INTO l_state_hash
        FROM dual;
    END compute_state_hash;

    PROCEDURE add_change (
        p_operation_code IN VARCHAR2,
        p_target_guid    IN VARCHAR2,
        p_field_number   IN VARCHAR2 DEFAULT NULL,
        p_attribute_code IN VARCHAR2 DEFAULT NULL,
        p_old_value      IN VARCHAR2 DEFAULT NULL,
        p_new_value      IN VARCHAR2 DEFAULT NULL
    )
    IS
        l_index PLS_INTEGER := l_changes.COUNT + 1;
    BEGIN
        l_changes(l_index).operation_order := l_index;
        l_changes(l_index).operation_code := p_operation_code;
        l_changes(l_index).target_electronic_rec_guid := p_target_guid;
        l_changes(l_index).field_number := p_field_number;
        l_changes(l_index).attribute_code := p_attribute_code;
        l_changes(l_index).old_value := p_old_value;
        l_changes(l_index).new_value := p_new_value;
    END add_change;

    PROCEDURE add_overlay_changes (p_state_index IN PLS_INTEGER)
    IS
        l_target_index      PLS_INTEGER := l_targets(p_state_index).option_index;
        l_requirement_index PLS_INTEGER;
        l_attribute_index   PLS_INTEGER;
        l_hef_index         PLS_INTEGER;
        l_match_index       PLS_INTEGER;
        l_attribute         pfc_option_types.t_attribute_code;
        l_action            pfc_option_types.t_action_code;
        l_value             pfc_option_types.t_value_text;
        l_sto_requirement   pfc_option_types.t_value_requirement;
        l_hard_requirement  pfc_option_types.t_value_requirement;
    BEGIN
        l_requirement_index := l_option.targets(l_target_index)
            .her_requirements.FIRST;
        WHILE l_requirement_index IS NOT NULL LOOP
            l_attribute := UPPER(TRIM(l_option.targets(l_target_index)
                .her_requirements(l_requirement_index).attribute_code));
            l_action := UPPER(TRIM(l_option.targets(l_target_index)
                .her_requirements(l_requirement_index).desired_value.action_code));
            l_value := l_option.targets(l_target_index)
                .her_requirements(l_requirement_index).desired_value.value_text;
            IF l_action = pfc_option_types.c_action_set THEN
                add_change('SET_HER_VALUE', l_targets(p_state_index).new_guid,
                    NULL, l_attribute,
                    l_targets(p_state_index).source_her.sto_proc_name, l_value);
            ELSIF l_action = pfc_option_types.c_action_clear THEN
                add_change('CLEAR_HER_VALUE', l_targets(p_state_index).new_guid,
                    NULL, l_attribute,
                    l_targets(p_state_index).source_her.sto_proc_name, NULL);
            END IF;
            l_requirement_index := l_option.targets(l_target_index)
                .her_requirements.NEXT(l_requirement_index);
        END LOOP;

        l_requirement_index := l_option.targets(l_target_index)
            .hef_requirements.FIRST;
        WHILE l_requirement_index IS NOT NULL LOOP
            l_match_index := NULL;
            l_hef_index := l_targets(p_state_index).source_hefs.FIRST;
            WHILE l_hef_index IS NOT NULL LOOP
                IF hef_matches_requirement(
                    l_target_index,
                    l_targets(p_state_index).source_hefs(l_hef_index),
                    l_requirement_index
                ) THEN
                    l_match_index := l_hef_index;
                END IF;
                l_hef_index := l_targets(p_state_index).source_hefs.NEXT(l_hef_index);
            END LOOP;
            l_sto_requirement.action_code := pfc_option_types.c_action_keep;
            l_sto_requirement.value_text := NULL;
            l_hard_requirement.action_code := pfc_option_types.c_action_keep;
            l_hard_requirement.value_text := NULL;
            l_attribute_index := l_option.targets(l_target_index)
                .hef_requirements(l_requirement_index)
                .attribute_requirements.FIRST;
            WHILE l_attribute_index IS NOT NULL LOOP
                l_attribute := UPPER(TRIM(l_option.targets(l_target_index)
                    .hef_requirements(l_requirement_index)
                    .attribute_requirements(l_attribute_index).attribute_code));
                l_action := UPPER(TRIM(l_option.targets(l_target_index)
                    .hef_requirements(l_requirement_index)
                    .attribute_requirements(l_attribute_index)
                    .desired_value.action_code));
                l_value := l_option.targets(l_target_index)
                    .hef_requirements(l_requirement_index)
                    .attribute_requirements(l_attribute_index)
                    .desired_value.value_text;
                IF l_attribute = pfc_option_types.c_attr_sto_proc_name THEN
                    l_sto_requirement := l_option.targets(l_target_index)
                        .hef_requirements(l_requirement_index)
                        .attribute_requirements(l_attribute_index).desired_value;
                ELSE
                    l_hard_requirement := l_option.targets(l_target_index)
                        .hef_requirements(l_requirement_index)
                        .attribute_requirements(l_attribute_index).desired_value;
                END IF;
                IF l_action = pfc_option_types.c_action_set THEN
                    add_change('SET_HEF_VALUE', l_targets(p_state_index).new_guid,
                        l_targets(p_state_index).source_hefs(l_match_index).field_number,
                        l_attribute,
                        CASE WHEN l_attribute = pfc_option_types.c_attr_sto_proc_name
                            THEN l_targets(p_state_index).source_hefs(l_match_index)
                                .sto_proc_name
                            ELSE l_targets(p_state_index).source_hefs(l_match_index)
                                .hard_coded_data END,
                        l_value);
                ELSIF l_action = pfc_option_types.c_action_clear THEN
                    add_change('CLEAR_HEF_VALUE', l_targets(p_state_index).new_guid,
                        l_targets(p_state_index).source_hefs(l_match_index).field_number,
                        l_attribute,
                        CASE WHEN l_attribute = pfc_option_types.c_attr_sto_proc_name
                            THEN l_targets(p_state_index).source_hefs(l_match_index)
                                .sto_proc_name
                            ELSE l_targets(p_state_index).source_hefs(l_match_index)
                                .hard_coded_data END,
                        NULL);
                END IF;
                l_attribute_index := l_option.targets(l_target_index)
                    .hef_requirements(l_requirement_index)
                    .attribute_requirements.NEXT(l_attribute_index);
            END LOOP;
            IF UPPER(TRIM(l_sto_requirement.action_code)) =
                    pfc_option_types.c_action_set
               AND l_sto_requirement.value_text IS NOT NULL
               AND UPPER(TRIM(l_hard_requirement.action_code)) <>
                    pfc_option_types.c_action_clear
               AND l_targets(p_state_index).source_hefs(l_match_index)
                    .hard_coded_data IS NOT NULL THEN
                add_change(
                    'CLEAR_HEF_VALUE',
                    l_targets(p_state_index).new_guid,
                    l_targets(p_state_index).source_hefs(l_match_index)
                        .field_number,
                    pfc_option_types.c_attr_hard_coded_data,
                    l_targets(p_state_index).source_hefs(l_match_index)
                        .hard_coded_data,
                    NULL
                );
            ELSIF UPPER(TRIM(l_hard_requirement.action_code)) =
                    pfc_option_types.c_action_set
                  AND l_hard_requirement.value_text IS NOT NULL
                  AND UPPER(TRIM(l_sto_requirement.action_code)) <>
                    pfc_option_types.c_action_clear
                  AND l_targets(p_state_index).source_hefs(l_match_index)
                    .sto_proc_name IS NOT NULL THEN
                add_change(
                    'CLEAR_HEF_VALUE',
                    l_targets(p_state_index).new_guid,
                    l_targets(p_state_index).source_hefs(l_match_index)
                        .field_number,
                    pfc_option_types.c_attr_sto_proc_name,
                    l_targets(p_state_index).source_hefs(l_match_index)
                        .sto_proc_name,
                    NULL
                );
            END IF;
            l_requirement_index := l_option.targets(l_target_index)
                .hef_requirements.NEXT(l_requirement_index);
        END LOOP;
    END add_overlay_changes;

    PROCEDURE assign_target_guids (p_preview IN BOOLEAN)
    IS
    BEGIN
        FOR i IN 1 .. l_targets.COUNT LOOP
            IF l_targets(i).target_action = c_target_rebuild_override THEN
                IF p_preview THEN
                    l_targets(i).new_guid := 'GENERATED_ON_APPLY_' ||
                        l_targets(i).target_code;
                ELSE
                    l_targets(i).new_guid := RAWTOHEX(SYS_GUID());
                    IF LENGTH(l_targets(i).new_guid) > 36 THEN
                        RAISE_APPLICATION_ERROR(c_err_unexpected_state,
                            'A generated HER identifier does not fit the POC schema.');
                    END IF;
                END IF;
            END IF;
        END LOOP;
    END assign_target_guids;

    PROCEDURE build_changes
    IS
    BEGIN
        l_changes.DELETE;
        l_change_count := 0;

        FOR i IN 1 .. l_targets.COUNT LOOP
            add_change(
                l_targets(i).target_action,
                l_targets(i).target_code,
                NULL,
                'TARGET_ACTION',
                l_targets(i).record_type_code,
                CASE WHEN l_targets(i).target_action = c_target_rebuild_override
                    THEN l_targets(i).new_guid ELSE NULL END
            );
        END LOOP;

        FOR i IN 1 .. l_targets.COUNT LOOP
            IF l_targets(i).target_action IN (
                c_target_remove_override, c_target_rebuild_override
            ) THEN
                FOR target_hef IN (
                    SELECT h.electronic_rec_guid, f.field_number,
                           f.order_num, f.position_from
                    FROM hcfa_electronic_records h
                    JOIN hcfa_electronic_fields f
                      ON f.electronic_rec_guid = h.electronic_rec_guid
                    WHERE h.payor_guid = l_resolved_payor_guid
                  AND (h.plan_guid = l_resolved_plan_guid OR (h.plan_guid IS NULL AND l_resolved_plan_guid IS NULL))
                      AND h.billing_form_code = l_billing_form_code
                      AND h.record_type_code = l_targets(i).record_type_code
                    ORDER BY h.electronic_rec_guid, f.order_num NULLS FIRST,
                             f.position_from, f.field_number
                ) LOOP
                    add_change('DELETE_HEF', target_hef.electronic_rec_guid,
                        target_hef.field_number);
                    l_change_count := l_change_count + 1;
                END LOOP;
            END IF;
        END LOOP;
        FOR i IN 1 .. l_targets.COUNT LOOP
            IF l_targets(i).target_action IN (
                c_target_remove_override, c_target_rebuild_override
            ) THEN
                FOR target_her IN (
                    SELECT h.electronic_rec_guid
                    FROM hcfa_electronic_records h
                    WHERE h.payor_guid = l_resolved_payor_guid
                  AND (h.plan_guid = l_resolved_plan_guid OR (h.plan_guid IS NULL AND l_resolved_plan_guid IS NULL))
                      AND h.billing_form_code = l_billing_form_code
                      AND h.record_type_code = l_targets(i).record_type_code
                    ORDER BY h.electronic_rec_guid
                ) LOOP
                    add_change('DELETE_HER', target_her.electronic_rec_guid);
                    l_change_count := l_change_count + 1;
                END LOOP;
            END IF;
        END LOOP;
        FOR i IN 1 .. l_targets.COUNT LOOP
            IF l_targets(i).target_action = c_target_rebuild_override THEN
                add_change('INSERT_HER', l_targets(i).new_guid);
                l_change_count := l_change_count + 1;
            END IF;
        END LOOP;
        FOR i IN 1 .. l_targets.COUNT LOOP
            IF l_targets(i).target_action = c_target_rebuild_override THEN
                FOR j IN 1 .. l_targets(i).desired_hefs.COUNT LOOP
                    add_change('INSERT_HEF', l_targets(i).new_guid,
                        l_targets(i).desired_hefs(j).field_number);
                    l_change_count := l_change_count + 1;
                END LOOP;
            END IF;
        END LOOP;
        FOR i IN 1 .. l_targets.COUNT LOOP
            IF l_targets(i).target_action = c_target_rebuild_override THEN
                add_overlay_changes(i);
            END IF;
        END LOOP;
    END build_changes;

    FUNCTION sql_literal (p_value IN VARCHAR2) RETURN VARCHAR2
    IS
    BEGIN
        IF p_value IS NULL THEN
            RETURN 'CAST(NULL AS VARCHAR2(4000))';
        END IF;
        RETURN '''' || REPLACE(p_value, '''', '''''') || '''';
    END sql_literal;

    FUNCTION sql_varchar_literal (
        p_value IN VARCHAR2,
        p_length IN PLS_INTEGER
    ) RETURN VARCHAR2
    IS
    BEGIN
        RETURN 'CAST(' || sql_literal(p_value) || ' AS VARCHAR2(' ||
            TO_CHAR(p_length) || '))';
    END sql_varchar_literal;

    PROCEDURE prepare_change_sql
    IS
    BEGIN
        l_changes_sql := NULL;
        IF l_changes.COUNT = 0 THEN
            RETURN;
        END IF;
        FOR i IN 1 .. l_changes.COUNT LOOP
            IF i > 1 THEN
                l_changes_sql := l_changes_sql || ' UNION ALL ';
            END IF;
            l_changes_sql := l_changes_sql ||
                'SELECT ' || TO_CHAR(l_changes(i).operation_order) ||
                ' operation_order, ' ||
                sql_varchar_literal(l_changes(i).operation_code, 30) ||
                ' operation_code, ' ||
                sql_varchar_literal(l_changes(i).target_electronic_rec_guid, 64) ||
                ' target_electronic_rec_guid, ' ||
                sql_varchar_literal(l_changes(i).field_number, 10) ||
                ' field_number, ' ||
                sql_varchar_literal(l_changes(i).attribute_code, 128) ||
                ' attribute_code, ' ||
                sql_varchar_literal(l_changes(i).old_value, 4000) ||
                ' old_value, ' ||
                sql_varchar_literal(l_changes(i).new_value, 4000) ||
                ' new_value FROM dual';
        END LOOP;
        l_changes_sql := l_changes_sql || ' ORDER BY operation_order';
    END prepare_change_sql;

    PROCEDURE lock_all_state
    IS
        l_lock_payor_type payors.payor_type_guid%TYPE;
        l_lock_guid hcfa_electronic_records.electronic_rec_guid%TYPE;
    BEGIN
        SELECT payor.payor_type_guid INTO l_lock_payor_type
        FROM payors payor
        WHERE payor.payor_guid = l_resolved_payor_guid
        FOR UPDATE;

        resolve_all_targets;
        SELECT pfc_guid INTO l_lock_guid FROM pfc
        WHERE pfc_guid = l_pfc_guid FOR UPDATE;
        FOR i IN 1 .. l_targets.COUNT LOOP
            SELECT h.electronic_rec_guid INTO l_lock_guid
            FROM hcfa_electronic_records h
            WHERE h.electronic_rec_guid = l_targets(i).source_guid
            FOR UPDATE;
            FOR source_hef IN (
                SELECT f.field_number
                FROM hcfa_electronic_fields f
                WHERE f.electronic_rec_guid = l_targets(i).source_guid
                ORDER BY f.field_number, f.order_num NULLS FIRST,
                         f.position_from
                FOR UPDATE
            ) LOOP
                NULL;
            END LOOP;
            FOR target_her IN (
                SELECT h.electronic_rec_guid
                FROM hcfa_electronic_records h
                WHERE h.payor_guid = l_resolved_payor_guid
                  AND (h.plan_guid = l_resolved_plan_guid OR (h.plan_guid IS NULL AND l_resolved_plan_guid IS NULL))
                  AND h.billing_form_code = l_billing_form_code
                  AND h.record_type_code = l_targets(i).record_type_code
                ORDER BY h.electronic_rec_guid
                FOR UPDATE
            ) LOOP
                FOR target_hef IN (
                    SELECT f.field_number
                    FROM hcfa_electronic_fields f
                    WHERE f.electronic_rec_guid = target_her.electronic_rec_guid
                    ORDER BY f.field_number, f.order_num NULLS FIRST,
                             f.position_from
                    FOR UPDATE
                ) LOOP
                    NULL;
                END LOOP;
            END LOOP;
        END LOOP;
        resolve_all_targets;
        compute_state_hash;
    END lock_all_state;

    PROCEDURE delete_target_hefs
    IS
    BEGIN
        FOR i IN 1 .. l_targets.COUNT LOOP
            IF l_targets(i).target_action IN (
                c_target_remove_override, c_target_rebuild_override
            ) THEN
                DELETE FROM hcfa_electronic_fields f
                WHERE EXISTS (
                    SELECT 1
                    FROM hcfa_electronic_records h
                    WHERE h.electronic_rec_guid = f.electronic_rec_guid
                      AND h.payor_guid = l_resolved_payor_guid
                  AND (h.plan_guid = l_resolved_plan_guid OR (h.plan_guid IS NULL AND l_resolved_plan_guid IS NULL))
                      AND h.billing_form_code = l_billing_form_code
                      AND h.record_type_code = l_targets(i).record_type_code
                );
            END IF;
        END LOOP;
    END delete_target_hefs;

    PROCEDURE delete_target_hers
    IS
    BEGIN
        FOR i IN 1 .. l_targets.COUNT LOOP
            IF l_targets(i).target_action IN (
                c_target_remove_override, c_target_rebuild_override
            ) THEN
                DELETE FROM hcfa_electronic_records h
                WHERE h.payor_guid = l_resolved_payor_guid
                  AND (h.plan_guid = l_resolved_plan_guid OR (h.plan_guid IS NULL AND l_resolved_plan_guid IS NULL))
                  AND h.billing_form_code = l_billing_form_code
                  AND h.record_type_code = l_targets(i).record_type_code;
            END IF;
        END LOOP;
    END delete_target_hers;

    PROCEDURE insert_target_hers
    IS
    BEGIN
        FOR i IN 1 .. l_targets.COUNT LOOP
            IF l_targets(i).target_action = c_target_rebuild_override THEN
                INSERT INTO hcfa_electronic_records (
                    electronic_rec_guid, loop_id, contiguity_ind,
                    billing_form_code, record_name, record_type_code,
                    record_size, mandatory_ind, req_for_claim_ind,
                    payor_type_guid, payor_guid, plan_guid, type_of_bill,
                    detail_ind, max_number, invoice_ind, form_template_guid,
                    carry_forward_ind, max_carry_forward, sto_proc_name,
                    user_form_template_guid, notes, rec_ent_date,
                    rec_ent_user, rec_mod_date, rec_mod_user,
                    include_record_data_onclaim
                ) VALUES (
                    l_targets(i).new_guid,
                    l_targets(i).desired_her.loop_id,
                    l_targets(i).desired_her.contiguity_ind,
                    l_targets(i).desired_her.billing_form_code,
                    l_targets(i).desired_her.record_name,
                    l_targets(i).desired_her.record_type_code,
                    l_targets(i).desired_her.record_size,
                    l_targets(i).desired_her.mandatory_ind,
                    l_targets(i).desired_her.req_for_claim_ind,
                    l_targets(i).desired_her.payor_type_guid,
                    l_targets(i).desired_her.payor_guid,
                    l_targets(i).desired_her.plan_guid,
                    l_targets(i).desired_her.type_of_bill,
                    l_targets(i).desired_her.detail_ind,
                    l_targets(i).desired_her.max_number,
                    l_targets(i).desired_her.invoice_ind,
                    l_targets(i).desired_her.form_template_guid,
                    l_targets(i).desired_her.carry_forward_ind,
                    l_targets(i).desired_her.max_carry_forward,
                    l_targets(i).desired_her.sto_proc_name,
                    l_targets(i).desired_her.user_form_template_guid,
                    l_targets(i).desired_her.notes,
                    SYSDATE, l_audit_user, NULL, NULL,
                    l_targets(i).desired_her.include_record_data_onclaim
                );
            END IF;
        END LOOP;
    END insert_target_hers;

    PROCEDURE insert_target_hefs
    IS
        l_hef_index PLS_INTEGER;
    BEGIN
        FOR i IN 1 .. l_targets.COUNT LOOP
            IF l_targets(i).target_action = c_target_rebuild_override THEN
                l_hef_index := l_targets(i).desired_hefs.FIRST;
                WHILE l_hef_index IS NOT NULL LOOP
                    INSERT INTO hcfa_electronic_fields (
                        field_number, electronic_rec_guid, field_name,
                        record_type_code, sto_proc_name, pic, field_spec,
                        position_from, position_thru, field_name_desc,
                        mandatory_ind, must_fit_length_ind, order_num,
                        repeats, detail_ind, occurs_next, hard_coded_data,
                        field_format, caps_ind, required_subelement_ind,
                        rec_ent_date, rec_ent_user, rec_mod_date,
                        rec_mod_user, include_data_onclaim
                    ) VALUES (
                        l_targets(i).desired_hefs(l_hef_index).field_number,
                        l_targets(i).new_guid,
                        l_targets(i).desired_hefs(l_hef_index).field_name,
                        l_targets(i).desired_hefs(l_hef_index).record_type_code,
                        l_targets(i).desired_hefs(l_hef_index).sto_proc_name,
                        l_targets(i).desired_hefs(l_hef_index).pic,
                        l_targets(i).desired_hefs(l_hef_index).field_spec,
                        l_targets(i).desired_hefs(l_hef_index).position_from,
                        l_targets(i).desired_hefs(l_hef_index).position_thru,
                        l_targets(i).desired_hefs(l_hef_index).field_name_desc,
                        l_targets(i).desired_hefs(l_hef_index).mandatory_ind,
                        l_targets(i).desired_hefs(l_hef_index).must_fit_length_ind,
                        l_targets(i).desired_hefs(l_hef_index).order_num,
                        l_targets(i).desired_hefs(l_hef_index).repeats,
                        l_targets(i).desired_hefs(l_hef_index).detail_ind,
                        l_targets(i).desired_hefs(l_hef_index).occurs_next,
                        l_targets(i).desired_hefs(l_hef_index).hard_coded_data,
                        l_targets(i).desired_hefs(l_hef_index).field_format,
                        l_targets(i).desired_hefs(l_hef_index).caps_ind,
                        l_targets(i).desired_hefs(l_hef_index)
                            .required_subelement_ind,
                        SYSDATE, l_audit_user, NULL, NULL,
                        l_targets(i).desired_hefs(l_hef_index)
                            .include_data_onclaim
                    );
                    l_hef_index := l_targets(i).desired_hefs.NEXT(l_hef_index);
                END LOOP;
            END IF;
        END LOOP;
    END insert_target_hefs;

    FUNCTION has_mutating_action RETURN BOOLEAN
    IS
    BEGIN
        FOR i IN 1 .. l_targets.COUNT LOOP
            IF l_targets(i).target_action <> c_target_no_change THEN
                RETURN TRUE;
            END IF;
        END LOOP;
        RETURN FALSE;
    END has_mutating_action;

    PROCEDURE verify_canonical_state
    IS
    BEGIN
        resolve_all_targets;
        FOR i IN 1 .. l_targets.COUNT LOOP
            IF l_targets(i).target_action <> c_target_no_change THEN
                RAISE_APPLICATION_ERROR(c_err_verification,
                    'A target failed canonical post-apply verification.');
            END IF;
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = c_err_verification THEN
                RAISE;
            END IF;
            RAISE_APPLICATION_ERROR(c_err_verification,
                'The applied configuration could not be verified.');
    END verify_canonical_state;

BEGIN
    -- Reject blank and oversized invalid inputs before assigning the bounded
    -- mode variable or resolving any configuration state.
    IF TRIM(p_mode) IS NULL
       OR UPPER(TRIM(p_mode)) NOT IN (c_mode_preview, c_mode_apply) THEN
        RAISE_APPLICATION_ERROR(c_err_invalid_mode,
            'Mode must be PREVIEW or APPLY.');
    END IF;
    l_mode := UPPER(TRIM(p_mode));
    l_audit_user := TRIM(p_audit_user);
    IF l_audit_user IS NULL OR LENGTH(l_audit_user) > 36 THEN
        RAISE_APPLICATION_ERROR(c_err_missing_audit_user,
            'A valid audit user is required.');
    END IF;
    IF l_mode = c_mode_apply AND TRIM(p_expected_state_hash) IS NULL THEN
        RAISE_APPLICATION_ERROR(c_err_expected_hash_missing,
            'EXPECTED_STATE_HASH is required for APPLY.');
    END IF;

    IF UPPER(TRIM(p_option_code)) = 'PROVIDER_TAXONOMY_CUSTOM' THEN
        IF TRIM(p_taxonomy_code) IS NULL THEN
            RAISE_APPLICATION_ERROR(-20043, 'Custom taxonomy requires a 10-character code.');
        END IF;
        l_option := pfc_opt_provider_taxonomy_on(p_taxonomy_code);
    ELSE
        IF p_taxonomy_code IS NOT NULL THEN
            RAISE_APPLICATION_ERROR(-20043, 'Only Custom taxonomy accepts a code.');
        END IF;
        l_option := pfc_option_registry.get_option(p_option_code);
    END IF;
    validate_option_definition;
    resolve_all_targets;
    compute_state_hash;

    IF l_mode = c_mode_preview THEN
        assign_target_guids(TRUE);
        build_changes;
        IF has_mutating_action THEN
            l_result_status := 'PREVIEW';
        ELSE
            l_result_status := 'NO_CHANGE';
        END IF;
    ELSE
        SAVEPOINT pfc_apply_start;
        l_savepoint_set := TRUE;
        lock_all_state;
        IF l_state_hash <> UPPER(TRIM(p_expected_state_hash)) THEN
            RAISE_APPLICATION_ERROR(c_err_stale_preview,
                'The preview is stale; run PREVIEW again before APPLY.');
        END IF;

        IF has_mutating_action THEN
            assign_target_guids(FALSE);
            build_changes;
            delete_target_hefs;
            delete_target_hers;
            insert_target_hers;
            insert_target_hefs;
            verify_canonical_state;
            l_result_status := 'APPLIED';
        ELSE
            build_changes;
            ROLLBACK TO pfc_apply_start;
            l_savepoint_set := FALSE;
            l_result_status := 'NO_CHANGE';
        END IF;
    END IF;

    IF l_targets.COUNT = 1 THEN
        l_output_record_type := l_targets(1).record_type_code;
        l_output_source_guid := l_targets(1).source_guid;
        l_output_target_action := l_targets(1).target_action;
        l_output_current_matches_source := CASE
            WHEN l_targets(1).existing_her_count <> 1 THEN NULL
            WHEN l_targets(1).current_matches_source THEN 'Y' ELSE 'N' END;
        l_output_current_matches_desired := CASE
            WHEN l_targets(1).existing_her_count <> 1 THEN NULL
            WHEN l_targets(1).current_matches_desired THEN 'Y' ELSE 'N' END;
    ELSE
        l_output_record_type := NULL;
        l_output_source_guid := NULL;
        l_output_target_action := NULL;
        l_output_current_matches_source := NULL;
        l_output_current_matches_desired := NULL;
    END IF;
    prepare_change_sql;

    OPEN p_summary FOR
        SELECT
            CAST(l_result_status AS VARCHAR2(20)) AS status,
            CAST(l_option.option_code AS VARCHAR2(100)) AS option_code,
            CAST(l_option.display_label AS VARCHAR2(200)) AS display_label,
            CAST(l_resolved_payor_guid AS VARCHAR2(36)) AS payor_guid,
            CAST(l_resolved_plan_guid AS VARCHAR2(36)) AS plan_guid,
            CAST(l_pfc_guid AS VARCHAR2(36)) AS pfc_guid,
            CAST(l_billing_form_code AS VARCHAR2(10)) AS billing_form_code,
            CAST(l_output_record_type AS VARCHAR2(20)) AS record_type_code,
            CAST(l_output_source_guid AS VARCHAR2(36)) AS source_electronic_rec_guid,
            CAST(l_output_target_action AS VARCHAR2(30)) AS target_action,
            CAST(l_output_current_matches_source AS VARCHAR2(1)) AS current_matches_source,
            CAST(l_output_current_matches_desired AS VARCHAR2(1)) AS current_matches_desired,
            CAST(l_existing_her_count AS NUMBER) AS existing_payor_her_count,
            CAST(l_existing_hef_count AS NUMBER) AS existing_payor_hef_count,
            CAST(l_new_hef_count AS NUMBER) AS new_hef_count,
            CAST(l_state_hash AS VARCHAR2(64)) AS state_hash,
            CAST(l_change_count AS NUMBER) AS change_count
        FROM dual;

    OPEN p_changes FOR l_changes_sql;
EXCEPTION
    WHEN OTHERS THEN
        l_error_code := SQLCODE;
        IF l_savepoint_set THEN
            ROLLBACK TO pfc_apply_start;
        END IF;
        IF l_error_code IN (
            pfc_option_registry.c_err_unknown_option,
            pfc_config_internal.c_err_pfc_not_found,
            pfc_config_internal.c_err_pfc_start_date_tie,
            pfc_config_internal.c_err_unsafe_source,
            -20020, -20021, -20043,
            c_err_invalid_mode,
            c_err_missing_audit_user,
            c_err_invalid_option,
            c_err_expected_hash_missing,
            c_err_stale_preview,
            c_err_hef_target_missing,
            c_err_hef_target_ambiguous,
            c_err_verification,
            c_err_unexpected_state
        ) THEN
            RAISE;
        END IF;
        RAISE_APPLICATION_ERROR(c_err_unexpected_state,
            'PFC option processing failed safely.');
END pfc_apply_option;
/
