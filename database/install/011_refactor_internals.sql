WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
PROMPT Updating local Oracle internals without reseeding configuration...
@@../packages/pfc_config_internal.pks
@@../packages/pfc_config_internal.pkb
@@../packages/pfc_line_of_business.pks
@@../packages/pfc_line_of_business.pkb
@@../procedures/02_pfc_resolve_her_hef.sql
@@../procedures/03_pfc_apply_option.sql
@@../procedures/04_pfc_get_current_config.sql
@@../packages/pfc_value_codes_api.pkb
@@../packages/pfc_remarks_api.pkb
@@../packages/pfc_copy.pkb
DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_objects
    WHERE object_name IN ('PFC_CONFIG_INTERNAL', 'PFC_LINE_OF_BUSINESS',
        'PFC_RESOLVE_HER_HEF', 'PFC_APPLY_OPTION', 'PFC_GET_CURRENT_CONFIG',
        'PFC_VALUE_CODES_API', 'PFC_REMARKS_API', 'PFC_COPY')
      AND status <> 'VALID';
    IF l_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20806, 'Refactored Oracle objects did not compile.');
    END IF;
END;
/
PROMPT Oracle internals compiled; existing configuration preserved.
