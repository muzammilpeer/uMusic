from pathlib import Path

import environ

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env(
    DJANGO_DEBUG=(bool, False),
    DJANGO_ALLOWED_HOSTS=(list, ["localhost", "127.0.0.1"]),
    DJANGO_CSRF_TRUSTED_ORIGINS=(list, []),
)
environ.Env.read_env(BASE_DIR / ".env")

SECRET_KEY = env("DJANGO_SECRET_KEY", default="unsafe-local-development-key")
DEBUG = env.bool("DJANGO_DEBUG")
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS")
CSRF_TRUSTED_ORIGINS = env.list("DJANGO_CSRF_TRUSTED_ORIGINS")

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "umusic.apps.accounts",
    "umusic.apps.library",
    "umusic.apps.playback",
    "umusic.apps.events",
    "umusic.apps.contexts",
    "umusic.apps.playlists",
    "umusic.apps.recommendations",
    "umusic.apps.imports",
    "umusic.apps.sync",
    "umusic.apps.operations",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "umusic.apps.operations.middleware.RequestLogMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SESSION_COOKIE_SECURE = env.bool("DJANGO_SECURE_COOKIES", default=False)
CSRF_COOKIE_SECURE = env.bool("DJANGO_SECURE_COOKIES", default=False)

ROOT_URLCONF = "config.urls"
TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ]
        },
    }
]
WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

DATABASES = {
    "default": env.db(
        "DATABASE_URL",
        default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}",
    )
}

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_ROOT = Path(env("UMUSIC_MEDIA_ROOT", default=str(BASE_DIR / "media")))
MEDIA_URL = "media/"
UMUSIC_QUARANTINE_ROOT = Path(env("UMUSIC_QUARANTINE_ROOT", default=str(BASE_DIR / "quarantine")))
UMUSIC_STORAGE_BACKEND = env("UMUSIC_STORAGE_BACKEND", default="local")
UMUSIC_MAX_UPLOAD_BYTES = env.int("UMUSIC_MAX_UPLOAD_BYTES", default=150 * 1024 * 1024)
UMUSIC_MAX_UPLOAD_FILES = env.int("UMUSIC_MAX_UPLOAD_FILES", default=100)
UMUSIC_SIGNED_URL_TTL_SECONDS = env.int("UMUSIC_SIGNED_URL_TTL_SECONDS", default=7 * 24 * 60 * 60)
UMUSIC_V2_ACCESS_TOKEN_TTL_SECONDS = env.int("UMUSIC_V2_ACCESS_TOKEN_TTL_SECONDS", default=900)
UMUSIC_V2_REFRESH_TOKEN_TTL_SECONDS = env.int(
    "UMUSIC_V2_REFRESH_TOKEN_TTL_SECONDS", default=30 * 24 * 60 * 60
)
UMUSIC_FFPROBE_PATH = env("UMUSIC_FFPROBE_PATH", default="ffprobe")
UMUSIC_USE_INTERNAL_REDIRECT = env.bool("UMUSIC_USE_INTERNAL_REDIRECT", default=False)
UMUSIC_INTERNAL_MEDIA_PREFIX = env("UMUSIC_INTERNAL_MEDIA_PREFIX", default="/protected-media/")
UMUSIC_FOLDER_IMPORT_ENABLED = env.bool("UMUSIC_FOLDER_IMPORT_ENABLED", default=True)
UMUSIC_TASTE_IMPORT_ENABLED = env.bool("UMUSIC_TASTE_IMPORT_ENABLED", default=True)
UMUSIC_YOUTUBE_IMPORT_ENABLED = env.bool("UMUSIC_YOUTUBE_IMPORT_ENABLED", default=False)
UMUSIC_IMPORT_ROOTS = [
    Path(value).resolve() for value in env.list("UMUSIC_IMPORT_ROOTS", default=[])
]
UMUSIC_YTDLP_PATH = env("UMUSIC_YTDLP_PATH", default="yt-dlp")
UMUSIC_YOUTUBE_MAX_ITEMS = env.int("UMUSIC_YOUTUBE_MAX_ITEMS", default=25)
UMUSIC_REMOTE_IMPORT_ENABLED = env.bool("UMUSIC_REMOTE_IMPORT_ENABLED", default=True)
UMUSIC_REMOTE_IMPORT_MAX_ITEMS = env.int("UMUSIC_REMOTE_IMPORT_MAX_ITEMS", default=50)
DATA_UPLOAD_MAX_MEMORY_SIZE = min(UMUSIC_MAX_UPLOAD_BYTES, 10 * 1024 * 1024)
FILE_UPLOAD_MAX_MEMORY_SIZE = 2 * 1024 * 1024

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
AUTH_USER_MODEL = "accounts.User"

REDIS_URL = env("REDIS_URL", default="redis://localhost:6379/0")
CELERY_BROKER_URL = env("CELERY_BROKER_URL", default="redis://localhost:6379/1")
CELERY_RESULT_BACKEND = env("CELERY_RESULT_BACKEND", default="redis://localhost:6379/2")
CELERY_TASK_TRACK_STARTED = True
CELERY_TASK_TIME_LIMIT = 30 * 60
UMUSIC_FFMPEG_PATH = env("UMUSIC_FFMPEG_PATH", default="ffmpeg")
UMUSIC_MERT_MODEL_ID = env("UMUSIC_MERT_MODEL_ID", default="m-a-p/MERT-v1-95M")
UMUSIC_MERT_MODEL_REVISION = env(
    "UMUSIC_MERT_MODEL_REVISION", default="12af15fef9d0ac838c3f475bfbbf26d2060dd4f5"
)
UMUSIC_MERT_CACHE = env("UMUSIC_MERT_CACHE", default="/models/huggingface")
UMUSIC_MERT_LOCAL_FILES_ONLY = env.bool("UMUSIC_MERT_LOCAL_FILES_ONLY", default=False)
UMUSIC_MERT_CPU_THREADS = env.int("UMUSIC_MERT_CPU_THREADS", default=4)
UMUSIC_MERT_EXCERPT_SECONDS = env.float("UMUSIC_MERT_EXCERPT_SECONDS", default=5.0)
UMUSIC_MERT_MAX_AUDIO_BYTES = env.int("UMUSIC_MERT_MAX_AUDIO_BYTES", default=200 * 1024 * 1024)
CELERY_BEAT_SCHEDULE = {
    "nightly-learning-rebuild": {
        "task": "umusic.apps.recommendations.tasks.rebuild_all_learning",
        "schedule": 24 * 60 * 60,
    },
    "daily-smart-playlist-refresh": {
        "task": "umusic.apps.operations.tasks.scheduled_smart_playlist_refresh",
        "schedule": 24 * 60 * 60,
    },
}

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "umusic.apps.accounts.authentication.DeviceTokenAuthentication",
        "rest_framework.authentication.SessionAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
        "umusic.apps.accounts.permissions.DeviceScopePermission",
    ],
    "DEFAULT_THROTTLE_CLASSES": ["rest_framework.throttling.UserRateThrottle"],
    "DEFAULT_THROTTLE_RATES": {
        "user": env("UMUSIC_API_RATE", default="600/min"),
        "auth_v2": env("UMUSIC_AUTH_V2_RATE", default="20/min"),
        "bootstrap_v2": env("UMUSIC_BOOTSTRAP_V2_RATE", default="60/min"),
    },
}

# Production containers must surface unhandled request failures in their logs.
# Django otherwise returns a generic 500 response with no actionable traceback.
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"console": {"class": "logging.StreamHandler"}},
    "loggers": {
        "django.request": {
            "handlers": ["console"],
            "level": "ERROR",
            "propagate": False,
        }
    },
}
