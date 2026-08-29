WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
PROMPT Applying authorized synthetic PAYOR_B canonical-data correction...

DECLARE
    l_record_name hcfa_electronic_records.record_name%TYPE;
    l_notes       hcfa_electronic_records.notes%TYPE;
BEGIN
    BEGIN
        SELECT h.record_name, h.notes
        INTO l_record_name, l_notes
        FROM hcfa_electronic_records h
        WHERE h.electronic_rec_guid =
            '30000000-0000-0000-0000-0000000000B1';

        IF NOT (
            (l_record_name = 'Synthetic PAYOR_B Provider'
             AND l_notes = 'Synthetic canonical payor-specific PRV')
            OR
            (l_record_name = 'Synthetic Generic Provider'
             AND l_notes = 'Synthetic billing-form-level PRV source')
        ) THEN
            RAISE_APPLICATION_ERROR(
                -20803,
                'Synthetic PAYOR_B is in an unexpected state; no correction was made.'
            );
        END IF;

        UPDATE hcfa_electronic_records h
        SET
            h.record_name = 'Synthetic Generic Provider',
            h.notes = 'Synthetic billing-form-level PRV source',
            h.payor_type_guid = NULL,
            h.carry_forward_ind = NULL,
            h.include_record_data_onclaim = 'Y'
        WHERE h.electronic_rec_guid =
            '30000000-0000-0000-0000-0000000000B1';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            NULL;
    END;
END;
/

PROMPT Installing explicit-target option definitions...
@@../types/pfc_option_types.pks
SHOW ERRORS PACKAGE pfc_option_types
@@../types/pfc_option_types.pkb
SHOW ERRORS PACKAGE BODY pfc_option_types
@@../functions/options/pfc_opt_provider_taxonomy_on.sql
SHOW ERRORS FUNCTION pfc_opt_provider_taxonomy_on
@@../functions/options/pfc_opt_provider_taxonomy_off.sql
SHOW ERRORS FUNCTION pfc_opt_provider_taxonomy_off
@@../functions/options/pfc_opt_service_facility.sql
SHOW ERRORS FUNCTION pfc_opt_service_facility
@@../packages/pfc_option_registry.pks
SHOW ERRORS PACKAGE pfc_option_registry
@@../packages/pfc_option_registry.pkb
SHOW ERRORS PACKAGE BODY pfc_option_registry

DECLARE
    l_invalid_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO l_invalid_count
    FROM user_objects
    WHERE object_name IN (
        'PFC_OPTION_TYPES',
        'PFC_OPT_PROVIDER_TAXONOMY_ON',
        'PFC_OPT_PROVIDER_TAXONOMY_OFF',
        'PFC_OPT_SERVICE_FACILITY',
        'PFC_OPTION_REGISTRY'
    )
      AND status <> 'VALID';

    IF l_invalid_count > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20804,
            'The explicit-target option definitions or registry are invalid.'
        );
    END IF;
END;
/

COMMIT;
PROMPT Script 3 prerequisites prepared without recreating or reseeding the POC schema.
