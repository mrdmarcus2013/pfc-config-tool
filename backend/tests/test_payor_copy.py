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


class CleanupCursor:
    def __init__(self, connection):
        self.connection = connection

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def var(self, *args):
        return self.connection.var(*args)

    def execute(self, sql, **params):
        self.connection.execute(sql, **params)

    def fetchall(self):
        return [("SYN-DESTINATION", "Synthetic destination")]

    def close(self):
        self.connection.events.append("cursor.close")
        if self.connection.cursor_error is not None:
            raise self.connection.cursor_error


class CleanupConnection(Connection):
    def __init__(self, result=None, error=None, *, cursor_error=None, rollback_error=None,
                 close_error=None, commit_error=None):
        super().__init__(result, error)
        self.cursor_error = cursor_error
        self.rollback_error = rollback_error
        self.close_error = close_error
        self.commit_error = commit_error
        self.events = []

    def cursor(self):
        return CleanupCursor(self)

    def commit(self):
        self.events.append("commit")
        if self.commit_error is not None:
            raise self.commit_error
        super().commit()

    def rollback(self):
        self.events.append("rollback")
        super().rollback()
        if self.rollback_error is not None:
            raise self.rollback_error

    def close(self):
        self.events.append("connection.close")
        super().close()
        if self.close_error is not None:
            raise self.close_error


def failing_cleanup(**overrides):
    return {"cursor_error": RuntimeError("private cursor cleanup detail"),
            "rollback_error": RuntimeError("private rollback cleanup detail"),
            "close_error": RuntimeError("private connection cleanup detail"), **overrides}


def test_saved_copy_survives_connection_cleanup_failure(caplog):
    connection = CleanupConnection({**RESPONSE, "status": "APPLIED"},
                                   close_error=RuntimeError("private connection cleanup detail"))
    result = PayorCopyService(lambda: connection).run(
        CopyApplyRequest(**REQUEST, expected_state_hash="B" * 64), apply=True)
    assert result.status == "APPLIED"
    assert connection.commits == 1 and connection.rollbacks == 0
    assert connection.events == ["cursor.close", "commit", "connection.close"]
    assert "private connection cleanup detail" not in caplog.text


def test_saved_copy_api_response_survives_connection_cleanup_failure():
    connection = CleanupConnection({**RESPONSE, "status": "APPLIED"},
                                   close_error=RuntimeError("private connection cleanup detail"))
    app.dependency_overrides[get_copy_service] = lambda: PayorCopyService(lambda: connection)
    try:
        with TestClient(app) as client:
            response = client.post("/api/payor-copy/apply", json={**REQUEST, "expected_state_hash": "B" * 64})
        assert response.status_code == 200
        assert response.json()["status"] == "APPLIED"
        assert connection.commits == 1 and connection.rollbacks == 0
    finally:
        app.dependency_overrides.pop(get_copy_service, None)


@pytest.mark.parametrize("primary,category", [
    (oracledb.DatabaseError(SimpleNamespace(code=20106, message="private Oracle detail")), "stale_preview"),
    (ApiError(409, "synthetic_primary", "Synthetic primary error"), "synthetic_primary"),
])
def test_copy_primary_error_survives_all_cleanup_failures(primary, category, caplog):
    connection = CleanupConnection(error=primary, **failing_cleanup())
    with pytest.raises(ApiError) as caught:
        PayorCopyService(lambda: connection).run(
            CopyApplyRequest(**REQUEST, expected_state_hash="B" * 64), apply=True)
    assert caught.value.category == category
    assert "private" not in caught.value.message and "private" not in caplog.text
    assert connection.commits == 0 and connection.rollbacks == 1
    assert connection.events == ["cursor.close", "rollback", "connection.close"]


def test_copy_cursor_cleanup_failure_before_commit_rolls_back():
    connection = CleanupConnection({**RESPONSE, "status": "APPLIED"}, **failing_cleanup())
    with pytest.raises(ApiError) as caught:
        PayorCopyService(lambda: connection).run(
            CopyApplyRequest(**REQUEST, expected_state_hash="B" * 64), apply=True)
    assert caught.value.category == "application_failure"
    assert connection.commits == 0 and connection.rollbacks == 1
    assert connection.events == ["cursor.close", "rollback", "connection.close"]


def test_copy_invalid_response_still_rolls_back_when_cleanup_also_fails():
    connection = CleanupConnection({"status": "APPLIED"}, **failing_cleanup())
    with pytest.raises(ApiError) as caught:
        PayorCopyService(lambda: connection).run(
            CopyApplyRequest(**REQUEST, expected_state_hash="B" * 64), apply=True)
    assert caught.value.category == "application_failure"
    assert connection.commits == 0 and connection.rollbacks == 1 and connection.closed


def test_copy_serialization_failure_rolls_back_before_commit(monkeypatch):
    def fail_serialization(self, *args, **kwargs):
        raise ValueError("private serialization detail")

    monkeypatch.setattr(CopyResponse, "model_dump_json", fail_serialization)
    connection = CleanupConnection({**RESPONSE, "status": "APPLIED"})
    with pytest.raises(ApiError) as caught:
        PayorCopyService(lambda: connection).run(
            CopyApplyRequest(**REQUEST, expected_state_hash="B" * 64), apply=True)
    assert caught.value.category == "application_failure"
    assert connection.commits == 0 and connection.rollbacks == 1
    assert connection.events == ["cursor.close", "rollback", "connection.close"]


def test_copy_commit_failure_keeps_primary_database_error_when_cleanup_also_fails():
    connection = CleanupConnection({**RESPONSE, "status": "APPLIED"},
        commit_error=oracledb.DatabaseError(SimpleNamespace(code=3113, message="private commit detail")),
        **failing_cleanup(cursor_error=None))
    with pytest.raises(ApiError) as caught:
        PayorCopyService(lambda: connection).run(
            CopyApplyRequest(**REQUEST, expected_state_hash="B" * 64), apply=True)
    assert caught.value.category == "database_failure"
    assert connection.commits == 0 and connection.rollbacks == 1
    assert connection.events == ["cursor.close", "commit", "rollback", "connection.close"]


@pytest.mark.parametrize("operation", ["preview", "destinations"])
def test_read_only_copy_results_survive_cleanup_failures(operation):
    connection = CleanupConnection(**failing_cleanup())
    service = PayorCopyService(lambda: connection)
    if operation == "preview":
        result = service.run(CopyPreviewRequest(**REQUEST))
        assert result.status == "READY"
    else:
        result = service.destinations(CopyDestinationRequest(source_payor_guid="SYN-SOURCE", audit_user="SYN-USER"))
        assert [item.payor_guid for item in result.destinations] == ["SYN-DESTINATION"]
    assert connection.commits == 0 and connection.rollbacks == 1
    assert connection.events == ["cursor.close", "rollback", "connection.close"]


@pytest.mark.parametrize("primary,category", [
    (oracledb.DatabaseError(SimpleNamespace(code=3113, message="private Oracle detail")), "database_failure"),
    (ApiError(409, "synthetic_primary", "Synthetic primary error"), "synthetic_primary"),
])
def test_destination_primary_error_survives_all_cleanup_failures(primary, category):
    connection = CleanupConnection(error=primary, **failing_cleanup())
    with pytest.raises(ApiError) as caught:
        PayorCopyService(lambda: connection).destinations(CopyDestinationRequest(
            source_payor_guid="SYN-SOURCE", audit_user="SYN-USER"))
    assert caught.value.category == category
    assert connection.commits == 0 and connection.rollbacks == 1
    assert connection.events == ["cursor.close", "rollback", "connection.close"]
