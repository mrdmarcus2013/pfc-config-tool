"""Current capabilities describe inheritance separately from the Default edit intent."""

import json

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from backend.app.errors import ApiError
from backend.app.main import app, get_configuration_service
from backend.app.models import ValueCodesCurrentResponse
from backend.app.services.configuration import ConfigurationService
from backend.tests.test_configuration_service import make_value_codes_current_connection


CONTEXT = {"payor_guid": "synthetic-payor", "plan_guid": None}
METADATA_COLUMNS = ("effective_selections", "inherited_selections")


def selections(**overrides):
    return {
        "cbsa": False, "fips": False, "care_location_value_code": False,
        "patient_entered_value_code": False, "covered_days_value_code": False,
        **overrides,
    }


def current(connection, **context):
    return ConfigurationService(lambda: connection).value_codes_current(**{**CONTEXT, **context})


@pytest.mark.parametrize(("plan_guid", "owner_level"), [
    (None, "USER_TEMPLATE"),
    ("synthetic-plan", "PAYOR"),
])
def test_inherited_capabilities_preserve_default_intent_and_parent_ownership(plan_guid, owner_level):
    capabilities = selections(cbsa=True, fips=True)
    owners = [{"target": "Value Codes", "level": owner_level, "identifier": "synthetic-owner"}]
    connection = make_value_codes_current_connection(
        effective_selections=json.dumps(capabilities), inherited_selections=json.dumps(capabilities),
        display_summary="CBSA and FIPS (inherited)", configuration_owners=json.dumps(owners),
    )

    response = current(connection, plan_guid=plan_guid)

    assert response["is_default"] is True
    assert response["selections"] == selections()
    assert response["effective_selections"] == capabilities
    assert response["inherited_selections"] == capabilities
    assert response["configuration_owners"] == owners
    assert response["display_summary"] == "CBSA and FIPS (inherited)"
    assert connection._cursor.binds["plan_guid"] == plan_guid
    assert connection._cursor.execute_count == 1
    assert connection.commits == 0
    assert connection.rollbacks == 1
    assert connection.closed
    assert ValueCodesCurrentResponse.model_validate(response).model_dump() == response


def test_plan_override_retains_distinct_effective_and_parent_capabilities():
    capabilities = selections(cbsa=True, fips=True)
    inherited = selections(cbsa=True)
    owners = [{"target": "Value Codes", "level": "PAYOR_PLAN", "identifier": "synthetic-plan"}]
    connection = make_value_codes_current_connection(
        is_default="N", cbsa="Y", fips="Y", canonical_status="CANONICAL",
        effective_selections=json.dumps(capabilities), inherited_selections=json.dumps(inherited),
        display_summary="CBSA and FIPS", configuration_owners=json.dumps(owners),
    )

    response = current(connection, plan_guid="synthetic-plan")

    assert response["is_default"] is False
    assert response["selections"] == capabilities
    assert response["effective_selections"] == capabilities
    assert response["inherited_selections"] == inherited
    assert response["configuration_owners"] == owners
    assert connection.commits == 0
    assert connection.rollbacks == 1


@pytest.mark.parametrize("unknown_columns", [
    ("effective_selections",), ("inherited_selections",), METADATA_COLUMNS,
])
def test_explicit_sql_null_remains_unknown_instead_of_disabled(unknown_columns):
    connection = make_value_codes_current_connection(**{column: None for column in unknown_columns})
    response = current(connection)
    for column in METADATA_COLUMNS:
        assert response[column] == (None if column in unknown_columns else selections())
    serialized = json.loads(ValueCodesCurrentResponse.model_validate(response).model_dump_json())
    assert all(serialized[column] is None for column in unknown_columns)
    assert connection.commits == 0
    assert connection.rollbacks == 1


@pytest.mark.parametrize(("lob", "capabilities"), [
    ("HOME_HEALTH", selections()),
    ("HOME_HEALTH", selections(cbsa=True)),
    ("HOSPICE", selections()),
    ("HOSPICE", selections(care_location_value_code=True)),
    ("HOSPICE", selections(patient_entered_value_code=True, covered_days_value_code=True)),
    ("HOSPICE", selections(covered_days_value_code=True)),
])
def test_known_capabilities_use_the_complete_supported_lob_shape(lob, capabilities):
    connection = make_value_codes_current_connection(
        line_of_business=lob,
        **{column: json.dumps(capabilities) for column in METADATA_COLUMNS},
    )
    response = current(connection)
    assert all(response[column] == capabilities for column in METADATA_COLUMNS)


@pytest.mark.parametrize("column", METADATA_COLUMNS)
@pytest.mark.parametrize(("raw", "lob"), [
    ("", "HOME_HEALTH"),
    ("{", "HOME_HEALTH"),
    ("null", "HOME_HEALTH"),
    ("[]", "HOME_HEALTH"),
    ('"CBSA"', "HOME_HEALTH"),
    ("true", "HOME_HEALTH"),
    ("{}", "HOME_HEALTH"),
    ('{"cbsa":true}', "HOME_HEALTH"),
    (json.dumps(selections(extra=False)), "HOME_HEALTH"),
    (json.dumps(selections(cbsa="Y")), "HOME_HEALTH"),
    (json.dumps(selections(cbsa="false")), "HOME_HEALTH"),
    (json.dumps(selections(cbsa=1)), "HOME_HEALTH"),
    (json.dumps(selections(cbsa=None)), "HOME_HEALTH"),
    (json.dumps(selections())[:-1] + ',"cbsa":true}', "HOME_HEALTH"),
    (selections(), "HOME_HEALTH"),
    (json.dumps(selections(fips=True)), "HOME_HEALTH"),
    (json.dumps(selections(care_location_value_code=True, patient_entered_value_code=True)), "HOSPICE"),
    (json.dumps(selections(care_location_value_code=True)), "HOME_HEALTH"),
    (json.dumps(selections(patient_entered_value_code=True)), "HOME_HEALTH"),
    (json.dumps(selections(covered_days_value_code=True)), "HOME_HEALTH"),
    (json.dumps(selections(cbsa=True, fips=True)), "HOSPICE"),
])
def test_invalid_metadata_fails_safely_without_partial_or_disabled_result(column, raw, lob):
    connection = make_value_codes_current_connection(line_of_business=lob, **{column: raw})

    with pytest.raises(ApiError) as caught:
        current(connection)

    assert caught.value.status_code == 500
    assert caught.value.category == "application_failure"
    assert caught.value.message == "Value Codes could not be resolved safely."
    assert connection.commits == 0
    assert connection.rollbacks == 1
    assert connection._cursor._output.getvalue().closed
    assert connection.closed


@pytest.mark.parametrize("column", METADATA_COLUMNS)
def test_missing_oracle_metadata_column_is_a_contract_failure(column):
    connection = make_value_codes_current_connection()
    cursor = connection._cursor._output.getvalue()
    index = [name[0].lower() for name in cursor.description].index(column)
    cursor.description.pop(index)
    cursor._rows[0].pop(index)

    with pytest.raises(ApiError) as caught:
        current(connection)

    assert caught.value.category == "application_failure"
    assert connection.commits == 0
    assert connection.rollbacks == 1


@pytest.mark.parametrize("column", METADATA_COLUMNS)
def test_current_response_requires_both_metadata_fields_even_when_unknown(column):
    response = current(make_value_codes_current_connection(
        effective_selections=None, inherited_selections=None,
    ))
    response.pop(column)
    with pytest.raises(ValidationError) as caught:
        ValueCodesCurrentResponse.model_validate(response)
    assert caught.value.errors()[0]["loc"] == (column,)
    assert caught.value.errors()[0]["type"] == "missing"


def test_current_api_serializes_unknown_metadata_explicitly():
    connection = make_value_codes_current_connection(
        effective_selections=None, inherited_selections=None,
    )
    app.dependency_overrides[get_configuration_service] = lambda: ConfigurationService(lambda: connection)
    try:
        response = TestClient(app).post("/api/config/value-codes/current", json=CONTEXT)
        assert response.status_code == 200
        assert response.json()["effective_selections"] is None
        assert response.json()["inherited_selections"] is None
        assert response.json()["selections"] == selections()
    finally:
        app.dependency_overrides.pop(get_configuration_service, None)


def test_openapi_distinguishes_required_nullable_current_metadata_from_edit_intent():
    schemas = app.openapi()["components"]["schemas"]
    current_schema = schemas["ValueCodesCurrentResponse"]
    for column in METADATA_COLUMNS:
        assert column in current_schema["required"]
        assert current_schema["properties"][column]["anyOf"] == [
            {"$ref": "#/components/schemas/ValueCodeSelections"}, {"type": "null"},
        ]
    for name in ("ValueCodesChangeRequest", "ValueCodesApplyRequest", "ValueCodesChangeResponse"):
        assert not set(METADATA_COLUMNS).intersection(schemas[name]["properties"])
