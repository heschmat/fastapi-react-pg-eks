import time
from prometheus_client import Counter, Histogram, Gauge

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "route", "status"]
)

REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["route"]
)

IN_FLIGHT = Gauge(
    "http_requests_in_flight",
    "In-flight HTTP requests"
)

DB_LATENCY = Histogram(
    "db_query_duration_seconds",
    "Database query latency",
    ["operation"]
)
