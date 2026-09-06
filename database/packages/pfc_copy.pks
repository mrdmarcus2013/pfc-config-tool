CREATE OR REPLACE PACKAGE pfc_copy AUTHID DEFINER AS
    PROCEDURE run_copy(
        p_source_payor IN VARCHAR2,
        p_source_plan IN VARCHAR2,
        p_destination_payor IN VARCHAR2,
        p_mode IN VARCHAR2,
        p_audit_user IN VARCHAR2,
        p_expected_hash IN VARCHAR2,
        p_result OUT CLOB
    );
END pfc_copy;
/
