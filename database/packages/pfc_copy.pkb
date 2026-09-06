CREATE OR REPLACE PACKAGE BODY pfc_copy AS
    TYPE t_strings IS TABLE OF VARCHAR2(32767) INDEX BY PLS_INTEGER;
    TYPE t_set IS TABLE OF VARCHAR2(36) INDEX BY VARCHAR2(20);
    TYPE t_contexts IS TABLE OF pfc_config_internal.t_pfc_resolution INDEX BY PLS_INTEGER;

    FUNCTION digest(p_text VARCHAR2) RETURN VARCHAR2 IS
        l_hash VARCHAR2(64);
    BEGIN
        SELECT RAWTOHEX(STANDARD_HASH(p_text, 'SHA256')) INTO l_hash FROM dual;
        RETURN l_hash;
    END;

    PROCEDURE feed(p_hash IN OUT VARCHAR2, p_text VARCHAR2) IS
    BEGIN
        p_hash := digest(p_hash || ':' || LENGTHB(p_text) || ':' || p_text);
    END;

    PROCEDURE strip_audit(p_json IN OUT JSON_OBJECT_T) IS
    BEGIN
        p_json.remove('ELECTRONIC_REC_GUID');
        p_json.remove('REC_ENT_DATE'); p_json.remove('REC_ENT_USER');
        p_json.remove('REC_MOD_DATE'); p_json.remove('REC_MOD_USER');
    END;

    FUNCTION json_digest(p_json JSON_OBJECT_T) RETURN VARCHAR2 IS
        l_keys JSON_KEY_LIST:=p_json.get_keys();
        l_temp VARCHAR2(4000);
        l_hash VARCHAR2(64):=digest('SORTED_JSON_OBJECT');
    BEGIN
        IF l_keys.COUNT>1 THEN
            FOR i IN 2..l_keys.COUNT LOOP
                FOR j IN REVERSE 2..i LOOP
                    IF l_keys(j)<l_keys(j-1) THEN
                        l_temp:=l_keys(j); l_keys(j):=l_keys(j-1); l_keys(j-1):=l_temp;
                    END IF;
                END LOOP;
            END LOOP;
        END IF;
        FOR i IN 1..l_keys.COUNT LOOP
            feed(l_hash,l_keys(i)); feed(l_hash,p_json.get(l_keys(i)).to_string());
        END LOOP;
        RETURN l_hash;
    END;

    FUNCTION signature(p_guid VARCHAR2, p_functional BOOLEAN DEFAULT FALSE,
        p_destination VARCHAR2 DEFAULT NULL, p_payor_type VARCHAR2 DEFAULT NULL)
        RETURN VARCHAR2 IS
        l_json JSON_OBJECT_T;
        l_text VARCHAR2(32767);
        l_hash VARCHAR2(64) := digest('HER_HEF_V1');
        l_parts t_strings;
        l_temp VARCHAR2(32767);
    BEGIN
        IF p_guid IS NULL THEN RETURN 'ABSENT'; END IF;
        SELECT JSON_OBJECT(h.* RETURNING VARCHAR2(32767)) INTO l_text
        FROM hcfa_electronic_records h WHERE electronic_rec_guid=p_guid;
        l_json := JSON_OBJECT_T.parse(l_text);
        strip_audit(l_json);
        IF p_destination IS NOT NULL THEN
            l_json.put('PAYOR_GUID', p_destination); l_json.put_null('PLAN_GUID');
            l_json.put('PAYOR_TYPE_GUID', p_payor_type);
            l_json.put_null('CARRY_FORWARD_IND'); l_json.put('INCLUDE_RECORD_DATA_ONCLAIM', 'Y');
            IF NVL(UPPER(TRIM(l_json.get_string('STO_PROC_NAME'))), '#NULL#') <> 'RETURN_1' THEN
                l_json.put('MANDATORY_IND', 'N');
            END IF;
        END IF;
        IF p_functional THEN
            l_json.remove('PAYOR_GUID'); l_json.remove('PLAN_GUID');
            l_json.remove('PAYOR_TYPE_GUID'); l_json.remove('FORM_TEMPLATE_GUID');
            l_json.remove('USER_FORM_TEMPLATE_GUID');
        END IF;
        feed(l_hash, json_digest(l_json));
        FOR f IN (SELECT JSON_OBJECT(f.* RETURNING VARCHAR2(32767)) row_json
                  FROM hcfa_electronic_fields f WHERE electronic_rec_guid=p_guid) LOOP
            l_json := JSON_OBJECT_T.parse(f.row_json); strip_audit(l_json);
            l_parts(l_parts.COUNT+1) := json_digest(l_json);
        END LOOP;
        -- Sort child signatures as a multiset; duplicates and every unmanaged field count.
        IF l_parts.COUNT > 1 THEN
            FOR i IN 2..l_parts.COUNT LOOP
                FOR j IN REVERSE 2..i LOOP
                    IF l_parts(j) < l_parts(j-1) THEN
                        l_temp:=l_parts(j); l_parts(j):=l_parts(j-1); l_parts(j-1):=l_temp;
                    END IF;
                END LOOP;
            END LOOP;
        END IF;
        feed(l_hash, TO_CHAR(l_parts.COUNT));
        IF l_parts.COUNT > 0 THEN
            FOR i IN 1..l_parts.COUNT LOOP feed(l_hash,l_parts(i)); END LOOP;
        END IF;
        RETURN l_hash;
    END;

    FUNCTION effective(p_ctx pfc_config_internal.t_pfc_resolution,
        p_record VARCHAR2, p_generic_only BOOLEAN DEFAULT FALSE) RETURN VARCHAR2 IS
        l_guid VARCHAR2(36); l_level NUMBER; l_type NUMBER;
    BEGIN
        FOR h IN (
            SELECT h.electronic_rec_guid,
                CASE WHEN h.payor_guid IS NOT NULL AND h.plan_guid IS NOT NULL THEN 0
                     WHEN h.payor_guid IS NOT NULL THEN 1
                     WHEN h.user_form_template_guid IS NOT NULL THEN 2
                     WHEN h.form_template_guid IS NOT NULL THEN 3 ELSE 4 END lvl,
                CASE WHEN h.payor_guid IS NULL AND h.payor_type_guid IS NULL THEN 1 ELSE 0 END typ
            FROM hcfa_electronic_records h
            WHERE h.billing_form_code=p_ctx.billing_form_code AND h.record_type_code=p_record
              AND h.type_of_bill IS NULL
              AND (h.payor_guid IS NULL OR h.payor_guid=p_ctx.payor_guid)
              AND (h.plan_guid IS NULL OR (h.payor_guid=p_ctx.payor_guid AND h.plan_guid=p_ctx.plan_guid))
              AND (h.payor_type_guid IS NULL OR h.payor_type_guid=p_ctx.payor_type_guid)
              AND (h.form_template_guid IS NULL OR h.form_template_guid=p_ctx.form_template_guid)
              AND (h.user_form_template_guid IS NULL OR h.user_form_template_guid=p_ctx.user_form_template_guid)
            ORDER BY lvl,typ,h.electronic_rec_guid
        ) LOOP
            IF NOT p_generic_only OR h.lvl >= 2 THEN
                IF l_guid IS NULL THEN
                    l_guid:=h.electronic_rec_guid; l_level:=h.lvl; l_type:=h.typ;
                ELSIF h.lvl=l_level AND h.typ=l_type THEN
                    RAISE_APPLICATION_ERROR(-20104,'Multiple applicable claim records make copying ambiguous.');
                ELSE EXIT;
                END IF;
            END IF;
        END LOOP;
        RETURN l_guid;
    END;

    PROCEDURE resolve_copy_context(p_payor VARCHAR2,p_plan VARCHAR2,
        p_context OUT pfc_config_internal.t_pfc_resolution) IS
        l_count NUMBER:=0;
        l_winner VARCHAR2(36);
    BEGIN
        -- Do not silently select an older supported form behind a newer different form.
        FOR candidate IN (
            SELECT * FROM (
                SELECT p.*,DENSE_RANK() OVER(ORDER BY rec_ent_date DESC NULLS FIRST) winner_rank
                FROM pfc p WHERE payor_guid=p_payor
                  AND (plan_guid=p_plan OR (plan_guid IS NULL AND p_plan IS NULL))
                  AND cpd_end_date>SYSDATE AND default_media_type='E' AND type_of_bill IS NULL
            ) WHERE winner_rank=1
        ) LOOP
            l_count:=l_count+1; l_winner:=candidate.pfc_guid;
            IF candidate.rec_ent_date IS NULL THEN
                RAISE_APPLICATION_ERROR(-20104,'A current configuration is missing its entry date.');
            END IF;
            IF candidate.billing_form_code<>'837I_5010' THEN
                RAISE_APPLICATION_ERROR(-20103,'Source and destination must use the supported matching billing form.');
            END IF;
        END LOOP;
        IF l_count<>1 THEN RAISE_APPLICATION_ERROR(-20104,'A required current configuration is missing or ambiguous.'); END IF;
        pfc_config_internal.resolve_pfc(p_payor,p_plan,p_context);
        IF p_context.pfc_guid<>l_winner THEN RAISE_APPLICATION_ERROR(-20104,'Configuration selection is inconsistent.'); END IF;
    END;

    PROCEDURE run_copy(p_source_payor VARCHAR2, p_source_plan VARCHAR2,
        p_destination_payor VARCHAR2, p_mode VARCHAR2, p_audit_user VARCHAR2,
        p_expected_hash VARCHAR2, p_result OUT CLOB) IS
        l_source pfc_config_internal.t_pfc_resolution;
        l_verified pfc_config_internal.t_pfc_resolution;
        l_contexts t_contexts;
        l_desired t_set; l_kept t_set;
        l_source_lob VARCHAR2(20); l_dest_lob VARCHAR2(20);
        l_hash VARCHAR2(64) := digest('PFC_COPY_V1');
        l_count NUMBER; l_scope_count NUMBER;
        l_guid VARCHAR2(36); l_actual VARCHAR2(36); l_key VARCHAR2(20);
        l_her hcfa_electronic_records%ROWTYPE;
        l_hef hcfa_electronic_fields%ROWTYPE;
        l_add NUMBER:=0; l_keep NUMBER:=0; l_remove NUMBER:=0; l_plan_remove NUMBER:=0;
        l_hef_add NUMBER:=0; l_hef_remove NUMBER:=0; l_template_updates NUMBER:=0;
        l_normalized NUMBER:=0;
        l_json JSON_OBJECT_T:=JSON_OBJECT_T();
        l_context_json JSON_ARRAY_T:=JSON_ARRAY_T();
        l_changes JSON_ARRAY_T:=JSON_ARRAY_T();
        l_item JSON_OBJECT_T;
        l_mode VARCHAR2(10):=UPPER(TRIM(p_mode));
        l_entry_name VARCHAR2(128);
        l_form_name VARCHAR2(128); l_user_name VARCHAR2(128);
        l_old_form_name VARCHAR2(128); l_old_user_name VARCHAR2(128);
        l_savepoint BOOLEAN:=FALSE;

        PROCEDURE add_change(p_label VARCHAR2,p_action VARCHAR2,p_level VARCHAR2,p_record VARCHAR2) IS
        BEGIN
            l_item:=JSON_OBJECT_T(); l_item.put('label',p_label); l_item.put('action',p_action);
            l_item.put('level',p_level); l_item.put('record_type',p_record); l_changes.append(l_item);
        END;

        PROCEDURE assert_effective(p_actual BOOLEAN) IS
            l_ctx pfc_config_internal.t_pfc_resolution;
            l_src VARCHAR2(36); l_dst VARCHAR2(36);
            l_src_sig VARCHAR2(64); l_dst_sig VARCHAR2(64);
            l_check hcfa_electronic_records%ROWTYPE;
        BEGIN
            FOR record_row IN (SELECT DISTINCT record_type_code FROM hcfa_electronic_records
                               WHERE billing_form_code=l_source.billing_form_code ORDER BY record_type_code) LOOP
                l_src:=effective(l_source,record_row.record_type_code);
                IF l_src IS NOT NULL AND NOT l_desired.EXISTS(record_row.record_type_code) THEN
                    SELECT * INTO l_check FROM hcfa_electronic_records WHERE electronic_rec_guid=l_src;
                    pfc_config_internal.assert_inherited_her_safe(l_check);
                END IF;
                IF l_desired.EXISTS(record_row.record_type_code) THEN
                    l_src_sig:=signature(l_src,TRUE,p_destination_payor,l_contexts(1).payor_type_guid);
                ELSE l_src_sig:=signature(l_src,TRUE);
                END IF;
                FOR i IN 1..l_contexts.COUNT LOOP
                    l_ctx:=l_contexts(i);
                    IF p_actual THEN
                        l_dst:=effective(l_ctx,record_row.record_type_code);
                        l_dst_sig:=signature(l_dst,TRUE);
                    ELSE
                        l_ctx.form_template_guid:=l_source.form_template_guid;
                        l_ctx.user_form_template_guid:=l_source.user_form_template_guid;
                        IF l_desired.EXISTS(record_row.record_type_code) THEN
                            l_dst_sig:=signature(l_desired(record_row.record_type_code),TRUE,
                                p_destination_payor,l_ctx.payor_type_guid);
                        ELSE
                            l_dst:=effective(l_ctx,record_row.record_type_code,TRUE);
                            l_dst_sig:=signature(l_dst,TRUE);
                        END IF;
                    END IF;
                    IF l_src_sig<>l_dst_sig THEN
                        RAISE_APPLICATION_ERROR(-20105,'The destination cannot inherit the same complete configuration as the source.');
                    END IF;
                END LOOP;
            END LOOP;
        END;

        PROCEDURE hash_rows(p_sql VARCHAR2) IS
            l_rows SYS_REFCURSOR; l_text VARCHAR2(32767); l_parts t_strings; l_temp VARCHAR2(32767);
        BEGIN
            OPEN l_rows FOR p_sql USING p_source_payor,p_destination_payor;
            LOOP FETCH l_rows INTO l_text; EXIT WHEN l_rows%NOTFOUND;
                l_parts(l_parts.COUNT+1):=digest(l_text);
            END LOOP;
            CLOSE l_rows;
            IF l_parts.COUNT>1 THEN
                FOR i IN 2..l_parts.COUNT LOOP
                    FOR j IN REVERSE 2..i LOOP
                        IF l_parts(j)<l_parts(j-1) THEN
                            l_temp:=l_parts(j); l_parts(j):=l_parts(j-1); l_parts(j-1):=l_temp;
                        END IF;
                    END LOOP;
                END LOOP;
            END IF;
            feed(l_hash,TO_CHAR(l_parts.COUNT));
            IF l_parts.COUNT>0 THEN
                FOR i IN 1..l_parts.COUNT LOOP feed(l_hash,l_parts(i)); END LOOP;
            END IF;
        END;

        PROCEDURE prepare_copy_contexts IS
        BEGIN
            resolve_copy_context(p_source_payor,p_source_plan,l_source);
            SELECT CASE WHEN l_source.form_template_guid IS NULL THEN 'None' ELSE
                NVL((SELECT MAX(template_name) FROM pfc_config_form_templates WHERE form_template_guid=l_source.form_template_guid),'Assigned form template') END,
                CASE WHEN l_source.user_form_template_guid IS NULL THEN 'None' ELSE
                NVL((SELECT MAX(template_name) FROM pfc_config_user_templates WHERE user_form_template_guid=l_source.user_form_template_guid),'Assigned user template') END
            INTO l_form_name,l_user_name FROM dual;
            pfc_line_of_business.require_defined(p_source_payor);
            pfc_line_of_business.require_defined(p_destination_payor);
            SELECT line_of_business INTO l_source_lob FROM pfc_config_payor_context WHERE payor_guid=p_source_payor;
            SELECT line_of_business INTO l_dest_lob FROM pfc_config_payor_context WHERE payor_guid=p_destination_payor;
            IF l_source_lob<>l_dest_lob THEN RAISE_APPLICATION_ERROR(-20102,'Source and destination Line of Business must match.'); END IF;

            FOR context_row IN (
                SELECT CAST(NULL AS VARCHAR2(36)) plan_guid FROM dual
                UNION SELECT plan_guid FROM pfc WHERE payor_guid=p_destination_payor
                  AND cpd_end_date>SYSDATE AND default_media_type='E' AND type_of_bill IS NULL
                UNION SELECT plan_guid FROM hcfa_electronic_records WHERE payor_guid=p_destination_payor
                  AND plan_guid IS NOT NULL
                ORDER BY plan_guid NULLS FIRST
            ) LOOP
                l_count:=l_contexts.COUNT+1;
                resolve_copy_context(p_destination_payor,context_row.plan_guid,l_contexts(l_count));
                -- Also inspect eligible PFC candidates without the customization resolver's billing filter.
                FOR winner IN (SELECT billing_form_code,rec_ent_date FROM pfc
                    WHERE payor_guid=p_destination_payor
                      AND (plan_guid=context_row.plan_guid OR (plan_guid IS NULL AND context_row.plan_guid IS NULL))
                      AND cpd_end_date>SYSDATE AND default_media_type='E' AND type_of_bill IS NULL
                    ORDER BY rec_ent_date DESC NULLS FIRST FETCH FIRST 1 ROW ONLY) LOOP
                    IF winner.billing_form_code<>l_source.billing_form_code THEN
                        RAISE_APPLICATION_ERROR(-20103,'Every destination billing form must match the source.');
                    END IF;
                END LOOP;
                IF l_contexts(l_count).billing_form_code<>l_source.billing_form_code THEN
                    RAISE_APPLICATION_ERROR(-20103,'Every destination billing form must match the source.');
                END IF;
                l_item:=JSON_OBJECT_T(); l_item.put('pfc_guid',l_contexts(l_count).pfc_guid);
                l_item.put('plan_guid',context_row.plan_guid);
                l_entry_name:='Payor-level settings';
                IF context_row.plan_guid IS NOT NULL THEN
                    SELECT NVL(plan_name,'Plan settings') INTO l_entry_name FROM pfc_config_plans WHERE plan_guid=context_row.plan_guid;
                END IF;
                l_item.put('label',l_entry_name);
                SELECT CASE WHEN l_contexts(l_count).form_template_guid IS NULL THEN 'None' ELSE
                    NVL((SELECT MAX(template_name) FROM pfc_config_form_templates WHERE form_template_guid=l_contexts(l_count).form_template_guid),'Assigned form template') END,
                    CASE WHEN l_contexts(l_count).user_form_template_guid IS NULL THEN 'None' ELSE
                    NVL((SELECT MAX(template_name) FROM pfc_config_user_templates WHERE user_form_template_guid=l_contexts(l_count).user_form_template_guid),'Assigned user template') END
                INTO l_old_form_name,l_old_user_name FROM dual;
                l_item.put('form_template_before',l_old_form_name); l_item.put('user_template_before',l_old_user_name);
                IF NVL(l_contexts(l_count).form_template_guid,'#')<>NVL(l_source.form_template_guid,'#')
                    OR NVL(l_contexts(l_count).user_form_template_guid,'#')<>NVL(l_source.user_form_template_guid,'#') THEN
                    l_template_updates:=l_template_updates+1; l_item.put('templates_changed',TRUE);
                ELSE l_item.put('templates_changed',FALSE);
                END IF;
                l_context_json.append(l_item);
            END LOOP;

            SELECT COUNT(*) INTO l_count FROM hcfa_electronic_records
            WHERE (payor_guid=p_destination_payor AND (type_of_bill IS NOT NULL OR billing_form_code<>l_source.billing_form_code))
               OR (payor_guid=p_source_payor AND billing_form_code=l_source.billing_form_code AND type_of_bill IS NOT NULL
                   AND (plan_guid IS NULL OR plan_guid=p_source_plan));
            IF l_count>0 THEN RAISE_APPLICATION_ERROR(-20104,'Unsupported billing-form or bill-type records require review before copying.'); END IF;
        END prepare_copy_contexts;

        PROCEDURE plan_destination_settings IS
        BEGIN
            -- Build the combined applicable override set. Plan wins as a complete HER/HEF unit.
            FOR record_row IN (SELECT DISTINCT record_type_code FROM hcfa_electronic_records
                WHERE payor_guid=p_source_payor AND billing_form_code=l_source.billing_form_code
                  AND (plan_guid IS NULL OR plan_guid=p_source_plan) ORDER BY record_type_code) LOOP
                l_guid:=effective(l_source,record_row.record_type_code);
                IF l_guid IS NOT NULL THEN
                    SELECT * INTO l_her FROM hcfa_electronic_records WHERE electronic_rec_guid=l_guid;
                    IF l_her.payor_guid=p_source_payor THEN l_desired(record_row.record_type_code):=l_guid; END IF;
                END IF;
            END LOOP;
            assert_effective(FALSE);

            -- Keep exactly one canonical matching destination row; remove duplicates/stale/extras.
            FOR h IN (SELECT * FROM hcfa_electronic_records WHERE payor_guid=p_destination_payor ORDER BY electronic_rec_guid) LOOP
                IF h.plan_guid IS NULL AND l_desired.EXISTS(h.record_type_code) AND NOT l_kept.EXISTS(h.record_type_code)
                  AND signature(h.electronic_rec_guid)=signature(l_desired(h.record_type_code),FALSE,p_destination_payor,l_contexts(1).payor_type_guid) THEN
                    l_kept(h.record_type_code):=h.electronic_rec_guid; l_keep:=l_keep+1;
                    add_change(h.record_name,'KEEP','Payor',h.record_type_code);
                ELSE
                    l_remove:=l_remove+1;
                    IF h.plan_guid IS NOT NULL THEN l_plan_remove:=l_plan_remove+1; END IF;
                    SELECT COUNT(*) INTO l_count FROM hcfa_electronic_fields WHERE electronic_rec_guid=h.electronic_rec_guid;
                    l_hef_remove:=l_hef_remove+l_count;
                    add_change(h.record_name,'REMOVE',CASE WHEN h.plan_guid IS NULL THEN 'Payor' ELSE 'Plan' END,h.record_type_code);
                END IF;
            END LOOP;
            l_key:=l_desired.FIRST;
            WHILE l_key IS NOT NULL LOOP
                IF NOT l_kept.EXISTS(l_key) THEN
                    l_add:=l_add+1;
                    SELECT * INTO l_her FROM hcfa_electronic_records WHERE electronic_rec_guid=l_desired(l_key);
                    IF (NVL(UPPER(TRIM(l_her.sto_proc_name)),'#')<>'RETURN_1' AND NVL(l_her.mandatory_ind,'#')<>'N')
                      OR l_her.carry_forward_ind IS NOT NULL OR NVL(l_her.include_record_data_onclaim,'#')<>'Y' THEN
                        l_normalized:=l_normalized+1;
                    END IF;
                    SELECT COUNT(*) INTO l_count FROM hcfa_electronic_fields WHERE electronic_rec_guid=l_desired(l_key);
                    l_hef_add:=l_hef_add+l_count;
                    add_change(l_her.record_name,'COPY',CASE WHEN l_her.plan_guid IS NULL THEN 'Source payor' ELSE 'Source plan' END,l_key);
                END IF;
                l_key:=l_desired.NEXT(l_key);
            END LOOP;
        END plan_destination_settings;

        PROCEDURE hash_copy_state IS
        BEGIN
            feed(l_hash,p_source_payor); feed(l_hash,p_source_plan); feed(l_hash,p_destination_payor);
            hash_rows('SELECT JSON_OBJECT(p.* RETURNING VARCHAR2(32767)) FROM payors p WHERE payor_guid IN (:s,:d)');
            hash_rows('SELECT JSON_OBJECT(p.* RETURNING VARCHAR2(32767)) FROM pfc p WHERE payor_guid IN (:s,:d)');
            hash_rows('SELECT JSON_OBJECT(p.* RETURNING VARCHAR2(32767)) FROM pfc_config_plans p WHERE payor_guid IN (:s,:d)');
            hash_rows('SELECT JSON_OBJECT(p.* RETURNING VARCHAR2(32767)) FROM pfc_config_payor_context p WHERE payor_guid IN (:s,:d)');
            hash_rows('SELECT JSON_OBJECT(h.* RETURNING VARCHAR2(32767)) FROM hcfa_electronic_records h WHERE payor_guid IS NULL OR payor_guid IN (:s,:d)');
            hash_rows('SELECT JSON_OBJECT(f.* RETURNING VARCHAR2(32767)) FROM hcfa_electronic_fields f WHERE electronic_rec_guid IN (SELECT electronic_rec_guid FROM hcfa_electronic_records WHERE payor_guid IS NULL OR payor_guid IN (:s,:d))');
            -- Include resolution outcomes, since eligibility can change with time alone.
            feed(l_hash,l_source.pfc_guid);
            FOR i IN 1..l_contexts.COUNT LOOP feed(l_hash,l_contexts(i).pfc_guid); END LOOP;
        END hash_copy_state;

        PROCEDURE apply_destination_changes IS
        BEGIN
            FOR h IN (SELECT electronic_rec_guid,record_type_code FROM hcfa_electronic_records WHERE payor_guid=p_destination_payor) LOOP
                IF NOT l_kept.EXISTS(h.record_type_code) OR l_kept(h.record_type_code)<>h.electronic_rec_guid THEN
                    DELETE FROM hcfa_electronic_fields WHERE electronic_rec_guid=h.electronic_rec_guid;
                    DELETE FROM hcfa_electronic_records WHERE electronic_rec_guid=h.electronic_rec_guid;
                END IF;
            END LOOP;
            FOR i IN 1..l_contexts.COUNT LOOP
                IF NVL(l_contexts(i).form_template_guid,'#')<>NVL(l_source.form_template_guid,'#')
                  OR NVL(l_contexts(i).user_form_template_guid,'#')<>NVL(l_source.user_form_template_guid,'#') THEN
                    UPDATE pfc SET form_template_guid=l_source.form_template_guid,
                        user_form_template_guid=l_source.user_form_template_guid,
                        rec_mod_date=SYSDATE,rec_mod_user=p_audit_user WHERE pfc_guid=l_contexts(i).pfc_guid;
                END IF;
                l_contexts(i).form_template_guid:=l_source.form_template_guid;
                l_contexts(i).user_form_template_guid:=l_source.user_form_template_guid;
            END LOOP;
            l_key:=l_desired.FIRST;
            WHILE l_key IS NOT NULL LOOP
                IF NOT l_kept.EXISTS(l_key) THEN
                    SELECT * INTO l_her FROM hcfa_electronic_records WHERE electronic_rec_guid=l_desired(l_key);
                    l_guid:=RAWTOHEX(SYS_GUID()); l_her.electronic_rec_guid:=l_guid;
                    l_her.payor_guid:=p_destination_payor; l_her.plan_guid:=NULL;
                    l_her.payor_type_guid:=l_contexts(1).payor_type_guid;
                    l_her.carry_forward_ind:=NULL; l_her.include_record_data_onclaim:='Y';
                    pfc_config_internal.apply_her_safety_invariants(l_her);
                    l_her.rec_ent_date:=SYSDATE; l_her.rec_ent_user:=p_audit_user;
                    l_her.rec_mod_date:=NULL; l_her.rec_mod_user:=NULL;
                    INSERT INTO hcfa_electronic_records VALUES l_her;
                    FOR f IN (SELECT * FROM hcfa_electronic_fields WHERE electronic_rec_guid=l_desired(l_key)) LOOP
                        l_hef:=f; l_hef.electronic_rec_guid:=l_guid;
                        l_hef.rec_ent_date:=SYSDATE; l_hef.rec_ent_user:=p_audit_user;
                        l_hef.rec_mod_date:=NULL; l_hef.rec_mod_user:=NULL;
                        INSERT INTO hcfa_electronic_fields VALUES l_hef;
                    END LOOP;
                END IF;
                l_key:=l_desired.NEXT(l_key);
            END LOOP;
        END apply_destination_changes;

        PROCEDURE verify_destination_changes IS
        BEGIN
            SELECT COUNT(*) INTO l_count FROM hcfa_electronic_records WHERE payor_guid=p_destination_payor;
            IF l_count<>l_desired.COUNT THEN RAISE_APPLICATION_ERROR(-20107,'Copy verification failed.'); END IF;
            l_key:=l_desired.FIRST;
            WHILE l_key IS NOT NULL LOOP
                SELECT electronic_rec_guid INTO l_guid FROM hcfa_electronic_records
                WHERE payor_guid=p_destination_payor AND plan_guid IS NULL AND record_type_code=l_key;
                IF signature(l_guid)<>signature(l_desired(l_key),FALSE,p_destination_payor,l_contexts(1).payor_type_guid) THEN
                    RAISE_APPLICATION_ERROR(-20107,'Complete copied record verification failed.');
                END IF;
                l_key:=l_desired.NEXT(l_key);
            END LOOP;
            assert_effective(TRUE);
            FOR i IN 1..l_contexts.COUNT LOOP
                resolve_copy_context(p_destination_payor,l_contexts(i).plan_guid,l_verified);
                IF l_verified.pfc_guid<>l_contexts(i).pfc_guid
                   OR NVL(l_verified.form_template_guid,'#')<>NVL(l_source.form_template_guid,'#')
                   OR NVL(l_verified.user_form_template_guid,'#')<>NVL(l_source.user_form_template_guid,'#') THEN
                    RAISE_APPLICATION_ERROR(-20107,'Destination template verification failed.');
                END IF;
            END LOOP;
            SELECT COUNT(DISTINCT NVL(plan_guid,'#')) INTO l_count FROM pfc
            WHERE payor_guid=p_destination_payor AND cpd_end_date>SYSDATE
              AND default_media_type='E' AND type_of_bill IS NULL;
            IF l_count<>l_contexts.COUNT THEN RAISE_APPLICATION_ERROR(-20107,'Destination context verification failed.'); END IF;
        END verify_destination_changes;

        PROCEDURE build_copy_result IS
        BEGIN
            l_json.put('status',CASE WHEN l_mode='APPLY' THEN 'APPLIED'
                WHEN l_add+l_remove+l_template_updates=0 THEN 'NO_CHANGE' ELSE 'READY' END);
            l_json.put('state_hash',l_hash); l_json.put('source_pfc_guid',l_source.pfc_guid);
            l_json.put('billing_form_code',l_source.billing_form_code); l_json.put('line_of_business',l_source_lob);
            l_json.put('source_form_template',l_form_name); l_json.put('source_user_template',l_user_name);
            l_json.put('records_copied',l_add); l_json.put('records_kept',l_keep);
            l_json.put('records_removed',l_remove); l_json.put('plan_records_removed',l_plan_remove);
            l_json.put('fields_copied',l_hef_add); l_json.put('fields_removed',l_hef_remove);
            l_json.put('records_normalized',l_normalized);
            l_json.put('template_contexts_updated',l_template_updates);
            l_json.put('contexts',l_context_json); l_json.put('changes',l_changes);
            p_result:=l_json.to_clob();
        END build_copy_result;

    BEGIN
        IF l_mode IS NULL OR l_mode NOT IN ('PREVIEW','APPLY') OR TRIM(p_audit_user) IS NULL THEN
            RAISE_APPLICATION_ERROR(-20100,'A valid copy operation and audit identity are required.');
        END IF;
        IF p_source_payor=p_destination_payor THEN
            RAISE_APPLICATION_ERROR(-20101,'Choose a different destination payor.');
        END IF;
        IF l_mode='APPLY' THEN
            SAVEPOINT pfc_copy_start;
            l_savepoint:=TRUE;
            -- Coarse, brief locks protect generic/template reads and all destination contexts.
            -- NOWAIT fails safely instead of holding a request behind another editor.
            FOR p IN (SELECT payor_guid FROM payors WHERE payor_guid IN (p_source_payor,p_destination_payor)
                      ORDER BY payor_guid FOR UPDATE NOWAIT) LOOP NULL; END LOOP;
            LOCK TABLE pfc IN SHARE ROW EXCLUSIVE MODE NOWAIT;
            LOCK TABLE pfc_config_plans IN SHARE ROW EXCLUSIVE MODE NOWAIT;
            LOCK TABLE pfc_config_payor_context IN SHARE ROW EXCLUSIVE MODE NOWAIT;
            LOCK TABLE hcfa_electronic_records IN SHARE ROW EXCLUSIVE MODE NOWAIT;
            LOCK TABLE hcfa_electronic_fields IN SHARE ROW EXCLUSIVE MODE NOWAIT;
        END IF;
        prepare_copy_contexts;
        plan_destination_settings;
        hash_copy_state;

        IF l_mode='APPLY' THEN
            IF p_expected_hash IS NULL OR p_expected_hash<>l_hash THEN
                RAISE_APPLICATION_ERROR(-20106,'The copy preview is stale. Run Preview again.');
            END IF;
            apply_destination_changes;
            verify_destination_changes;
        END IF;
        build_copy_result;
    EXCEPTION WHEN OTHERS THEN
        IF l_savepoint THEN ROLLBACK TO pfc_copy_start; END IF;
        RAISE;
    END;
END pfc_copy;
/
