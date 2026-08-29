WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

DECLARE
    l_stale_her_count      PLS_INTEGER;
    l_stale_template_count PLS_INTEGER;
    l_stale_hef_count      PLS_INTEGER;

    PROCEDURE assert_scenario (
        p_label                      IN VARCHAR2,
        p_payor_guid                 IN payors.payor_guid%TYPE,
        p_expected_pfc_guid          IN pfc.pfc_guid%TYPE,
        p_expected_payor_type_guid   IN payors.payor_type_guid%TYPE,
        p_expected_clone_source_guid IN hcfa_electronic_records.electronic_rec_guid%TYPE,
        p_expected_payor_exists      IN VARCHAR2,
        p_expected_payor_her_guid    IN hcfa_electronic_records.electronic_rec_guid%TYPE
            DEFAULT NULL,
        p_expected_target_proc       IN hcfa_electronic_fields.sto_proc_name%TYPE
            DEFAULT NULL,
        p_record_type_code           IN hcfa_electronic_records.record_type_code%TYPE
            DEFAULT 'B2000A0030PRV080',
        p_expected_source_hef_count  IN PLS_INTEGER DEFAULT NULL,
        p_expected_target_hard       IN hcfa_electronic_fields.hard_coded_data%TYPE
            DEFAULT NULL
    ) IS
        l_results                    SYS_REFCURSOR;
        l_pfc_guid                   pfc.pfc_guid%TYPE;
        l_payor_guid                 pfc.payor_guid%TYPE;
        l_plan_guid                  pfc.plan_guid%TYPE;
        l_payor_type_guid            payors.payor_type_guid%TYPE;
        l_billing_form_code          pfc.billing_form_code%TYPE;
        l_form_template_guid         pfc.form_template_guid%TYPE;
        l_user_form_template_guid    pfc.user_form_template_guid%TYPE;
        l_cpd_start_date             pfc.cpd_start_date%TYPE;
        l_cpd_end_date               pfc.cpd_end_date%TYPE;
        l_payor_specific_exists      VARCHAR2(1);
        l_her_scope_code             VARCHAR2(20);
        l_is_clone_source            VARCHAR2(1);
        l_clone_template_rank        PLS_INTEGER;
        l_clone_payor_type_rank      PLS_INTEGER;
        l_electronic_rec_guid        hcfa_electronic_records.electronic_rec_guid%TYPE;
        l_record_type_code           hcfa_electronic_records.record_type_code%TYPE;
        l_record_name                hcfa_electronic_records.record_name%TYPE;
        l_her_payor_guid             hcfa_electronic_records.payor_guid%TYPE;
        l_her_payor_type_guid        hcfa_electronic_records.payor_type_guid%TYPE;
        l_her_form_template_guid     hcfa_electronic_records.form_template_guid%TYPE;
        l_her_user_template_guid     hcfa_electronic_records.user_form_template_guid%TYPE;
        l_her_sto_proc_name          hcfa_electronic_records.sto_proc_name%TYPE;
        l_field_number               hcfa_electronic_fields.field_number%TYPE;
        l_field_name                 hcfa_electronic_fields.field_name%TYPE;
        l_hef_sto_proc_name          hcfa_electronic_fields.sto_proc_name%TYPE;
        l_hef_hard_coded_data        hcfa_electronic_fields.hard_coded_data%TYPE;
        l_position_from              hcfa_electronic_fields.position_from%TYPE;
        l_position_thru              hcfa_electronic_fields.position_thru%TYPE;
        l_order_num                  hcfa_electronic_fields.order_num%TYPE;
        l_row_count                  PLS_INTEGER := 0;
        l_clone_source_found         BOOLEAN := FALSE;
        l_expected_payor_her_found   BOOLEAN := FALSE;
        l_expected_target_proc_found BOOLEAN := FALSE;
        l_expected_target_hard_found BOOLEAN := FALSE;
        l_source_hef_count            PLS_INTEGER := 0;
    BEGIN
        pfc_resolve_her_hef(
            p_payor_guid       => p_payor_guid,
            p_plan_guid        => NULL,
            p_record_type_code => p_record_type_code,
            p_results          => l_results
        );

        LOOP
            FETCH l_results INTO
                l_pfc_guid,
                l_payor_guid,
                l_plan_guid,
                l_payor_type_guid,
                l_billing_form_code,
                l_form_template_guid,
                l_user_form_template_guid,
                l_cpd_start_date,
                l_cpd_end_date,
                l_payor_specific_exists,
                l_her_scope_code,
                l_is_clone_source,
                l_clone_template_rank,
                l_clone_payor_type_rank,
                l_electronic_rec_guid,
                l_record_type_code,
                l_record_name,
                l_her_payor_guid,
                l_her_payor_type_guid,
                l_her_form_template_guid,
                l_her_user_template_guid,
                l_her_sto_proc_name,
                l_field_number,
                l_field_name,
                l_hef_sto_proc_name,
                l_hef_hard_coded_data,
                l_position_from,
                l_position_thru,
                l_order_num;
            EXIT WHEN l_results%NOTFOUND;

            l_row_count := l_row_count + 1;

            IF l_pfc_guid <> p_expected_pfc_guid THEN
                RAISE_APPLICATION_ERROR(
                    -20910,
                    p_label || ': unexpected selected PFC ' || l_pfc_guid || '.'
                );
            END IF;

            IF l_payor_type_guid <> p_expected_payor_type_guid THEN
                RAISE_APPLICATION_ERROR(
                    -20911,
                    p_label || ': PAYORS.PAYOR_TYPE_GUID was not returned.'
                );
            END IF;

            IF l_payor_specific_exists <> p_expected_payor_exists THEN
                RAISE_APPLICATION_ERROR(
                    -20912,
                    p_label || ': unexpected payor-specific HER flag.'
                );
            END IF;

            IF l_is_clone_source = 'Y' THEN
                IF l_electronic_rec_guid <> p_expected_clone_source_guid THEN
                    RAISE_APPLICATION_ERROR(
                        -20913,
                        p_label || ': wrong generic clone source selected.'
                    );
                END IF;
                l_clone_source_found := TRUE;
                IF l_field_number IS NOT NULL THEN
                    l_source_hef_count := l_source_hef_count + 1;
                END IF;
            END IF;

            IF l_electronic_rec_guid = p_expected_payor_her_guid THEN
                l_expected_payor_her_found := TRUE;

                IF l_field_name = 'PRV03'
                   AND l_hef_sto_proc_name = p_expected_target_proc THEN
                    l_expected_target_proc_found := TRUE;
                END IF;
                IF l_field_name = 'PRV03'
                   AND l_hef_hard_coded_data = p_expected_target_hard THEN
                    l_expected_target_hard_found := TRUE;
                END IF;
            END IF;
        END LOOP;
        CLOSE l_results;

        IF l_row_count = 0 OR NOT l_clone_source_found THEN
            RAISE_APPLICATION_ERROR(
                -20914,
                p_label || ': no rows or no clone source returned.'
            );
        END IF;

        IF p_expected_payor_her_guid IS NOT NULL
           AND NOT l_expected_payor_her_found THEN
            RAISE_APPLICATION_ERROR(
                -20915,
                p_label || ': expected payor-specific HER was not returned.'
            );
        END IF;

        IF p_expected_target_proc IS NOT NULL
           AND NOT l_expected_target_proc_found THEN
            RAISE_APPLICATION_ERROR(
                -20916,
                p_label || ': expected PRV03 procedure value was not returned.'
            );
        END IF;

        IF p_expected_target_hard IS NOT NULL
           AND NOT l_expected_target_hard_found THEN
            RAISE_APPLICATION_ERROR(
                -20916,
                p_label || ': expected PRV03 hard-coded value was not returned.'
            );
        END IF;

        IF p_expected_source_hef_count IS NOT NULL
           AND l_source_hef_count <> p_expected_source_hef_count THEN
            RAISE_APPLICATION_ERROR(
                -20918,
                p_label || ': unexpected source HEF count.'
            );
        END IF;

        DBMS_OUTPUT.PUT_LINE(
            'PASS: ' || p_label || ' -> PFC ' || p_expected_pfc_guid ||
            ', clone source ' || p_expected_clone_source_guid || '.'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF l_results%ISOPEN THEN
                CLOSE l_results;
            END IF;
            RAISE;
    END assert_scenario;

BEGIN
    assert_scenario(
        'PAYOR_A billing-form default',
        '10000000-0000-0000-0000-0000000000A1',
        '20000000-0000-0000-0000-0000000000A1',
        '11000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001',
        'N'
    );

    assert_scenario(
        'PAYOR_B canonical payor HER',
        '10000000-0000-0000-0000-0000000000A2',
        '20000000-0000-0000-0000-0000000000A2',
        '11000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001',
        'Y',
        '30000000-0000-0000-0000-0000000000B1',
        'G_PROVIDER_TAXONOMY_CODE'
    );

    assert_scenario(
        'PAYOR_C stale templates excluded',
        '10000000-0000-0000-0000-0000000000A3',
        '20000000-0000-0000-0000-0000000000A3',
        '11000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-0000000000F1',
        'N'
    );

    SELECT
        COUNT(*),
        COUNT(DISTINCT h.form_template_guid)
    INTO
        l_stale_her_count,
        l_stale_template_count
    FROM hcfa_electronic_records h
    WHERE h.payor_guid = '10000000-0000-0000-0000-0000000000A3'
      AND h.record_type_code = 'B2000A0030PRV080';

    SELECT COUNT(*)
    INTO l_stale_hef_count
    FROM hcfa_electronic_fields f
    WHERE EXISTS (
        SELECT 1
        FROM hcfa_electronic_records h
        WHERE h.electronic_rec_guid = f.electronic_rec_guid
          AND h.payor_guid = '10000000-0000-0000-0000-0000000000A3'
          AND h.record_type_code = 'B2000A0030PRV080'
    );

    IF l_stale_her_count <> 2
       OR l_stale_template_count <> 2
       OR l_stale_hef_count <> 8 THEN
        RAISE_APPLICATION_ERROR(
            -20917,
            'PAYOR_C stale duplicate setup is incomplete.'
        );
    END IF;
    DBMS_OUTPUT.PUT_LINE('PASS: PAYOR_C retains 2 stale HERs and 8 HEFs for future Script 3.');

    assert_scenario(
        'PAYOR_D incorrect PRV03 visible',
        '10000000-0000-0000-0000-0000000000A4',
        '20000000-0000-0000-0000-0000000000A4',
        '11000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001',
        'Y',
        p_expected_payor_her_guid =>
            '30000000-0000-0000-0000-0000000000D1',
        p_expected_target_hard => 'SYNTHETIC_HARD_CODED_TAXONOMY'
    );

    assert_scenario(
        'PAYOR_E form template',
        '10000000-0000-0000-0000-0000000000A5',
        '20000000-0000-0000-0000-0000000000A5',
        '11000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-0000000000E1',
        'N'
    );

    assert_scenario(
        'PAYOR_F user template',
        '10000000-0000-0000-0000-0000000000A6',
        '20000000-0000-0000-0000-0000000000A6',
        '11000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-0000000000F1',
        'N'
    );

    assert_scenario(
        'PAYOR_G newest CPD start date',
        '10000000-0000-0000-0000-0000000000A7',
        '20000000-0000-0000-0000-0000000000B7',
        '11000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001',
        'N'
    );

    assert_scenario(
        'PAYOR_H exact payor type',
        '10000000-0000-0000-0000-0000000000A8',
        '20000000-0000-0000-0000-0000000000A8',
        '11000000-0000-0000-0000-000000000002',
        '30000000-0000-0000-0000-0000000000A8',
        'N'
    );

    assert_scenario(
        'Service Facility NM1 explicit target',
        '10000000-0000-0000-0000-0000000000A1',
        '20000000-0000-0000-0000-0000000000A1',
        '11000000-0000-0000-0000-000000000001',
        '31000000-0000-0000-0000-000000000001',
        'N', NULL, NULL, 'D2310E2500NM1343', 5
    );

    assert_scenario(
        'Service Facility N3 explicit target',
        '10000000-0000-0000-0000-0000000000A1',
        '20000000-0000-0000-0000-0000000000A1',
        '11000000-0000-0000-0000-000000000001',
        '31000000-0000-0000-0000-000000000002',
        'N', NULL, NULL, 'D2310E2650N3346', 2
    );

    assert_scenario(
        'Service Facility N4 explicit target',
        '10000000-0000-0000-0000-0000000000A1',
        '20000000-0000-0000-0000-0000000000A1',
        '11000000-0000-0000-0000-000000000001',
        '31000000-0000-0000-0000-000000000003',
        'N', NULL, NULL, 'D2310E2700N4347', 3
    );

    DBMS_OUTPUT.PUT_LINE('PASS: all Script 2 synthetic scenarios passed.');
END;
/
