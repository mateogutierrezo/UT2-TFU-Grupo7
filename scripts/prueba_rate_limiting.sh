BASE="${1:-http://localhost:8080}"
FAIL=0

code() { curl -s -o /dev/null -w "%{http_code}" "$@"; }

echo "== 1. Auth estricto: 8 POST rápidos a /api/auth/login (esperado: 1-5 pasan, 429 desde el 7) =="
echo "   (burst=5 tolera la ráfaga inicial; ver comentario sobre off-by-one de nginx)"
HIT429_AUTH=0
for i in $(seq 1 8); do
  C=$(code -X POST "$BASE/api/auth/login" -H "Content-Type: application/json" \
    -d '{"email":"abuso@example.com","password":"x"}')
  echo "  intento $i -> $C"
  if [ "$i" -le 5 ] && [ "$C" = "429" ]; then
    echo "  FAIL: 429 prematuro en intento $i"; FAIL=1
  fi
  if [ "$i" -gt 5 ] && [ "$C" = "429" ]; then
    HIT429_AUTH=1
  fi
done
[ "$HIT429_AUTH" = "1" ] || { echo "  FAIL: ningún 429 entre intentos 6-8"; FAIL=1; }

echo "== 2. API general: 105 GET rápidos a /api/tasks (esperado: 100 pasan + 429 desde el 101) =="
HIT429=0
for i in $(seq 1 105); do
  C=$(code "$BASE/api/tasks")
  if [ "$i" -le 100 ] && [ "$C" = "429" ]; then
    echo "  FAIL: 429 prematuro en request $i"; FAIL=1
  fi
  if [ "$i" -gt 100 ] && [ "$C" = "429" ]; then
    HIT429=1
  fi
done
[ "$HIT429" = "1" ] || { echo "  FAIL: ningún 429 entre requests 101-105"; FAIL=1; }
echo "  429 observado tras el request 100: $HIT429"

exit "$FAIL"
