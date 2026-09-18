TOKEN="cambiar_token"
TASK_ID=1

echo "Enviando requests simultáneamente..."

(
  echo "[$(date +%H:%M:%S.%N)] Request A: modificando título"
  curl -sS -X PATCH \
    "http://localhost:8080/api/tasks/$TASK_ID" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"title":"Título A"}'
  echo
  echo "[$(date +%H:%M:%S.%N)] Request A finalizada"
) &

(
  echo "[$(date +%H:%M:%S.%N)] Request B: modificando descripción"
  curl -sS -X PATCH \
    "http://localhost:8080/api/tasks/$TASK_ID" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"description":"Descripción B"}'
  echo
  echo "[$(date +%H:%M:%S.%N)] Request B finalizada"
) &

wait

echo "Ambas requests finalizaron."