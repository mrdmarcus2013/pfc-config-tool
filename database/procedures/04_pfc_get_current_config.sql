/*
 * Resolve one supported field's effective configuration without DML.
 * Source/PFC selection is delegated to the authoritative shared resolver.
 */
CREATE OR REPLACE PROCEDURE pfc_get_current_config (
    p_payor_guid  IN pfc.payor_guid%TYPE,
    p_plan_guid   IN pfc.plan_guid%TYPE DEFAULT NULL,
    p_field_number IN VARCHAR2,
    p_result      OUT SYS_REFCURSOR
)
AUTHID DEFINER
IS
    c_err_current_unsupported CONSTANT PLS_INTEGER := -20041;
    c_err_unsupported_field   CONSTANT PLS_INTEGER := -20042;

    TYPE t_effective_record IS RECORD (
        her_guid VARCHAR2(36),
        pfc_guid       pfc.pfc_guid%TYPE,
        her_sto_proc   hcfa_electronic_records.sto_proc_name%TYPE,
        her_mandatory  hcfa_electronic_records.mandatory_ind%TYPE,
        hef_sto_proc   hcfa_electronic_fields.sto_proc_name%TYPE,
        hef_hard_code  hcfa_electronic_fields.hard_coded_data%TYPE
    );

    l_owners VARCHAR2(4000);
    l_field_number VARCHAR2(10) := TRIM(p_field_number);
    l_pfc_guid pfc.pfc_guid%TYPE;
    l_option_code VARCHAR2(100);
    l_capability VARCHAR2(40);
    l_mode VARCHAR2(20);
    l_report_address VARCHAR2(1);
    l_enabled VARCHAR2(1);
    l_taxonomy_code VARCHAR2(10);
    l_canonical VARCHAR2(1);
    l_prv t_effective_record;
    l_nm1 t_effective_record;
    l_n3 t_effective_record;
    l_n4 t_effective_record;

    PROCEDURE resolve_effective_record (
        p_record_type_code IN hcfa_electronic_records.record_type_code%TYPE,
        p_managed_field_name IN hcfa_electronic_fields.field_name%TYPE,
        p_effective OUT t_effective_record
    )
    IS
        l_results SYS_REFCURSOR;
        l_row pfc_config_internal.t_resolved_her_hef_row;
        l_source_guid hcfa_electronic_records.electronic_rec_guid%TYPE;
        l_source_her_proc hcfa_electronic_records.sto_proc_name%TYPE;
        l_source_hef_proc hcfa_electronic_fields.sto_proc_name%TYPE;
        l_source_hard_code hcfa_electronic_fields.hard_coded_data%TYPE;
        l_source_field_count PLS_INTEGER := 0;
        l_payor_guid hcfa_electronic_records.electronic_rec_guid%TYPE;
        l_payor_her_proc hcfa_electronic_records.sto_proc_name%TYPE;
        l_payor_hef_proc hcfa_electronic_fields.sto_proc_name%TYPE;
        l_payor_hard_code hcfa_electronic_fields.hard_coded_data%TYPE;
        l_payor_field_count PLS_INTEGER := 0;
        l_payor_count PLS_INTEGER := 0;
        l_row_count PLS_INTEGER := 0;
    BEGIN
        pfc_resolve_her_hef(
            p_payor_guid => p_payor_guid,
            p_plan_guid => p_plan_guid,
            p_record_type_code => p_record_type_code,
            p_results => l_results
        );

        LOOP
            FETCH l_results INTO l_row;
            EXIT WHEN l_results%NOTFOUND;
            l_row_count := l_row_count + 1;

            IF p_effective.pfc_guid IS NULL THEN
                p_effective.pfc_guid := l_row.pfc_guid;
            ELSIF p_effective.pfc_guid <> l_row.pfc_guid THEN
                RAISE_APPLICATION_ERROR(
                    c_err_current_unsupported,
                    'Current-state rows resolved to inconsistent PFC contexts.'
                );
            END IF;

            IF l_row.is_clone_source = 'Y' THEN
                IF l_source_guid IS NULL THEN
                    l_source_guid := l_row.electronic_rec_guid;
                    l_source_her_proc := l_row.her_sto_proc_name;
                ELSIF l_source_guid <> l_row.electronic_rec_guid THEN
                    RAISE_APPLICATION_ERROR(
                        c_err_current_unsupported,
                        'Current-state source rows are inconsistent.'
                    );
                END IF;
                IF p_managed_field_name IS NOT NULL
                   AND l_row.field_name = p_managed_field_name THEN
                    l_source_field_count := l_source_field_count + 1;
                    l_source_hef_proc := l_row.hef_sto_proc_name;
                    l_source_hard_code := l_row.hef_hard_coded_data;
                END IF;
            END IF;

            IF l_row.her_scope_code = 'PAYOR_SPECIFIC' THEN
                IF l_payor_guid IS NULL THEN
                    l_payor_guid := l_row.electronic_rec_guid;
                    l_payor_count := 1;
                    l_payor_her_proc := l_row.her_sto_proc_name;
                ELSIF l_payor_guid <> l_row.electronic_rec_guid THEN
                    l_payor_count := l_payor_count + 1;
                    l_payor_guid := l_row.electronic_rec_guid;
                END IF;
                IF p_managed_field_name IS NOT NULL
                   AND l_row.field_name = p_managed_field_name THEN
                    l_payor_field_count := l_payor_field_count + 1;
                    l_payor_hef_proc := l_row.hef_sto_proc_name;
                    l_payor_hard_code := l_row.hef_hard_coded_data;
                END IF;
            END IF;
        END LOOP;
        CLOSE l_results;

        IF l_row_count = 0 OR l_source_guid IS NULL THEN
            RAISE_APPLICATION_ERROR(
                c_err_current_unsupported,
                'Current-state resolution returned no authoritative source.'
            );
        END IF;
        IF l_payor_count > 1 THEN
            RAISE_APPLICATION_ERROR(
                c_err_current_unsupported,
                'Multiple payor overrides make the effective state ambiguous.'
            );
        END IF;

        IF l_payor_count = 1 THEN
            p_effective.her_guid := l_payor_guid;
            p_effective.her_sto_proc := l_payor_her_proc;
            SELECT h.mandatory_ind INTO p_effective.her_mandatory
            FROM hcfa_electronic_records h
            WHERE h.electronic_rec_guid = l_payor_guid;
            p_effective.hef_sto_proc := l_payor_hef_proc;
            p_effective.hef_hard_code := l_payor_hard_code;
            IF p_managed_field_name IS NOT NULL AND l_payor_field_count <> 1 THEN
                RAISE_APPLICATION_ERROR(
                    c_err_current_unsupported,
                    'The payor override has an unsupported managed-field state.'
                );
            END IF;
        ELSE
            p_effective.her_guid := l_source_guid;
            p_effective.her_sto_proc := l_source_her_proc;
            SELECT h.mandatory_ind INTO p_effective.her_mandatory
            FROM hcfa_electronic_records h
            WHERE h.electronic_rec_guid = l_source_guid;
            p_effective.hef_sto_proc := l_source_hef_proc;
            p_effective.hef_hard_code := l_source_hard_code;
            IF p_managed_field_name IS NOT NULL AND l_source_field_count <> 1 THEN
                RAISE_APPLICATION_ERROR(
                    c_err_current_unsupported,
                    'The inherited source has an unsupported managed-field state.'
                );
            END IF;
        END IF;
        IF NOT pfc_config_internal.her_satisfies_safety_invariants(
            p_effective.her_sto_proc, p_effective.her_mandatory
        ) THEN
            RAISE_APPLICATION_ERROR(
                CASE WHEN l_payor_count = 0
                    THEN pfc_config_internal.c_err_unsafe_source
                    ELSE c_err_current_unsupported END,
                CASE WHEN l_payor_count = 0
                    THEN 'The inherited claim configuration violates the mandatory-record rule.'
                    ELSE 'The payor override violates the mandatory-record rule.' END
            );
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF l_results%ISOPEN THEN
                CLOSE l_results;
            END IF;
            RAISE;
    END resolve_effective_record;

    PROCEDURE retain_pfc (p_value IN pfc.pfc_guid%TYPE)
    IS
    BEGIN
        IF l_pfc_guid IS NULL THEN
            l_pfc_guid := p_value;
        ELSIF l_pfc_guid <> p_value THEN
            RAISE_APPLICATION_ERROR(
                c_err_current_unsupported,
                'Current-state targets resolved to inconsistent PFC contexts.'
            );
        END IF;
    END retain_pfc;
BEGIN
    IF l_field_number = '81' THEN
        resolve_effective_record('B2000A0030PRV080', 'PRV03', l_prv);
        retain_pfc(l_prv.pfc_guid);
        l_capability := 'provider-taxonomy';

        CASE UPPER(TRIM(l_prv.her_sto_proc))
            WHEN 'RETURN_1' THEN
                l_option_code := 'PROVIDER_TAXONOMY_ON';
                l_enabled := 'Y';
            WHEN 'RETURN_0' THEN
                l_option_code := 'PROVIDER_TAXONOMY_OFF';
                l_enabled := 'N';
            ELSE
                RAISE_APPLICATION_ERROR(
                    c_err_current_unsupported,
                    'Provider Taxonomy has an unsupported effective state.'
                );
        END CASE;
        l_canonical := CASE
            WHEN l_prv.hef_sto_proc = 'G_PROVIDER_TAXONOMY_CODE'
             AND l_prv.hef_hard_code IS NULL THEN 'Y'
            ELSE 'N'
        END;
        IF l_enabled = 'Y' AND l_canonical = 'N' THEN
            IF l_prv.hef_sto_proc IS NULL
               AND LENGTH(l_prv.hef_hard_code) = 10
               AND REGEXP_LIKE(l_prv.hef_hard_code, '^[A-Z0-9]{10}$', 'c') THEN
                l_option_code := 'PROVIDER_TAXONOMY_CUSTOM';
                l_taxonomy_code := l_prv.hef_hard_code;
                l_canonical := 'Y';
            ELSE
                RAISE_APPLICATION_ERROR(c_err_current_unsupported,
                    'Provider Taxonomy has an unsupported effective value.');
            END IF;
        END IF;
    ELSIF l_field_number = '77' THEN
        resolve_effective_record('D2310E2500NM1343', NULL, l_nm1);
        resolve_effective_record('D2310E2650N3346', NULL, l_n3);
        resolve_effective_record('D2310E2700N4347', NULL, l_n4);
        retain_pfc(l_nm1.pfc_guid);
        retain_pfc(l_n3.pfc_guid);
        retain_pfc(l_n4.pfc_guid);
        l_capability := 'service-facility';

        IF UPPER(TRIM(l_nm1.her_sto_proc)) = 'RETURN_1'
           AND UPPER(TRIM(l_n3.her_sto_proc)) = 'RETURN_1'
           AND UPPER(TRIM(l_n4.her_sto_proc)) = 'RETURN_1' THEN
            l_option_code := 'SERVICE_FACILITY_ALWAYS_ADDRESS_YES';
            l_mode := 'ALWAYS';
            l_report_address := 'Y';
        ELSIF UPPER(TRIM(l_nm1.her_sto_proc)) = 'RETURN_1'
           AND UPPER(TRIM(l_n3.her_sto_proc)) = 'RETURN_0'
           AND UPPER(TRIM(l_n4.her_sto_proc)) = 'RETURN_0' THEN
            l_option_code := 'SERVICE_FACILITY_ALWAYS_ADDRESS_NO';
            l_mode := 'ALWAYS';
            l_report_address := 'N';
        ELSIF UPPER(TRIM(l_nm1.her_sto_proc)) = 'G_D2310E2500NM1343_COUNT'
           AND UPPER(TRIM(l_n3.her_sto_proc)) = 'G_D2310E2500NM1343_COUNT'
           AND UPPER(TRIM(l_n4.her_sto_proc)) = 'G_D2310E2500NM1343_COUNT' THEN
            l_option_code := 'SERVICE_FACILITY_CONDITIONAL_ADDRESS_YES';
            l_mode := 'CONDITIONAL';
            l_report_address := 'Y';
        ELSIF UPPER(TRIM(l_nm1.her_sto_proc)) = 'G_D2310E2500NM1343_COUNT'
           AND UPPER(TRIM(l_n3.her_sto_proc)) = 'RETURN_0'
           AND UPPER(TRIM(l_n4.her_sto_proc)) = 'RETURN_0' THEN
            l_option_code := 'SERVICE_FACILITY_CONDITIONAL_ADDRESS_NO';
            l_mode := 'CONDITIONAL';
            l_report_address := 'N';
        ELSIF UPPER(TRIM(l_nm1.her_sto_proc)) = 'RETURN_0'
           AND UPPER(TRIM(l_n3.her_sto_proc)) = 'RETURN_0'
           AND UPPER(TRIM(l_n4.her_sto_proc)) = 'RETURN_0' THEN
            l_option_code := 'SERVICE_FACILITY_NEVER';
            l_mode := 'NEVER';
            l_report_address := 'N';
        ELSE
            RAISE_APPLICATION_ERROR(
                c_err_current_unsupported,
                'Service Facility has an inconsistent effective state.'
            );
        END IF;
    ELSE
        RAISE_APPLICATION_ERROR(
            c_err_unsupported_field,
            'Current configuration is not available for that field.'
        );
    END IF;

    IF l_field_number = '81' THEN
        l_owners := '[' || pfc_config_internal.owner_json(l_prv.her_guid, 'Provider Taxonomy') || ']';
    ELSE
        l_owners := '[' || pfc_config_internal.owner_json(l_nm1.her_guid, 'Service facility') || ',' ||
            pfc_config_internal.owner_json(l_n3.her_guid, 'Street address') || ',' ||
            pfc_config_internal.owner_json(l_n4.her_guid, 'City, state and postal code') || ']';
    END IF;
    OPEN p_result FOR
        SELECT
            CAST('RESOLVED' AS VARCHAR2(20)) AS "STATUS",
            CAST(l_field_number AS VARCHAR2(10)) AS "FIELD_NUMBER",
            CAST(l_capability AS VARCHAR2(40)) AS "CAPABILITY",
            CAST(l_option_code AS VARCHAR2(100)) AS "EFFECTIVE_OPTION_CODE",
            CAST(l_mode AS VARCHAR2(20)) AS "MODE",
            CAST(l_report_address AS VARCHAR2(1)) AS "REPORT_ADDRESS",
            CAST(l_enabled AS VARCHAR2(1)) AS "ENABLED",
            CAST(l_taxonomy_code AS VARCHAR2(10)) AS "TAXONOMY_CODE",
            CAST(l_pfc_guid AS VARCHAR2(36)) AS "PFC_GUID",
            CAST(l_canonical AS VARCHAR2(1)) AS "IS_CANONICAL",
            l_owners AS "CONFIGURATION_OWNERS"
        FROM dual;
END pfc_get_current_config;
/
