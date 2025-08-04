#!/bin/sh

echo "⏳ Waiting for PostgreSQL using wait-for-it.sh..."
./wait-for-it.sh db:5432 --timeout=30 --strict -- echo "✅ PostgreSQL is up"

echo "🚀 Running Alembic migrations..."
alembic upgrade head
# alembic upgrade head --raiseerr --config alembic.ini

echo "⚙️ Starting FastAPI app..."
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
