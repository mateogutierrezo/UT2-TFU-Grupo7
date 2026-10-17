#!/bin/bash
# Demuestra Health Endpoint Monitoring (/api/health) con 2 réplicas tras Nginx:
# la réplica sin acceso a la BD responde 503, Nginx la saca de rotación y todas
# las respuestas llegan desde la réplica sana; con ambas caídas el balanceador
# devuelve un 503 JSON controlado.
# Asserts: ambas sanas alternan api-1/api-2, /health y /health/live sin JWT -> 200,
# BD caída en api-1 -> 503 directo, 8 x 200 desde api-2 por Nginx y api-1 unhealthy,
# restauración, api-1 detenida -> 200 desde api-2, ambas detenidas -> 503 JSON.
# Uso:       bash scripts/prueba-health.sh        (CLEAN=1 para down -v + build)
# Evidencia: mkdir -p evidencia && bash scripts/prueba-health.sh | tee evidencia/prueba-health.txt
BASE="${BASE:-http://localhost:8080}"
CLEAN="${CLEAN:-0}"
FAIL=0
FORCED=0

cd "$(dirname "$0")/.." || exit 1
trap 'unset API1_FORCE_DB_FAIL; if [ "$FORCED" = "1" ]; then docker compose up -d api1; docker compose restart loadbalancer; fi' EXIT

# GET al balanceador -> H_CODE, H_SECS, H_BODY, H_INST
http_get() {
  local tmp meta
  tmp=$(mktemp)
  meta=$(curl -s -m 15 -o "$tmp" -w "%{http_code} %{time_total}" "$BASE$1")
  H_CODE="${meta%% *}"
  H_SECS="${meta##* }"
  H_BODY=$(cat "$tmp")
  rm -f "$tmp"
  H_INST=$(echo "$H_BODY" | sed -n 's/.*"instance":"\([^"]*\)".*/\1/p')
  [ -z "$H_INST" ] && H_INST="-"
}

# probe N: N consultas seguidas a /api/health; deja CODES, INSTS y SECS
probe() {
  CODES=""; INSTS=""; SECS=""
  for i in $(seq 1 "$1"); do
    http_get /api/health
    echo "  #$i  HTTP $H_CODE  ${H_SECS}s  instance=$H_INST"
    CODES="$CODES $H_CODE"; INSTS="$INSTS $H_INST"; SECS="$SECS $H_SECS"
  done
}
count_code() { echo $CODES | tr ' ' '\n' | grep -c "^$1$"; }
uniq_inst() { echo $INSTS | tr ' ' '\n' | grep -v '^-$' | sort -u | tr '\n' ' ' | sed 's/ $//'; }
lt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < b) }'; }

container_health() {
  docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$1" 2>/dev/null || echo "missing"
}

# wait_health ESTADO SEGUNDOS contenedor...
wait_health() {
  local expected="$1" timeout="$2" deadline n ok
  shift 2
  deadline=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$deadline" ]; do
    ok=1
    for n in "$@"; do
      [ "$(container_health "$n")" != "$expected" ] && ok=0
    done
    [ "$ok" = "1" ] && return 0
    sleep 2
  done
  return 1
}

wait_http200() {
  local path="${1:-/api/health}" timeout="${2:-60}" deadline
  deadline=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$deadline" ]; do
    http_get "$path"
    [ "$H_CODE" = "200" ] && return 0
    sleep 2
  done
  return 1
}

echo "== 0. Preparación =="
if [ "$CLEAN" = "1" ]; then
  docker compose down -v
  docker compose up --build -d
else
  docker compose up -d
fi
wait_health healthy 120 tfu-api-1 tfu-api-2 || { echo "FAIL: api-1/api-2 no llegaron a healthy"; docker compose ps; exit 1; }
wait_http200 /api/health 30 || { echo "FAIL: el balanceador no responde 200 en /api/health"; exit 1; }
docker compose ps

echo "== 1. Ambas réplicas sanas =="
probe 6
N200=$(count_code 200)
echo "respuestas 200: $N200/6   instancias: $(uniq_inst)"
[ "$N200" != "6" ] && { echo "FAIL: se esperaban 6 x 200"; FAIL=1; }
[ "$(uniq_inst)" != "api-1 api-2" ] && { echo "FAIL: se esperaba alternancia api-1/api-2"; FAIL=1; }

echo "== 2. /health y /health/live sin JWT =="
http_get /api/health/live; C_LIVE=$H_CODE
http_get /api/health;      C_HEALTH=$H_CODE
echo "live=$C_LIVE health=$C_HEALTH"
[ "$C_LIVE" != "200" ] && { echo "FAIL: /api/health/live esperado 200"; FAIL=1; }
[ "$C_HEALTH" != "200" ] && { echo "FAIL: /api/health esperado 200"; FAIL=1; }

echo "== 3. BD no disponible en api-1 (FORCE_DB_FAIL) =="
FORCED=1
export API1_FORCE_DB_FAIL=true
docker compose up -d api1
docker compose restart loadbalancer
wait_health unhealthy 90 tfu-api-1; UNHEALTHY=$?
sleep 2
DIRECT=$(docker compose exec -T api1 node -e "fetch('http://127.0.0.1:3000/api/health').then(async r=>console.log(r.status, await r.text()))" < /dev/null)
echo "api-1 directo: $DIRECT"
[ "${DIRECT%% *}" != "503" ] && { echo "FAIL: api-1 directo esperado 503"; FAIL=1; }
echo "$DIRECT" | grep -q '"status":"degraded"' || { echo "FAIL: esperado status degraded"; FAIL=1; }
echo "$DIRECT" | grep -q '"database":{"status":"down"}' || { echo "FAIL: esperado database down"; FAIL=1; }
probe 8
N200=$(count_code 200)
echo "por Nginx: 200=$N200/8   instancias: $(uniq_inst)"
[ "$N200" != "8" ] && { echo "FAIL: se esperaban 8 x 200 por Nginx"; FAIL=1; }
[ "$(uniq_inst)" != "api-2" ] && { echo "FAIL: debía responder solo api-2"; FAIL=1; }
docker compose ps
[ "$UNHEALTHY" != "0" ] && { echo "FAIL: tfu-api-1 debía quedar unhealthy"; FAIL=1; }
docker compose logs --tail 20 api1 | grep -q "fallo de BD" || { echo "FAIL: el log de api-1 no registra el fallo"; FAIL=1; }

echo "== 4. Restauración de api-1 =="
unset API1_FORCE_DB_FAIL
FORCED=0
docker compose up -d api1
docker compose restart loadbalancer
wait_health healthy 90 tfu-api-1 tfu-api-2; HEALTHY=$?
sleep 3
docker compose ps
probe 6
N200=$(count_code 200)
echo "200=$N200/6   instancias: $(uniq_inst)"
[ "$HEALTHY" != "0" ] && { echo "FAIL: las réplicas no volvieron a healthy"; FAIL=1; }
[ "$N200" != "6" ] && { echo "FAIL: se esperaban 6 x 200"; FAIL=1; }
[ "$(uniq_inst)" != "api-1 api-2" ] && { echo "FAIL: alternancia no restablecida"; FAIL=1; }

echo "== 5. api-1 detenida =="
docker compose stop api1
probe 6
N200=$(count_code 200)
FIRST=$(echo $SECS | awk '{print $1}')
REST_MAX=$(echo $SECS | tr ' ' '\n' | tail -n +2 | sort -g | tail -n 1)
echo "200=$N200/6   instancias: $(uniq_inst)   primera=${FIRST}s (incluye proxy_connect_timeout 2s)   resto<=${REST_MAX}s"
[ "$N200" != "6" ] && { echo "FAIL: se esperaban 6 x 200"; FAIL=1; }
[ "$(uniq_inst)" != "api-2" ] && { echo "FAIL: debía responder solo api-2"; FAIL=1; }
lt "$FIRST" 6 || { echo "FAIL: la primera respuesta tardó demasiado"; FAIL=1; }
docker compose start api1
wait_health healthy 90 tfu-api-1
docker compose ps

echo "== 6. Ambas réplicas detenidas =="
docker compose stop api1 api2
http_get /api/health
C6=$H_CODE; B6=$H_BODY
echo "status=$C6 en ${H_SECS}s  cuerpo=$B6"
[ "$C6" != "503" ] && { echo "FAIL: esperado 503, fue $C6 (si es 504 falta '=503' en error_page de nginx.conf)"; FAIL=1; }
echo "$B6" | grep -q '"status":"unavailable"' || { echo "FAIL: esperado JSON con status unavailable"; FAIL=1; }
docker compose start api1 api2
wait_health healthy 90 tfu-api-1 tfu-api-2; BACK=$?
docker compose ps
wait_http200 /api/health 60; RECOVERED=$?
[ "$BACK" != "0" ] && { echo "FAIL: las réplicas no volvieron a healthy"; FAIL=1; }
[ "$RECOVERED" != "0" ] && { echo "FAIL: /api/health no volvió a responder 200"; FAIL=1; }

[ "$FAIL" = "0" ] && echo "RESULTADO: OK" || echo "RESULTADO: FAIL"
exit $FAIL