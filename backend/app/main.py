from fastapi import FastAPI
from app.db import database
from app.models import metadata
from app.db import engine
from app.routes import router

app = FastAPI()
app.include_router(router)

# metadata.create_all(engine)  # Run if needed

@app.on_event("startup")
async def startup():
    await database.connect()

@app.on_event("shutdown")
async def shutdown():
    await database.disconnect()
