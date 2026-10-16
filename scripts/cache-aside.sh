#!/usr/bin/env bash
# Pruebas empíricas del patrón Cache-Aside sobre GET /tasks.

# El script registra dos usuarios, crea un proyecto, una tarea y asigna al segundo usuario al proyecto.

# Uso:
# Desde la raíz del proyecto, levantar con: docker compose up --build
# Luego ejecutar: bash scripts/cache-aside.sh

# Se requiere tener instalado: bash, curl y docker compose. En Windows usar Git Bash o WSL.

cd "$(dirname "$0")/.." || exit 1
BASE_URL="${BASE_URL:-http://localhost:8080/api}"
REGISTER_PATH="${REGISTER_PATH:-/auth/register}"
LOGIN_PATH="${LOGIN_PATH:-/auth/login}"            
TOKEN_FIELD="${TOKEN_FIELD:-token}"                # campo del token en la respuesta del login
EXTRA_FIELDS="${EXTRA_FIELDS:-}"                   # campos extra del registro
REDIS_SERVICE="${REDIS_SERVICE:-redis}"            # nombre del servicio en docker-compose.yaml
CACHE_TTL_SECONDS="${CACHE_TTL_SECONDS:-60}"
TEST_TTL="${TEST_TTL:-0}"                          # TEST_TTL=1 agrega la prueba de vencimiento

EMAIL_A="userA@test.com"
EMAIL_B="userB@test.com"
PASSWORD="123456"

HDR=$(mktemp); BODY=$(mktemp)
trap 'rm -f "$HDR" "$BODY"' EXIT

PASS=0; FAIL=0

# utilidades

json_post() { # ruta token cuerpo -> deja la respuesta en $BODY y el código en $STATUS
  local auth=()
  [ -n "$2" ] && auth=(-H "Authorization: Bearer $2")
  STATUS=$(curl -s -o "$BODY" -w "%{http_code}" -X POST "$BASE_URL$1" \
    -H "Content-Type: application/json" "${auth[@]}" -d "$3")
}

first_id() { grep -o '"id":[0-9]*' "$BODY" | head -1 | cut -d: -f2; }

user_id_from_token() { # el JWT lleva el id del usuario en su payload
  local p
  p=$(echo "$1" | cut -d. -f2 | tr '_-' '/+')
  while [ $((${#p} % 4)) -ne 0 ]; do p="$p="; done
  echo "$p" | base64 -d 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2
}

register_and_login() { # email -> imprime el token
  json_post "$REGISTER_PATH" "" "{\"email\":\"$1\",\"password\":\"$PASSWORD\"$EXTRA_FIELDS}"
  json_post "$LOGIN_PATH" "" "{\"email\":\"$1\",\"password\":\"$PASSWORD\"}"
  sed -n "s/.*\"$TOKEN_FIELD\":\"\([^\"]*\)\".*/\1/p" "$BODY"
}

# Hace GET /tasks y deja en variables STATUS, XCACHE e INSTANCE
get_tasks() {
  curl -s -D "$HDR" -o "$BODY" -H "Authorization: Bearer $1" "$BASE_URL/tasks"
  STATUS=$(head -1 "$HDR" | awk '{print $2}')
  XCACHE=$(grep -i '^x-cache:' "$HDR" | awk '{print $2}' | tr -d '\r')
  INSTANCE=$(grep -o '"instance":"[^"]*"' "$BODY" | cut -d'"' -f4)
  echo "      -> HTTP $STATUS | X-Cache: ${XCACHE:-(ninguno)} | instance: ${INSTANCE:-?}"
}

edit_task() { # token titulo
  curl -s -o /dev/null -w "      -> PATCH /tasks/$TASK_ID: HTTP %{http_code}\n" \
    -X PATCH "$BASE_URL/tasks/$TASK_ID" \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d "{\"title\":\"$2\"}"
}

check() { # descripcion esperado actual
  if [ "$2" = "$3" ]; then
    echo "   [OK]    $1"; PASS=$((PASS+1))
  else
    echo "   [FALLO] $1 (esperado: $2, obtenido: ${3:-vacio})"; FAIL=$((FAIL+1))
  fi
}

abort() { echo "   ERROR: $1"; exit 1; }

# Preparación: usuarios, proyecto y tarea

echo "----- Preparación"
TOKEN_A=$(register_and_login "$EMAIL_A")
[ -n "$TOKEN_A" ] || abort "no se pudo registrar/loguear al usuario A. Revisar REGISTER_PATH, LOGIN_PATH, TOKEN_FIELD o EXTRA_FIELDS."
TOKEN_B=$(register_and_login "$EMAIL_B")
[ -n "$TOKEN_B" ] || abort "no se pudo registrar/loguear al usuario B."
ID_B=$(user_id_from_token "$TOKEN_B")
[ -n "$ID_B" ] || abort "no se pudo leer el id del usuario B desde el token."
echo "   Usuarios creados: $EMAIL_A y $EMAIL_B (id de B = $ID_B)"

json_post "/projects" "$TOKEN_A" "{\"name\":\"Proyecto Cache-Aside\"}"
PROJECT_ID=$(first_id)
[ -n "$PROJECT_ID" ] || abort "no se pudo crear el proyecto (HTTP $STATUS)."
echo "   Proyecto creado: id = $PROJECT_ID (dueño: USER A)"

json_post "/tasks" "$TOKEN_A" "{\"title\":\"tarea de prueba\",\"project_id\":$PROJECT_ID}"
TASK_ID=$(first_id)
[ -n "$TASK_ID" ] || abort "no se pudo crear la tarea (HTTP $STATUS)."
echo "   Tarea creada: id = $TASK_ID"

json_post "/projects/assign" "$TOKEN_A" "{\"project_id\":$PROJECT_ID,\"user_id\":$ID_B}"
[ "$STATUS" = "200" ] || abort "no se pudo asignar al usuario B al proyecto (HTTP $STATUS)."
echo "   Usuario B asignado al proyecto"

# Prueba 1: MISS y HIT

echo
echo "----- Prueba 1: primera consulta MISS, segunda HIT"
echo "   GET /tasks de usuario A"
get_tasks "$TOKEN_A"; check "1ra consulta es MISS" "MISS" "$XCACHE"
echo "   GET /tasks de usuario A"
get_tasks "$TOKEN_A"; check "2da consulta es HIT" "HIT" "$XCACHE"

# Prueba 2: invalidación al modificar

echo
echo "----- Prueba 2: al editar una tarea se invalida la caché"
NEW_TITLE="titulo de la tarea editado $(date +%s)"
echo "   Editando la tarea $TASK_ID"
edit_task "$TOKEN_A" "$NEW_TITLE"
echo "   GET /tasks de usuario A"
get_tasks "$TOKEN_A"
check "después de editar es MISS" "MISS" "$XCACHE"
grep -q "$NEW_TITLE" "$BODY" && R=si || R=no
check "la lista trae el título nuevo" "si" "$R"
echo "   GET /tasks de usuario A"
get_tasks "$TOKEN_A"; check "la siguiente consulta es HIT" "HIT" "$XCACHE"

# Prueba 3: invalidación para otros miembros

echo
echo "----- Prueba 3: la edición de un usuario invalida la caché de los demás miembros"
echo "   GET /tasks de usuario B, dos veces"
get_tasks "$TOKEN_B"; get_tasks "$TOKEN_B"
check "B tiene la lista en caché (HIT)" "HIT" "$XCACHE"
NEW_TITLE="titulo de la tarea editado por A $(date +%s)"
echo "   El usuario A edita la tarea $TASK_ID"
edit_task "$TOKEN_A" "$NEW_TITLE"
echo "   GET /tasks de usuario B"
get_tasks "$TOKEN_B"
check "B recibe MISS aunque no editó nada" "MISS" "$XCACHE"
grep -q "$NEW_TITLE" "$BODY" && R=si || R=no
check "B ve el título nuevo" "si" "$R"

# Prueba 4: Redis caído

echo
echo "----- Prueba 4: con Redis caído la API sigue respondiendo"
echo "   Deteniendo Redis..."
docker compose stop "$REDIS_SERVICE" > /dev/null 2>&1
echo "   GET /tasks de usuario A"
get_tasks "$TOKEN_A"
check "responde 200 sin Redis" "200" "$STATUS"
[ "$XCACHE" != "HIT" ] && R=si || R=no
check "no se sirve desde caché (lee de SQLite)" "si" "$R"
echo "   Levantando Redis de nuevo..."
docker compose start "$REDIS_SERVICE" > /dev/null 2>&1
sleep 3
echo "   GET /tasks de usuario A"
get_tasks "$TOKEN_A"
check "con Redis de vuelta responde 200" "200" "$STATUS"

# Prueba 5: vencimiento por TTL

if [ "$TEST_TTL" = "1" ]; then
  echo
  echo "----- Prueba 5: vencimiento por TTL (${CACHE_TTL_SECONDS} s)"
  echo "   GET /tasks de usuario A, dos veces"
  get_tasks "$TOKEN_A"; get_tasks "$TOKEN_A"
  check "dentro del TTL es HIT" "HIT" "$XCACHE"
  echo "   Esperando $((CACHE_TTL_SECONDS + 2)) segundos..."
  sleep $((CACHE_TTL_SECONDS + 2))
  echo "   GET /tasks de usuario A"
  get_tasks "$TOKEN_A"; check "pasado el TTL es MISS" "MISS" "$XCACHE"
fi

# resultado

echo
echo "== Resultado: $PASS pruebas OK, $FAIL con fallo =="
[ "$FAIL" -eq 0 ]