/*
 * PRODUCTION HARNESS CLASS: ROLLBACK_ONLY_APPLY
 * STANDALONE: YES
 * TOOL-OWNED OBJECT DEPENDENCIES: NONE
 *
 * UB-04 Field 80 Remarks rollback-only APPLY validation. Use a fresh dedicated
 * session with no unrelated uncommitted work. The fixed safety token and exact
 * Script 11 Preview hash are mandatory. This script always rolls back and has
 * no COMMIT path.
 */
SET SERVEROUTPUT ON
SET DEFINE OFF

DECLARE
    /* MANUAL INPUTS - keep these aligned with Script 11. */
    c_payor_guid CONSTANT VARCHAR2(36) := 'PUT_PAYOR_GUID_HERE';
    c_plan_guid CONSTANT VARCHAR2(36) := NULL;
    c_line_of_business CONSTANT VARCHAR2(20) := 'HOME_HEALTH';
    c_mode CONSTANT VARCHAR2(10) := 'DEFAULT';
    c_custom_remark CONSTANT VARCHAR2(128) := NULL;
    c_audit_user CONSTANT VARCHAR2(36) := 'PUT_AUDIT_USER_HERE';
    c_expected_preview_state_hash CONSTANT VARCHAR2(64) :=
        'PUT_EXPECTED_PREVIEW_STATE_HASH_HERE';
    c_safety_token CONSTANT VARCHAR2(30) := 'ROLLBACK_ONLY_REMARKS';

    c_record_type CONSTANT VARCHAR2(20) := 'D23001900NTE182';
    c_max_remark_length CONSTANT PLS_INTEGER := 100;
    c_err_input CONSTANT PLS_INTEGER := -20601;
    c_err_resolution CONSTANT PLS_INTEGER := -20602;
    c_err_overlay CONSTANT PLS_INTEGER := -20603;
    c_err_hash CONSTANT PLS_INTEGER := -20604;
    c_err_stale CONSTANT PLS_INTEGER := -20605;
    c_err_verify CONSTANT PLS_INTEGER := -20606;
    c_no_change CONSTANT VARCHAR2(30) := 'NO_CHANGE';
    c_remove CONSTANT VARCHAR2(30) := 'REMOVE_OVERRIDE';
    c_rebuild CONSTANT VARCHAR2(30) := 'REBUILD_OVERRIDE';

    TYPE t_hefs IS TABLE OF hcfa_electronic_fields%ROWTYPE INDEX BY PLS_INTEGER;
    TYPE t_hers IS TABLE OF hcfa_electronic_records%ROWTYPE INDEX BY PLS_INTEGER;
    TYPE t_texts IS TABLE OF VARCHAR2(32767) INDEX BY PLS_INTEGER;
    TYPE t_atoms IS TABLE OF VARCHAR2(32767) INDEX BY PLS_INTEGER;

    l_payor payors.payor_guid%TYPE;
    l_plan pfc.plan_guid%TYPE;
    l_lob VARCHAR2(20);
    l_mode VARCHAR2(10);
    l_custom VARCHAR2(128);
    l_audit hcfa_electronic_records.rec_ent_user%TYPE;
    l_pfc_guid pfc.pfc_guid%TYPE;
    l_pfc_plan pfc.plan_guid%TYPE;
    l_payor_type payors.payor_type_guid%TYPE;
    l_billing_form pfc.billing_form_code%TYPE;
    l_form_template pfc.form_template_guid%TYPE;
    l_user_template pfc.user_form_template_guid%TYPE;
    l_start_date pfc.cpd_start_date%TYPE;
    l_end_date pfc.cpd_end_date%TYPE;
    l_source_guid hcfa_electronic_records.electronic_rec_guid%TYPE;
    l_source_level VARCHAR2(20);
    l_source_her hcfa_electronic_records%ROWTYPE;
    l_source_hefs t_hefs;
    l_overlay_her hcfa_electronic_records%ROWTYPE;
    l_overlay_hefs t_hefs;
    l_desired_her hcfa_electronic_records%ROWTYPE;
    l_desired_hefs t_hefs;
    l_current_hers t_hers;
    l_current_hefs t_hefs;
    l_single_hefs t_hefs;
    l_source_equals_desired VARCHAR2(1);
    l_current_matches_desired VARCHAR2(1);
    l_action VARCHAR2(30);
    l_state_hash VARCHAR2(64);
    l_original_hash VARCHAR2(64);
    l_original_hers PLS_INTEGER;
    l_original_hefs PLS_INTEGER;
    l_new_guid hcfa_electronic_records.electronic_rec_guid%TYPE;
    l_atoms t_atoms;

    FUNCTION equal_value(p_left VARCHAR2, p_right VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        RETURN p_left = p_right OR (p_left IS NULL AND p_right IS NULL);
    END;

    FUNCTION enc(p_value VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        IF p_value IS NULL THEN RETURN '-1:'; END IF;
        RETURN TO_CHAR(LENGTH(p_value)) || ':' || p_value;
    END;

    FUNCTION enc_num(p_value NUMBER) RETURN VARCHAR2 IS
    BEGIN
        IF p_value IS NULL THEN RETURN enc(NULL); END IF;
        RETURN enc(TO_CHAR(p_value, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,'''));
    END;

    FUNCTION her_serial(p_row hcfa_electronic_records%ROWTYPE)
        RETURN VARCHAR2 IS
    BEGIN
        RETURN enc(p_row.loop_id) || enc(p_row.contiguity_ind) ||
          enc(p_row.billing_form_code) || enc(p_row.record_name) ||
          enc(p_row.record_type_code) || enc_num(p_row.record_size) ||
          enc(p_row.mandatory_ind) || enc(p_row.req_for_claim_ind) ||
          enc(p_row.payor_type_guid) || enc(p_row.payor_guid) ||
          enc(p_row.plan_guid) || enc(p_row.type_of_bill) ||
          enc(p_row.detail_ind) || enc(p_row.max_number) ||
          enc(p_row.invoice_ind) || enc(p_row.form_template_guid) ||
          enc(p_row.carry_forward_ind) || enc_num(p_row.max_carry_forward) ||
          enc(p_row.sto_proc_name) || enc(p_row.user_form_template_guid) ||
          enc(p_row.notes) || enc(p_row.include_record_data_onclaim);
    END;

    FUNCTION hef_serial(p_row hcfa_electronic_fields%ROWTYPE)
        RETURN VARCHAR2 IS
    BEGIN
        RETURN enc(p_row.field_number) || enc(p_row.field_name) ||
          enc(p_row.record_type_code) || enc(p_row.sto_proc_name) ||
          enc(p_row.pic) || enc(p_row.field_spec) ||
          enc_num(p_row.position_from) || enc_num(p_row.position_thru) ||
          enc(p_row.field_name_desc) || enc(p_row.mandatory_ind) ||
          enc(p_row.must_fit_length_ind) || enc_num(p_row.order_num) ||
          enc_num(p_row.repeats) || enc(p_row.detail_ind) ||
          enc(p_row.occurs_next) || enc(p_row.hard_coded_data) ||
          enc(p_row.field_format) || enc(p_row.caps_ind) ||
          enc(p_row.required_subelement_ind) || enc(p_row.include_data_onclaim);
    END;

    PROCEDURE sort_texts(p_rows IN OUT NOCOPY t_texts) IS
        l_key VARCHAR2(32767); l_j PLS_INTEGER;
    BEGIN
        IF p_rows.COUNT < 2 THEN RETURN; END IF;
        FOR i IN 2 .. p_rows.COUNT LOOP
            l_key := p_rows(i); l_j := i - 1;
            WHILE l_j >= 1 AND p_rows(l_j) > l_key LOOP
                p_rows(l_j + 1) := p_rows(l_j); l_j := l_j - 1;
            END LOOP;
            p_rows(l_j + 1) := l_key;
        END LOOP;
    END;

    FUNCTION hef_sets_equal(p_left t_hefs, p_right t_hefs) RETURN BOOLEAN IS
        l_left t_texts; l_right t_texts; l_index PLS_INTEGER;
    BEGIN
        IF p_left.COUNT <> p_right.COUNT THEN RETURN FALSE; END IF;
        l_index := p_left.FIRST;
        WHILE l_index IS NOT NULL LOOP
            l_left(l_left.COUNT + 1) := hef_serial(p_left(l_index));
            l_index := p_left.NEXT(l_index);
        END LOOP;
        l_index := p_right.FIRST;
        WHILE l_index IS NOT NULL LOOP
            l_right(l_right.COUNT + 1) := hef_serial(p_right(l_index));
            l_index := p_right.NEXT(l_index);
        END LOOP;
        IF l_left.COUNT > 1 THEN sort_texts(l_left); sort_texts(l_right); END IF;
        IF l_left.COUNT > 0 THEN
            FOR i IN 1 .. l_left.COUNT LOOP
                IF l_left(i) <> l_right(i) THEN RETURN FALSE; END IF;
            END LOOP;
        END IF;
        RETURN TRUE;
    END;

    FUNCTION configs_equal(p_left_her hcfa_electronic_records%ROWTYPE,
        p_left_hefs t_hefs, p_right_her hcfa_electronic_records%ROWTYPE,
        p_right_hefs t_hefs) RETURN BOOLEAN IS
    BEGIN
        RETURN her_serial(p_left_her) = her_serial(p_right_her)
           AND hef_sets_equal(p_left_hefs, p_right_hefs);
    END;

    FUNCTION payor_equal(p_current hcfa_electronic_records%ROWTYPE,
        p_current_hefs t_hefs, p_desired hcfa_electronic_records%ROWTYPE,
        p_desired_rows t_hefs) RETURN BOOLEAN IS
        l_current hcfa_electronic_records%ROWTYPE := p_current;
        l_desired hcfa_electronic_records%ROWTYPE := p_desired;
    BEGIN
        IF p_current.payor_type_guid IS NOT NULL
           AND NOT equal_value(p_current.payor_type_guid,
                               p_desired.payor_type_guid) THEN RETURN FALSE; END IF;
        l_current.payor_type_guid := NULL; l_desired.payor_type_guid := NULL;
        RETURN configs_equal(l_current, p_current_hefs,
                             l_desired, p_desired_rows);
    END;

    PROCEDURE validate_inputs IS
    BEGIN
        l_payor := TRIM(c_payor_guid); l_plan := TRIM(c_plan_guid);
        l_lob := UPPER(TRIM(c_line_of_business));
        l_mode := UPPER(TRIM(c_mode)); l_custom := TRIM(c_custom_remark);
        l_audit := TRIM(c_audit_user);
        IF l_payor IS NULL OR l_payor = 'PUT_PAYOR_GUID_HERE' THEN
            RAISE_APPLICATION_ERROR(c_err_input, 'PAYOR_GUID is required.');
        END IF;
        IF l_lob NOT IN ('HOME_HEALTH', 'HOSPICE') THEN
            RAISE_APPLICATION_ERROR(c_err_input,
                'LINE_OF_BUSINESS must be HOME_HEALTH or HOSPICE.');
        END IF;
        IF l_mode NOT IN ('DEFAULT', 'CUSTOM') THEN
            RAISE_APPLICATION_ERROR(c_err_input, 'MODE must be DEFAULT or CUSTOM.');
        END IF;
        IF l_mode = 'DEFAULT' AND l_custom IS NOT NULL THEN
            RAISE_APPLICATION_ERROR(c_err_input,
                'DEFAULT must not include CUSTOM_REMARK.');
        END IF;
        IF l_mode = 'CUSTOM' AND l_custom IS NULL THEN
            RAISE_APPLICATION_ERROR(c_err_input, 'CUSTOM_REMARK is required.');
        END IF;
        IF LENGTH(l_custom) > c_max_remark_length THEN
            RAISE_APPLICATION_ERROR(c_err_input,
                'CUSTOM_REMARK exceeds the configured 100-character limit.');
        END IF;
        IF l_audit IS NULL OR l_audit = 'PUT_AUDIT_USER_HERE'
           OR LENGTH(l_audit) > 36 THEN
            RAISE_APPLICATION_ERROR(c_err_input, 'A valid AUDIT_USER is required.');
        END IF;
        IF c_safety_token <> 'ROLLBACK_ONLY_REMARKS' THEN
            RAISE_APPLICATION_ERROR(c_err_input, 'The rollback-only safety token is invalid.');
        END IF;
        IF c_expected_preview_state_hash IS NULL
           OR c_expected_preview_state_hash = 'PUT_EXPECTED_PREVIEW_STATE_HASH_HERE'
           OR NOT REGEXP_LIKE(c_expected_preview_state_hash, '^[0-9A-F]{64}$') THEN
            RAISE_APPLICATION_ERROR(c_err_input,
                'The exact uppercase Script 11 state hash is required.');
        END IF;
    END;

    PROCEDURE resolve_pfc(p_lock BOOLEAN) IS l_count PLS_INTEGER;
        l_lock_guid pfc.pfc_guid%TYPE;
    BEGIN
        SELECT payor_type_guid INTO l_payor_type FROM payors
        WHERE payor_guid = l_payor;
        SELECT COUNT(*), MAX(pfc_guid), MAX(plan_guid), MAX(billing_form_code),
               MAX(form_template_guid), MAX(user_form_template_guid),
               MAX(cpd_start_date), MAX(cpd_end_date)
        INTO l_count, l_pfc_guid, l_pfc_plan, l_billing_form,
             l_form_template, l_user_template, l_start_date, l_end_date
        FROM (SELECT p.*, DENSE_RANK() OVER (
                ORDER BY cpd_start_date DESC NULLS LAST) winner_rank
              FROM pfc p WHERE p.payor_guid = l_payor
                AND p.cpd_end_date > SYSDATE AND p.default_media_type = 'E'
                AND p.type_of_bill IS NULL
                AND ((l_plan IS NULL AND p.plan_guid IS NULL)
                  OR (l_plan IS NOT NULL
                      AND (p.plan_guid = l_plan OR p.plan_guid IS NULL))))
        WHERE winner_rank = 1;
        IF l_count <> 1 THEN RAISE_APPLICATION_ERROR(c_err_resolution,
            'PFC resolution is missing or ambiguous.'); END IF;
        IF p_lock THEN
            SELECT pfc_guid INTO l_lock_guid FROM pfc
            WHERE pfc_guid = l_pfc_guid FOR UPDATE;
            SELECT payor_type_guid INTO l_payor_type FROM payors
            WHERE payor_guid = l_payor FOR UPDATE;
        END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_resolution,
            'PAYOR/PFC resolution failed.');
    END;

    PROCEDURE resolve_source(p_lock BOOLEAN) IS l_count PLS_INTEGER;
        l_lock_guid hcfa_electronic_records.electronic_rec_guid%TYPE;
    BEGIN
        SELECT COUNT(*), MAX(electronic_rec_guid)
        INTO l_count, l_source_guid
        FROM (SELECT q.*, DENSE_RANK() OVER (
                ORDER BY template_rank, type_rank) source_rank
              FROM (SELECT h.electronic_rec_guid,
                    CASE WHEN h.user_form_template_guid IS NOT NULL THEN 1
                         WHEN h.form_template_guid IS NOT NULL THEN 2 ELSE 3 END template_rank,
                    CASE WHEN h.payor_type_guid = l_payor_type
                              AND h.payor_type_guid IS NOT NULL THEN 1 ELSE 2 END type_rank
                    FROM hcfa_electronic_records h
                    WHERE h.billing_form_code = l_billing_form
                      AND h.record_type_code = c_record_type
                      AND h.payor_guid IS NULL AND h.plan_guid IS NULL
                      AND h.type_of_bill IS NULL
                      AND (h.payor_type_guid = l_payor_type
                           OR h.payor_type_guid IS NULL)
                      AND ((h.user_form_template_guid IS NOT NULL
                            AND h.user_form_template_guid = l_user_template
                            AND (h.form_template_guid = l_form_template
                                 OR h.form_template_guid IS NULL))
                        OR (h.user_form_template_guid IS NULL
                            AND h.form_template_guid IS NOT NULL
                            AND h.form_template_guid = l_form_template)
                        OR (h.user_form_template_guid IS NULL
                            AND h.form_template_guid IS NULL))) q)
        WHERE source_rank = 1;
        IF l_count <> 1 THEN RAISE_APPLICATION_ERROR(c_err_resolution,
            'Remarks source is missing or ambiguous.'); END IF;
        SELECT * INTO l_source_her FROM hcfa_electronic_records
        WHERE electronic_rec_guid = l_source_guid;
        l_source_level := CASE
            WHEN l_source_her.user_form_template_guid IS NOT NULL THEN 'USER'
            WHEN l_source_her.form_template_guid IS NOT NULL THEN 'FORM'
            ELSE 'BILLING' END;
        IF p_lock THEN
            SELECT electronic_rec_guid INTO l_lock_guid
            FROM hcfa_electronic_records
            WHERE electronic_rec_guid = l_source_guid FOR UPDATE;
            FOR f IN (SELECT field_number FROM hcfa_electronic_fields
                WHERE electronic_rec_guid = l_source_guid
                ORDER BY field_number, order_num NULLS FIRST, position_from
                FOR UPDATE) LOOP NULL; END LOOP;
        END IF;
        SELECT * BULK COLLECT INTO l_source_hefs
        FROM hcfa_electronic_fields WHERE electronic_rec_guid = l_source_guid
        ORDER BY field_number, order_num NULLS FIRST, position_from;
    END;

    PROCEDURE set_managed(p_number VARCHAR2, p_name VARCHAR2,
        p_hard_value VARCHAR2) IS l_match PLS_INTEGER; l_count PLS_INTEGER := 0;
        l_index PLS_INTEGER;
    BEGIN
        l_index := l_overlay_hefs.FIRST;
        WHILE l_index IS NOT NULL LOOP
            IF l_overlay_hefs(l_index).field_number = p_number
               AND l_overlay_hefs(l_index).field_name = p_name THEN
                l_count := l_count + 1; l_match := l_index;
            END IF;
            l_index := l_overlay_hefs.NEXT(l_index);
        END LOOP;
        IF l_count <> 1 THEN RAISE_APPLICATION_ERROR(c_err_overlay,
            p_name || ' must match exactly one source HEF.'); END IF;
        l_overlay_hefs(l_match).sto_proc_name := NULL;
        l_overlay_hefs(l_match).hard_coded_data := p_hard_value;
    END;

    PROCEDURE build_desired_state IS l_index PLS_INTEGER;
    BEGIN
        l_overlay_her := l_source_her; l_overlay_hefs := l_source_hefs;
        IF l_mode = 'DEFAULT'
           AND NVL(UPPER(TRIM(l_source_her.sto_proc_name)), '<NULL>') <>
                'RETURN_1'
           AND NVL(UPPER(TRIM(l_source_her.mandatory_ind)), '<NULL>') <>
                'N' THEN
            DBMS_OUTPUT.PUT_LINE('STATUS: BLOCKED');
            DBMS_OUTPUT.PUT_LINE(
                'SOURCE_SAFETY_STATUS: INVALID_MANDATORY_COMBINATION');
            RAISE_APPLICATION_ERROR(c_err_resolution,
                'The inherited Remarks source violates the mandatory-record rule; correct the template or billing-form source.');
        END IF;
        IF l_mode = 'CUSTOM' THEN
            l_overlay_her.sto_proc_name := 'RETURN_1';
            set_managed('00', 'NTE00', 'NTE');
            set_managed('01', 'NTE01', 'ADD');
            set_managed('02', 'NTE02', l_custom);
        END IF;
        IF l_mode = 'CUSTOM'
           AND (UPPER(TRIM(l_overlay_her.sto_proc_name)) <> 'RETURN_1'
                OR l_overlay_her.sto_proc_name IS NULL) THEN
            l_overlay_her.mandatory_ind := 'N';
        END IF;
        l_source_equals_desired := CASE WHEN configs_equal(l_source_her,
            l_source_hefs, l_overlay_her, l_overlay_hefs) THEN 'Y' ELSE 'N' END;
        l_desired_her := l_overlay_her;
        l_desired_her.electronic_rec_guid := NULL;
        l_desired_her.payor_guid := l_payor;
        l_desired_her.payor_type_guid := l_payor_type;
        l_desired_her.carry_forward_ind := NULL;
        l_desired_her.include_record_data_onclaim := 'Y';
        l_desired_her.rec_ent_date := NULL; l_desired_her.rec_ent_user := NULL;
        l_desired_her.rec_mod_date := NULL; l_desired_her.rec_mod_user := NULL;
        l_desired_hefs := l_overlay_hefs;
        l_index := l_desired_hefs.FIRST;
        WHILE l_index IS NOT NULL LOOP
            l_desired_hefs(l_index).electronic_rec_guid := NULL;
            l_desired_hefs(l_index).rec_ent_date := NULL;
            l_desired_hefs(l_index).rec_ent_user := NULL;
            l_desired_hefs(l_index).rec_mod_date := NULL;
            l_desired_hefs(l_index).rec_mod_user := NULL;
            l_index := l_desired_hefs.NEXT(l_index);
        END LOOP;
    END;

    PROCEDURE read_current(p_lock BOOLEAN) IS
    BEGIN
        IF p_lock THEN
            FOR h IN (SELECT electronic_rec_guid FROM hcfa_electronic_records
                WHERE payor_guid = l_payor AND billing_form_code = l_billing_form
                  AND record_type_code = c_record_type
                ORDER BY electronic_rec_guid FOR UPDATE) LOOP
                FOR f IN (SELECT field_number FROM hcfa_electronic_fields
                    WHERE electronic_rec_guid = h.electronic_rec_guid
                    ORDER BY field_number, order_num NULLS FIRST, position_from
                    FOR UPDATE) LOOP NULL; END LOOP;
            END LOOP;
        END IF;
        SELECT * BULK COLLECT INTO l_current_hers
        FROM hcfa_electronic_records h
        WHERE h.payor_guid = l_payor AND h.billing_form_code = l_billing_form
          AND h.record_type_code = c_record_type ORDER BY electronic_rec_guid;
        SELECT f.* BULK COLLECT INTO l_current_hefs
        FROM hcfa_electronic_fields f
        WHERE EXISTS (SELECT 1 FROM hcfa_electronic_records h
          WHERE h.electronic_rec_guid = f.electronic_rec_guid
            AND h.payor_guid = l_payor AND h.billing_form_code = l_billing_form
            AND h.record_type_code = c_record_type)
        ORDER BY electronic_rec_guid, field_number, order_num NULLS FIRST,
                 position_from;
        l_single_hefs.DELETE;
        IF l_current_hers.COUNT = 1 THEN
            SELECT * BULK COLLECT INTO l_single_hefs
            FROM hcfa_electronic_fields
            WHERE electronic_rec_guid = l_current_hers(1).electronic_rec_guid;
        END IF;
        IF l_current_hers.COUNT = 0 THEN
            l_current_matches_desired := l_source_equals_desired;
        ELSIF l_current_hers.COUNT = 1 AND payor_equal(l_current_hers(1),
            l_single_hefs, l_desired_her, l_desired_hefs) THEN
            l_current_matches_desired := 'Y';
        ELSE l_current_matches_desired := 'N'; END IF;
        IF l_source_equals_desired = 'Y' THEN
            l_action := CASE WHEN l_current_hers.COUNT = 0
                THEN c_no_change ELSE c_remove END;
        ELSIF l_current_matches_desired = 'Y' THEN l_action := c_no_change;
        ELSE l_action := c_rebuild; END IF;
    END;

    /* HASH CONTRACT START: keep byte-for-byte aligned with Script 11. */
    PROCEDURE add_atom(p_text VARCHAR2) IS
    BEGIN l_atoms(l_atoms.COUNT + 1) := p_text; END;

    PROCEDURE build_hash_atoms IS l_index PLS_INTEGER;
    BEGIN
        l_atoms.DELETE;
        add_atom('REMARKS_STATE_V1|' || enc(l_lob) || enc(l_mode) ||
            enc(CASE WHEN l_mode = 'CUSTOM' THEN l_custom END) || enc(l_payor) ||
            enc(l_plan) || enc(l_pfc_guid) || enc(l_pfc_plan) ||
            enc(l_payor_type) || enc(l_billing_form) || enc(l_form_template) ||
            enc(l_user_template) || enc(TO_CHAR(l_start_date, 'YYYYMMDDHH24MISS')) ||
            enc(TO_CHAR(l_end_date, 'YYYYMMDDHH24MISS')) || enc(l_action));
        add_atom('SOURCE_HER|' || enc(l_source_guid) || her_serial(l_source_her));
        l_index := l_source_hefs.FIRST;
        WHILE l_index IS NOT NULL LOOP
            add_atom('SOURCE_HEF|' || hef_serial(l_source_hefs(l_index)));
            l_index := l_source_hefs.NEXT(l_index);
        END LOOP;
        add_atom('DESIRED_HER|' || her_serial(l_desired_her));
        l_index := l_desired_hefs.FIRST;
        WHILE l_index IS NOT NULL LOOP
            add_atom('DESIRED_HEF|' || hef_serial(l_desired_hefs(l_index)));
            l_index := l_desired_hefs.NEXT(l_index);
        END LOOP;
        l_index := l_current_hers.FIRST;
        WHILE l_index IS NOT NULL LOOP
            add_atom('CURRENT_HER|' || enc(l_current_hers(l_index).electronic_rec_guid) ||
                her_serial(l_current_hers(l_index)));
            l_index := l_current_hers.NEXT(l_index);
        END LOOP;
        l_index := l_current_hefs.FIRST;
        WHILE l_index IS NOT NULL LOOP
            add_atom('CURRENT_HEF|' || enc(l_current_hefs(l_index).electronic_rec_guid) ||
                hef_serial(l_current_hefs(l_index)));
            l_index := l_current_hefs.NEXT(l_index);
        END LOOP;
    END;

    PROCEDURE calculate_preview_state_hash(p_hash OUT VARCHAR2) IS
        l_atom_hashes t_texts; l_bucket_hashes t_texts;
        l_text VARCHAR2(32767); l_bucket_count PLS_INTEGER;
        l_first PLS_INTEGER; l_last PLS_INTEGER;
    BEGIN
        build_hash_atoms;
        FOR i IN 1 .. l_atoms.COUNT LOOP
            SELECT RAWTOHEX(STANDARD_HASH(l_atoms(i), 'SHA256'))
            INTO l_atom_hashes(i) FROM dual;
        END LOOP;
        l_bucket_count := CEIL(l_atom_hashes.COUNT / 40);
        IF l_bucket_count > 60 THEN RAISE_APPLICATION_ERROR(c_err_hash,
            'Remarks state exceeds the supported hash size.'); END IF;
        FOR b IN 1 .. l_bucket_count LOOP
            l_text := NULL; l_first := ((b - 1) * 40) + 1;
            l_last := LEAST(b * 40, l_atom_hashes.COUNT);
            FOR i IN l_first .. l_last LOOP l_text := l_text || l_atom_hashes(i); END LOOP;
            SELECT RAWTOHEX(STANDARD_HASH(l_text, 'SHA256'))
            INTO l_bucket_hashes(b) FROM dual;
        END LOOP;
        l_text := NULL;
        FOR b IN 1 .. l_bucket_hashes.COUNT LOOP
            l_text := l_text || l_bucket_hashes(b);
        END LOOP;
        SELECT RAWTOHEX(STANDARD_HASH(l_text, 'SHA256')) INTO p_hash FROM dual;
    END;
    /* HASH CONTRACT END */

    PROCEDURE resolve_all(p_lock BOOLEAN) IS
    BEGIN
        resolve_pfc(p_lock); resolve_source(p_lock);
        build_desired_state; read_current(p_lock);
        calculate_preview_state_hash(l_state_hash);
    END;

    PROCEDURE remove_scope IS
    BEGIN
        DELETE FROM hcfa_electronic_fields f WHERE EXISTS (
            SELECT 1 FROM hcfa_electronic_records h
            WHERE h.electronic_rec_guid = f.electronic_rec_guid
              AND h.payor_guid = l_payor
              AND h.billing_form_code = l_billing_form
              AND h.record_type_code = c_record_type);
        DELETE FROM hcfa_electronic_records h
        WHERE h.payor_guid = l_payor
          AND h.billing_form_code = l_billing_form
          AND h.record_type_code = c_record_type;
    END;

    PROCEDURE rebuild_override IS l_index PLS_INTEGER;
    BEGIN
        l_new_guid := LOWER(REGEXP_REPLACE(RAWTOHEX(SYS_GUID()),
            '(.{8})(.{4})(.{4})(.{4})(.{12})', '\1-\2-\3-\4-\5'));
        INSERT INTO hcfa_electronic_records (
            electronic_rec_guid, loop_id, contiguity_ind, billing_form_code,
            record_name, record_type_code, record_size, mandatory_ind,
            req_for_claim_ind, payor_type_guid, payor_guid, plan_guid,
            type_of_bill, detail_ind, max_number, invoice_ind,
            form_template_guid, carry_forward_ind, max_carry_forward,
            sto_proc_name, user_form_template_guid, notes, rec_ent_date,
            rec_ent_user, rec_mod_date, rec_mod_user,
            include_record_data_onclaim
        ) VALUES (
            l_new_guid, l_desired_her.loop_id, l_desired_her.contiguity_ind,
            l_desired_her.billing_form_code, l_desired_her.record_name,
            l_desired_her.record_type_code, l_desired_her.record_size,
            l_desired_her.mandatory_ind, l_desired_her.req_for_claim_ind,
            l_payor_type, l_payor, l_desired_her.plan_guid,
            l_desired_her.type_of_bill, l_desired_her.detail_ind,
            l_desired_her.max_number, l_desired_her.invoice_ind,
            l_source_her.form_template_guid, NULL,
            l_desired_her.max_carry_forward, l_desired_her.sto_proc_name,
            l_source_her.user_form_template_guid, l_desired_her.notes,
            SYSDATE, l_audit, NULL, NULL, 'Y');
        l_index := l_desired_hefs.FIRST;
        WHILE l_index IS NOT NULL LOOP
            INSERT INTO hcfa_electronic_fields (
                field_number, electronic_rec_guid, field_name,
                record_type_code, sto_proc_name, pic, field_spec,
                position_from, position_thru, field_name_desc, mandatory_ind,
                must_fit_length_ind, order_num, repeats, detail_ind,
                occurs_next, hard_coded_data, field_format, caps_ind,
                required_subelement_ind, rec_ent_date, rec_ent_user,
                rec_mod_date, rec_mod_user, include_data_onclaim
            ) VALUES (
                l_desired_hefs(l_index).field_number, l_new_guid,
                l_desired_hefs(l_index).field_name,
                l_desired_hefs(l_index).record_type_code,
                l_desired_hefs(l_index).sto_proc_name,
                l_desired_hefs(l_index).pic,
                l_desired_hefs(l_index).field_spec,
                l_desired_hefs(l_index).position_from,
                l_desired_hefs(l_index).position_thru,
                l_desired_hefs(l_index).field_name_desc,
                l_desired_hefs(l_index).mandatory_ind,
                l_desired_hefs(l_index).must_fit_length_ind,
                l_desired_hefs(l_index).order_num,
                l_desired_hefs(l_index).repeats,
                l_desired_hefs(l_index).detail_ind,
                l_desired_hefs(l_index).occurs_next,
                l_desired_hefs(l_index).hard_coded_data,
                l_desired_hefs(l_index).field_format,
                l_desired_hefs(l_index).caps_ind,
                l_desired_hefs(l_index).required_subelement_ind,
                SYSDATE, l_audit, NULL, NULL,
                l_desired_hefs(l_index).include_data_onclaim);
            l_index := l_desired_hefs.NEXT(l_index);
        END LOOP;
    END;

    PROCEDURE verify_temporary IS l_count PLS_INTEGER;
    BEGIN
        resolve_all(FALSE);
        IF l_action <> c_no_change THEN RAISE_APPLICATION_ERROR(c_err_verify,
            'Temporary canonical state verification failed.'); END IF;
        IF l_mode = 'DEFAULT' THEN
            IF l_current_hers.COUNT <> 0 THEN RAISE_APPLICATION_ERROR(c_err_verify,
                'DEFAULT did not leave zero overrides.'); END IF;
        ELSE
            SELECT COUNT(*) INTO l_count FROM hcfa_electronic_fields f
            JOIN hcfa_electronic_records h
              ON h.electronic_rec_guid = f.electronic_rec_guid
            WHERE h.payor_guid = l_payor AND h.record_type_code = c_record_type
              AND f.field_number = '02' AND f.field_name = 'NTE02'
              AND f.sto_proc_name IS NULL AND f.hard_coded_data = l_custom;
            IF l_count <> CASE WHEN l_source_equals_desired = 'Y' THEN 0 ELSE 1 END
               AND l_source_equals_desired <> 'Y' THEN
                RAISE_APPLICATION_ERROR(c_err_verify,
                    'NTE02 exact custom text verification failed.');
            END IF;
            IF l_source_equals_desired = 'N' THEN
                SELECT COUNT(*) INTO l_count
                FROM hcfa_electronic_records h
                WHERE h.payor_guid = l_payor
                  AND h.billing_form_code = l_billing_form
                  AND h.record_type_code = c_record_type
                  AND DECODE(h.form_template_guid,
                             l_source_her.form_template_guid, 1, 0) = 1
                  AND DECODE(h.user_form_template_guid,
                             l_source_her.user_form_template_guid, 1, 0) = 1
                  AND h.rec_ent_date IS NOT NULL
                  AND h.rec_ent_user = l_audit
                  AND h.rec_mod_date IS NULL
                  AND h.rec_mod_user IS NULL;
                IF l_count <> 1 THEN RAISE_APPLICATION_ERROR(c_err_verify,
                    'Canonical HER template/audit verification failed.'); END IF;

                SELECT COUNT(*) INTO l_count
                FROM hcfa_electronic_fields f
                JOIN hcfa_electronic_records h
                  ON h.electronic_rec_guid = f.electronic_rec_guid
                WHERE h.payor_guid = l_payor
                  AND h.billing_form_code = l_billing_form
                  AND h.record_type_code = c_record_type
                  AND (f.rec_ent_date IS NULL OR f.rec_ent_user <> l_audit
                    OR f.rec_ent_user IS NULL OR f.rec_mod_date IS NOT NULL
                    OR f.rec_mod_user IS NOT NULL);
                IF l_count <> 0 THEN RAISE_APPLICATION_ERROR(c_err_verify,
                    'Complete HEF audit verification failed.'); END IF;
            END IF;
        END IF;
    END;
BEGIN
    validate_inputs;
    SAVEPOINT remarks_rollback_apply;
    resolve_all(TRUE);
    l_original_hash := l_state_hash;
    l_original_hers := l_current_hers.COUNT;
    l_original_hefs := l_current_hefs.COUNT;
    IF l_state_hash <> c_expected_preview_state_hash THEN
        RAISE_APPLICATION_ERROR(c_err_stale,
            'The Script 11 Preview hash is stale; no target DML was performed.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('HASH MATCH: YES');

    DBMS_OUTPUT.PUT_LINE('TARGET_ACTION: ' || l_action);
    IF l_action = c_remove THEN
        remove_scope;
    ELSIF l_action = c_rebuild THEN
        remove_scope;
        rebuild_override;
    END IF;
    verify_temporary;
    DBMS_OUTPUT.PUT_LINE('TEMPORARY_CANONICAL_STATE: VERIFIED');

    ROLLBACK TO remarks_rollback_apply;
    resolve_all(FALSE);
    IF l_state_hash <> l_original_hash
       OR l_current_hers.COUNT <> l_original_hers
       OR l_current_hefs.COUNT <> l_original_hefs THEN
        RAISE_APPLICATION_ERROR(c_err_verify,
            'Original Remarks state was not restored exactly.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('RESTORATION HASH MATCH: YES');
    DBMS_OUTPUT.PUT_LINE('ORIGINAL_STATE_RESTORED: VERIFIED');
    DBMS_OUTPUT.PUT_LINE('ROLLBACK-ONLY APPLY: NO CHANGES RETAINED');
    ROLLBACK;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/
