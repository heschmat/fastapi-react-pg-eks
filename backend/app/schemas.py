from pydantic import BaseModel, conint

class RatingIn(BaseModel):
    username: str
    series_name: str
    rating: conint(ge=0, le=5)

class RatingOut(BaseModel):
    username: str
    series_name: str
    rating: int
