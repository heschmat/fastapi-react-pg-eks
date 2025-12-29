import time
from fastapi import FastAPI, Request
from starlette.responses import Response
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

from app.db import database
from app.routes import router
from app.models import metadata
from app.metrics import (
    REQUEST_COUNT,
    REQUEST_LATENCY,
    IN_FLIGHT,
)

app = FastAPI()
app.include_router(router)

# metadata.create_all(engine)  # Run if needed

@app.on_event("startup")
async def startup():
    await database.connect()

@app.on_event("shutdown")
async def shutdown():
    await database.disconnect()

@app.middleware("http")
async def prometheus_middleware(request: Request, call_next):
    route = request.scope.get("route")
    route_label = route.path if route else "unknown"

    IN_FLIGHT.inc()
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start
    IN_FLIGHT.dec()

    REQUEST_COUNT.labels(
        request.method,
        route_label,
        response.status_code
    ).inc()

    REQUEST_LATENCY.labels(route_label).observe(duration)

    return response


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
