"""Live copy tests use only dedicated synthetic fixtures and always roll back."""
import json
import os

import oracledb
import pytest

from backend.app.database import create_connection, get_oracle_settings
from database.maintenance.rebuild_hierarchy import read_state, fingerprint, insert_rows, procedure_row
from database.maintenance.seed_payor_copy import SOURCE, SOURCE_PLAN, DESTINATION, DESTINATION_PLANS, HISTORICAL_PFC

pytestmark=pytest.mark.skipif(os.getenv("RUN_ORACLE_COPY")!="1",reason="Set RUN_ORACLE_COPY=1 for the dedicated local copy demos")


def run(q,mode="PREVIEW",state_hash=None,source=SOURCE,plan=SOURCE_PLAN,destination=DESTINATION):
    out=q.var(oracledb.DB_TYPE_CLOB)
    q.execute("BEGIN pfc_copy.run_copy(:s,:p,:d,:m,'SYN_COPY_TEST',:h,:o); END;",
              s=source,p=plan,d=destination,m=mode,h=state_hash,o=out)
    return json.loads(out.getvalue().read())


@pytest.fixture
def q():
    assert get_oracle_settings().host in {"localhost", "127.0.0.1", "::1"}, "Local synthetic copy tests only"
    with create_connection() as c:
        with c.cursor() as q:
            before=fingerprint(read_state(q))
            try: yield q
            finally:
                c.rollback()
                assert fingerprint(read_state(q))==before


def test_preview_readonly_apply_flattens_and_clears_every_plan(q):
    before=read_state(q)
    preview=run(q)
    assert preview["status"]=="READY" and len(preview["contexts"])==3
    assert preview["plan_records_removed"]>0
    assert fingerprint(read_state(q))==fingerprint(before)
    result=run(q,"APPLY",preview["state_hash"])
    assert result["status"]=="APPLIED"
    after=read_state(q)
    assert [r for r in before["PFC"] if r["pfc_guid"]==HISTORICAL_PFC]==[r for r in after["PFC"] if r["pfc_guid"]==HISTORICAL_PFC]
    for table in ("PAYORS","PFC","HCFA_ELECTRONIC_RECORDS"):
        assert fingerprint({table:[r for r in before[table] if r.get("payor_guid")!=DESTINATION]})==fingerprint({table:[r for r in after[table] if r.get("payor_guid")!=DESTINATION]})
    parent_guids={r["electronic_rec_guid"] for r in before["HCFA_ELECTRONIC_RECORDS"] if r["payor_guid"]!=DESTINATION}
    assert fingerprint({"hefs":[r for r in before["HCFA_ELECTRONIC_FIELDS"] if r["electronic_rec_guid"] in parent_guids]})==fingerprint({"hefs":[r for r in after["HCFA_ELECTRONIC_FIELDS"] if r["electronic_rec_guid"] in parent_guids]})
    for plan in [None,*DESTINATION_PLANS]:
        row=procedure_row(q,"pfc_get_current_config",[DESTINATION,plan,"81"])
        assert row["effective_option_code"]=="PROVIDER_TAXONOMY_OFF"
        row=procedure_row(q,"pfc_remarks_api.current_configuration",[DESTINATION,plan])
        assert row["configuration_status"]=="RESOLVED"
    q.execute("SELECT COUNT(*) FROM hcfa_electronic_records WHERE payor_guid=:d AND plan_guid IS NOT NULL",d=DESTINATION)
    assert q.fetchone()[0]==0
    q.execute("SELECT record_type_code FROM hcfa_electronic_records WHERE payor_guid=:d",d=DESTINATION)
    records={r[0] for r in q}
    assert "SYN_COPY_UNKNOWN" in records and "SYN_COPY_EXTRA" not in records
    repeat=run(q)
    assert repeat["status"]=="NO_CHANGE" and repeat["records_kept"]==preview["records_copied"]


def test_destination_catalog_matches_live_preview_without_changes(q):
    from backend.app.services.payor_copy import PayorCopyService, CopyDestinationRequest
    before = fingerprint(read_state(q))
    result = PayorCopyService().destinations(CopyDestinationRequest(
        source_payor_guid=SOURCE, source_plan_guid=SOURCE_PLAN, audit_user="SYN_COPY_TEST"))
    actual = {item.payor_guid for item in result.destinations}
    assert DESTINATION in actual and SOURCE not in actual
    q.execute("SELECT payor_guid FROM payors WHERE payor_id LIKE 'SYN-%' AND payor_guid<>:s", s=SOURCE)
    candidates = [row[0] for row in q.fetchall()]
    for candidate in candidates:
        try:
            preview = run(q, destination=candidate)
        except oracledb.DatabaseError:
            assert candidate not in actual
        else:
            assert preview["status"] in {"READY", "NO_CHANGE"}
            assert candidate in actual
    assert fingerprint(read_state(q)) == before


def test_no_plan_source_does_not_copy_source_plan_overrides(q):
    preview=run(q,plan=None)
    run(q,"APPLY",preview["state_hash"],plan=None)
    row=procedure_row(q,"pfc_get_current_config",[DESTINATION,None,"81"])
    assert row["effective_option_code"]=="PROVIDER_TAXONOMY_ON"
    q.execute("SELECT COUNT(*) FROM hcfa_electronic_records WHERE payor_guid=:d AND record_type_code='SYN_COPY_UNKNOWN'",d=DESTINATION)
    assert q.fetchone()[0]==0


@pytest.mark.parametrize("side",["source","destination","template","pfc","plan"])
def test_stale_preview_catches_both_hierarchies_and_context_changes(q,side):
    preview=run(q)
    if side in {"source","destination"}:
        q.execute("UPDATE hcfa_electronic_records SET notes='Synthetic changed after preview' WHERE payor_guid=:p",p=SOURCE if side=="source" else DESTINATION)
    elif side=="template":
        q.execute("UPDATE hcfa_electronic_records SET notes='Synthetic template change' WHERE payor_guid IS NULL AND record_type_code='D23002310HI286'")
    elif side=="pfc":
        q.execute("UPDATE pfc SET rec_ent_date=rec_ent_date+1/86400 WHERE payor_guid=:d",d=DESTINATION)
    else:
        q.execute("UPDATE pfc_config_plans SET plan_name='Synthetic changed label' WHERE plan_guid=:p",p=DESTINATION_PLANS[0])
    before=fingerprint(read_state(q))
    with pytest.raises(oracledb.DatabaseError,match="20106"):
        run(q,"APPLY",preview["state_hash"])
    assert fingerprint(read_state(q))==before


def test_same_payor_lob_and_billing_mismatches_block(q):
    with pytest.raises(oracledb.DatabaseError,match="20101"): run(q,destination=SOURCE)
    q.execute("UPDATE pfc_config_payor_context SET line_of_business='HOSPICE' WHERE payor_guid=:d",d=DESTINATION)
    with pytest.raises(oracledb.DatabaseError,match="20102"): run(q)
    q.connection.rollback()
    q.execute("UPDATE pfc SET billing_form_code='837P_5010' WHERE payor_guid=:d AND plan_guid=:p",d=DESTINATION,p=DESTINATION_PLANS[0])
    with pytest.raises(oracledb.DatabaseError,match="20103"): run(q)


def test_tied_winner_blocks_and_older_pfc_does_not_win(q):
    q.execute("UPDATE pfc SET rec_ent_date=DATE '2026-09-01' WHERE pfc_guid=:g",g=HISTORICAL_PFC)
    with pytest.raises(oracledb.DatabaseError,match="20104"): run(q)


def test_complete_unknown_hefs_and_large_state_are_copied(q):
    source_guid="F4000000-0000-0000-0000-000000000001"
    q.execute("SELECT * FROM hcfa_electronic_fields WHERE electronic_rec_guid=:g FETCH FIRST 1 ROW ONLY",g=source_guid)
    field=dict(zip([d[0].lower() for d in q.description],q.fetchone()))
    insert_rows(q,"HCFA_ELECTRONIC_FIELDS",[{**field,"field_number":f"SYN{i}","field_name_desc":"Synthetic "+"x"*1900,"order_num":100+i} for i in range(40)])
    preview=run(q)
    run(q,"APPLY",preview["state_hash"])
    q.execute("SELECT electronic_rec_guid FROM hcfa_electronic_records WHERE payor_guid=:d AND record_type_code='SYN_COPY_UNKNOWN'",d=DESTINATION)
    copied=q.fetchone()[0]
    assert copied!=source_guid
    def children(guid):
        q.execute("SELECT * FROM hcfa_electronic_fields WHERE electronic_rec_guid=:g",g=guid)
        keys=[d[0].lower() for d in q.description]
        return sorted([repr({k:v for k,v in zip(keys,row) if k not in {'electronic_rec_guid','rec_ent_date','rec_ent_user','rec_mod_date','rec_mod_user'}}) for row in q])
    assert children(source_guid)==children(copied)


def test_empty_source_override_set_clears_destination(q):
    q.execute("DELETE FROM hcfa_electronic_fields WHERE electronic_rec_guid IN (SELECT electronic_rec_guid FROM hcfa_electronic_records WHERE payor_guid=:s)",s=SOURCE)
    q.execute("DELETE FROM hcfa_electronic_records WHERE payor_guid=:s",s=SOURCE)
    preview=run(q)
    assert preview["records_copied"]==0 and preview["records_removed"]>0
    run(q,"APPLY",preview["state_hash"])
    q.execute("SELECT COUNT(*) FROM hcfa_electronic_records WHERE payor_guid=:d",d=DESTINATION)
    assert q.fetchone()[0]==0


def test_failure_after_mutation_restores_full_destination(q):
    # Install a dedicated failure trigger in a separate DDL session; never commit test DML.
    with create_connection() as ddl:
        with ddl.cursor() as trigger:
            trigger.execute("""CREATE OR REPLACE TRIGGER syn_copy_failure
                BEFORE INSERT ON hcfa_electronic_fields FOR EACH ROW
                BEGIN
                    IF :NEW.rec_ent_user='SYN_COPY_TEST' THEN
                        RAISE_APPLICATION_ERROR(-20998,'Synthetic forced copy failure');
                    END IF;
                END;""")
    try:
        before=fingerprint(read_state(q)); preview=run(q)
        with pytest.raises(oracledb.DatabaseError,match="20998"):
            run(q,"APPLY",preview["state_hash"])
        assert fingerprint(read_state(q))==before
    finally:
        q.connection.rollback()
        with create_connection() as ddl:
            with ddl.cursor() as trigger: trigger.execute("DROP TRIGGER syn_copy_failure")


def test_explicit_safety_normalization_changes_only_destination(q):
    q.execute("UPDATE hcfa_electronic_records SET mandatory_ind='Y',carry_forward_ind='Y',include_record_data_onclaim='N' WHERE electronic_rec_guid='F4000000-0000-0000-0000-000000000001'")
    preview=run(q)
    assert preview["records_normalized"]>0
    run(q,"APPLY",preview["state_hash"])
    q.execute("SELECT mandatory_ind,carry_forward_ind,include_record_data_onclaim FROM hcfa_electronic_records WHERE payor_guid=:d AND record_type_code='SYN_COPY_UNKNOWN'",d=DESTINATION)
    assert q.fetchone()==('N',None,'Y')
    q.execute("SELECT mandatory_ind FROM hcfa_electronic_records WHERE electronic_rec_guid='F4000000-0000-0000-0000-000000000001'")
    assert q.fetchone()[0]=='Y'


def test_null_source_template_associations_clear_all_current_destination_associations(q):
    q.execute("UPDATE pfc SET form_template_guid=NULL,user_form_template_guid=NULL WHERE payor_guid=:s",s=SOURCE)
    preview=run(q)
    run(q,"APPLY",preview["state_hash"])
    q.execute("SELECT COUNT(*) FROM pfc WHERE payor_guid=:d AND pfc_guid<>:h AND (form_template_guid IS NOT NULL OR user_form_template_guid IS NOT NULL)",d=DESTINATION,h=HISTORICAL_PFC)
    assert q.fetchone()[0]==0


def test_type_specific_inherited_difference_blocks_copy(q):
    q.execute("UPDATE payors SET payor_type_guid='SYN_COPY_OTHER_TYPE' WHERE payor_guid=:d",d=DESTINATION)
    q.execute("SELECT * FROM hcfa_electronic_records WHERE electronic_rec_guid='F4000000-0000-0000-0000-000000000001'")
    row=dict(zip([d[0].lower() for d in q.description],q.fetchone()))
    insert_rows(q,'HCFA_ELECTRONIC_RECORDS',[{**row,'electronic_rec_guid':'SYN_COPY_TYPE_ONLY','payor_guid':None,'plan_guid':None,
        'payor_type_guid':'SYN_COPY_OTHER_TYPE','record_type_code':'SYN_COPY_TYPE_ONLY'}])
    with pytest.raises(oracledb.DatabaseError,match='20105'): run(q)


def test_normal_plan_editing_after_copy_keeps_parent_and_unknown_settings(q):
    from database.maintenance.seed_payor_plans import apply_option
    preview=run(q);run(q,'APPLY',preview['state_hash'])
    apply_option(q,DESTINATION,DESTINATION_PLANS[0],'PROVIDER_TAXONOMY_ON')
    assert procedure_row(q,'pfc_get_current_config',[DESTINATION,DESTINATION_PLANS[0],'81'])['effective_option_code']=='PROVIDER_TAXONOMY_ON'
    assert procedure_row(q,'pfc_get_current_config',[DESTINATION,None,'81'])['effective_option_code']=='PROVIDER_TAXONOMY_OFF'
    assert procedure_row(q,'pfc_get_current_config',[DESTINATION,DESTINATION_PLANS[1],'81'])['effective_option_code']=='PROVIDER_TAXONOMY_OFF'
    q.execute("SELECT COUNT(*) FROM hcfa_electronic_records WHERE payor_guid=:d AND record_type_code='SYN_COPY_UNKNOWN'",d=DESTINATION)
    assert q.fetchone()[0]==1
