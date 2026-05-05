"""Health profile defaults router for the Hearty food journal application.

This module provides the unauthenticated GET /api/health-profile/defaults endpoint
that returns the canonical lists of quick-select options for health profile onboarding
and settings UI. This is the authoritative source of allergens, intolerances, conditions,
and dietary protocols that users can choose from.

The endpoint requires no authentication and returns static reference data only.
"""

from fastapi import APIRouter
from pydantic import BaseModel
from .constants import (
    BIG_9_ALLERGENS,
    COMMON_INTOLERANCES,
    COMMON_CONDITIONS,
    COMMON_DIETARY_PROTOCOLS,
)


class HealthProfileDefaultsResponse(BaseModel):
    allergens: list[str]
    intolerances: list[str]
    conditions: list[str]
    dietary_protocols: list[str]


# Mount in main.py with: app.include_router(router, prefix="/api/health-profile")
router = APIRouter()


@router.get("/defaults", response_model=HealthProfileDefaultsResponse, tags=["health-profile"])
def get_health_profile_defaults() -> HealthProfileDefaultsResponse:
    """Get canonical health profile quick-select options.

    Returns all four canonical lists of health-related items for onboarding
    and settings UI. This is the authoritative source of quick-select defaults
    that the user can choose from when building their health profile.

    No authentication required — returns static reference data only.

    Returns:
        dict: A dictionary with four keys:
            - allergens: List of major allergens (Big 9 FASTER Act)
            - intolerances: List of common food intolerances
            - conditions: List of known medical conditions
            - dietary_protocols: List of common dietary approaches
    """
    return HealthProfileDefaultsResponse(
        allergens=BIG_9_ALLERGENS,
        intolerances=COMMON_INTOLERANCES,
        conditions=COMMON_CONDITIONS,
        dietary_protocols=COMMON_DIETARY_PROTOCOLS,
    )
