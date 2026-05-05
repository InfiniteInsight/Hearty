"""Pydantic validation schemas for health profile JSONB fields.

Used by the REST API layer (Phase 3) to validate incoming data and by the
context-injection helper (Phase 4) to serialise outgoing data.
"""

import re
from datetime import datetime
from enum import Enum

from pydantic import BaseModel, field_validator


class SeverityEnum(str, Enum):
    mild = "mild"
    moderate = "moderate"
    severe = "severe"


class AllergenEntry(BaseModel):
    name: str
    severity: SeverityEnum
    reaction: str | None = None
    confirmed_by_doctor: bool = False
    notes: str | None = None


class IntoleranceEntry(BaseModel):
    name: str
    severity: SeverityEnum | None = None
    threshold: str | None = None
    notes: str | None = None


class ConditionEntry(BaseModel):
    name: str
    diagnosed: bool = False
    diagnosis_year: int | None = None
    notes: str | None = None


_ISO_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


class DietaryProtocolEntry(BaseModel):
    name: str
    active: bool = True
    started: str | None = None
    phase: str | None = None
    notes: str | None = None

    @field_validator("started")
    @classmethod
    def validate_started_date(cls, v: str | None) -> str | None:
        if v is not None and not _ISO_DATE_RE.match(v):
            raise ValueError("started must be an ISO 8601 date string (YYYY-MM-DD)")
        return v


class HealthProfileResponse(BaseModel):
    allergens: list[AllergenEntry] = []
    intolerances: list[IntoleranceEntry] = []
    conditions: list[ConditionEntry] = []
    dietary_protocols: list[DietaryProtocolEntry] = []
    updated_at: datetime


class HealthProfilePutRequest(BaseModel):
    allergens: list[AllergenEntry]
    intolerances: list[IntoleranceEntry]
    conditions: list[ConditionEntry]
    dietary_protocols: list[DietaryProtocolEntry]


class HealthProfilePatchRequest(BaseModel):
    allergens: list[AllergenEntry] | None = None
    intolerances: list[IntoleranceEntry] | None = None
    conditions: list[ConditionEntry] | None = None
    dietary_protocols: list[DietaryProtocolEntry] | None = None


class AllergensUpdateRequest(BaseModel):
    allergens: list[AllergenEntry]


class IntolerancesUpdateRequest(BaseModel):
    intolerances: list[IntoleranceEntry]


class ConditionsUpdateRequest(BaseModel):
    conditions: list[ConditionEntry]


class DietaryProtocolsUpdateRequest(BaseModel):
    dietary_protocols: list[DietaryProtocolEntry]
