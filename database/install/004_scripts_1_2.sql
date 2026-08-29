WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
PROMPT Installing shared PFC resolver...
@@../packages/pfc_config_internal.pks
SHOW ERRORS PACKAGE pfc_config_internal
@@../packages/pfc_config_internal.pkb
SHOW ERRORS PACKAGE BODY pfc_config_internal
PROMPT Installing Scripts 1 and 2...
@@../procedures/01_pfc_discover_field.sql
SHOW ERRORS PROCEDURE pfc_discover_field
@@../procedures/02_pfc_resolve_her_hef.sql
SHOW ERRORS PROCEDURE pfc_resolve_her_hef

DECLARE
    l_invalid_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO l_invalid_count
    FROM user_objects
    WHERE object_name IN (
        'PFC_CONFIG_INTERNAL',
        'PFC_DISCOVER_FIELD',
        'PFC_RESOLVE_HER_HEF'
    )
      AND status <> 'VALID';

    IF l_invalid_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20802, 'Scripts 1 or 2 have invalid objects.');
    END IF;
END;
/
PROMPT Scripts 1 and 2 installed.
