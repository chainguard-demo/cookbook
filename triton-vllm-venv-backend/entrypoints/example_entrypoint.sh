#!/bin/sh
set -euo pipefail

echo "[entrypoint] Starting example-vllm..."
echo "[entrypoint] Args: $@"

# Prefer Triton's venv python if present, else fallback to PATH python
if [ -x /opt/tritonserver/venv/bin/python3 ]; then
  PY=/opt/tritonserver/venv/bin/python3
else
  PY=python3
fi

exec "$PY" /work/main.py "$@"
