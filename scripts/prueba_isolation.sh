TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MSwiZW1haWwiOiJ1c2VyMUBleGFtcGxlLmNvbSIsImlhdCI6MTc5MDAzMTc2NSwiZXhwIjoxNzkwMDM1MzY1fQ.duUhXro5JQexDJH52b6e7UGVPQ5D_EpKaG5KCsHMfw8"
TASK_ID=12

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