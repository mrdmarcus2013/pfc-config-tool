/* Read-only reference-source checks. Payor/plan overrides are permitted. */
DECLARE
    l_count NUMBER;
    PROCEDURE expect(p_sql VARCHAR2, p_expected NUMBER) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql INTO l_count;
        IF l_count <> p_expected THEN
            RAISE_APPLICATION_ERROR(-20990, 'Hierarchy assertion failed: ' || p_sql);
        END IF;
    END;
BEGIN
    expect('SELECT COUNT(*) FROM hcfa_electronic_records WHERE payor_guid IS NULL', 17);
    expect('SELECT COUNT(*) FROM hcfa_electronic_fields f JOIN hcfa_electronic_records h ON h.electronic_rec_guid=f.electronic_rec_guid WHERE h.payor_guid IS NULL', 67);
    expect('SELECT COUNT(*) FROM pfc_config_form_templates', 2);
    expect('SELECT COUNT(*) FROM pfc_config_user_templates', 5);
    expect('SELECT COUNT(*) FROM hcfa_electronic_fields f WHERE NOT EXISTS (SELECT 1 FROM hcfa_electronic_records h WHERE h.electronic_rec_guid=f.electronic_rec_guid)', 0);
    expect('SELECT COUNT(*) FROM pfc WHERE billing_form_code<>''837I_5010'' OR form_template_guid IS NULL', 0);
    expect('SELECT COUNT(*) FROM hcfa_electronic_records WHERE billing_form_code<>''837I_5010''', 0);
    expect('SELECT COUNT(*) FROM hcfa_electronic_records WHERE payor_guid IS NULL AND form_template_guid IS NOT NULL AND user_form_template_guid IS NULL AND record_type_code<>''D23002310HI286''', 0);
    expect('SELECT COUNT(*) FROM pfc p WHERE p.plan_guid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pfc_config_plans o WHERE o.plan_guid=p.plan_guid AND o.payor_guid=p.payor_guid)', 0);
    expect('SELECT COUNT(*) FROM hcfa_electronic_records h WHERE h.plan_guid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pfc_config_plans o WHERE o.plan_guid=h.plan_guid AND o.payor_guid=h.payor_guid)', 0);
    DBMS_OUTPUT.PUT_LINE('Reference hierarchy passed: 17 source HER, 67 source HEF; plan ownership and child integrity valid.');
END;
/
