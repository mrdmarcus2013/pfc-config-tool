CREATE OR REPLACE PACKAGE pfc_line_of_business AUTHID DEFINER AS
    c_err_payor_not_found    CONSTANT PLS_INTEGER := -20050;
    c_err_invalid_lob        CONSTANT PLS_INTEGER := -20051;
    c_err_lob_already_saved  CONSTANT PLS_INTEGER := -20052;
    c_err_lob_required       CONSTANT PLS_INTEGER := -20053;
    c_err_expected_hash      CONSTANT PLS_INTEGER := -20054;
    c_err_stale_preview      CONSTANT PLS_INTEGER := -20055;
    c_err_verification       CONSTANT PLS_INTEGER := -20056;
    c_err_unexpected_state   CONSTANT PLS_INTEGER := -20057;

    PROCEDURE require_defined (
        p_payor_guid IN payors.payor_guid%TYPE,
        p_lock       IN VARCHAR2 DEFAULT 'N'
    );

    PROCEDURE get_current (
        p_payor_guid IN payors.payor_guid%TYPE,
        p_result     OUT SYS_REFCURSOR
    );

    PROCEDURE save_initial (
        p_payor_guid       IN payors.payor_guid%TYPE,
        p_line_of_business IN pfc_config_payor_context.line_of_business%TYPE,
        p_audit_user       IN pfc_config_payor_context.rec_ent_user%TYPE,
        p_result           OUT SYS_REFCURSOR
    );

    PROCEDURE preview_change (
        p_payor_guid                IN payors.payor_guid%TYPE,
        p_requested_line_of_business IN pfc_config_payor_context.line_of_business%TYPE,
        p_summary                   OUT SYS_REFCURSOR,
        p_target_counts             OUT SYS_REFCURSOR
    );

    PROCEDURE apply_change (
        p_payor_guid                 IN payors.payor_guid%TYPE,
        p_requested_line_of_business IN pfc_config_payor_context.line_of_business%TYPE,
        p_expected_state_hash        IN VARCHAR2,
        p_audit_user                 IN pfc_config_payor_context.rec_ent_user%TYPE,
        p_summary                    OUT SYS_REFCURSOR,
        p_target_counts              OUT SYS_REFCURSOR
    );
END pfc_line_of_business;
/
