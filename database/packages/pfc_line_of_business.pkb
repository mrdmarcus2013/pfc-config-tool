CREATE OR REPLACE PACKAGE BODY pfc_line_of_business AS
    SUBTYPE t_lob IS pfc_config_payor_context.line_of_business%TYPE;
    TYPE t_numbers IS TABLE OF PLS_INTEGER INDEX BY PLS_INTEGER;

    PROCEDURE validate_payor (p_payor_guid IN payors.payor_guid%TYPE)
    IS
        l_count PLS_INTEGER;
    BEGIN
        SELECT COUNT(*) INTO l_count
        FROM payors p
        WHERE p.payor_guid = p_payor_guid;
        IF l_count <> 1 THEN
            RAISE_APPLICATION_ERROR(c_err_payor_not_found,
                'The requested payor does not exist.');
        END IF;
    END validate_payor;

    PROCEDURE validate_lob (p_lob IN t_lob)
    IS
    BEGIN
        IF p_lob IS NULL OR p_lob NOT IN ('HOME_HEALTH', 'HOSPICE') THEN
            RAISE_APPLICATION_ERROR(c_err_invalid_lob,
                'Line of Business must be HOME_HEALTH or HOSPICE.');
        END IF;
    END validate_lob;

    PROCEDURE validate_audit_user (
        p_audit_user IN pfc_config_payor_context.rec_ent_user%TYPE
    )
    IS
    BEGIN
        IF TRIM(p_audit_user) IS NULL OR LENGTH(TRIM(p_audit_user)) > 36 THEN
            RAISE_APPLICATION_ERROR(-20031, 'A valid audit user is required.');
        END IF;
    END validate_audit_user;

    PROCEDURE require_defined (
        p_payor_guid IN payors.payor_guid%TYPE,
        p_lock       IN VARCHAR2
    )
    IS
        l_lob t_lob;
    BEGIN
        validate_payor(p_payor_guid);
        IF UPPER(TRIM(p_lock)) = 'Y' THEN
            SELECT c.line_of_business INTO l_lob
            FROM pfc_config_payor_context c
            WHERE c.payor_guid = p_payor_guid
            FOR UPDATE;
        ELSIF UPPER(TRIM(p_lock)) = 'N' THEN
            SELECT c.line_of_business INTO l_lob
            FROM pfc_config_payor_context c
            WHERE c.payor_guid = p_payor_guid;
        ELSE
            RAISE_APPLICATION_ERROR(c_err_unexpected_state,
                'Invalid Line of Business lock mode.');
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(c_err_lob_required,
                'Line of Business must be saved before claim fields can be configured.');
    END require_defined;

    PROCEDURE get_current (
        p_payor_guid IN payors.payor_guid%TYPE,
        p_result     OUT SYS_REFCURSOR
    )
    IS
        l_lob t_lob;
    BEGIN
        validate_payor(p_payor_guid);
        BEGIN
            SELECT c.line_of_business INTO l_lob
            FROM pfc_config_payor_context c
            WHERE c.payor_guid = p_payor_guid;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN l_lob := NULL;
        END;
        OPEN p_result FOR
            SELECT CASE WHEN l_lob IS NULL THEN 'UNDEFINED' ELSE 'DEFINED' END status,
                   l_lob line_of_business
            FROM dual;
    END get_current;

    PROCEDURE save_initial (
        p_payor_guid       IN payors.payor_guid%TYPE,
        p_line_of_business IN pfc_config_payor_context.line_of_business%TYPE,
        p_audit_user       IN pfc_config_payor_context.rec_ent_user%TYPE,
        p_result           OUT SYS_REFCURSOR
    )
    IS
        l_lock payors.payor_guid%TYPE;
        l_count PLS_INTEGER;
    BEGIN
        validate_lob(p_line_of_business);
        validate_audit_user(p_audit_user);
        BEGIN
            SELECT p.payor_guid INTO l_lock
            FROM payors p
            WHERE p.payor_guid = p_payor_guid
            FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(c_err_payor_not_found,
                    'The requested payor does not exist.');
        END;
        SELECT COUNT(*) INTO l_count
        FROM pfc_config_payor_context c
        WHERE c.payor_guid = p_payor_guid;
        IF l_count <> 0 THEN
            RAISE_APPLICATION_ERROR(c_err_lob_already_saved,
                'Line of Business is already saved for this payor.');
        END IF;
        INSERT INTO pfc_config_payor_context (
            payor_guid, line_of_business, rec_ent_date, rec_ent_user,
            rec_mod_date, rec_mod_user
        ) VALUES (
            p_payor_guid, p_line_of_business, SYSDATE, TRIM(p_audit_user),
            NULL, NULL
        );
        OPEN p_result FOR
            SELECT 'SAVED' status, p_line_of_business line_of_business
            FROM dual;
    END save_initial;

    PROCEDURE sort_targets (
        p_targets IN OUT NOCOPY pfc_option_registry.t_managed_targets
    )
    IS
        l_key pfc_option_registry.t_managed_target;
        l_j PLS_INTEGER;
    BEGIN
        IF p_targets.COUNT < 2 THEN RETURN; END IF;
        FOR i IN 2 .. p_targets.COUNT LOOP
            l_key := p_targets(i);
            l_j := i - 1;
            WHILE l_j >= 1 AND
                  p_targets(l_j).billing_form_code || '|' ||
                  p_targets(l_j).record_type_code >
                  l_key.billing_form_code || '|' || l_key.record_type_code LOOP
                p_targets(l_j + 1) := p_targets(l_j);
                l_j := l_j - 1;
            END LOOP;
            p_targets(l_j + 1) := l_key;
        END LOOP;
    END sort_targets;

    FUNCTION enc(p_value IN VARCHAR2) RETURN VARCHAR2
    IS
    BEGIN
        IF p_value IS NULL THEN RETURN '-1:'; END IF;
        RETURN TO_CHAR(LENGTH(p_value)) || ':' || p_value;
    END enc;

    FUNCTION enc_num(p_value IN NUMBER) RETURN VARCHAR2
    IS
    BEGIN
        IF p_value IS NULL THEN RETURN enc(NULL); END IF;
        RETURN enc(TO_CHAR(p_value, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,'''));
    END enc_num;

    FUNCTION enc_date(p_value IN DATE) RETURN VARCHAR2
    IS
    BEGIN
        IF p_value IS NULL THEN RETURN enc(NULL); END IF;
        RETURN enc(TO_CHAR(p_value, 'YYYYMMDDHH24MISS'));
    END enc_date;

    PROCEDURE calculate_state (
        p_payor_guid     IN payors.payor_guid%TYPE,
        p_requested_lob  IN t_lob,
        p_targets        OUT pfc_option_registry.t_managed_targets,
        p_her_counts     OUT t_numbers,
        p_hef_counts     OUT t_numbers,
        p_affected_count OUT PLS_INTEGER,
        p_total_hers     OUT PLS_INTEGER,
        p_total_hefs     OUT PLS_INTEGER,
        p_current_lob    OUT t_lob,
        p_state_hash     OUT VARCHAR2
    )
    IS
        l_context pfc_config_payor_context%ROWTYPE;
        l_hash VARCHAR2(64);
        PROCEDURE add_value(p_value IN VARCHAR2) IS
            l_encoded VARCHAR2(32767);
        BEGIN
            l_encoded := enc(p_value);
            SELECT RAWTOHEX(STANDARD_HASH(l_hash || l_encoded, 'SHA256'))
            INTO l_hash FROM dual;
        END add_value;
    BEGIN
        validate_payor(p_payor_guid);
        validate_lob(p_requested_lob);
        BEGIN
            SELECT * INTO l_context
            FROM pfc_config_payor_context c
            WHERE c.payor_guid = p_payor_guid;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(c_err_lob_required,
                    'Line of Business must be saved before it can be changed.');
        END;
        p_current_lob := l_context.line_of_business;
        pfc_option_registry.get_managed_targets(p_targets);
        sort_targets(p_targets);
        IF p_targets.COUNT = 0 THEN
            RAISE_APPLICATION_ERROR(c_err_unexpected_state,
                'No managed configuration targets are registered.');
        END IF;

        SELECT RAWTOHEX(STANDARD_HASH('PFC_LOB_CHANGE_STATE_V1', 'SHA256'))
        INTO l_hash FROM dual;
        add_value(p_payor_guid);
        add_value(l_context.line_of_business);
        add_value(enc_date(l_context.rec_ent_date));
        add_value(l_context.rec_ent_user);
        add_value(enc_date(l_context.rec_mod_date));
        add_value(l_context.rec_mod_user);
        add_value(p_requested_lob);
        add_value(TO_CHAR(p_targets.COUNT));
        p_affected_count := 0;
        p_total_hers := 0;
        p_total_hefs := 0;

        FOR i IN 1 .. p_targets.COUNT LOOP
            SELECT COUNT(*), NVL(SUM((
                SELECT COUNT(*) FROM hcfa_electronic_fields f
                WHERE f.electronic_rec_guid = h.electronic_rec_guid
            )), 0)
            INTO p_her_counts(i), p_hef_counts(i)
            FROM hcfa_electronic_records h
            WHERE h.payor_guid = p_payor_guid
              AND h.billing_form_code = p_targets(i).billing_form_code
              AND h.record_type_code = p_targets(i).record_type_code;
            IF p_her_counts(i) > 0 THEN p_affected_count := p_affected_count + 1; END IF;
            p_total_hers := p_total_hers + p_her_counts(i);
            p_total_hefs := p_total_hefs + p_hef_counts(i);
            add_value(p_targets(i).billing_form_code);
            add_value(p_targets(i).record_type_code);
            add_value(TO_CHAR(p_her_counts(i)));
            add_value(TO_CHAR(p_hef_counts(i)));

            FOR h IN (
                SELECT * FROM hcfa_electronic_records r
                WHERE r.payor_guid = p_payor_guid
                  AND r.billing_form_code = p_targets(i).billing_form_code
                  AND r.record_type_code = p_targets(i).record_type_code
                ORDER BY r.electronic_rec_guid
            ) LOOP
                add_value(h.electronic_rec_guid); add_value(h.loop_id);
                add_value(h.contiguity_ind); add_value(h.billing_form_code);
                add_value(h.record_name); add_value(h.record_type_code);
                add_value(enc_num(h.record_size)); add_value(h.mandatory_ind);
                add_value(h.req_for_claim_ind); add_value(h.payor_type_guid);
                add_value(h.payor_guid); add_value(h.plan_guid);
                add_value(h.type_of_bill); add_value(h.detail_ind);
                add_value(h.max_number); add_value(h.invoice_ind);
                add_value(h.form_template_guid); add_value(h.carry_forward_ind);
                add_value(enc_num(h.max_carry_forward)); add_value(h.sto_proc_name);
                add_value(h.user_form_template_guid); add_value(h.notes);
                add_value(enc_date(h.rec_ent_date)); add_value(h.rec_ent_user);
                add_value(enc_date(h.rec_mod_date)); add_value(h.rec_mod_user);
                add_value(h.include_record_data_onclaim);
                FOR f IN (
                    SELECT * FROM hcfa_electronic_fields x
                    WHERE x.electronic_rec_guid = h.electronic_rec_guid
                    ORDER BY x.field_number, x.order_num NULLS FIRST,
                        x.position_from, x.field_name, x.record_type_code,
                        x.sto_proc_name NULLS FIRST, x.pic,
                        x.field_spec NULLS FIRST, x.position_thru,
                        x.field_name_desc NULLS FIRST,
                        x.mandatory_ind NULLS FIRST,
                        x.must_fit_length_ind NULLS FIRST,
                        x.repeats NULLS FIRST, x.detail_ind,
                        x.occurs_next NULLS FIRST,
                        x.hard_coded_data NULLS FIRST,
                        x.field_format NULLS FIRST, x.caps_ind NULLS FIRST,
                        x.required_subelement_ind NULLS FIRST,
                        x.rec_ent_date, x.rec_ent_user,
                        x.rec_mod_date NULLS FIRST, x.rec_mod_user NULLS FIRST,
                        x.include_data_onclaim NULLS FIRST
                ) LOOP
                    add_value(f.field_number); add_value(f.electronic_rec_guid);
                    add_value(f.field_name); add_value(f.record_type_code);
                    add_value(f.sto_proc_name); add_value(f.pic);
                    add_value(f.field_spec); add_value(enc_num(f.position_from));
                    add_value(enc_num(f.position_thru)); add_value(f.field_name_desc);
                    add_value(f.mandatory_ind); add_value(f.must_fit_length_ind);
                    add_value(enc_num(f.order_num)); add_value(enc_num(f.repeats));
                    add_value(f.detail_ind); add_value(f.occurs_next);
                    add_value(f.hard_coded_data); add_value(f.field_format);
                    add_value(f.caps_ind); add_value(f.required_subelement_ind);
                    add_value(enc_date(f.rec_ent_date)); add_value(f.rec_ent_user);
                    add_value(enc_date(f.rec_mod_date)); add_value(f.rec_mod_user);
                    add_value(f.include_data_onclaim);
                END LOOP;
            END LOOP;
        END LOOP;
        p_state_hash := UPPER(l_hash);
    END calculate_state;

    PROCEDURE open_target_counts (
        p_targets    IN pfc_option_registry.t_managed_targets,
        p_her_counts IN t_numbers,
        p_hef_counts IN t_numbers,
        p_result     OUT SYS_REFCURSOR
    )
    IS
        l_sql VARCHAR2(32767);
    BEGIN
        FOR i IN 1 .. p_targets.COUNT LOOP
            IF i > 1 THEN l_sql := l_sql || ' UNION ALL '; END IF;
            l_sql := l_sql || 'SELECT ' || TO_CHAR(i) || ' target_order, ''' ||
                REPLACE(p_targets(i).billing_form_code, '''', '''''') ||
                ''' billing_form_code, ''' ||
                REPLACE(p_targets(i).record_type_code, '''', '''''') ||
                ''' record_type_code, ' || TO_CHAR(p_her_counts(i)) ||
                ' her_count, ' || TO_CHAR(p_hef_counts(i)) ||
                ' hef_count FROM dual';
        END LOOP;
        l_sql := l_sql || ' ORDER BY target_order';
        OPEN p_result FOR l_sql;
    END open_target_counts;

    PROCEDURE preview_change (
        p_payor_guid                 IN payors.payor_guid%TYPE,
        p_requested_line_of_business IN pfc_config_payor_context.line_of_business%TYPE,
        p_summary                    OUT SYS_REFCURSOR,
        p_target_counts              OUT SYS_REFCURSOR
    )
    IS
        l_targets pfc_option_registry.t_managed_targets;
        l_hers t_numbers; l_hefs t_numbers;
        l_affected PLS_INTEGER; l_total_hers PLS_INTEGER; l_total_hefs PLS_INTEGER;
        l_current t_lob; l_hash VARCHAR2(64); l_status VARCHAR2(20);
        l_target_count PLS_INTEGER;
    BEGIN
        calculate_state(p_payor_guid, p_requested_line_of_business,
            l_targets, l_hers, l_hefs, l_affected, l_total_hers,
            l_total_hefs, l_current, l_hash);
        l_status := CASE WHEN l_current = p_requested_line_of_business
            THEN 'NO_CHANGE' ELSE 'CHANGES_REQUIRED' END;
        l_target_count := l_targets.COUNT;
        OPEN p_summary FOR
            SELECT l_status status,
                   CASE WHEN l_status = 'CHANGES_REQUIRED' THEN 'Y' ELSE 'N' END changes_required,
                   l_current current_line_of_business,
                   p_requested_line_of_business requested_line_of_business,
                   l_target_count managed_target_count,
                   l_affected affected_managed_target_count,
                   l_total_hers managed_her_count,
                   l_total_hefs managed_hef_count,
                   l_hash preview_state_hash
            FROM dual;
        open_target_counts(l_targets, l_hers, l_hefs, p_target_counts);
    END preview_change;

    PROCEDURE apply_change (
        p_payor_guid                 IN payors.payor_guid%TYPE,
        p_requested_line_of_business IN pfc_config_payor_context.line_of_business%TYPE,
        p_expected_state_hash        IN VARCHAR2,
        p_audit_user                 IN pfc_config_payor_context.rec_ent_user%TYPE,
        p_summary                    OUT SYS_REFCURSOR,
        p_target_counts              OUT SYS_REFCURSOR
    )
    IS
        l_targets pfc_option_registry.t_managed_targets;
        l_hers t_numbers; l_hefs t_numbers;
        l_affected PLS_INTEGER; l_total_hers PLS_INTEGER; l_total_hefs PLS_INTEGER;
        l_current t_lob; l_hash VARCHAR2(64); l_lock_lob t_lob;
        l_remaining PLS_INTEGER; l_savepoint BOOLEAN := FALSE;
        l_target_count PLS_INTEGER;
    BEGIN
        validate_lob(p_requested_line_of_business);
        validate_audit_user(p_audit_user);
        IF TRIM(p_expected_state_hash) IS NULL THEN
            RAISE_APPLICATION_ERROR(c_err_expected_hash,
                'A preview state hash is required.');
        END IF;
        SAVEPOINT pfc_lob_change_start;
        l_savepoint := TRUE;
        BEGIN
            SELECT c.line_of_business INTO l_lock_lob
            FROM pfc_config_payor_context c
            WHERE c.payor_guid = p_payor_guid
            FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                validate_payor(p_payor_guid);
                RAISE_APPLICATION_ERROR(c_err_lob_required,
                    'Line of Business must be saved before it can be changed.');
        END;

        pfc_option_registry.get_managed_targets(l_targets);
        sort_targets(l_targets);
        FOR i IN 1 .. l_targets.COUNT LOOP
            FOR h IN (
                SELECT r.electronic_rec_guid
                FROM hcfa_electronic_records r
                WHERE r.payor_guid = p_payor_guid
                  AND r.billing_form_code = l_targets(i).billing_form_code
                  AND r.record_type_code = l_targets(i).record_type_code
                ORDER BY r.electronic_rec_guid FOR UPDATE
            ) LOOP
                FOR f IN (
                    SELECT x.field_number
                    FROM hcfa_electronic_fields x
                    WHERE x.electronic_rec_guid = h.electronic_rec_guid
                    ORDER BY x.field_number, x.order_num NULLS FIRST,
                             x.position_from FOR UPDATE
                ) LOOP NULL; END LOOP;
            END LOOP;
        END LOOP;

        calculate_state(p_payor_guid, p_requested_line_of_business,
            l_targets, l_hers, l_hefs, l_affected, l_total_hers,
            l_total_hefs, l_current, l_hash);
        l_target_count := l_targets.COUNT;
        IF l_hash <> UPPER(TRIM(p_expected_state_hash)) THEN
            RAISE_APPLICATION_ERROR(c_err_stale_preview,
                'The Line of Business preview is stale.');
        END IF;
        IF l_current = p_requested_line_of_business THEN
            ROLLBACK TO pfc_lob_change_start;
            l_savepoint := FALSE;
            OPEN p_summary FOR SELECT 'NO_CHANGE' status, 'N' changes_required,
                l_current current_line_of_business,
                p_requested_line_of_business requested_line_of_business,
                l_target_count managed_target_count,
                l_affected affected_managed_target_count,
                l_total_hers managed_her_count, l_total_hefs managed_hef_count,
                l_hash preview_state_hash FROM dual;
            open_target_counts(l_targets, l_hers, l_hefs, p_target_counts);
            RETURN;
        END IF;

        FOR i IN 1 .. l_targets.COUNT LOOP
            DELETE FROM hcfa_electronic_fields f
            WHERE EXISTS (
                SELECT 1 FROM hcfa_electronic_records h
                WHERE h.electronic_rec_guid = f.electronic_rec_guid
                  AND h.payor_guid = p_payor_guid
                  AND h.billing_form_code = l_targets(i).billing_form_code
                  AND h.record_type_code = l_targets(i).record_type_code
            );
            DELETE FROM hcfa_electronic_records h
            WHERE h.payor_guid = p_payor_guid
              AND h.billing_form_code = l_targets(i).billing_form_code
              AND h.record_type_code = l_targets(i).record_type_code;
        END LOOP;
        UPDATE pfc_config_payor_context c
        SET c.line_of_business = p_requested_line_of_business,
            c.rec_mod_date = SYSDATE,
            c.rec_mod_user = TRIM(p_audit_user)
        WHERE c.payor_guid = p_payor_guid;

        l_remaining := 0;
        FOR i IN 1 .. l_targets.COUNT LOOP
            SELECT l_remaining + COUNT(*) INTO l_remaining
            FROM hcfa_electronic_records h
            WHERE h.payor_guid = p_payor_guid
              AND h.billing_form_code = l_targets(i).billing_form_code
              AND h.record_type_code = l_targets(i).record_type_code;
        END LOOP;
        IF l_remaining <> 0 THEN
            RAISE_APPLICATION_ERROR(c_err_verification,
                'Managed payor overrides remain after reset.');
        END IF;
        SELECT COUNT(*) INTO l_remaining
        FROM pfc_config_payor_context c
        WHERE c.payor_guid = p_payor_guid
          AND c.line_of_business = p_requested_line_of_business
          AND c.rec_ent_date IS NOT NULL AND c.rec_ent_user IS NOT NULL
          AND c.rec_mod_date IS NOT NULL AND c.rec_mod_user = TRIM(p_audit_user);
        IF l_remaining <> 1 THEN
            RAISE_APPLICATION_ERROR(c_err_verification,
                'Line of Business update verification failed.');
        END IF;

        OPEN p_summary FOR SELECT 'APPLIED' status, 'Y' changes_required,
            l_current current_line_of_business,
            p_requested_line_of_business requested_line_of_business,
            l_target_count managed_target_count,
            l_affected affected_managed_target_count,
            l_total_hers managed_her_count, l_total_hefs managed_hef_count,
            l_hash preview_state_hash FROM dual;
        open_target_counts(l_targets, l_hers, l_hefs, p_target_counts);
    EXCEPTION
        WHEN OTHERS THEN
            IF l_savepoint THEN ROLLBACK TO pfc_lob_change_start; END IF;
            RAISE;
    END apply_change;
END pfc_line_of_business;
/
