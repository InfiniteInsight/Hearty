from fastapi import APIRouter, Depends

from app.auth import get_current_user
from app.models.schemas import (FoodLookupRequest, FoodLookupResponse,
                                 FoodCacheResponse)
from app.services import food_lookup, food_cache

router = APIRouter()


@router.post("/api/food/lookup", status_code=200)
async def lookup(body: FoodLookupRequest,
                 user=Depends(get_current_user)) -> FoodLookupResponse:
    result = food_lookup.lookup_food(body.type, body.value, body.restaurant, user["id"])
    return FoodLookupResponse(**result)


@router.get("/api/food/cache/{key:path}", status_code=200)
async def cache_check(key: str,
                      user=Depends(get_current_user)) -> FoodCacheResponse:
    cached = food_cache.get_cached(key)
    return FoodCacheResponse(hit=cached is not None, nutrition=cached)
