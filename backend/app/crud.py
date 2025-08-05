from sqlalchemy import func, select
from app.models import ratings
from app.db import database

async def insert_rating(rating_data):
    query = ratings.insert().values(**rating_data)
    await database.execute(query)

async def get_recent_ratings(limit=4):
    query = ratings.select().order_by(ratings.c.id.desc()).limit(limit)
    return await database.fetch_all(query)

async def get_series_stats(series_name: str):
    query = select(
        func.count(ratings.c.id).label("num_ratings"),
        func.avg(ratings.c.rating).label("avg_rating")
    ).where(func.lower(ratings.c.series_name) == series_name.lower())

    return await database.fetch_one(query)
