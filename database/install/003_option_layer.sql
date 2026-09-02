WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
PROMPT Installing option definitions and registry...
@@../types/pfc_option_types.pks
SHOW ERRORS PACKAGE pfc_option_types
@@../types/pfc_option_types.pkb
SHOW ERRORS PACKAGE BODY pfc_option_types
@@../packages/pfc_value_codes.pks
SHOW ERRORS PACKAGE pfc_value_codes
@@../packages/pfc_value_codes.pkb
SHOW ERRORS PACKAGE BODY pfc_value_codes
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
        'PFC_VALUE_CODES',
        'PFC_OPT_PROVIDER_TAXONOMY_ON',
        'PFC_OPT_PROVIDER_TAXONOMY_OFF',
        'PFC_OPT_SERVICE_FACILITY',
        'PFC_OPTION_REGISTRY'
    )
      AND status <> 'VALID';

    IF l_invalid_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20801, 'The option layer has invalid objects.');
    END IF;
END;
/
PROMPT Option definitions and registry installed.
