.PHONY: makemigrations migrate init history up up-build up-nocache down down-full

# Usage:
#   make makemigrations m="add review column"
#   make migrate
#   make init
#   make history
#   make up
#   make up-build
#   make up-nocache
#
# Requirements:
#   * docker compose (v2+)
#   * alembic configured inside the "api" service

makemigrations:
	@if [ -z "$(m)" ]; then \
		echo "❌  Migration message is required. Example:"; \
		echo "    make makemigrations m=\"add review column\""; \
		exit 1; \
	fi
	@echo "📦  Generating migration: $(m)"
	docker compose run --rm api alembic revision --autogenerate -m "$(m)"
	@latest=$$(ls -t backend/alembic/versions/*.py | head -n 1); \
	if ! grep -q "op\." "$$latest"; then \
		echo "⚠️   No schema changes detected. Removing empty migration $$latest"; \
		rm "$$latest"; \
	else \
		echo "✅  Created migration $$latest"; \
	fi

migrate:
	@echo "🚀  Applying migrations …"
	docker compose run --rm api alembic upgrade head
	@echo "✅  Database is up-to-date."

init:
	@echo "📁  Initializing Alembic directory …"
	docker compose run --rm api alembic init alembic
	@echo "✅  Alembic initialized."

history:
	@echo "📜  Viewing migration history …"
	docker compose run --rm api alembic history

up:
	@echo "🔼  Starting Docker Compose services …"
	docker compose up

up-build:
	@echo "🔨  Building and starting Docker Compose services …"
	docker compose up --build

up-nocache:
	@echo "♻️  Building without cache and starting Docker Compose services …"
	docker compose build --no-cache
	docker compose up

down:
	@echo "🔽  Stopping and removing Docker Compose containers …"
	docker compose down

down-full:
	@echo "🔽  Stopping containers and removing **volumes** …"
	docker compose down -v
