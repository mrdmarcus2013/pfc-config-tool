WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
PROMPT Installing Line of Business foundation...

DECLARE
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count
    FROM user_tables
    WHERE table_name = 'PFC_CONFIG_PAYOR_CONTEXT';
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE q'~
            CREATE TABLE pfc_config_payor_context (
                payor_guid       VARCHAR2(36) NOT NULL,
                line_of_business VARCHAR2(20) NOT NULL,
                rec_ent_date     DATE         NOT NULL,
                rec_ent_user     VARCHAR2(36) NOT NULL,
                rec_mod_date     DATE,
                rec_mod_user     VARCHAR2(36),
                CONSTRAINT pk_pfc_config_payor_context PRIMARY KEY (payor_guid),
                CONSTRAINT fk_pfc_config_context_payor FOREIGN KEY (payor_guid)
                    REFERENCES payors (payor_guid),
                CONSTRAINT ck_pfc_config_context_lob CHECK (
                    line_of_business IN ('HOME_HEALTH', 'HOSPICE')
                )
            )~';
    END IF;
END;
/

MERGE INTO pfc_config_payor_context c
USING (
    SELECT p.payor_guid,
           CASE WHEN p.payor_guid IN (
                    '10000000-0000-0000-0000-0000000000A1',
                    '10000000-0000-0000-0000-00000000D002')
                THEN 'HOME_HEALTH' ELSE 'HOSPICE' END line_of_business
    FROM payors p
    WHERE p.payor_guid IN (
        '10000000-0000-0000-0000-0000000000A1',
        '10000000-0000-0000-0000-0000000000A8',
        '10000000-0000-0000-0000-00000000D002'
    )
) seed
ON (c.payor_guid = seed.payor_guid)
WHEN NOT MATCHED THEN INSERT (
    payor_guid, line_of_business, rec_ent_date, rec_ent_user,
    rec_mod_date, rec_mod_user
) VALUES (
    seed.payor_guid, seed.line_of_business, DATE '2026-01-01',
    '90000000-0000-0000-0000-000000000001', NULL, NULL
);

@@../packages/pfc_line_of_business.pks
SHOW ERRORS PACKAGE pfc_line_of_business
@@../packages/pfc_line_of_business.pkb
SHOW ERRORS PACKAGE BODY pfc_line_of_business

DECLARE
    l_invalid_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_invalid_count
    FROM user_objects
    WHERE object_name = 'PFC_LINE_OF_BUSINESS'
      AND status <> 'VALID';
    IF l_invalid_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20806,
            'The Line of Business package is invalid.');
    END IF;
END;
/
COMMIT;
PROMPT Line of Business foundation installed.
