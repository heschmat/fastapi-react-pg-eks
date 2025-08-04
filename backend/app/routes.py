from fastapi import APIRouter, HTTPException, Path
from typing import List

from app.schemas import RatingIn, RatingOut
from app.crud import insert_rating, get_recent_ratings, get_series_stats

router = APIRouter()

@router.get("/")
async def feeling_lucky():
    return {"message": "helloooooooo"}

@router.post("/rate")
async def rate_series(rating: RatingIn):
    await insert_rating(rating.dict())
    return {"status": "success", "data": rating}

@router.get("/recent", response_model=List[RatingOut])
async def recent_ratings():
    return await get_recent_ratings()

@router.get("/series/{series_name}/stats")
async def series_stats(series_name: str = Path(..., description="Series name to get stats for")):
    result = await get_series_stats(series_name)

    if not result or result["num_ratings"] == 0:
        return {"series_name": series_name, "num_ratings": 0, "avg_rating": None}

    return {
        "series_name": series_name,
        "num_ratings": result["num_ratings"],
        "avg_rating": round(result["avg_rating"], 2)
    }
