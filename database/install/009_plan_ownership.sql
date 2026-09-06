-- Synthetic local ownership catalog. This is not a validated production object.
DECLARE
    l_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM (
        SELECT plan_guid FROM pfc WHERE plan_guid IS NOT NULL
        GROUP BY plan_guid HAVING COUNT(DISTINCT payor_guid) <> 1
            OR COUNT(payor_guid) <> COUNT(*)
    );
    IF l_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20010, 'Conflicting plan owners must be corrected before installation.');
    END IF;
    SELECT COUNT(*) INTO l_count FROM user_tables WHERE table_name = 'PFC_CONFIG_PLANS';
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'CREATE TABLE pfc_config_plans (
            plan_guid VARCHAR2(36) PRIMARY KEY,
            payor_guid VARCHAR2(36) NOT NULL REFERENCES payors(payor_guid),
            plan_name VARCHAR2(128),
            CONSTRAINT uq_config_plan_owner UNIQUE(plan_guid, payor_guid))';
    END IF;
END;
/
MERGE INTO pfc_config_plans d USING (
    SELECT DISTINCT plan_guid, payor_guid FROM pfc WHERE plan_guid IS NOT NULL
) s ON (d.plan_guid = s.plan_guid)
WHEN NOT MATCHED THEN INSERT(plan_guid, payor_guid) VALUES(s.plan_guid, s.payor_guid);

CREATE OR REPLACE TRIGGER pfc_plan_owner_guard
BEFORE INSERT OR UPDATE OR DELETE ON pfc
FOR EACH ROW
DECLARE
    l_owner VARCHAR2(36);
BEGIN
    -- Serialize PFC changes with configuration Apply, including new winners.
    FOR owner_row IN (
        SELECT payor_guid FROM payors
        WHERE payor_guid IN (:NEW.payor_guid, :OLD.payor_guid)
        ORDER BY payor_guid FOR UPDATE
    ) LOOP
        NULL;
    END LOOP;
    IF NOT DELETING AND :NEW.plan_guid IS NOT NULL THEN
        IF :NEW.payor_guid IS NULL THEN
            RAISE_APPLICATION_ERROR(-20010, 'A plan requires its owner payor.');
        END IF;
        BEGIN
            INSERT INTO pfc_config_plans(plan_guid, payor_guid)
            VALUES(:NEW.plan_guid, :NEW.payor_guid);
        EXCEPTION WHEN DUP_VAL_ON_INDEX THEN NULL;
        END;
        SELECT payor_guid INTO l_owner FROM pfc_config_plans WHERE plan_guid = :NEW.plan_guid;
        IF l_owner <> :NEW.payor_guid THEN
            RAISE_APPLICATION_ERROR(-20010, 'A plan can belong only to its owner payor.');
        END IF;
    END IF;
END;
/

CREATE OR REPLACE TRIGGER config_plan_owner_immutable
BEFORE UPDATE OF plan_guid, payor_guid ON pfc_config_plans
FOR EACH ROW
BEGIN
    IF :NEW.plan_guid <> :OLD.plan_guid OR :NEW.payor_guid <> :OLD.payor_guid THEN
        RAISE_APPLICATION_ERROR(-20010, 'Plan ownership cannot be reassigned.');
    END IF;
END;
/

DECLARE
    l_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM user_constraints WHERE constraint_name = 'FK_PFC_PLAN_OWNER';
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE pfc ADD CONSTRAINT fk_pfc_plan_owner
            FOREIGN KEY(plan_guid, payor_guid) REFERENCES pfc_config_plans(plan_guid, payor_guid)';
    END IF;
    SELECT COUNT(*) INTO l_count FROM user_constraints WHERE constraint_name = 'FK_HER_PLAN_OWNER';
    IF l_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE hcfa_electronic_records ADD CONSTRAINT fk_her_plan_owner
            FOREIGN KEY(plan_guid, payor_guid) REFERENCES pfc_config_plans(plan_guid, payor_guid)';
        EXECUTE IMMEDIATE 'ALTER TABLE hcfa_electronic_records ADD CONSTRAINT ck_her_plan_payor
            CHECK(plan_guid IS NULL OR payor_guid IS NOT NULL)';
    END IF;
END;
/
