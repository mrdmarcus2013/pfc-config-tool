CREATE OR REPLACE PACKAGE pfc_remarks_api AUTHID DEFINER AS
    PROCEDURE current_configuration (
        p_payor_guid IN payors.payor_guid%TYPE,
        p_plan_guid  IN pfc.plan_guid%TYPE DEFAULT NULL,
        p_result     OUT SYS_REFCURSOR
    );

    PROCEDURE preview_configuration (
        p_payor_guid  IN payors.payor_guid%TYPE,
        p_plan_guid   IN pfc.plan_guid%TYPE DEFAULT NULL,
        p_mode        IN pfc_remarks.t_mode,
        p_custom_remark IN pfc_remarks.t_custom_remark,
        p_audit_user  IN hcfa_electronic_records.rec_ent_user%TYPE,
        p_summary     OUT SYS_REFCURSOR,
        p_changes     OUT SYS_REFCURSOR
    );

    PROCEDURE apply_configuration (
        p_payor_guid          IN payors.payor_guid%TYPE,
        p_plan_guid           IN pfc.plan_guid%TYPE DEFAULT NULL,
        p_mode                IN pfc_remarks.t_mode,
        p_custom_remark       IN pfc_remarks.t_custom_remark,
        p_audit_user          IN hcfa_electronic_records.rec_ent_user%TYPE,
        p_expected_state_hash IN VARCHAR2,
        p_summary             OUT SYS_REFCURSOR,
        p_changes             OUT SYS_REFCURSOR
    );
END pfc_remarks_api;
/
