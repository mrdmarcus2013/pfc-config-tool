CREATE OR REPLACE PACKAGE pfc_config_internal AUTHID DEFINER AS
    c_err_pfc_not_found      CONSTANT PLS_INTEGER := -20010;
    c_err_pfc_start_date_tie CONSTANT PLS_INTEGER := -20011;
    c_err_unsafe_source      CONSTANT PLS_INTEGER := -20012;

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

    -- Positional contract of PFC_RESOLVE_HER_HEF's public SYS_REFCURSOR.
    -- Keep this field order aligned with its SELECT list. Derived flags/ranks
    -- retain their original scalar types; stored values use column anchors.
    TYPE t_resolved_her_hef_row IS RECORD (
        pfc_guid                pfc.pfc_guid%TYPE,
        payor_guid              pfc.payor_guid%TYPE,
        plan_guid               pfc.plan_guid%TYPE,
        payor_type_guid         payors.payor_type_guid%TYPE,
        billing_form_code       pfc.billing_form_code%TYPE,
        form_template_guid      pfc.form_template_guid%TYPE,
        user_form_template_guid pfc.user_form_template_guid%TYPE,
        cpd_start_date          pfc.cpd_start_date%TYPE,
        cpd_end_date            pfc.cpd_end_date%TYPE,
        payor_specific_her_exists VARCHAR2(1),
        her_scope_code          VARCHAR2(20),
        is_clone_source         VARCHAR2(1),
        clone_template_rank     PLS_INTEGER,
        clone_payor_type_rank   PLS_INTEGER,
        electronic_rec_guid     hcfa_electronic_records.electronic_rec_guid%TYPE,
        record_type_code        hcfa_electronic_records.record_type_code%TYPE,
        record_name             hcfa_electronic_records.record_name%TYPE,
        her_payor_guid          hcfa_electronic_records.payor_guid%TYPE,
        her_payor_type_guid     hcfa_electronic_records.payor_type_guid%TYPE,
        her_form_template_guid  hcfa_electronic_records.form_template_guid%TYPE,
        her_user_template_guid  hcfa_electronic_records.user_form_template_guid%TYPE,
        her_sto_proc_name       hcfa_electronic_records.sto_proc_name%TYPE,
        field_number            hcfa_electronic_fields.field_number%TYPE,
        field_name              hcfa_electronic_fields.field_name%TYPE,
        hef_sto_proc_name       hcfa_electronic_fields.sto_proc_name%TYPE,
        hef_hard_coded_data     hcfa_electronic_fields.hard_coded_data%TYPE,
        position_from           hcfa_electronic_fields.position_from%TYPE,
        position_thru           hcfa_electronic_fields.position_thru%TYPE,
        order_num               hcfa_electronic_fields.order_num%TYPE
    );

    FUNCTION owner_json(p_her_guid IN VARCHAR2, p_target IN VARCHAR2) RETURN VARCHAR2;

    PROCEDURE resolve_pfc (
        p_payor_guid IN pfc.payor_guid%TYPE,
        p_plan_guid  IN pfc.plan_guid%TYPE DEFAULT NULL,
        p_resolution OUT t_pfc_resolution
    );

    FUNCTION her_satisfies_safety_invariants (
        p_sto_proc_name IN hcfa_electronic_records.sto_proc_name%TYPE,
        p_mandatory_ind IN hcfa_electronic_records.mandatory_ind%TYPE
    ) RETURN BOOLEAN;

    PROCEDURE apply_her_safety_invariants (
        p_her IN OUT NOCOPY hcfa_electronic_records%ROWTYPE
    );

    PROCEDURE assert_inherited_her_safe (
        p_her IN hcfa_electronic_records%ROWTYPE
    );
END pfc_config_internal;
/
