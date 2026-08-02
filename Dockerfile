FROM python:3.13.7-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

RUN apt-get update \
    && apt-get install --yes --no-install-recommends curl ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml README.md ./
COPY config ./config
COPY umusic ./umusic
RUN pip install --no-cache-dir .

COPY manage.py ./

RUN addgroup --system umusic \
    && adduser --system --ingroup umusic umusic \
    && mkdir -p /data/media /data/quarantine /backups \
    && chown -R umusic:umusic /app /data /backups

USER umusic

EXPOSE 8000

CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "2"]
