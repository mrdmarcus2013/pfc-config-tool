CREATE OR REPLACE PACKAGE pfc_config_internal AUTHID DEFINER AS
    c_err_pfc_not_found      CONSTANT PLS_INTEGER := -20010;
    c_err_pfc_start_date_tie CONSTANT PLS_INTEGER := -20011;

    TYPE t_pfc_resolution IS RECORD (
        pfc_guid                pfc.pfc_guid%TYPE,
        payor_guid              pfc.payor_guid%TYPE,
        plan_guid               pfc.plan_guid%TYPE,
        payor_type_guid         payors.payor_type_guid%TYPE,
        billing_form_code       pfc.billing_form_code%TYPE,
        form_template_guid      pfc.form_template_guid%TYPE,
        user_form_template_guid pfc.user_form_template_guid%TYPE,
        cpd_start_date           pfc.cpd_start_date%TYPE,
        cpd_end_date             pfc.cpd_end_date%TYPE
    );

    PROCEDURE resolve_pfc (
        p_payor_guid IN pfc.payor_guid%TYPE,
        p_plan_guid  IN pfc.plan_guid%TYPE DEFAULT NULL,
        p_resolution OUT t_pfc_resolution
    );
END pfc_config_internal;
/
