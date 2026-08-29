WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

DECLARE
    l_results             SYS_REFCURSOR;
    l_billing_form_code   linking_form_lu.billing_form_code%TYPE;
    l_phys_form_field_num linking_form_lu.phys_form_field_num%TYPE;
    l_record_type_code    linking_form_lu.record_type_code%TYPE;
    l_loop_id             linking_form_lu.loop_id%TYPE;
    l_field_number        linking_form_lu.field_number%TYPE;
    l_field_name          linking_form_lu.field_name%TYPE;
    l_field_name_desc     linking_form_lu.field_name_desc%TYPE;
    l_line_num            linking_form_lu.line_num%TYPE;
    l_order_num           linking_form_lu.order_num%TYPE;
    l_mandatory_ind       linking_form_lu.mandatory_ind%TYPE;
    l_dependency_loop     linking_form_lu.dependency_loop%TYPE;
    l_row_count           PLS_INTEGER := 0;
    l_taxonomy_count      PLS_INTEGER := 0;
BEGIN
    pfc_discover_field(
        p_payor_guid          => '10000000-0000-0000-0000-0000000000A1',
        p_plan_guid           => NULL,
        p_phys_form_field_num => '81',
        p_results             => l_results
    );

    LOOP
        FETCH l_results INTO
            l_billing_form_code,
            l_phys_form_field_num,
            l_record_type_code,
            l_loop_id,
            l_field_number,
            l_field_name,
            l_field_name_desc,
            l_line_num,
            l_order_num,
            l_mandatory_ind,
            l_dependency_loop;
        EXIT WHEN l_results%NOTFOUND;

        l_row_count := l_row_count + 1;

        IF l_field_number = '03'
           AND l_field_name = 'PRV03'
           AND l_record_type_code = 'B2000A0030PRV080'
           AND l_billing_form_code = 'UB04' THEN
            l_taxonomy_count := l_taxonomy_count + 1;
        END IF;
    END LOOP;
    CLOSE l_results;

    IF l_row_count <> 3 THEN
        RAISE_APPLICATION_ERROR(
            -20901,
            'Field 81 discovery expected 3 PRV rows; found ' || l_row_count || '.'
        );
    END IF;

    IF l_taxonomy_count <> 1 THEN
        RAISE_APPLICATION_ERROR(
            -20902,
            'Field 81 did not resolve exactly one synthetic PRV03 taxonomy row.'
        );
    END IF;

    DBMS_OUTPUT.PUT_LINE(
        'PASS: diagnostic Field 81 research returned the synthetic PRV mapping.'
    );
EXCEPTION
    WHEN OTHERS THEN
        IF l_results%ISOPEN THEN
            CLOSE l_results;
        END IF;
        RAISE;
END;
/
