/* Local synthetic reset. The CLI previews counts before --confirm-reset.
 * Run directly only after reviewing the scope: every row of the eight local
 * checkpoint tables is removed. This is never a production script. */
DECLARE
    l_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM payors
    WHERE payor_name NOT LIKE 'Synthetic %';
    IF l_count <> 0 THEN
        RAISE_APPLICATION_ERROR(-20991, 'Reset requires exclusively synthetic payors.');
    END IF;
END;
/
DELETE FROM hcfa_electronic_fields;
DELETE FROM hcfa_electronic_records;
DELETE FROM pfc;
DELETE FROM pfc_config_plans;
DELETE FROM pfc_config_payor_context;
DELETE FROM linking_form_lu;
DELETE FROM pfc_config_user_templates;
DELETE FROM pfc_config_form_templates;
DELETE FROM payors;
/* The caller commits only after the selected replacement seed succeeds. */
