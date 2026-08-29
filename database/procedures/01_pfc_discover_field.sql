/*
 * Diagnostic/development research helper only.
 * LINKING_FORM_LU results are not authoritative option targets and this
 * procedure is intentionally outside the APPLY path.
 */
CREATE OR REPLACE PROCEDURE pfc_discover_field (
    p_payor_guid          IN pfc.payor_guid%TYPE,
    p_plan_guid           IN pfc.plan_guid%TYPE DEFAULT NULL,
    p_phys_form_field_num IN linking_form_lu.phys_form_field_num%TYPE,
    p_results             OUT SYS_REFCURSOR
)
AUTHID DEFINER
IS
    l_pfc pfc_config_internal.t_pfc_resolution;
BEGIN
    pfc_config_internal.resolve_pfc(
        p_payor_guid => p_payor_guid,
        p_plan_guid  => p_plan_guid,
        p_resolution => l_pfc
    );

    OPEN p_results FOR
        SELECT
            linking.billing_form_code AS billing_form_code,
            linking.phys_form_field_num AS phys_form_field_num,
            linking.record_type_code AS record_type_code,
            linking.loop_id AS loop_id,
            linking.field_number AS field_number,
            linking.field_name AS field_name,
            linking.field_name_desc AS field_name_desc,
            linking.line_num AS line_num,
            linking.order_num AS order_num,
            linking.mandatory_ind AS mandatory_ind,
            linking.dependency_loop AS dependency_loop
        FROM linking_form_lu linking
        WHERE linking.billing_form_code = l_pfc.billing_form_code
          AND linking.phys_form_field_num = p_phys_form_field_num
        ORDER BY
            linking.record_type_code,
            linking.loop_id,
            linking.line_num,
            linking.order_num,
            linking.field_number;
END pfc_discover_field;
/
