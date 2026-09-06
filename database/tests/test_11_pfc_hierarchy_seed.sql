WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

DECLARE
    l_payor_count          NUMBER;
    l_pfc_count            NUMBER;
    l_plan_count           NUMBER;
    l_distinct_plan_count  NUMBER;
    l_form_count           NUMBER;
    l_distinct_form_count  NUMBER;
    l_user_count           NUMBER;
    l_distinct_user_count  NUMBER;
    l_shared_plan_count    NUMBER;

    PROCEDURE assert_number(
        p_label    IN VARCHAR2,
        p_actual   IN NUMBER,
        p_expected IN NUMBER
    ) IS
    BEGIN
        IF p_actual != p_expected THEN
            RAISE_APPLICATION_ERROR(
                -20961,
                p_label || ': expected ' || p_expected || ', got ' || p_actual
            );
        END IF;
    END;
BEGIN
    SELECT COUNT(*)
    INTO l_payor_count
    FROM payors
    WHERE payor_id LIKE 'SYN-HIER-%';

    SELECT
        COUNT(*),
        COUNT(p.plan_guid),
        COUNT(DISTINCT p.plan_guid),
        COUNT(p.form_template_guid),
        COUNT(DISTINCT p.form_template_guid),
        COUNT(p.user_form_template_guid),
        COUNT(DISTINCT p.user_form_template_guid)
    INTO
        l_pfc_count,
        l_plan_count,
        l_distinct_plan_count,
        l_form_count,
        l_distinct_form_count,
        l_user_count,
        l_distinct_user_count
    FROM pfc p
    JOIN payors y ON y.payor_guid = p.payor_guid
    WHERE y.payor_id LIKE 'SYN-HIER-%';

    SELECT COUNT(*)
    INTO l_shared_plan_count
    FROM (
        SELECT p.plan_guid
        FROM pfc p
        WHERE p.plan_guid IS NOT NULL
        GROUP BY p.plan_guid
        HAVING COUNT(DISTINCT p.payor_guid) > 1
    ) shared_plans
    WHERE shared_plans.plan_guid IN (
        SELECT p.plan_guid
        FROM pfc p
        JOIN payors y ON y.payor_guid = p.payor_guid
        WHERE y.payor_id LIKE 'SYN-HIER-%'
    );

    assert_number('Hierarchy payor count', l_payor_count, 9);
    assert_number('Hierarchy PFC count', l_pfc_count, 9);
    assert_number('Populated plan count', l_plan_count, 9);
    assert_number('Distinct plan count', l_distinct_plan_count, 9);
    assert_number('Plans shared across payors', l_shared_plan_count, 0);
    assert_number('Populated form-template count', l_form_count, 6);
    assert_number('Distinct form-template count', l_distinct_form_count, 2);
    assert_number('Populated user-template count', l_user_count, 5);
    assert_number('Distinct user-template count', l_distinct_user_count, 3);

    DBMS_OUTPUT.PUT_LINE('PASS: synthetic PFC hierarchy seed matrix');
END;
/
