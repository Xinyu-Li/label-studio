#!/usr/bin/env bash
set -euo pipefail

export LABEL_STUDIO_HOST="${LABEL_STUDIO_HOST:-https://yidelearn.com/label-studio}"
export HOST="${HOST:-https://yidelearn.com/label-studio}"
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK="${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-true}"
export DISABLE_SIGNUP_WITHOUT_LINK="${DISABLE_SIGNUP_WITHOUT_LINK:-true}"
export USE_USERNAME_FOR_LOGIN="${USE_USERNAME_FOR_LOGIN:-true}"
export LABEL_STUDIO_BASE_DATA_DIR="${LABEL_STUDIO_BASE_DATA_DIR:-/opt/label-studio/data}"
export SSRF_PROTECTION_ENABLED="${SSRF_PROTECTION_ENABLED:-true}"
export DJANGO_DB="${DJANGO_DB:-sqlite}"
export LOG_LEVEL="${LOG_LEVEL:-INFO}"

/opt/label-studio/venv/bin/python /opt/label-studio/config/seed_users.py
