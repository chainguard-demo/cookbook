#!/bin/sh
docker run --rm -it \
  -e TRUSTSTORE_PASSWORD=changeme \
  -e KEY_PASSWORD=changeme \
  -e FIPS_APPROVED_ONLY=1 \
  -e FORCE_REGEN=1 \
  --entrypoint sh bcfks-app -lc '
set -e
echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Starting BCFKS + FIPS test container"
echo "  • TRUSTSTORE_PASSWORD set (len=${#TRUSTSTORE_PASSWORD})"
echo "  • KEY_PASSWORD set (len=${#KEY_PASSWORD})"
echo "  • FIPS_APPROVED_ONLY=${FIPS_APPROVED_ONLY:-0}"
echo "  • FORCE_REGEN=${FORCE_REGEN:-0}"
echo

# 1) Start local HTTP server for Java client to test connectivity
echo "[INFO] Starting local HTTP server on port 8080..."
python3 -m http.server 8080 >/tmp/http.log 2>&1 &
HTTP_PID=$!
sleep 1
echo "    → HTTP server PID $HTTP_PID"
echo

# 2) Run the BCFKS initializer + Java app
echo "[INFO] Launching /app/bin/run.sh (this will build truststore/keystore and start app.jar)..."
 /app/bin/run.sh >/tmp/run.log 2>&1 &
APP_PID=$!
sleep 5
echo "    → App process PID $APP_PID"
echo

# 3) Show summary of keystores created
echo "[INFO] Listing generated BCFKS stores..."
keytool -list -keystore /app/certs/truststore.bcfks \
  -storetype BCFKS -providername BCFIPS -storepass "$TRUSTSTORE_PASSWORD" 2>/dev/null || echo "    (truststore not found)"
echo
keytool -list -keystore /app/certs/keystore.bcfks \
  -storetype BCFKS -providername BCFIPS -storepass "$KEY_PASSWORD" 2>/dev/null || echo "    (keystore not found)"
echo

# 4) Stream both logs with section headers
echo "========================"
echo ">>> run.sh (app) output"
echo "========================"
tail -n +1 -f /tmp/run.log &
RUN_TAIL=$!

echo "========================"
echo ">>> Python HTTP server log"
echo "========================"
tail -n +1 -f /tmp/http.log &
HTTP_TAIL=$!

# 5) Keep container alive briefly for interactive observation
sleep 30

# Cleanup background processes
kill $RUN_TAIL $HTTP_TAIL $APP_PID $HTTP_PID 2>/dev/null || true
echo
echo "[DONE] Test complete — exiting container."
'