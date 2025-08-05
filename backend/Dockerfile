FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy app code and supporting scripts
COPY app ./app
COPY start.sh .
COPY wait-for-it.sh .
COPY alembic.ini .
COPY alembic ./alembic

# Make sure scripts are executable
RUN chmod +x start.sh wait-for-it.sh

# Use the script as entrypoint
ENTRYPOINT ["./start.sh"]
