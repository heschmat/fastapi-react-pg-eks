from sqlalchemy import Table, Column, Integer, String
from app.db import metadata

ratings = Table(
    "ratings",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("username", String, nullable=False),
    Column("series_name", String, nullable=False),
    Column("rating", Integer, nullable=False),
)
