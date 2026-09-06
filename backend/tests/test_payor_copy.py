import json
from types import SimpleNamespace

import oracledb
import pytest
from fastapi.testclient import TestClient

from backend.app.errors import ApiError
from backend.app.main import app, get_copy_service
from backend.app.services.payor_copy import CopyPreviewRequest, CopyApplyRequest, CopyResponse, PayorCopyService
from backend.app.services.payor_copy import CopyDestinationRequest

REQUEST={"source_payor_guid":"SYN-SOURCE","source_plan_guid":"SYN-PLAN","destination_payor_guid":"SYN-DESTINATION","audit_user":"SYN-USER"}
RESPONSE={"status":"READY","state_hash":"A"*64,"source_pfc_guid":"SYN-PFC","billing_form_code":"837I_5010",
    "line_of_business":"HOME_HEALTH","records_copied":1,"records_kept":0,"records_removed":2,
    "plan_records_removed":1,"fields_copied":4,"fields_removed":7,"template_contexts_updated":2,
    "contexts":[{"pfc_guid":"SYN-DST-PFC","plan_guid":None,"label":"Payor-level settings","templates_changed":True}],
    "changes":[{"label":"Synthetic setting","action":"COPY","level":"Source plan","record_type":"SYN-UNKNOWN"}]}


class Connection:
    def __init__(self,result=None,error=None):
        self.result=result if result is not None else RESPONSE
        self.error=error; self.statements=[]; self.commits=0; self.rollbacks=0; self.closed=False
    def cursor(self): return self
    def __enter__(self): return self
    def __exit__(self,*args): pass
    def var(self,*args): return SimpleNamespace(getvalue=lambda:json.dumps(self.result))
    def execute(self,sql,**params):
        self.statements.append((sql,params))
        if self.error and "run_copy" in sql: raise self.error
    def commit(self): self.commits+=1
    def rollback(self): self.rollbacks+=1
    def close(self): self.closed=True


@pytest.mark.parametrize("as_lob", [False, True])
def test_preview_uses_consistent_read_only_transaction_and_never_commits(as_lob):
    connection=Connection()
    if as_lob:
        connection.var = lambda *args: SimpleNamespace(
            getvalue=lambda: SimpleNamespace(read=lambda: json.dumps(connection.result)))
    result=PayorCopyService(lambda:connection).run(CopyPreviewRequest(**REQUEST))
    assert result.status=="READY"
    assert connection.statements[0][0]=="SET TRANSACTION READ ONLY"
    assert connection.statements[1][1]["source_plan"]=="SYN-PLAN"
    assert connection.statements[1][1]["expected_hash"] is None
    assert connection.commits==0 and connection.rollbacks==1 and connection.closed


def test_apply_forwards_exact_hash_and_commits_only_validated_success():
    connection=Connection({**RESPONSE,"status":"APPLIED"})
    PayorCopyService(lambda:connection).run(CopyApplyRequest(**REQUEST,expected_state_hash="B"*64),apply=True)
    assert connection.statements[0][1]["expected_hash"]=="B"*64
    assert connection.commits==1 and connection.rollbacks==0 and connection.closed


def test_malformed_apply_response_rolls_back():
    connection=Connection({"status":"APPLIED"})
    with pytest.raises(ApiError):
        PayorCopyService(lambda:connection).run(CopyApplyRequest(**REQUEST,expected_state_hash="B"*64),apply=True)
    assert connection.commits==0 and connection.rollbacks==1 and connection.closed


def test_stale_preview_and_database_details_are_translated_safely():
    connection=Connection(error=oracledb.DatabaseError(SimpleNamespace(code=20106,message="private database detail")))
    with pytest.raises(ApiError) as error:
        PayorCopyService(lambda:connection).run(CopyPreviewRequest(**REQUEST))
    assert error.value.category=="stale_preview"
    assert "private" not in error.value.message
    assert connection.rollbacks==1 and connection.closed


def test_routes_reject_destination_plan_and_require_hash_for_apply():
    with TestClient(app) as client:
        assert client.post("/api/payor-copy/preview",json={**REQUEST,"destination_plan_guid":"SYN-PLAN"}).status_code==422
        assert client.post("/api/payor-copy/apply",json=REQUEST).status_code==422
        assert client.post("/api/payor-copy/apply",json={**REQUEST,"expected_state_hash":"wrong"}).status_code==422


def test_routes_use_separate_copy_service():
    class Service:
        def run(self,request,*,apply=False):
            assert request.source_plan_guid=="SYN-PLAN"
            return CopyResponse.model_validate({**RESPONSE,"status":"APPLIED" if apply else "READY"})
    app.dependency_overrides[get_copy_service]=Service
    try:
        with TestClient(app) as client:
            assert client.post("/api/payor-copy/preview",json=REQUEST).json()["status"]=="READY"
            assert client.post("/api/payor-copy/apply",json={**REQUEST,"expected_state_hash":"B"*64}).json()["status"]=="APPLIED"
    finally: app.dependency_overrides.pop(get_copy_service,None)


@pytest.mark.parametrize("blocker", [20102, 20103, 20104, 20105, 20010, 20053])
def test_destinations_use_oracle_preview_and_exclude_blocked_candidates(blocker):
    class CatalogConnection(Connection):
        def fetchall(self): return [("SYN-GOOD", "Eligible"), ("SYN-BAD", "Ineligible")]
        def execute(self, sql, **params):
            super().execute(sql, **params)
            if params.get("destination_payor") == "SYN-BAD":
                raise oracledb.DatabaseError(SimpleNamespace(code=blocker))
    connection = CatalogConnection()
    request = CopyDestinationRequest(**{k:v for k,v in REQUEST.items() if k != "destination_payor_guid"})
    result = PayorCopyService(lambda: connection).destinations(request)
    assert [d.payor_guid for d in result.destinations] == ["SYN-GOOD"]
    assert connection.statements[0][0] == "SET TRANSACTION READ ONLY"
    assert connection.statements[1][1]["source_payor"] == "SYN-SOURCE"
    assert "payor_guid <> :source_payor" in connection.statements[1][0]
    assert all(p["source_plan"] == "SYN-PLAN" for sql,p in connection.statements if "run_copy" in sql)
    assert connection.commits == 0 and connection.rollbacks == 1 and connection.closed


def test_destinations_do_not_hide_database_failures():
    connection = Connection(error=oracledb.DatabaseError(SimpleNamespace(code=3113)))
    connection.fetchall = lambda: [("SYN-DEST", "Synthetic")]
    with pytest.raises(ApiError) as error:
        PayorCopyService(lambda: connection).destinations(CopyDestinationRequest(
            source_payor_guid="SYN-SOURCE", audit_user="SYN-USER"))
    assert error.value.category == "database_failure"
    assert connection.commits == 0 and connection.rollbacks == 1 and connection.closed
