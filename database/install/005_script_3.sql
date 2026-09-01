WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
PROMPT Installing Script 3...
@@../procedures/03_pfc_apply_option.sql
SHOW ERRORS PROCEDURE pfc_apply_option
@@../procedures/04_pfc_get_current_config.sql
SHOW ERRORS PROCEDURE pfc_get_current_config

DECLARE
    l_invalid_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO l_invalid_count
    FROM user_objects
    WHERE object_name IN ('PFC_APPLY_OPTION', 'PFC_GET_CURRENT_CONFIG')
      AND object_type = 'PROCEDURE'
      AND status <> 'VALID';

    IF l_invalid_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20805, 'Script 3 or current-state resolver is invalid.');
    END IF;
END;
/

PROMPT Script 3 installed without recreating or reseeding the POC schema.
