WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
PROMPT Installing Script 3...
@@../procedures/03_pfc_apply_option.sql
SHOW ERRORS PROCEDURE pfc_apply_option

DECLARE
    l_invalid_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO l_invalid_count
    FROM user_objects
    WHERE object_name = 'PFC_APPLY_OPTION'
      AND object_type = 'PROCEDURE'
      AND status <> 'VALID';

    IF l_invalid_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20805, 'Script 3 is invalid.');
    END IF;
END;
/

PROMPT Script 3 installed without recreating or reseeding the POC schema.
