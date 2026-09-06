WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
@@../packages/pfc_copy.pks
@@../packages/pfc_copy.pkb
DECLARE
    l_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_errors WHERE name='PFC_COPY';
    IF l_count>0 THEN RAISE_APPLICATION_ERROR(-20107,'Copy package did not compile.'); END IF;
END;
/
