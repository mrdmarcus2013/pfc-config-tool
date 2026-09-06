WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
PROMPT Updating local configuration validation without changing stored settings...
@@../packages/pfc_config_internal.pkb
@@../procedures/03_pfc_apply_option.sql
DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_objects
    WHERE (object_name = 'PFC_CONFIG_INTERNAL' AND object_type = 'PACKAGE BODY'
        OR object_name = 'PFC_APPLY_OPTION' AND object_type = 'PROCEDURE')
      AND status <> 'VALID';
    IF l_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20807, 'Configuration validation objects did not compile.');
    END IF;
END;
/
PROMPT Configuration validation compiled; existing settings preserved.
