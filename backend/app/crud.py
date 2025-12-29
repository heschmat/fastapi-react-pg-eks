import time
from sqlalchemy import func, select
from app.models import ratings
from app.db import database
from app.metrics import DB_LATENCY


async def insert_rating(rating_data):
    start = time.time()
    query = ratings.insert().values(**rating_data)
    await database.execute(query)
    DB_LATENCY.labels("insert_rating").observe(time.time() - start)


async def get_recent_ratings(limit=3):
    start = time.time()
    query = ratings.select().order_by(ratings.c.id.desc()).limit(limit)
    result = await database.fetch_all(query)
    DB_LATENCY.labels("get_recent_ratings").observe(time.time() - start)
    return result


async def get_series_stats(series_name: str):
    start = time.time()
    query = select(
        func.count(ratings.c.id).label("num_ratings"),
        func.avg(ratings.c.rating).label("avg_rating")
    ).where(func.lower(ratings.c.series_name) == series_name.lower())

    result = await database.fetch_one(query)
    DB_LATENCY.labels("get_series_stats").observe(time.time() - start)
    return result
