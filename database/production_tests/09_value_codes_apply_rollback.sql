/*
 * PRODUCTION HARNESS CLASS: ROLLBACK_ONLY_APPLY
 * STANDALONE: YES
 * TOOL-OWNED OBJECT DEPENDENCIES: NONE
 * COMMIT: FORBIDDEN
 *
 * Value Codes production rollback-only APPLY validation.
 *
 * This anonymous block never commits and cannot be switched to persistence.
 * It locks and independently rebuilds the Script 08 state, rejects a stale
 * preview hash before DML, applies the explicit HI target, verifies temporary
 * canonical state, rolls back to its savepoint, and verifies restoration.
 *
 * IMPORTANT: Execute this script only in a fresh, dedicated Toad session
 * containing no unrelated uncommitted work. The harness intentionally issues
 * a final full ROLLBACK so every row/table lock acquired by the test is
 * released before the block finishes.
 *
 * Keep production identifiers only in an unsaved editor buffer.
 */
SET SERVEROUTPUT ON
SET DEFINE OFF

DECLARE
    /* ================================================================
     * MANUAL INPUTS - edit only these ten constants.
     * ================================================================ */
    c_payor_guid CONSTANT VARCHAR2(36) := 'PUT_PAYOR_GUID_HERE';
    c_plan_guid CONSTANT VARCHAR2(36) := NULL;
    c_line_of_business CONSTANT VARCHAR2(20) := 'HOME_HEALTH';
    c_cbsa CONSTANT VARCHAR2(1) := 'N';
    c_fips CONSTANT VARCHAR2(1) := 'N';
    c_care_location_value_code CONSTANT VARCHAR2(1) := 'N';
    c_patient_entered_value_code CONSTANT VARCHAR2(1) := 'N';
    c_covered_days_value_code CONSTANT VARCHAR2(1) := 'N';
    c_expected_preview_state_hash CONSTANT VARCHAR2(64) :=
        'PUT_64_CHARACTER_PREVIEW_STATE_HASH_HERE';
    c_audit_user CONSTANT VARCHAR2(36) := 'PUT_AUDIT_USER_HERE';
    c_safety_token CONSTANT VARCHAR2(40) :=
        'ROLLBACK_ONLY_VALUE_CODES';

    c_err_invalid_input     CONSTANT PLS_INTEGER := -20501;
    c_err_resolution        CONSTANT PLS_INTEGER := -20502;
    c_err_hash_too_large    CONSTANT PLS_INTEGER := -20503;
    c_err_stale_preview     CONSTANT PLS_INTEGER := -20504;
    c_err_overlay           CONSTANT PLS_INTEGER := -20505;
    c_err_verification      CONSTANT PLS_INTEGER := -20506;
    c_err_restoration       CONSTANT PLS_INTEGER := -20507;

    c_no_change       CONSTANT VARCHAR2(30) := 'NO_CHANGE';
    c_remove_override CONSTANT VARCHAR2(30) := 'REMOVE_OVERRIDE';
    c_rebuild_override CONSTANT VARCHAR2(30) := 'REBUILD_OVERRIDE';

    TYPE t_hef_rows IS TABLE OF hcfa_electronic_fields%ROWTYPE
        INDEX BY PLS_INTEGER;
    TYPE t_her_rows IS TABLE OF hcfa_electronic_records%ROWTYPE
        INDEX BY PLS_INTEGER;
    TYPE t_text_rows IS TABLE OF VARCHAR2(32767)
        INDEX BY PLS_INTEGER;
    TYPE t_number_rows IS TABLE OF PLS_INTEGER
        INDEX BY PLS_INTEGER;

    TYPE t_target_state IS RECORD (
        target_order        PLS_INTEGER,
        target_segment      VARCHAR2(3),
        record_type_code    hcfa_electronic_records.record_type_code%TYPE,
        desired_sto_proc    hcfa_electronic_records.sto_proc_name%TYPE,
        source_template_level VARCHAR2(10),
        source_guid         hcfa_electronic_records.electronic_rec_guid%TYPE,
        source_her          hcfa_electronic_records%ROWTYPE,
        source_hefs         t_hef_rows,
        overlay_her         hcfa_electronic_records%ROWTYPE,
        overlay_hefs        t_hef_rows,
        desired_her         hcfa_electronic_records%ROWTYPE,
        desired_hefs        t_hef_rows,
        current_hers        t_her_rows,
        current_hefs        t_hef_rows,
        single_current_hefs t_hef_rows,
        existing_her_count  PLS_INTEGER,
        existing_hef_count  PLS_INTEGER,
        source_equals_desired VARCHAR2(1),
        current_matches_desired VARCHAR2(1),
        target_action       VARCHAR2(30),
        new_guid            hcfa_electronic_records.electronic_rec_guid%TYPE,
        deleted_hefs        PLS_INTEGER,
        deleted_hers        PLS_INTEGER,
        inserted_hers       PLS_INTEGER,
        cloned_hefs         PLS_INTEGER
    );
    TYPE t_target_states IS TABLE OF t_target_state INDEX BY PLS_INTEGER;

    TYPE t_atom IS RECORD (
        atom_group   PLS_INTEGER,
        target_order PLS_INTEGER,
        sort_value_1 VARCHAR2(4000),
        sort_value_2 VARCHAR2(4000),
        atom_text    VARCHAR2(32767)
    );
    TYPE t_atoms IS TABLE OF t_atom INDEX BY PLS_INTEGER;

    l_targets              t_target_states;
    l_atoms                t_atoms;
    l_line_of_business     VARCHAR2(20);
    l_cbsa                 VARCHAR2(1);
    l_fips                 VARCHAR2(1);
    l_care_location        VARCHAR2(1);
    l_patient_entered      VARCHAR2(1);
    l_covered_days         VARCHAR2(1);
    l_option_code          VARCHAR2(100);
    l_selection_label      VARCHAR2(200);
    l_payor_guid           payors.payor_guid%TYPE;
    l_plan_guid            pfc.plan_guid%TYPE;
    l_audit_user           hcfa_electronic_records.rec_ent_user%TYPE;
    l_pfc_guid             pfc.pfc_guid%TYPE;
    l_pfc_plan_guid        pfc.plan_guid%TYPE;
    l_payor_type_guid      payors.payor_type_guid%TYPE;
    l_billing_form_code    pfc.billing_form_code%TYPE;
    l_form_template_guid   pfc.form_template_guid%TYPE;
    l_user_template_guid   pfc.user_form_template_guid%TYPE;
    l_cpd_start_date       pfc.cpd_start_date%TYPE;
    l_cpd_end_date         pfc.cpd_end_date%TYPE;
    l_expected_hash        VARCHAR2(64);
    l_recalculated_hash    VARCHAR2(64);
    l_pre_apply_hash       VARCHAR2(64);
    l_post_rollback_hash   VARCHAR2(64);
    l_pre_her_counts       t_number_rows;
    l_pre_hef_counts       t_number_rows;
    l_pre_actions          t_text_rows;
    l_savepoint_set        BOOLEAN := FALSE;
    l_dml_started          BOOLEAN := FALSE;

    FUNCTION values_equal (
        p_left  IN VARCHAR2,
        p_right IN VARCHAR2
    ) RETURN BOOLEAN
    IS
    BEGIN
        RETURN (p_left = p_right)
            OR (p_left IS NULL AND p_right IS NULL);
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
        l_left  t_text_rows;
        l_right t_text_rows;
        l_index PLS_INTEGER;
    BEGIN
        IF p_left.COUNT <> p_right.COUNT THEN
            RETURN FALSE;
        END IF;
        l_index := p_left.FIRST;
        WHILE l_index IS NOT NULL LOOP
            l_left(l_left.COUNT + 1) := hef_business_serial(p_left(l_index));
            l_index := p_left.NEXT(l_index);
        END LOOP;
        l_index := p_right.FIRST;
        WHILE l_index IS NOT NULL LOOP
            l_right(l_right.COUNT + 1) := hef_business_serial(p_right(l_index));
            l_index := p_right.NEXT(l_index);
        END LOOP;
        sort_text_rows(l_left);
        sort_text_rows(l_right);
        IF l_left.COUNT > 0 THEN
            FOR i IN 1 .. l_left.COUNT LOOP
                IF l_left(i) <> l_right(i) THEN
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

    FUNCTION payor_configurations_equal (
        p_current_her  IN hcfa_electronic_records%ROWTYPE,
        p_current_hefs IN t_hef_rows,
        p_desired_her  IN hcfa_electronic_records%ROWTYPE,
        p_desired_hefs IN t_hef_rows
    ) RETURN BOOLEAN
    IS
        l_current hcfa_electronic_records%ROWTYPE;
        l_desired hcfa_electronic_records%ROWTYPE;
    BEGIN
        IF p_current_her.payor_type_guid IS NOT NULL
           AND encoded_value(p_current_her.payor_type_guid) <>
               encoded_value(p_desired_her.payor_type_guid) THEN
            RETURN FALSE;
        END IF;
        l_current := p_current_her;
        l_desired := p_desired_her;
        l_current.payor_type_guid := NULL;
        l_desired.payor_type_guid := NULL;
        RETURN configurations_equal(
            l_current, p_current_hefs, l_desired, p_desired_hefs
        );
    END payor_configurations_equal;

    FUNCTION shown (p_value IN VARCHAR2) RETURN VARCHAR2
    IS
    BEGIN
        RETURN NVL(p_value, '<NULL>');
    END shown;

    FUNCTION shown_number (p_value IN NUMBER) RETURN VARCHAR2
    IS
    BEGIN
        RETURN NVL(TO_CHAR(p_value, 'TM9'), '<NULL>');
    END shown_number;

    FUNCTION hef_signature (
        p_row IN hcfa_electronic_fields%ROWTYPE
    ) RETURN VARCHAR2
    IS
        l_hash VARCHAR2(64);
    BEGIN
        SELECT RAWTOHEX(STANDARD_HASH(
            NVL(p_row.field_number, CHR(0)) || CHR(31) ||
            NVL(p_row.field_name, CHR(0)) || CHR(31) ||
            NVL(p_row.record_type_code, CHR(0)) || CHR(31) ||
            NVL(p_row.sto_proc_name, CHR(0)) || CHR(31) ||
            NVL(p_row.pic, CHR(0)) || CHR(31) ||
            NVL(p_row.field_spec, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(p_row.position_from, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(p_row.position_thru, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(p_row.field_name_desc, CHR(0)) || CHR(31) ||
            NVL(p_row.mandatory_ind, CHR(0)) || CHR(31) ||
            NVL(p_row.must_fit_length_ind, CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(p_row.order_num, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(TO_CHAR(p_row.repeats, 'TM9'), CHR(0)) || CHR(31) ||
            NVL(p_row.detail_ind, CHR(0)) || CHR(31) ||
            NVL(p_row.occurs_next, CHR(0)) || CHR(31) ||
            NVL(p_row.hard_coded_data, CHR(0)) || CHR(31) ||
            NVL(p_row.field_format, CHR(0)) || CHR(31) ||
            NVL(p_row.caps_ind, CHR(0)) || CHR(31) ||
            NVL(p_row.required_subelement_ind, CHR(0)) || CHR(31) ||
            NVL(p_row.include_data_onclaim, CHR(0)),
            'SHA256'
        )) INTO l_hash FROM dual;
        RETURN l_hash;
    END hef_signature;

    PROCEDURE initialize_targets
    IS
    BEGIN
        l_targets.DELETE;
        l_targets(1).target_order := 1;
        l_targets(1).target_segment := 'HI';
        l_targets(1).record_type_code := 'D23002310HI286';
        l_targets(1).desired_sto_proc := CASE
            WHEN l_option_code LIKE '%|N|N|N|N|N' THEN NULL
            ELSE 'RETURN_1'
        END;
    END initialize_targets;

    PROCEDURE validate_inputs
    IS
    BEGIN
        l_payor_guid := TRIM(c_payor_guid);
        l_plan_guid := TRIM(c_plan_guid);
        l_line_of_business := UPPER(TRIM(c_line_of_business));
        l_cbsa := UPPER(TRIM(c_cbsa));
        l_fips := UPPER(TRIM(c_fips));
        l_care_location := UPPER(TRIM(c_care_location_value_code));
        l_patient_entered := UPPER(TRIM(c_patient_entered_value_code));
        l_covered_days := UPPER(TRIM(c_covered_days_value_code));
        l_expected_hash := UPPER(TRIM(c_expected_preview_state_hash));
        l_audit_user := TRIM(c_audit_user);

        IF c_safety_token <> 'ROLLBACK_ONLY_VALUE_CODES' THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_input,
                'SAFETY TOKEN INVALID: rollback-only APPLY refused.');
        END IF;
        IF l_payor_guid IS NULL OR l_payor_guid = 'PUT_PAYOR_GUID_HERE' THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_input,
                'PAYOR_GUID is required.');
        END IF;
        IF l_line_of_business NOT IN ('HOME_HEALTH', 'HOSPICE') THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_input,
                'LINE_OF_BUSINESS must be HOME_HEALTH or HOSPICE.');
        END IF;
        IF l_cbsa NOT IN ('Y', 'N') OR l_fips NOT IN ('Y', 'N')
           OR l_care_location NOT IN ('Y', 'N')
           OR l_patient_entered NOT IN ('Y', 'N')
           OR l_covered_days NOT IN ('Y', 'N') THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_input,
                'Every Value Codes selection must be Y or N.');
        END IF;
        IF l_line_of_business = 'HOME_HEALTH' THEN
            IF l_care_location = 'Y' OR l_patient_entered = 'Y'
               OR l_covered_days = 'Y' THEN
                RAISE_APPLICATION_ERROR(c_err_invalid_input,
                    'Home Health cannot use Hospice selections.');
            END IF;
            IF l_fips = 'Y' AND l_cbsa = 'N' THEN
                RAISE_APPLICATION_ERROR(c_err_invalid_input,
                    'FIPS requires CBSA.');
            END IF;
        ELSE
            IF l_cbsa = 'Y' OR l_fips = 'Y' THEN
                RAISE_APPLICATION_ERROR(c_err_invalid_input,
                    'Hospice cannot use Home Health selections.');
            END IF;
            IF l_care_location = 'Y' AND l_patient_entered = 'Y' THEN
                RAISE_APPLICATION_ERROR(c_err_invalid_input,
                    'Care-location and patient-entered are mutually exclusive.');
            END IF;
        END IF;
        IF l_expected_hash IS NULL
           OR NOT REGEXP_LIKE(l_expected_hash, '^[0-9A-F]{64}$') THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_input,
                'A 64-character EXPECTED_PREVIEW_STATE_HASH is mandatory.');
        END IF;
        IF l_audit_user IS NULL
           OR l_audit_user = 'PUT_AUDIT_USER_HERE'
           OR LENGTH(l_audit_user) > 36 THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_input,
                'A valid AUDIT_USER is required.');
        END IF;

        l_option_code := 'VALUE_CODES|' || l_line_of_business || '|' ||
            l_cbsa || '|' || l_fips || '|' || l_care_location || '|' ||
            l_patient_entered || '|' || l_covered_days;
        IF l_cbsa = 'N' AND l_fips = 'N' AND l_care_location = 'N'
           AND l_patient_entered = 'N' AND l_covered_days = 'N' THEN
            l_selection_label := 'Default';
        ELSIF l_line_of_business = 'HOME_HEALTH' AND l_fips = 'Y' THEN
            l_selection_label := 'CBSA and FIPS';
        ELSIF l_line_of_business = 'HOME_HEALTH' THEN
            l_selection_label := 'CBSA';
        ELSIF l_care_location = 'Y' AND l_covered_days = 'Y' THEN
            l_selection_label := 'Care-location value code 61/G8 and VC80/days';
        ELSIF l_care_location = 'Y' THEN
            l_selection_label := 'Care-location value code 61/G8';
        ELSIF l_patient_entered = 'Y' AND l_covered_days = 'Y' THEN
            l_selection_label := 'Patient-entered value code and VC80/days';
        ELSIF l_patient_entered = 'Y' THEN
            l_selection_label := 'Patient-entered value code and amount';
        ELSE
            l_selection_label := 'Value code 80 with days covered';
        END IF;
        initialize_targets;
    END validate_inputs;

    PROCEDURE resolve_and_lock_pfc
    IS
        l_winner_count PLS_INTEGER;
        l_lock_guid    pfc.pfc_guid%TYPE;
    BEGIN
        SELECT payor.payor_type_guid
        INTO l_payor_type_guid
        FROM payors payor
        WHERE payor.payor_guid = l_payor_guid
        FOR UPDATE;

        SELECT
            COUNT(*),
            MAX(x.pfc_guid),
            MAX(x.plan_guid),
            MAX(x.billing_form_code),
            MAX(x.form_template_guid),
            MAX(x.user_form_template_guid),
            MAX(x.cpd_start_date),
            MAX(x.cpd_end_date)
        INTO
            l_winner_count,
            l_pfc_guid,
            l_pfc_plan_guid,
            l_billing_form_code,
            l_form_template_guid,
            l_user_template_guid,
            l_cpd_start_date,
            l_cpd_end_date
        FROM (
            SELECT
                p.pfc_guid,
                p.plan_guid,
                p.billing_form_code,
                p.form_template_guid,
                p.user_form_template_guid,
                p.cpd_start_date,
                p.cpd_end_date,
                DENSE_RANK() OVER (
                    ORDER BY p.cpd_start_date DESC NULLS LAST
                ) AS start_date_rank
            FROM pfc p
            WHERE p.payor_guid = l_payor_guid
              AND p.cpd_end_date > SYSDATE
              AND p.default_media_type = 'E'
              AND p.type_of_bill IS NULL
              AND (
                    (l_plan_guid IS NULL AND p.plan_guid IS NULL)
                    OR
                    (l_plan_guid IS NOT NULL AND (
                        p.plan_guid = l_plan_guid OR p.plan_guid IS NULL
                    ))
                  )
        ) x
        WHERE x.start_date_rank = 1;

        IF l_winner_count = 0 THEN
            RAISE_APPLICATION_ERROR(c_err_resolution,
                'PFC resolution failed: no eligible PFC.');
        ELSIF l_winner_count > 1 THEN
            RAISE_APPLICATION_ERROR(c_err_resolution,
                'PFC resolution failed: newest CPD_START_DATE is tied.');
        END IF;

        SELECT p.pfc_guid
        INTO l_lock_guid
        FROM pfc p
        WHERE p.pfc_guid = l_pfc_guid
        FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(c_err_resolution,
                'PAYOR/PFC resolution failed.');
    END resolve_and_lock_pfc;

    PROCEDURE resolve_and_lock_source (p_target_index IN PLS_INTEGER)
    IS
        l_source_count PLS_INTEGER;
        l_lock_guid    hcfa_electronic_records.electronic_rec_guid%TYPE;
    BEGIN
        SELECT COUNT(*), MAX(x.electronic_rec_guid)
        INTO l_source_count, l_targets(p_target_index).source_guid
        FROM (
            SELECT
                ranked.electronic_rec_guid,
                DENSE_RANK() OVER (
                    ORDER BY ranked.template_rank, ranked.payor_type_rank
                ) AS source_rank
            FROM (
                SELECT
                    h.electronic_rec_guid,
                    CASE
                        WHEN h.user_form_template_guid IS NOT NULL THEN 1
                        WHEN h.form_template_guid IS NOT NULL THEN 2
                        ELSE 3
                    END AS template_rank,
                    CASE
                        WHEN h.payor_type_guid = l_payor_type_guid
                         AND h.payor_type_guid IS NOT NULL THEN 1
                        ELSE 2
                    END AS payor_type_rank
                FROM hcfa_electronic_records h
                WHERE h.billing_form_code = l_billing_form_code
                  AND h.record_type_code =
                        l_targets(p_target_index).record_type_code
                  AND h.payor_guid IS NULL
                  AND h.plan_guid IS NULL
                  AND h.type_of_bill IS NULL
                  AND (h.payor_type_guid = l_payor_type_guid
                       OR h.payor_type_guid IS NULL)
                  AND (
                        (h.user_form_template_guid IS NOT NULL
                         AND l_user_template_guid IS NOT NULL
                         AND h.user_form_template_guid = l_user_template_guid
                         AND (h.form_template_guid = l_form_template_guid
                              OR h.form_template_guid IS NULL))
                        OR
                        (h.user_form_template_guid IS NULL
                         AND h.form_template_guid IS NOT NULL
                         AND l_form_template_guid IS NOT NULL
                         AND h.form_template_guid = l_form_template_guid)
                        OR
                        (h.user_form_template_guid IS NULL
                         AND h.form_template_guid IS NULL)
                      )
            ) ranked
        ) x
        WHERE x.source_rank = 1;

        IF l_source_count = 0 THEN
            RAISE_APPLICATION_ERROR(c_err_resolution,
                l_targets(p_target_index).target_segment ||
                ' source resolution failed: no source HER.');
        ELSIF l_source_count > 1 THEN
            RAISE_APPLICATION_ERROR(c_err_resolution,
                l_targets(p_target_index).target_segment ||
                ' source resolution failed: tied source HERs.');
        END IF;

        SELECT h.*
        INTO l_targets(p_target_index).source_her
        FROM hcfa_electronic_records h
        WHERE h.electronic_rec_guid = l_targets(p_target_index).source_guid
        FOR UPDATE;

        l_targets(p_target_index).source_template_level := CASE
            WHEN l_targets(p_target_index).source_her.user_form_template_guid
                    IS NOT NULL THEN 'USER'
            WHEN l_targets(p_target_index).source_her.form_template_guid
                    IS NOT NULL THEN 'FORM'
            ELSE 'BILLING'
        END;

        SELECT h.electronic_rec_guid
        INTO l_lock_guid
        FROM hcfa_electronic_records h
        WHERE h.electronic_rec_guid = l_targets(p_target_index).source_guid
        FOR UPDATE;

        l_targets(p_target_index).source_hefs.DELETE;
        SELECT f.* BULK COLLECT
        INTO l_targets(p_target_index).source_hefs
        FROM hcfa_electronic_fields f
        WHERE f.electronic_rec_guid = l_targets(p_target_index).source_guid
        ORDER BY f.field_number, f.order_num NULLS FIRST,
                 f.position_from, f.position_thru
        FOR UPDATE;
    END resolve_and_lock_source;

    PROCEDURE set_hef_value (
        p_target_index IN PLS_INTEGER,
        p_field_number IN VARCHAR2,
        p_field_name   IN VARCHAR2,
        p_attribute    IN VARCHAR2,
        p_value        IN VARCHAR2
    )
    IS
        l_match_index PLS_INTEGER := NULL;
        l_match_count PLS_INTEGER := 0;
        l_index       PLS_INTEGER;
    BEGIN
        l_index := l_targets(p_target_index).overlay_hefs.FIRST;
        WHILE l_index IS NOT NULL LOOP
            IF l_targets(p_target_index).overlay_hefs(l_index).field_number =
                    p_field_number
               AND l_targets(p_target_index).overlay_hefs(l_index).field_name =
                    p_field_name THEN
                l_match_count := l_match_count + 1;
                l_match_index := l_index;
            END IF;
            l_index := l_targets(p_target_index).overlay_hefs.NEXT(l_index);
        END LOOP;
        IF l_match_count <> 1 THEN
            RAISE_APPLICATION_ERROR(c_err_overlay,
                l_targets(p_target_index).target_segment || ' field ' ||
                p_field_number || '/' || p_field_name || ' matched ' ||
                l_match_count ||
                ' source HEFs; expected exactly one.');
        END IF;
        IF p_attribute = 'STO_PROC_NAME' THEN
            l_targets(p_target_index).overlay_hefs(l_match_index).sto_proc_name :=
                p_value;
            IF p_value IS NOT NULL THEN
                l_targets(p_target_index).overlay_hefs(l_match_index)
                    .hard_coded_data := NULL;
            END IF;
        ELSIF p_attribute = 'HARD_CODED_DATA' THEN
            l_targets(p_target_index).overlay_hefs(l_match_index).hard_coded_data :=
                p_value;
            IF p_value IS NOT NULL THEN
                l_targets(p_target_index).overlay_hefs(l_match_index)
                    .sto_proc_name := NULL;
            END IF;
        ELSE
            RAISE_APPLICATION_ERROR(c_err_overlay,
                'Unsupported HEF overlay attribute.');
        END IF;
    END set_hef_value;

    PROCEDURE set_managed_pair (
        p_target_index IN PLS_INTEGER,
        p_field_number IN VARCHAR2,
        p_sto_proc_name IN VARCHAR2,
        p_hard_coded_data IN VARCHAR2
    ) IS
    BEGIN
        IF p_sto_proc_name IS NOT NULL THEN
            set_hef_value(p_target_index, p_field_number,
                'HI' || p_field_number, 'STO_PROC_NAME', p_sto_proc_name);
        ELSIF p_hard_coded_data IS NOT NULL THEN
            set_hef_value(p_target_index, p_field_number,
                'HI' || p_field_number, 'HARD_CODED_DATA', p_hard_coded_data);
        ELSE
            RAISE_APPLICATION_ERROR(c_err_overlay,
                'A managed Value Codes pair must select one value mechanism.');
        END IF;
    END set_managed_pair;

    PROCEDURE build_desired_state (p_target_index IN PLS_INTEGER)
    IS
        l_index PLS_INTEGER;
    BEGIN
        l_targets(p_target_index).overlay_her :=
            l_targets(p_target_index).source_her;
        l_targets(p_target_index).overlay_hefs :=
            l_targets(p_target_index).source_hefs;
        IF l_cbsa = 'N' AND l_fips = 'N' AND l_care_location = 'N'
           AND l_patient_entered = 'N' AND l_covered_days = 'N' THEN
            IF NVL(UPPER(TRIM(
                    l_targets(p_target_index).source_her.sto_proc_name)),
                    '<NULL>') <> 'RETURN_1'
               AND NVL(UPPER(TRIM(
                    l_targets(p_target_index).source_her.mandatory_ind)),
                    '<NULL>') <> 'N' THEN
                DBMS_OUTPUT.PUT_LINE('STATUS: BLOCKED');
                DBMS_OUTPUT.PUT_LINE(
                    'SOURCE_SAFETY_STATUS: INVALID_MANDATORY_COMBINATION');
                RAISE_APPLICATION_ERROR(c_err_resolution,
                    'The inherited Value Codes source violates the mandatory-record rule; correct the template or billing-form source.');
            END IF;
            l_targets(p_target_index).desired_sto_proc :=
                l_targets(p_target_index).source_her.sto_proc_name;
        ELSE
            l_targets(p_target_index).desired_sto_proc := 'RETURN_1';
            l_targets(p_target_index).overlay_her.sto_proc_name := 'RETURN_1';
            IF l_line_of_business = 'HOME_HEALTH' THEN
                set_managed_pair(p_target_index, '012', NULL, '61');
                set_managed_pair(p_target_index, '015',
                    'GET_PAT_CBSA_CODE', NULL);
                IF l_fips = 'Y' THEN
                    set_managed_pair(p_target_index, '022',
                        'GET_FIPS_CODE', NULL);
                    set_managed_pair(p_target_index, '025',
                        'GET_FIPS_CODE_VALUE', NULL);
                ELSE
                    set_managed_pair(p_target_index, '022',
                        'GET_VAL_CODE', NULL);
                    set_managed_pair(p_target_index, '025',
                        'GET_VAL_CODE_AMT', NULL);
                END IF;
            ELSIF l_care_location = 'Y' AND l_covered_days = 'Y' THEN
                set_managed_pair(p_target_index, '012', NULL, '61');
                set_managed_pair(p_target_index, '015',
                    'GET_PAT_CBSA_CODE', NULL);
                set_managed_pair(p_target_index, '022', NULL, '80');
                set_managed_pair(p_target_index, '025',
                    'GET_DISTINCT_COVERED_DAYS', NULL);
            ELSIF l_care_location = 'Y' THEN
                set_managed_pair(p_target_index, '012',
                    'GET_CARE_LOC_CODE', NULL);
                set_managed_pair(p_target_index, '015',
                    'GET_CARE_LOC_VAL_CODE', NULL);
                set_managed_pair(p_target_index, '022',
                    'GET_VAL_CODE', NULL);
                set_managed_pair(p_target_index, '025',
                    'GET_VAL_CODE_AMT', NULL);
            ELSIF l_patient_entered = 'Y' AND l_covered_days = 'Y' THEN
                set_managed_pair(p_target_index, '012',
                    'GET_VAL_CODE', NULL);
                set_managed_pair(p_target_index, '015',
                    'GET_VAL_CODE_AMT', NULL);
                set_managed_pair(p_target_index, '022', NULL, '80');
                set_managed_pair(p_target_index, '025',
                    'GET_DISTINCT_COVERED_DAYS', NULL);
            ELSIF l_patient_entered = 'Y' THEN
                set_managed_pair(p_target_index, '012',
                    'GET_VAL_CODE', NULL);
                set_managed_pair(p_target_index, '015',
                    'GET_VAL_CODE_AMT', NULL);
                set_managed_pair(p_target_index, '022',
                    'GET_VAL_CODE', NULL);
                set_managed_pair(p_target_index, '025',
                    'GET_VAL_CODE_AMT', NULL);
            ELSE
                set_managed_pair(p_target_index, '012', NULL, '80');
                set_managed_pair(p_target_index, '015',
                    'GET_DISTINCT_COVERED_DAYS', NULL);
                set_managed_pair(p_target_index, '022',
                    'GET_VAL_CODE', NULL);
                set_managed_pair(p_target_index, '025',
                    'GET_VAL_CODE_AMT', NULL);
            END IF;
        END IF;

        IF NOT (l_cbsa = 'N' AND l_fips = 'N' AND l_care_location = 'N'
                AND l_patient_entered = 'N' AND l_covered_days = 'N')
           AND (UPPER(TRIM(l_targets(p_target_index).overlay_her.sto_proc_name)) <>
                    'RETURN_1'
                OR l_targets(p_target_index).overlay_her.sto_proc_name IS NULL) THEN
            l_targets(p_target_index).overlay_her.mandatory_ind := 'N';
        END IF;

        IF configurations_equal(
            l_targets(p_target_index).source_her,
            l_targets(p_target_index).source_hefs,
            l_targets(p_target_index).overlay_her,
            l_targets(p_target_index).overlay_hefs
        ) THEN
            l_targets(p_target_index).source_equals_desired := 'Y';
        ELSE
            l_targets(p_target_index).source_equals_desired := 'N';
        END IF;

        l_targets(p_target_index).desired_her :=
            l_targets(p_target_index).overlay_her;
        l_targets(p_target_index).desired_her.electronic_rec_guid := NULL;
        l_targets(p_target_index).desired_her.payor_guid := l_payor_guid;
        l_targets(p_target_index).desired_her.payor_type_guid :=
            l_payor_type_guid;
        l_targets(p_target_index).desired_her.carry_forward_ind := NULL;
        l_targets(p_target_index).desired_her.include_record_data_onclaim := 'Y';
        l_targets(p_target_index).desired_her.rec_ent_date := NULL;
        l_targets(p_target_index).desired_her.rec_ent_user := NULL;
        l_targets(p_target_index).desired_her.rec_mod_date := NULL;
        l_targets(p_target_index).desired_her.rec_mod_user := NULL;

        l_targets(p_target_index).desired_hefs :=
            l_targets(p_target_index).overlay_hefs;
        l_index := l_targets(p_target_index).desired_hefs.FIRST;
        WHILE l_index IS NOT NULL LOOP
            l_targets(p_target_index).desired_hefs(l_index)
                .electronic_rec_guid := NULL;
            l_targets(p_target_index).desired_hefs(l_index).rec_ent_date := NULL;
            l_targets(p_target_index).desired_hefs(l_index).rec_ent_user := NULL;
            l_targets(p_target_index).desired_hefs(l_index).rec_mod_date := NULL;
            l_targets(p_target_index).desired_hefs(l_index).rec_mod_user := NULL;
            l_index := l_targets(p_target_index).desired_hefs.NEXT(l_index);
        END LOOP;
    END build_desired_state;

    PROCEDURE read_and_lock_current (p_target_index IN PLS_INTEGER)
    IS
    BEGIN
        l_targets(p_target_index).current_hers.DELETE;
        l_targets(p_target_index).current_hefs.DELETE;
        l_targets(p_target_index).single_current_hefs.DELETE;

        SELECT h.* BULK COLLECT
        INTO l_targets(p_target_index).current_hers
        FROM hcfa_electronic_records h
        WHERE h.payor_guid = l_payor_guid
          AND h.billing_form_code = l_billing_form_code
          AND h.record_type_code = l_targets(p_target_index).record_type_code
        ORDER BY h.electronic_rec_guid
        FOR UPDATE;

        SELECT f.* BULK COLLECT
        INTO l_targets(p_target_index).current_hefs
        FROM hcfa_electronic_fields f
        WHERE EXISTS (
            SELECT 1
            FROM hcfa_electronic_records h
            WHERE h.electronic_rec_guid = f.electronic_rec_guid
              AND h.payor_guid = l_payor_guid
              AND h.billing_form_code = l_billing_form_code
              AND h.record_type_code =
                    l_targets(p_target_index).record_type_code
        )
        ORDER BY f.electronic_rec_guid, f.field_number,
                 f.order_num NULLS FIRST, f.position_from
        FOR UPDATE;

        l_targets(p_target_index).existing_her_count :=
            l_targets(p_target_index).current_hers.COUNT;
        l_targets(p_target_index).existing_hef_count :=
            l_targets(p_target_index).current_hefs.COUNT;

        IF l_targets(p_target_index).existing_her_count = 1 THEN
            SELECT f.* BULK COLLECT
            INTO l_targets(p_target_index).single_current_hefs
            FROM hcfa_electronic_fields f
            WHERE f.electronic_rec_guid =
                l_targets(p_target_index).current_hers(1).electronic_rec_guid;
        END IF;
    END read_and_lock_current;

    PROCEDURE decide_target_action (p_target_index IN PLS_INTEGER)
    IS
    BEGIN
        IF l_targets(p_target_index).existing_her_count = 0 THEN
            l_targets(p_target_index).current_matches_desired :=
                l_targets(p_target_index).source_equals_desired;
        ELSIF l_targets(p_target_index).existing_her_count = 1
          AND payor_configurations_equal(
                l_targets(p_target_index).current_hers(1),
                l_targets(p_target_index).single_current_hefs,
                l_targets(p_target_index).desired_her,
                l_targets(p_target_index).desired_hefs
              ) THEN
            l_targets(p_target_index).current_matches_desired := 'Y';
        ELSE
            l_targets(p_target_index).current_matches_desired := 'N';
        END IF;
        IF l_targets(p_target_index).source_equals_desired = 'Y' THEN
            IF l_targets(p_target_index).existing_her_count = 0 THEN
                l_targets(p_target_index).target_action := c_no_change;
            ELSE
                l_targets(p_target_index).target_action := c_remove_override;
            END IF;
        ELSIF l_targets(p_target_index).current_matches_desired = 'Y' THEN
            l_targets(p_target_index).target_action := c_no_change;
        ELSE
            l_targets(p_target_index).target_action := c_rebuild_override;
        END IF;
    END decide_target_action;

    PROCEDURE resolve_locked_state
    IS
    BEGIN
        resolve_and_lock_pfc;
        FOR i IN 1 .. l_targets.COUNT LOOP
            resolve_and_lock_source(i);
            build_desired_state(i);
            read_and_lock_current(i);
            decide_target_action(i);
        END LOOP;
    END resolve_locked_state;

    PROCEDURE add_atom (
        p_group        IN PLS_INTEGER,
        p_target_order IN PLS_INTEGER,
        p_sort_1       IN VARCHAR2,
        p_sort_2       IN VARCHAR2,
        p_text         IN VARCHAR2
    )
    IS
        l_index PLS_INTEGER := l_atoms.COUNT + 1;
    BEGIN
        l_atoms(l_index).atom_group := p_group;
        l_atoms(l_index).target_order := p_target_order;
        l_atoms(l_index).sort_value_1 := p_sort_1;
        l_atoms(l_index).sort_value_2 := p_sort_2;
        l_atoms(l_index).atom_text := p_text;
    END add_atom;

    FUNCTION atom_greater (p_left IN t_atom, p_right IN t_atom)
        RETURN BOOLEAN
    IS
    BEGIN
        IF p_left.atom_group <> p_right.atom_group THEN
            RETURN p_left.atom_group > p_right.atom_group;
        ELSIF p_left.target_order <> p_right.target_order THEN
            RETURN p_left.target_order > p_right.target_order;
        ELSIF p_left.sort_value_1 <> p_right.sort_value_1 THEN
            RETURN p_left.sort_value_1 > p_right.sort_value_1;
        ELSIF p_left.sort_value_2 <> p_right.sort_value_2 THEN
            RETURN p_left.sort_value_2 > p_right.sort_value_2;
        ELSE
            RETURN p_left.atom_text > p_right.atom_text;
        END IF;
    END atom_greater;

    PROCEDURE sort_atoms
    IS
        l_key t_atom;
        l_j   PLS_INTEGER;
    BEGIN
        IF l_atoms.COUNT < 2 THEN
            RETURN;
        END IF;
        FOR i IN 2 .. l_atoms.COUNT LOOP
            l_key := l_atoms(i);
            l_j := i - 1;
            WHILE l_j >= 1 AND atom_greater(l_atoms(l_j), l_key) LOOP
                l_atoms(l_j + 1) := l_atoms(l_j);
                l_j := l_j - 1;
            END LOOP;
            l_atoms(l_j + 1) := l_key;
        END LOOP;
    END sort_atoms;

    FUNCTION her_atom_text (
        p_prefix  IN VARCHAR2,
        p_segment IN VARCHAR2,
        p_row     IN hcfa_electronic_records%ROWTYPE
    ) RETURN VARCHAR2
    IS
    BEGIN
        RETURN p_prefix || '|' || p_segment || '|' ||
            p_row.electronic_rec_guid || '|' ||
            shown(p_row.loop_id) || '|' || shown(p_row.contiguity_ind) || '|' ||
            p_row.billing_form_code || '|' || p_row.record_name || '|' ||
            p_row.record_type_code || '|' || TO_CHAR(p_row.record_size, 'TM9') ||
            '|' || shown(p_row.mandatory_ind) || '|' ||
            shown(p_row.req_for_claim_ind) || '|' ||
            shown(p_row.payor_type_guid) || '|' || shown(p_row.payor_guid) ||
            '|' || shown(p_row.plan_guid) || '|' || shown(p_row.type_of_bill) ||
            '|' || shown(p_row.detail_ind) || '|' || shown(p_row.max_number) ||
            '|' || shown(p_row.invoice_ind) || '|' ||
            shown(p_row.form_template_guid) || '|' ||
            shown(p_row.carry_forward_ind) || '|' ||
            shown_number(p_row.max_carry_forward) || '|' ||
            shown(p_row.sto_proc_name) || '|' ||
            shown(p_row.user_form_template_guid) || '|' || shown(p_row.notes) ||
            '|' || shown(p_row.include_record_data_onclaim);
    END her_atom_text;

    PROCEDURE build_state_atoms
    IS
        l_index PLS_INTEGER;
    BEGIN
        l_atoms.DELETE;
        add_atom(
            0,
            0,
            'CONTEXT',
            'CONTEXT',
            'CONTEXT|' || shown(l_option_code) || '|' ||
            shown(l_payor_guid) || '|' || shown(l_plan_guid) || '|' ||
            shown(l_pfc_guid) || '|' || shown(l_pfc_plan_guid) || '|' ||
            shown(l_payor_type_guid) || '|' ||
            shown(l_billing_form_code) || '|' ||
            shown(l_form_template_guid) || '|' ||
            shown(l_user_template_guid) || '|' ||
            shown(TO_CHAR(l_cpd_start_date, 'YYYYMMDDHH24MISS')) || '|' ||
            shown(TO_CHAR(l_cpd_end_date, 'YYYYMMDDHH24MISS'))
        );

        FOR i IN 1 .. l_targets.COUNT LOOP
            add_atom(
                1,
                l_targets(i).target_order,
                l_targets(i).target_segment,
                l_targets(i).record_type_code,
                'TARGET|' || l_targets(i).target_segment || '|' ||
                l_targets(i).record_type_code || '|RESOLVED|RESOLVED|' ||
                shown(l_targets(i).source_guid) || '|' ||
                shown(l_targets(i).source_her.sto_proc_name) || '|' ||
                shown(l_targets(i).desired_sto_proc) || '|' ||
                'DESIRED_PAYOR_METADATA|<NULL>|Y|' ||
                l_targets(i).source_equals_desired || '|' ||
                l_targets(i).target_action
            );

            add_atom(
                2,
                l_targets(i).target_order,
                l_targets(i).target_segment,
                l_targets(i).source_guid,
                her_atom_text(
                    'SOURCE_HER',
                    l_targets(i).target_segment,
                    l_targets(i).source_her
                )
            );

            l_index := l_targets(i).source_hefs.FIRST;
            WHILE l_index IS NOT NULL LOOP
                add_atom(
                    3,
                    l_targets(i).target_order,
                    l_targets(i).target_segment,
                    l_targets(i).source_hefs(l_index).electronic_rec_guid ||
                        '|' || l_targets(i).source_hefs(l_index).field_number,
                    'SOURCE_HEF|' || l_targets(i).target_segment || '|' ||
                    l_targets(i).source_hefs(l_index).electronic_rec_guid ||
                    '|' || hef_signature(l_targets(i).source_hefs(l_index))
                );
                l_index := l_targets(i).source_hefs.NEXT(l_index);
            END LOOP;

            l_index := l_targets(i).desired_hefs.FIRST;
            WHILE l_index IS NOT NULL LOOP
                add_atom(
                    4,
                    l_targets(i).target_order,
                    l_targets(i).target_segment,
                    l_targets(i).desired_hefs(l_index).field_number || '|' ||
                        shown_number(l_targets(i).desired_hefs(l_index).order_num),
                    'DESIRED_HEF|' || l_targets(i).target_segment || '|' ||
                    hef_signature(l_targets(i).desired_hefs(l_index))
                );
                l_index := l_targets(i).desired_hefs.NEXT(l_index);
            END LOOP;

            l_index := l_targets(i).current_hers.FIRST;
            WHILE l_index IS NOT NULL LOOP
                add_atom(
                    5,
                    l_targets(i).target_order,
                    l_targets(i).target_segment,
                    l_targets(i).current_hers(l_index).electronic_rec_guid,
                    her_atom_text(
                        'CURRENT_HER',
                        l_targets(i).target_segment,
                        l_targets(i).current_hers(l_index)
                    )
                );
                l_index := l_targets(i).current_hers.NEXT(l_index);
            END LOOP;

            l_index := l_targets(i).current_hefs.FIRST;
            WHILE l_index IS NOT NULL LOOP
                add_atom(
                    6,
                    l_targets(i).target_order,
                    l_targets(i).target_segment,
                    l_targets(i).current_hefs(l_index).electronic_rec_guid ||
                        '|' || l_targets(i).current_hefs(l_index).field_number,
                    'CURRENT_HEF|' || l_targets(i).target_segment || '|' ||
                    l_targets(i).current_hefs(l_index).electronic_rec_guid ||
                    '|' || hef_signature(l_targets(i).current_hefs(l_index))
                );
                l_index := l_targets(i).current_hefs.NEXT(l_index);
            END LOOP;
        END LOOP;
    END build_state_atoms;

    PROCEDURE calculate_preview_state_hash (p_hash OUT VARCHAR2)
    IS
        l_atom_hashes   t_text_rows;
        l_bucket_hashes t_text_rows;
        l_bucket_text   VARCHAR2(32767);
        l_final_text    VARCHAR2(32767);
        l_bucket_count  PLS_INTEGER;
        l_bucket_index  PLS_INTEGER;
        l_bucket_start  PLS_INTEGER;
        l_bucket_end    PLS_INTEGER;
    BEGIN
        build_state_atoms;
        sort_atoms;
        FOR i IN 1 .. l_atoms.COUNT LOOP
            SELECT RAWTOHEX(STANDARD_HASH(l_atoms(i).atom_text, 'SHA256'))
            INTO l_atom_hashes(i)
            FROM dual;
        END LOOP;

        l_bucket_count := CEIL(l_atom_hashes.COUNT / 40);
        IF l_bucket_count > 60 THEN
            RAISE_APPLICATION_ERROR(c_err_hash_too_large,
                'State hash is blocked because the state exceeds 60 buckets.');
        END IF;

        FOR b IN 1 .. l_bucket_count LOOP
            l_bucket_text := NULL;
            l_bucket_start := ((b - 1) * 40) + 1;
            l_bucket_end := LEAST(b * 40, l_atom_hashes.COUNT);
            FOR i IN l_bucket_start .. l_bucket_end LOOP
                l_bucket_text := l_bucket_text || l_atom_hashes(i);
            END LOOP;
            SELECT RAWTOHEX(STANDARD_HASH(l_bucket_text, 'SHA256'))
            INTO l_bucket_hashes(b)
            FROM dual;
        END LOOP;

        l_final_text := NULL;
        l_bucket_index := l_bucket_hashes.FIRST;
        WHILE l_bucket_index IS NOT NULL LOOP
            l_final_text := l_final_text || l_bucket_hashes(l_bucket_index);
            l_bucket_index := l_bucket_hashes.NEXT(l_bucket_index);
        END LOOP;
        SELECT RAWTOHEX(STANDARD_HASH(l_final_text, 'SHA256'))
        INTO p_hash
        FROM dual;
    END calculate_preview_state_hash;

    PROCEDURE assign_new_guids
    IS
    BEGIN
        FOR i IN 1 .. l_targets.COUNT LOOP
            IF l_targets(i).target_action = c_rebuild_override THEN
                SELECT RAWTOHEX(SYS_GUID())
                INTO l_targets(i).new_guid
                FROM dual;
            ELSE
                l_targets(i).new_guid := NULL;
            END IF;
        END LOOP;
    END assign_new_guids;

    PROCEDURE delete_all_target_hefs
    IS
    BEGIN
        FOR i IN 1 .. l_targets.COUNT LOOP
            l_targets(i).deleted_hefs := 0;
            IF l_targets(i).target_action IN (
                c_remove_override, c_rebuild_override
            ) THEN
                l_dml_started := TRUE;
                DELETE FROM hcfa_electronic_fields f
                WHERE EXISTS (
                    SELECT 1
                    FROM hcfa_electronic_records h
                    WHERE h.electronic_rec_guid = f.electronic_rec_guid
                      AND h.payor_guid = l_payor_guid
                      AND h.billing_form_code = l_billing_form_code
                      AND h.record_type_code = l_targets(i).record_type_code
                );
                l_targets(i).deleted_hefs := SQL%ROWCOUNT;
            END IF;
            DBMS_OUTPUT.PUT_LINE(
                l_targets(i).target_segment || ' deleted HEFs: ' ||
                l_targets(i).deleted_hefs
            );
        END LOOP;
    END delete_all_target_hefs;

    PROCEDURE delete_all_target_hers
    IS
    BEGIN
        FOR i IN 1 .. l_targets.COUNT LOOP
            l_targets(i).deleted_hers := 0;
            IF l_targets(i).target_action IN (
                c_remove_override, c_rebuild_override
            ) THEN
                l_dml_started := TRUE;
                DELETE FROM hcfa_electronic_records h
                WHERE h.payor_guid = l_payor_guid
                  AND h.billing_form_code = l_billing_form_code
                  AND h.record_type_code = l_targets(i).record_type_code;
                l_targets(i).deleted_hers := SQL%ROWCOUNT;
            END IF;
            DBMS_OUTPUT.PUT_LINE(
                l_targets(i).target_segment || ' deleted HERs: ' ||
                l_targets(i).deleted_hers
            );
        END LOOP;
    END delete_all_target_hers;

    PROCEDURE insert_all_target_hers
    IS
    BEGIN
        FOR i IN 1 .. l_targets.COUNT LOOP
            l_targets(i).inserted_hers := 0;
            IF l_targets(i).target_action = c_rebuild_override THEN
                l_dml_started := TRUE;
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
                    SYSDATE,
                    l_audit_user,
                    NULL,
                    NULL,
                    l_targets(i).desired_her.include_record_data_onclaim
                );
                l_targets(i).inserted_hers := SQL%ROWCOUNT;
            END IF;
            DBMS_OUTPUT.PUT_LINE(
                l_targets(i).target_segment || ' inserted HERs: ' ||
                l_targets(i).inserted_hers
            );
        END LOOP;
    END insert_all_target_hers;

    PROCEDURE insert_all_target_hefs
    IS
        l_index PLS_INTEGER;
    BEGIN
        FOR i IN 1 .. l_targets.COUNT LOOP
            l_targets(i).cloned_hefs := 0;
            IF l_targets(i).target_action = c_rebuild_override THEN
                l_index := l_targets(i).desired_hefs.FIRST;
                WHILE l_index IS NOT NULL LOOP
                    l_dml_started := TRUE;
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
                        l_targets(i).desired_hefs(l_index).field_number,
                        l_targets(i).new_guid,
                        l_targets(i).desired_hefs(l_index).field_name,
                        l_targets(i).desired_hefs(l_index).record_type_code,
                        l_targets(i).desired_hefs(l_index).sto_proc_name,
                        l_targets(i).desired_hefs(l_index).pic,
                        l_targets(i).desired_hefs(l_index).field_spec,
                        l_targets(i).desired_hefs(l_index).position_from,
                        l_targets(i).desired_hefs(l_index).position_thru,
                        l_targets(i).desired_hefs(l_index).field_name_desc,
                        l_targets(i).desired_hefs(l_index).mandatory_ind,
                        l_targets(i).desired_hefs(l_index).must_fit_length_ind,
                        l_targets(i).desired_hefs(l_index).order_num,
                        l_targets(i).desired_hefs(l_index).repeats,
                        l_targets(i).desired_hefs(l_index).detail_ind,
                        l_targets(i).desired_hefs(l_index).occurs_next,
                        l_targets(i).desired_hefs(l_index).hard_coded_data,
                        l_targets(i).desired_hefs(l_index).field_format,
                        l_targets(i).desired_hefs(l_index).caps_ind,
                        l_targets(i).desired_hefs(l_index)
                            .required_subelement_ind,
                        SYSDATE,
                        l_audit_user,
                        NULL,
                        NULL,
                        l_targets(i).desired_hefs(l_index).include_data_onclaim
                    );
                    l_targets(i).cloned_hefs :=
                        l_targets(i).cloned_hefs + SQL%ROWCOUNT;
                    l_index := l_targets(i).desired_hefs.NEXT(l_index);
                END LOOP;
            END IF;
            DBMS_OUTPUT.PUT_LINE(
                l_targets(i).target_segment || ' cloned HEFs: ' ||
                l_targets(i).cloned_hefs
            );
        END LOOP;
    END insert_all_target_hefs;

    PROCEDURE verify_temporary_state
    IS
        l_her_count   PLS_INTEGER;
        l_hef_count   PLS_INTEGER;
        l_audit_count PLS_INTEGER;
        l_managed_count PLS_INTEGER;
        l_unmanaged_count PLS_INTEGER;
        l_match_count PLS_INTEGER;
        l_source_index PLS_INTEGER;
        l_actual_index PLS_INTEGER;
        l_actual_her  hcfa_electronic_records%ROWTYPE;
        l_actual_hefs t_hef_rows;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('--- TEMPORARY CANONICAL VERIFICATION ---');
        FOR i IN 1 .. l_targets.COUNT LOOP
            SELECT
                COUNT(DISTINCT h.electronic_rec_guid),
                COUNT(f.electronic_rec_guid)
            INTO l_her_count, l_hef_count
            FROM hcfa_electronic_records h
            LEFT JOIN hcfa_electronic_fields f
              ON f.electronic_rec_guid = h.electronic_rec_guid
            WHERE h.payor_guid = l_payor_guid
              AND h.billing_form_code = l_billing_form_code
              AND h.record_type_code = l_targets(i).record_type_code;

            IF l_targets(i).source_equals_desired = 'Y' THEN
                IF l_her_count <> 0 OR l_hef_count <> 0 THEN
                    RAISE_APPLICATION_ERROR(c_err_verification,
                        l_targets(i).target_segment ||
                        ' should have zero payor overrides.');
                END IF;
            ELSE
                IF l_her_count <> 1
                   OR l_hef_count <> l_targets(i).desired_hefs.COUNT THEN
                    RAISE_APPLICATION_ERROR(c_err_verification,
                        l_targets(i).target_segment ||
                        ' temporary HER/HEF counts are not canonical.');
                END IF;

                SELECT h.*
                INTO l_actual_her
                FROM hcfa_electronic_records h
                WHERE h.payor_guid = l_payor_guid
                  AND h.billing_form_code = l_billing_form_code
                  AND h.record_type_code = l_targets(i).record_type_code;

                l_actual_hefs.DELETE;
                SELECT f.* BULK COLLECT
                INTO l_actual_hefs
                FROM hcfa_electronic_fields f
                WHERE f.electronic_rec_guid = l_actual_her.electronic_rec_guid;

                IF NOT payor_configurations_equal(
                    l_actual_her,
                    l_actual_hefs,
                    l_targets(i).desired_her,
                    l_targets(i).desired_hefs
                ) THEN
                    RAISE_APPLICATION_ERROR(c_err_verification,
                        l_targets(i).target_segment ||
                        ' temporary HER/HEF multiset does not match desired.');
                END IF;
                SELECT COUNT(*)
                INTO l_managed_count
                FROM hcfa_electronic_fields f
                WHERE f.electronic_rec_guid = l_actual_her.electronic_rec_guid
                  AND (f.field_number, f.field_name) IN (
                        ('012', 'HI012'), ('015', 'HI015'),
                        ('022', 'HI022'), ('025', 'HI025')
                      );
                IF l_managed_count <> 4 THEN
                    RAISE_APPLICATION_ERROR(c_err_verification,
                        'Value Codes must contain all four managed HEFs.');
                END IF;

                l_unmanaged_count := 0;
                l_source_index := l_targets(i).source_hefs.FIRST;
                WHILE l_source_index IS NOT NULL LOOP
                    IF NOT (
                        (l_targets(i).source_hefs(l_source_index).field_number = '012'
                         AND l_targets(i).source_hefs(l_source_index).field_name = 'HI012')
                        OR (l_targets(i).source_hefs(l_source_index).field_number = '015'
                         AND l_targets(i).source_hefs(l_source_index).field_name = 'HI015')
                        OR (l_targets(i).source_hefs(l_source_index).field_number = '022'
                         AND l_targets(i).source_hefs(l_source_index).field_name = 'HI022')
                        OR (l_targets(i).source_hefs(l_source_index).field_number = '025'
                         AND l_targets(i).source_hefs(l_source_index).field_name = 'HI025')
                    ) THEN
                        l_unmanaged_count := l_unmanaged_count + 1;
                        l_match_count := 0;
                        l_actual_index := l_actual_hefs.FIRST;
                        WHILE l_actual_index IS NOT NULL LOOP
                            IF hef_business_serial(l_actual_hefs(l_actual_index)) =
                               hef_business_serial(
                                   l_targets(i).source_hefs(l_source_index)) THEN
                                l_match_count := l_match_count + 1;
                            END IF;
                            l_actual_index := l_actual_hefs.NEXT(l_actual_index);
                        END LOOP;
                        IF l_match_count <> 1 THEN
                            RAISE_APPLICATION_ERROR(c_err_verification,
                                'An unmanaged source HEF was not copied exactly.');
                        END IF;
                    END IF;
                    l_source_index := l_targets(i).source_hefs.NEXT(l_source_index);
                END LOOP;
                IF l_unmanaged_count <> l_actual_hefs.COUNT - 4 THEN
                    RAISE_APPLICATION_ERROR(c_err_verification,
                        'The unmanaged complete-clone count is not exact.');
                END IF;
                IF NOT values_equal(
                    l_actual_her.payor_type_guid,
                    l_payor_type_guid
                )
                   OR l_actual_her.carry_forward_ind IS NOT NULL
                   OR NOT values_equal(
                        l_actual_her.include_record_data_onclaim,
                        'Y'
                      ) THEN
                    RAISE_APPLICATION_ERROR(c_err_verification,
                        l_targets(i).target_segment ||
                        ' payor-specific HER metadata is not canonical.');
                END IF;
                IF NOT values_equal(
                    l_actual_her.form_template_guid,
                    l_targets(i).source_her.form_template_guid
                )
                   OR NOT values_equal(
                        l_actual_her.user_form_template_guid,
                        l_targets(i).source_her.user_form_template_guid
                      ) THEN
                    RAISE_APPLICATION_ERROR(c_err_verification,
                        l_targets(i).target_segment ||
                        ' source template scope was not preserved.');
                END IF;

                IF l_pre_actions(i) = c_rebuild_override THEN
                    SELECT COUNT(*)
                    INTO l_audit_count
                    FROM hcfa_electronic_fields f
                    WHERE f.electronic_rec_guid = l_actual_her.electronic_rec_guid
                      AND f.rec_ent_date IS NOT NULL
                      AND f.rec_ent_user = l_audit_user
                      AND f.rec_mod_date IS NULL
                      AND f.rec_mod_user IS NULL;
                    IF l_actual_her.rec_ent_date IS NULL
                       OR l_actual_her.rec_ent_user <> l_audit_user
                       OR l_actual_her.rec_mod_date IS NOT NULL
                       OR l_actual_her.rec_mod_user IS NOT NULL
                       OR l_audit_count <> l_actual_hefs.COUNT THEN
                        RAISE_APPLICATION_ERROR(c_err_verification,
                            l_targets(i).target_segment ||
                            ' inserted audit values are not canonical.');
                    END IF;
                END IF;
            END IF;

            DBMS_OUTPUT.PUT_LINE(
                l_targets(i).target_segment || ' VERIFY PASS: ' ||
                l_her_count || ' HER / ' || l_hef_count || ' HEFs'
            );
        END LOOP;
    END verify_temporary_state;

    PROCEDURE verify_restoration
    IS
    BEGIN
        initialize_targets;
        resolve_locked_state;
        calculate_preview_state_hash(l_post_rollback_hash);
        FOR i IN 1 .. l_targets.COUNT LOOP
            IF l_targets(i).existing_her_count <> l_pre_her_counts(i)
               OR l_targets(i).existing_hef_count <> l_pre_hef_counts(i) THEN
                RAISE_APPLICATION_ERROR(c_err_restoration,
                    l_targets(i).target_segment ||
                    ' pre/post rollback counts differ.');
            END IF;
            DBMS_OUTPUT.PUT_LINE(
                l_targets(i).target_segment || ' RESTORED: ' ||
                l_targets(i).existing_her_count || ' HER / ' ||
                l_targets(i).existing_hef_count || ' HEFs'
            );
        END LOOP;
        IF l_post_rollback_hash <> l_pre_apply_hash THEN
            RAISE_APPLICATION_ERROR(c_err_restoration,
                'The post-rollback state hash does not match the pre-DML state.');
        END IF;
        DBMS_OUTPUT.PUT_LINE('POST-ROLLBACK HASH: ' || l_post_rollback_hash);
        DBMS_OUTPUT.PUT_LINE('RESTORATION HASH MATCH: YES');
    END verify_restoration;

BEGIN
    validate_inputs;
    SAVEPOINT value_codes_apply_test;
    l_savepoint_set := TRUE;

    resolve_locked_state;
    calculate_preview_state_hash(l_recalculated_hash);
    l_pre_apply_hash := l_recalculated_hash;

    DBMS_OUTPUT.PUT_LINE('==================================================');
    DBMS_OUTPUT.PUT_LINE('ROLLBACK-ONLY VALUE CODES APPLY');
    DBMS_OUTPUT.PUT_LINE('PAYOR_GUID: ' || l_payor_guid);
    DBMS_OUTPUT.PUT_LINE('PLAN_GUID: ' || shown(l_plan_guid));
    DBMS_OUTPUT.PUT_LINE('LINE_OF_BUSINESS: ' || l_line_of_business);
    DBMS_OUTPUT.PUT_LINE('PFC_GUID: ' || l_pfc_guid);
    DBMS_OUTPUT.PUT_LINE('PAYOR_TYPE_GUID: ' || l_payor_type_guid);
    DBMS_OUTPUT.PUT_LINE('BILLING_FORM_CODE: ' || l_billing_form_code);
    DBMS_OUTPUT.PUT_LINE('RECORD_TYPE_CODE: D23002310HI286');
    DBMS_OUTPUT.PUT_LINE('SELECTION: ' || l_selection_label);
    DBMS_OUTPUT.PUT_LINE('SOURCE_HER_STO_PROC_NAME: ' ||
        shown(l_targets(1).source_her.sto_proc_name));
    DBMS_OUTPUT.PUT_LINE('SOURCE_HER_MANDATORY_IND: ' ||
        shown(l_targets(1).source_her.mandatory_ind));
    DBMS_OUTPUT.PUT_LINE('SOURCE_SAFETY_STATUS: SAFE');
    DBMS_OUTPUT.PUT_LINE('DESIRED_HER_STO_PROC_NAME: ' ||
        shown(l_targets(1).desired_her.sto_proc_name));
    DBMS_OUTPUT.PUT_LINE('DESIRED_HER_MANDATORY_IND: ' ||
        shown(l_targets(1).desired_her.mandatory_ind));
    DBMS_OUTPUT.PUT_LINE('EXPECTED PREVIEW HASH: ' || l_expected_hash);
    DBMS_OUTPUT.PUT_LINE('RECALCULATED HASH: ' || l_recalculated_hash);

        FOR i IN 1 .. l_targets.COUNT LOOP
        l_pre_her_counts(i) := l_targets(i).existing_her_count;
        l_pre_hef_counts(i) := l_targets(i).existing_hef_count;
        l_pre_actions(i) := l_targets(i).target_action;
        DBMS_OUTPUT.PUT_LINE(
            l_targets(i).target_segment || ' SOURCE_GUID=' ||
            l_targets(i).source_guid || ' SOURCE_HEFS=' ||
            l_targets(i).source_hefs.COUNT || ' EXISTING=' ||
            l_targets(i).existing_her_count || ' HER/' ||
            l_targets(i).existing_hef_count || ' HEFs TEMPLATE_LEVEL=' ||
            l_targets(i).source_template_level || ' SOURCE_EQUALS_DESIRED=' ||
            l_targets(i).source_equals_desired || ' CURRENT_MATCHES_DESIRED=' ||
            l_targets(i).current_matches_desired || ' ACTION=' ||
            l_targets(i).target_action
        );
    END LOOP;

    IF l_recalculated_hash <> l_expected_hash THEN
        DBMS_OUTPUT.PUT_LINE('HASH MATCH: NO');
        DBMS_OUTPUT.PUT_LINE(
            'STALE_PREVIEW: no DML was performed; rerun Script 08.'
        );
        RAISE_APPLICATION_ERROR(c_err_stale_preview,
            'STALE_PREVIEW: expected and recalculated hashes differ.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('HASH MATCH: YES');

    assign_new_guids;
    DBMS_OUTPUT.PUT_LINE('--- TEMPORARY DML ---');
    delete_all_target_hefs;
    delete_all_target_hers;
    insert_all_target_hers;
    insert_all_target_hefs;
    verify_temporary_state;

    DBMS_OUTPUT.PUT_LINE('TEMPORARY APPLY VERIFICATION: PASS');
    DBMS_OUTPUT.PUT_LINE('ROLLING BACK ALL VALUE CODES TEST DML...');
    ROLLBACK TO value_codes_apply_test;
    l_dml_started := FALSE;
    verify_restoration;
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE(
        'FINAL FULL ROLLBACK COMPLETE: all harness locks released.'
    );

    DBMS_OUTPUT.PUT_LINE('==================================================');
    DBMS_OUTPUT.PUT_LINE('ROLLBACK-ONLY TEST COMPLETE:');
    DBMS_OUTPUT.PUT_LINE(
        'all Value Codes DML was rolled back and original state was restored.'
    );
    DBMS_OUTPUT.PUT_LINE('==================================================');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ROLLBACK-ONLY TEST FAILED: ' || SQLERRM);
        IF l_savepoint_set THEN
            BEGIN
                ROLLBACK TO value_codes_apply_test;
                l_dml_started := FALSE;
                DBMS_OUTPUT.PUT_LINE(
                    'FAILURE PATH: rolled back to value_codes_apply_test.'
                );
                IF l_pre_apply_hash IS NOT NULL THEN
                    verify_restoration;
                    DBMS_OUTPUT.PUT_LINE(
                        'FAILURE PATH RESTORATION VERIFICATION: PASS'
                    );
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    DBMS_OUTPUT.PUT_LINE(
                        'RESTORATION VERIFICATION FAILED PROMINENTLY: ' || SQLERRM
                    );
                    ROLLBACK;
                    DBMS_OUTPUT.PUT_LINE(
                        'FINAL FULL ROLLBACK COMPLETE ON FAILURE.'
                    );
                    RAISE;
            END;
        END IF;
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE(
            'FINAL FULL ROLLBACK COMPLETE ON FAILURE.'
        );
        RAISE;
END;
/
