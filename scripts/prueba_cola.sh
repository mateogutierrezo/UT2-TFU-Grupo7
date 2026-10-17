#!/bin/bash
# Demuestra Queue-Based Load Leveling en POST /api/tasks:
# ráfaga de N POST concurrentes -> N x 202 rápidos (cola absorbe),
# el worker drena a ritmo estable (concurrencia 1) y cada job
# termina en done con la tarea creada.
# Asserts: N x 202, todos los jobs llegan a done, GET lista N nuevas,
# job inexistente -> 404, proyecto inexistente -> 4xx sin encolar.
BASE="http://localhost:8080"
N=10
STAMP=$(date +%s)
EMAIL="cola-demo-${STAMP}@ucu.edu.uy"
PASS=" ColaDemo123"
TMPDIR=$(mktemp -d)
FAIL=0

jget() { python3 -c "import sys,json; print(json.load(sys.stdin).get('$1',''))" 2>/dev/null; }
auth_h() { echo "Authorization: Bearer $1"; }

echo "== 1. Registro (o login si ya existe) =="
REG=$(curl -s -X POST "$BASE/api/auth/register" -H "Content-Type: application/json" -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")
TOKEN=$(echo "$REG" | jget token)
if [ -z "$TOKEN" ]; then
  TOKEN=$(curl -s -X POST "$BASE/api/auth/login" -H "Content-Type: application/json" -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" | jget token)
fi
[ -z "$TOKEN" ] && { echo "FAIL: sin token"; exit 1; }
echo "token ok"

echo "== 2. Proyecto para las tareas =="
PROJ=$(curl -s -X POST "$BASE/api/projects" -H "$(auth_h "$TOKEN")" -H "Content-Type: application/json" -d "{\"name\":\"Cola demo $STAMP\"}")
PROJECT_ID=$(echo "$PROJ" | python3 -c "import sys,json; print(json.load(sys.stdin).get('project',{}).get('id',''))" 2>/dev/null)
[ -z "$PROJECT_ID" ] && { echo "FAIL: sin project_id. Resp: $PROJ"; exit 1; }
echo "project_id=$PROJECT_ID"

echo "== 3. Ráfaga de $N POST concurrentes =="
BEFORE=$(curl -s "$BASE/api/tasks" -H "$(auth_h "$TOKEN")" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('tasks',[])))")
START=$(date +%s)
for i in $(seq 1 "$N"); do
  (
    curl -s -o "$TMPDIR/resp_$i.json" -w "%{http_code}" -X POST "$BASE/api/tasks" \
      -H "$(auth_h "$TOKEN")" -H "Content-Type: application/json" \
      -d "{\"title\":\"Tarea cola $STAMP-$i\",\"project_id\":$PROJECT_ID}" > "$TMPDIR/code_$i.txt"
  ) &
done
wait
END=$(date +%s)
echo "ráfaga aceptada en $((END-START))s"

OK202=$(grep -h -c "^202$" "$TMPDIR"/code_*.txt | awk '{s+=$1} END {print s}')
echo "respuestas 202: $OK202/$N"
[ "$OK202" != "$N" ] && { echo "FAIL: se esperaban $N x 202"; FAIL=1; }

JOBS=$(for i in $(seq 1 "$N"); do jget jobId < "$TMPDIR/resp_$i.json"; done | grep -v '^$')
echo "jobs encolados: $(echo "$JOBS" | wc -l | tr -d ' ')"

echo "== 4. Polling hasta done (timeout 60s) =="
DONE=0; FAILED=0
for j in $JOBS; do
  for _ in $(seq 1 60); do
    ST=$(curl -s "$BASE/api/tasks/jobs/$j" -H "$(auth_h "$TOKEN")" | jget status)
    [ "$ST" = "done" ] && { DONE=$((DONE+1)); break; }
    [ "$ST" = "failed" ] && { FAILED=$((FAILED+1)); break; }
    sleep 1
  done
done
echo "done=$DONE failed=$FAILED"
[ "$DONE" != "$N" ] && { echo "FAIL: no todos llegaron a done"; FAIL=1; }

echo "== 5. GET /api/tasks trae las $N nuevas =="
AFTER=$(curl -s "$BASE/api/tasks" -H "$(auth_h "$TOKEN")" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('tasks',[])))")
DELTA=$((AFTER-BEFORE))
echo "antes=$BEFORE después=$AFTER delta=$DELTA"
[ "$DELTA" != "$N" ] && { echo "FAIL: delta esperado $N"; FAIL=1; }

echo "== 6. Job inexistente -> 404 =="
C404=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/api/tasks/jobs/99999999" -H "$(auth_h "$TOKEN")")
echo "status=$C404"
[ "$C404" != "404" ] && { echo "FAIL: esperado 404"; FAIL=1; }

echo "== 7. Proyecto inexistente -> 4xx sin encolar =="
CBAD=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/api/tasks" -H "$(auth_h "$TOKEN")" -H "Content-Type: application/json" -d '{"title":"Mala","project_id":99999999}')
echo "status=$CBAD"
[ "$CBAD" != "400" ] && [ "$CBAD" != "404" ] && [ "$CBAD" != "403" ] && { echo "FAIL: esperado 4xx, fue $CBAD"; FAIL=1; }

rm -rf "$TMPDIR"
[ "$FAIL" = "0" ] && echo "RESULTADO: OK" || echo "RESULTADO: FAIL"
exit $FAIL
