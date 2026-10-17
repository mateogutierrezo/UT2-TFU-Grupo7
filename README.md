# Universidad Católica del Uruguay

## Trabajo Final de Unidad 4 — Patrones de Arquitectura — Grupo 7

Video demostrativo: https://www.youtube.com/watch?v=LJ6lN3oZzkw

## Introducción

### Objetivo

Este trabajo corresponde a la **Unidad Temática 4 (Patrones de Arquitectura)**. Aplica patrones arquitectónicos a la aplicación desarrollada en la unidad anterior: una API REST para la gestión de usuarios, proyectos y tareas, construida con **Node.js y Express**, que persiste en **SQLite** y autentica con **tokens JWT**.

La aplicación se ejecuta con Docker Compose en **dos réplicas** (`api-1` y `api-2`) detrás de un balanceador **Nginx**, que es el único punto de entrada al sistema (puerto `8080`).

La consigna exige al menos dos patrones de cada grupo de disponibilidad, rendimiento y seguridad, y uno de facilidad de modificación y despliegue (siete en total). La selección priorizó patrones que pudieran incorporarse **conservando la arquitectura existente** y demostrarse con **pruebas observables**.

### Conceptos de la Unidad 3 que se conservan

- Componentes e interfaces
- Escalabilidad horizontal
- Contenedores
- ACID mediante transacciones
- Servicios sin estado

### Patrones de la Unidad 4

| Grupo | Patrón | Qué hace en el sistema | Dónde vive |
| --- | --- | --- | --- |
| Disponibilidad | **Rate Limiting** | Limita solicitudes por IP y rechaza el exceso con `429` | `nginx/nginx.conf` |
| Disponibilidad | **Health Endpoint Monitoring** | Cada réplica informa su estado, incluida la base de datos, para retirar a la degradada de la rotación | `/api/health`, `/api/health/live`, healthchecks de Docker |
| Rendimiento | **Cache-Aside** | Cachea en Redis la lista de tareas de cada usuario, con invalidación en cada escritura | `src/cache.js`, módulo de tareas |
| Rendimiento | **Queue-Based Load Leveling** | Desacopla la creación de tareas de su escritura en SQLite mediante una cola y un worker | `src/queue/`, contenedor `worker` |
| Seguridad | **Gatekeeper** | Autenticación y validación previas a la lógica de negocio | `src/middlewares/` |
| Seguridad | **Gateway Offloading** | Traslada a Nginx el control del tráfico y la entrada única | `nginx/nginx.conf`, `docker-compose.yaml` |
| Facilidad de modificación y despliegue | **External Configuration Store** | Separa del código y de la imagen los parámetros de ejecución | `.env`, `docker-compose.yaml` |

Los patrones no operan de forma aislada:

- Rate Limiting se ejecuta en el balanceador gracias a Gateway Offloading.
- El límite por cliente se complementa con la cola, que regula las escrituras que sí fueron admitidas.
- La variable de entorno que simula una base no disponible aplica External Configuration Store a las pruebas de Health Endpoint Monitoring.

## Estructura del proyecto

```
.
├── Dockerfile
├── docker-compose.yaml
├── .env
├── .env.example
├── evidencia/                    # salidas de las corridas de prueba (p. ej. prueba-health.txt)
├── nginx/
│   └── nginx.conf                # balanceo, rate limiting, reintentos y error 503 controlado
├── scripts/
│   ├── prueba_isolation.sh       # demo de aislamiento (ACID)
│   ├── prueba_cola.sh            # demo Queue-Based Load Leveling
│   └── prueba-health.sh          # demo Health Endpoint Monitoring
└── src/
    ├── app.js
    ├── cache.js                  # cliente Redis y operaciones de Cache-Aside
    ├── queue/
    │   ├── taskQueue.js          # definición de la cola Bull (instancia compartida)
    │   └── taskWorker.js         # entrypoint del worker (único .process())
    ├── db/
    │   └── database.js
    ├── middlewares/
    │   ├── validate.js           # valida el body con Zod
    │   └── authenticate.js       # valida el JWT del header
    ├── routes/
    │   └── unstable.routes.js    # endpoint que falla a propósito
    └── modules/
        ├── auth/        (routes, controller, service, schema)
        ├── tasks/       (routes, controller, service, schema)
        └── projects/    (routes, controller, service, schema)
```

## Arquitectura

La solución utiliza una partición técnica por responsabilidades:

```
┌──────────────────────────────────────┐
│            Presentación              │
│           Postman / curl             │
└──────────────────┬───────────────────┘
                   ▼
┌──────────────────────────────────────┐
│           Infraestructura            │
│              Nginx                   │
└──────────────────┬───────────────────┘
                   ▼
┌──────────────────────────────────────┐
│          Lógica de Negocio           │
│  ModuloAuth / Proyectos / Tareas     │
│  (+ middlewares, cola y caché)       │
└──────────────────┬───────────────────┘
                   ▼
┌──────────────────────────────────────┐
│             Persistencia             │
│        SQLite  ·  Redis              │
└──────────────────────────────────────┘
```

### Arquitectura de despliegue

```
Cliente (curl/Postman)
        │
        ▼
 Load Balancer (nginx, puerto 8080)   ← único puerto publicado en el host
        │
   ┌────┴────┐
   ▼         ▼
 API #1    API #2      (Express, misma imagen, INSTANCE_ID distinto)
   │  ╲   ╱  │
   │   Redis │         (caché Cache-Aside + cola Bull)
   │     │   │
   │     ▼   │
   │   Worker          (misma imagen, ejecuta src/queue/taskWorker.js)
   └────┬────┘
        ▼
  SQLite compartida (volumen dbdata)
```

| Servicio | Contenedor | Imagen | Rol |
| --- | --- | --- | --- |
| `loadbalancer` | `tfu-lb` | `nginx:alpine` | Único punto de entrada (`8080`), rate limiting, reparto y reintentos |
| `api1` | `tfu-api-1` | `build: .` | Réplica de la API (`INSTANCE_ID=api-1`) |
| `api2` | `tfu-api-2` | `build: .` | Réplica de la API (`INSTANCE_ID=api-2`) |
| `worker` | `tfu-worker-1` | `build: .` | Consume la cola y escribe en SQLite (`INSTANCE_ID=worker-1`) |
| `redis` | `redis-queue` | `redis:7-alpine` | Caché y cola (puerto interno `6379`) |

Los puertos de las APIs **no se publican** en el host: todo acceso externo pasa por Nginx. El `loadbalancer` solo arranca cuando `api1` y `api2` están `healthy`, y estas esperan a que Redis esté `healthy`.

## Componentes e interfaces

Los clientes interactúan con la API HTTP a través de Nginx, que distribuye las solicitudes entre las réplicas disponibles. La API accede a SQLite con `better-sqlite3` y a Redis para la caché y la cola.

### Interfaz HTTP

| Método | Ruta | Protegido | Descripción |
| --- | --- | --- | --- |
| POST | `/api/auth/register` | No | Registra un usuario (email + password) |
| POST | `/api/auth/login` | No | Autentica un usuario y devuelve un JWT |
| GET | `/api/tasks` | Sí (JWT) | Lista las tareas de los proyectos del usuario (con caché; ver encabezado `X-Cache`) |
| POST | `/api/tasks` | Sí (JWT) | Encola la creación de una tarea; responde `202` con un `jobId` |
| GET | `/api/tasks/jobs/:id` | Sí (JWT) | Consulta el estado de un trabajo encolado (`pending` / `done` / `failed`) |
| PATCH | `/api/tasks/:id` | Sí (JWT) | Modifica una tarea (invalida la caché de los miembros del proyecto) |
| DELETE | `/api/tasks/:id` | Sí (JWT) | Elimina una tarea (invalida la caché de los miembros del proyecto) |
| POST | `/api/projects` | Sí (JWT) | Crea un proyecto |
| GET | `/api/projects` | Sí (JWT) | Lista los proyectos del usuario |
| POST | `/api/projects/assign` | Sí (JWT) | Asigna un usuario a un proyecto (solo el propietario) |
| GET | `/api/health` | No | Estado de la instancia, incluida la base de datos: `200` (`ok`) o `503` (`degraded`) |
| GET | `/api/health/live` | No | Vitalidad: indica solo que el proceso responde, sin consultar la base |

Las operaciones protegidas requieren `Authorization: Bearer <token>`. Las solicitudes con datos usan `Content-Type: application/json`.

### Interfaz de acceso a datos

Tablas principales de SQLite: `users` (email y hash de la contraseña), `projects`, `tasks` y `users_projects`. Las consultas usan parámetros preparados.

Redis guarda las listas de tareas cacheadas (clave `tasks:user:{id}`) y los trabajos de la cola.

---

# Conceptos de la Unidad 3

## Escalabilidad horizontal

La aplicación ejecuta dos instancias del mismo servicio detrás de Nginx, en lugar de aumentar los recursos de una sola. Ante más carga, se pueden incorporar nuevas instancias.

**Demostración:** realizar varias solicitudes a `GET /api/health` y observar que `instance` alterna entre `api-1` y `api-2`. También se puede detener una instancia y comprobar que la otra sigue atendiendo (ver *Health Endpoint Monitoring*).

## Contenedores

Docker permite ejecutar las instancias de forma aislada y reproducible. Se eligieron contenedores en lugar de máquinas virtuales por su menor sobrecarga y su arranque más rápido: una máquina virtual requiere su propio sistema operativo.

## ACID

SQLite es una base relacional con transacciones ACID.

- **Atomicidad:** `createProject` en `projects.service.js` usa una transacción; ante un error en las inserciones se hace rollback.
- **Consistencia:** intentar crear una tarea sin `project_id` y comprobar que se rechaza.
- **Aislamiento:** `scripts/prueba_isolation.sh` envía dos `PATCH` concurrentes sobre la misma tarea (uno modifica el título, otro la descripción). Antes de ejecutarlo hay que reemplazar `TOKEN` por un JWT válido y verificar que `TASK_ID` corresponda a una tarea existente.
  ```bash
  bash scripts/prueba_isolation.sh
  ```
- **Durabilidad:** crear un usuario, detener los contenedores, volver a levantarlos y comprobar que las credenciales siguen funcionando (los datos viven en el volumen `dbdata`).

## Servicios sin estado

Las instancias no guardan sesión en memoria. Tras el login, el cliente envía el JWT en cada solicitud protegida, por lo que cualquier réplica puede atenderla.

**Demostración:** iniciar sesión, usar el mismo JWT para varias solicitudes y observar que las atienden instancias distintas.

---

# Patrones de la Unidad 4

## Disponibilidad

### Rate Limiting

Limita la cantidad de solicitudes por cliente en un intervalo de tiempo, para que ningún cliente degrade el servicio del resto. Se aplica en Nginx con `ngx_http_limit_req_module`.

| Zona | Rutas | Tasa | Ráfaga | Respuesta al exceder |
| --- | --- | --- | --- | --- |
| `auth_zone` | `/api/auth/*` | 1 solicitud/min por IP | 5 (con `nodelay`) | `429` |
| `api_zone` | `/api/tasks` y `/api/projects` (comparten zona) | 7 solicitudes/min por IP | 100 (con `nodelay`) | `429` |

- Los contadores viven en memoria compartida de Nginx. Como todo el tráfico pasa por el mismo balanceador, el límite es **global por cliente**, no por réplica, y no requiere Redis.
- El rechazo ocurre antes de la autenticación, la validación y cualquier consulta a SQLite o Redis.
- `/api/health` y el resto de las rutas no tienen límite.
- **Contrapartida:** el límite por IP puede afectar a usuarios legítimos detrás de un mismo NAT, y los clientes con `429` deben reintentar más tarde.

**Demostración:**

1. Partiendo de un estado sin tráfico previo, enviar rápidamente 8 `POST /api/auth/login` con credenciales incorrectas y formato válido: deben aparecer **seis `401`** (la solicitud base más cinco de ráfaga) y luego `429`.
2. Alternar entre `/api/auth/login` y `/api/auth/register`: ambas consumen el mismo límite.
3. Repetir solicitudes a `/api/tasks` y `/api/projects` hasta superar la ráfaga: comparten política y reciben `429`.
4. Tras un `429` en login, esperar aproximadamente un minuto: se admite **una** solicitud (la zona libera un lugar por minuto). Recuperar la ráfaga completa lleva unos cinco minutos.

> **Atención al probar:** la zona de autenticación es muy restrictiva (1/min). Si repetís el flujo de prueba varias veces seguidas, `register` y `login` pueden recibir `429`. Esperá unos minutos o recreá el balanceador (`docker compose restart loadbalancer`) para reiniciar los contadores.

### Health Endpoint Monitoring

Cada réplica expone un endpoint que informa su estado real, para detectar una réplica con el proceso vivo pero sin acceso a la base de datos.

- **`GET /api/health`** (sin JWT): devuelve el identificador de instancia, estado general, tiempo de actividad, hora y resultado de cada comprobación. Verifica que la conexión esté abierta, que el archivo sea accesible y que pueda leerse una tabla real (`task_states`). Responde `200` (`ok`) o `503` (`degraded`). El detalle del error se registra en el log de la instancia y no se expone al cliente.
- **`GET /api/health/live`** (sin JWT): indica solo que el proceso responde, sin consultar la base. Separa una instancia *viva* de una *lista para atender*.
- **Detección pasiva en Nginx:** la versión de código abierto no consulta `/health` periódicamente. Si una réplica responde `5xx`, no responde o excede el tiempo de conexión (2 s), Nginx reenvía el pedido a la otra (hasta 2 intentos) y, con `max_fails=1` y `fail_timeout=5s`, la deja fuera de rotación 5 segundos. Si ninguna réplica puede atender, responde un `503` en JSON (`{"status":"unavailable", ...}`).
- **Healthcheck de Docker:** cada contenedor consulta su propio `/api/health` cada 5 s y pasa a `unhealthy` tras dos fallas consecutivas. Se ve con `docker compose ps`.
- **Simulación de fallas:** la variable `FORCE_DB_FAIL` simula que la base no está disponible en una réplica, sin modificar imagen ni código. Es una simulación: reproduce el comportamiento del endpoint, no una corrupción real del archivo.

**Límites declarados:**

- *Detección pasiva:* el primer pedido que llega a una réplica caída paga el tiempo de espera (en las pruebas, 2,01 s frente a unos pocos ms en los siguientes).
- *Base compartida:* ambas réplicas y el worker usan el mismo SQLite; una falla real del archivo afectaría a todos. El patrón la detecta, pero no la evita.
- *Alcance:* el worker no expone HTTP, por lo que no tiene healthcheck propio; Docker lo reinicia ante una caída (`restart: always`).
- Lo que se demuestra es tolerancia a la caída de una réplica, no alta disponibilidad total.

**Demostración automática** — `scripts/prueba-health.sh` ejecuta seis pruebas contra el balanceador y termina con `RESULTADO: OK` o `RESULTADO: FAIL`:

| # | Prueba | Resultado esperado |
| --- | --- | --- |
| 1 | Ambas réplicas sanas, 6 consultas a `/api/health` | 6 × `200`, alternando `api-1` / `api-2` |
| 2 | `/api/health` y `/api/health/live` sin JWT | Ambos `200` |
| 3 | BD caída en `api-1` (`FORCE_DB_FAIL`) | `api-1` directo: `503` `degraded`; por Nginx: 8 × `200` desde `api-2`; `api-1` queda `unhealthy` y el log registra el fallo |
| 4 | Restauración de `api-1` | Ambas `healthy`, vuelve la alternancia |
| 5 | `api-1` detenida | 6 × `200` desde `api-2`; solo la primera demora ~2 s |
| 6 | Ambas réplicas detenidas | `503` con JSON `unavailable` |

```bash
# Corrida rápida
bash scripts/prueba-health.sh

# Corrida limpia (down -v + build) guardando la evidencia
mkdir -p evidencia
CLEAN=1 bash scripts/prueba-health.sh | tee evidencia/prueba-health.txt
```

En PowerShell, `CLEAN=1` se define con `$env:CLEAN=1` y el script requiere `bash` (Git Bash o WSL). Alternativamente, ejecutar directamente desde Git Bash.

## Rendimiento

### Cache-Aside

La lectura más frecuente, `GET /api/tasks`, ejecuta una consulta con unión de tablas sobre SQLite. Con Cache-Aside, la API consulta primero Redis; si no está (*miss*) lee de SQLite, guarda el resultado y responde.

- **Caché compartida:** un único Redis accesible por ambas réplicas, para que una invalidación sea visible para las dos.
- **Clave por usuario:** `tasks:user:{id}`, porque la respuesta depende de quién consulta.
- **Invalidación en escritura:** al crear, editar o eliminar una tarea, se actualiza **primero** SQLite y luego se eliminan de Redis las claves de **todos los miembros** del proyecto. Al asignar un usuario a un proyecto se elimina la clave de ese usuario.
- **TTL de 60 s** (`CACHE_TTL_SECONDS`) como red de seguridad frente a invalidaciones fallidas.
- **Tolerancia a fallas:** si Redis no responde, la API lo trata como *miss* y consulta SQLite; el servicio continúa.
- **Observabilidad:** el encabezado `X-Cache` indica `HIT` o `MISS`.
- **Contrapartida:** consistencia eventual acotada por la invalidación y el TTL, y un componente más para operar.

**Demostración:**

```bash
# Dos consultas consecutivas: MISS y luego HIT
curl -i http://localhost:8080/api/tasks -H "Authorization: Bearer <TOKEN>"
curl -i http://localhost:8080/api/tasks -H "Authorization: Bearer <TOKEN>"
```

1. Dos `GET /api/tasks` consecutivos deben dar `MISS` y luego `HIT`.
2. Tras editar una tarea (`PATCH`), la siguiente consulta debe dar `MISS` con el dato nuevo.
3. Si otro miembro del mismo proyecto edita una tarea, la consulta del primero también debe dar `MISS` (invalidación para todos los miembros).
4. Con Redis detenido (`docker compose stop redis`), `GET /api/tasks` debe seguir respondiendo con éxito.
5. Pasados 60 s (TTL), la consulta vuelve a dar `MISS`.
6. Para cuantificar el efecto, comparar los tiempos promedio de una serie de consultas `MISS` contra otra de `HIT`.

### Queue-Based Load Leveling

La creación de tareas (`POST /api/tasks`) es el punto crítico de escritura bajo concurrencia. En lugar de escribir directo en SQLite, la API encola el trabajo en Redis (con la librería **Bull**) y responde de inmediato **`202 Accepted`** con un `jobId`. Un worker dedicado consume la cola con concurrencia 1 (SQLite admite un solo escritor a la vez) y persiste a un ritmo estable.

```
Cliente -> Nginx -> API (productor, .add()) -> Redis/Bull -> worker (.process(1)) -> SQLite
                                                              (tfu-worker-1)
```

- La validación (Zod) y los chequeos de negocio (proyecto existente y pertenencia) se hacen **de forma síncrona antes de encolar**: si fallan, se responde `4xx` y no se genera ningún trabajo.
- El resultado se consulta con `GET /api/tasks/jobs/:id`: `pending`, `done` (con la tarea creada y su id) o `failed` (con el motivo). Un `jobId` inexistente responde `404`.
- Si Redis no está disponible, `POST /api/tasks` responde `503` (reintentable), en lugar de aceptar un trabajo que no podrá procesarse.
- Los trabajos tienen 3 intentos con *backoff* de 3 s.
- **Por qué Bull y no comandos crudos de Redis:** ofrece de forma nativa la abstracción de trabajos, estados, control de concurrencia y reintentos con espera.

**Trade-offs:** la creación pasa a ser eventualmente consistente (agrega latencia a cambio de absorber picos) y depende de Redis, a diferencia de la caché. No se encoló el registro de usuarios porque implicaba transportar contraseñas en texto plano por la cola. Limitación conocida: los reintentos del cliente pueden duplicar tareas (mitigación futura: *idempotency keys*).

**Demostración:**

```bash
bash scripts/prueba_cola.sh
```

Dispara 10 `POST /api/tasks` concurrentes (10 × `202`), espera que los 10 trabajos lleguen a `done`, verifica que `GET /api/tasks` trae las 10 tareas nuevas y prueba los casos de fallo (`404` ante un job inexistente, `4xx` ante un proyecto inexistente o ajeno).

## Seguridad

### Gatekeeper

Controles obligatorios previos a la lógica de negocio, implementados como **middlewares** de Express:

- **`authenticate.js`:** exige `Authorization: Bearer <token>`, verifica firma y vencimiento con `JWT_SECRET` y guarda la identidad en `req.user`. Si falta o es inválido, responde `401` sin ejecutar el controlador.
- **`validate.js`:** valida el cuerpo con esquemas Zod y responde `400` con los campos erróneos.
- **Rutas públicas:** `register` y `login` no requieren token, pero validan el cuerpo. `/api/health` queda fuera del Gatekeeper para que lo consulten Nginx y Docker sin credenciales.
- **Autorización sobre recursos:** permanece en los servicios, porque depende del recurso (pertenencia al proyecto para crear o modificar tareas, y ser propietario para asignar usuarios).

**Límite declarado:** al ejecutarse dentro de la misma API, no hay aislamiento de privilegios: si la API fuera comprometida, el atacante accedería tanto a `JWT_SECRET` como a la base. Azure recomienda un límite de cómputo separado; aquí se priorizó conservar la arquitectura. Se reduce parcialmente porque los puertos de las APIs no se publican.

**Demostración (Postman o curl):**

1. `GET /api/tasks` sin `Authorization` → `401`.
2. Con un token alterado o vencido → `401`.
3. Con un token válido → `200`.
4. `POST /api/tasks` con token válido y cuerpo vacío → `400` con los errores de validación.
5. Crear una tarea en un proyecto al que el usuario no pertenece → rechazada, sin insertar.
6. Crear una tarea con un usuario autorizado y datos válidos → `202` (la tarea se encola; ver *Queue-Based Load Leveling*).

### Gateway Offloading

Se traslada a Nginx el control de la frecuencia de solicitudes. *Rate Limiting* define la política (cuánto se admite); *Gateway Offloading* decide que se ejecute en el gateway, antes de que las solicitudes lleguen a las APIs.

- **Control centralizado** en `nginx/nginx.conf`.
- **Punto de entrada único:** las APIs no publican puertos en el host; solo `8080` es accesible.
- **Distribución entre réplicas:** Nginx reparte las solicitudes; las APIs no gestionan ese reparto.
- **Contexto del cliente:** Nginx agrega `Host`, `X-Real-IP`, `X-Forwarded-For` y `X-Forwarded-Proto`.
- **Separación de responsabilidades:** autenticación, validación y lógica de negocio quedan en Express.
- Si se agregara una tercera réplica, la cuota por cliente seguiría siendo la misma, sin modificar las APIs.

**Demostración:**

1. Intentar acceder a `localhost:3000`: no debe responder, porque los contenedores no publican ese puerto. El acceso previsto funciona por `localhost:8080`.
2. Consultar repetidamente `GET /api/health` por `localhost:8080` y comprobar que `instance` alterna entre `api-1` y `api-2`.
3. Superar el límite en `/api/auth/login` y comprobar que Nginx responde `429` sin que la solicitud llegue a las APIs.

## Facilidad de modificación y despliegue

### External Configuration Store

Los parámetros se separan del código y de la imagen y se suministran desde el exterior mediante `process.env`.

- **Configuración compartida:** `env_file` entrega los valores de `.env` a las réplicas y al worker.
- **Identificación por instancia:** `INSTANCE_ID` se define distinto para cada servicio en `docker-compose.yaml`.
- **Aplicación y persistencia:** `PORT` (`src/app.js`), `DB_PATH` (`src/db/database.js`) y `JWT_SECRET`.
- **Caché y cola:** `REDIS_HOST`, `REDIS_PORT` y `CACHE_TTL_SECONDS` (`src/cache.js`), con valores predeterminados en el código si no se proporcionan.
- **Simulación de fallas:** `FORCE_DB_FAIL` por réplica, controlada desde Compose mediante `API1_FORCE_DB_FAIL` / `API2_FORCE_DB_FAIL`.
- **Una misma imagen, distintos roles:** las APIs y el worker usan la misma imagen; el worker ejecuta `src/queue/taskWorker.js` en lugar del servidor HTTP.
- `.env.example` actúa como plantilla libre de credenciales; a partir de él se genera `.env`.

**Demostración:**

1. Cambiar `CACHE_TTL_SECONDS` a un valor pequeño (por ejemplo, 10) y recrear ambas APIs **sin reconstruir la imagen**. `GET /api/tasks` debe dar `MISS`, luego `HIT` y, tras el vencimiento, `MISS` otra vez. Evitar escrituras durante la prueba.
2. Cambiar `INSTANCE_ID` de una réplica en Compose y recrearla: `GET /api/health` mostrará la nueva identificación sin editar código.
3. Comparar los identificadores de imagen antes y después del cambio: deben ser iguales aunque los contenedores se hayan recreado.
4. Modificar `.env` sin recrear las APIs: conservan los valores anteriores. Después de recrearlas, adoptan los nuevos.

---

## Requisitos

- Docker y Docker Compose
- Docker Desktop (levantado antes de correr el proyecto)
- `curl` o Postman
- `bash` (Git Bash o WSL en Windows) para ejecutar los scripts de `scripts/`

## Variables de entorno

Configurar `.env` a partir de `.env.example`:

```env
PORT=3000
JWT_SECRET=un_secreto_muy_seguro
DB_PATH=/app/data/database.sqlite
REDIS_HOST=redis
REDIS_PORT=6379
CACHE_TTL_SECONDS=60
```

| Variable | Uso |
| --- | --- |
| `PORT` | Puerto interno de la API |
| `JWT_SECRET` | Firma y verificación de tokens |
| `DB_PATH` | Ubicación del archivo SQLite |
| `REDIS_HOST`, `REDIS_PORT` | Conexión a Redis (caché y cola) |
| `CACHE_TTL_SECONDS` | Vencimiento de las entradas de caché (60 por defecto) |
| `INSTANCE_ID` | Definida por servicio en `docker-compose.yaml` |
| `FORCE_DB_FAIL` | Simula base no disponible; se controla con `API1_FORCE_DB_FAIL` / `API2_FORCE_DB_FAIL` |

## Cómo levantar la demo

1. Verificar `.env` (ver arriba).

2. Levantar todo:
   ```bash
   docker compose up --build
   ```

3. Confirmar que los servicios estén corriendo y que las réplicas figuren como `healthy`:
   ```bash
   docker compose ps
   ```
   Se deberían observar `redis-queue`, `tfu-api-1`, `tfu-api-2`, `tfu-worker-1` y `tfu-lb`.

Todas las pruebas se hacen contra el balanceador: `http://localhost:8080`.

## Flujo de prueba sugerido

> En PowerShell, usar `curl.exe` en lugar de `curl`.

### 1. Registrar un usuario

```bash
curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@ucu.edu.uy","password":"123456"}'
```

### 2. Iniciar sesión

```bash
# Login -> guardar el token que devuelve
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@ucu.edu.uy","password":"123456"}'

# Sin token -> 401 (Gatekeeper: autenticación)
curl -i http://localhost:8080/api/tasks

# Con token -> 200
curl -i http://localhost:8080/api/tasks \
  -H "Authorization: Bearer <TOKEN>"

# Body inválido -> 400 (Gatekeeper: validación)
curl -X POST http://localhost:8080/api/tasks \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{}'
```

### 3. Crear un proyecto

```bash
curl -X POST http://localhost:8080/api/projects \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name":"Proyecto de prueba"}'
```

### 4. Listar proyectos

```bash
curl http://localhost:8080/api/projects \
  -H "Authorization: Bearer <TOKEN>"
```

### 5. Crear tarea (encolada)

```bash
# Responde 202 con un jobId
curl -X POST http://localhost:8080/api/tasks \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"title":"Preparar demo","project_id":1}'

# Consultar el estado del trabajo (pending -> done)
curl http://localhost:8080/api/tasks/jobs/<JOB_ID> \
  -H "Authorization: Bearer <TOKEN>"
```

### 6. Listar tareas (con caché)

```bash
# Primera consulta: X-Cache: MISS. Segunda: X-Cache: HIT
curl -i http://localhost:8080/api/tasks \
  -H "Authorization: Bearer <TOKEN>"
```

### 7. Asignar un usuario a un proyecto

```bash
curl -X POST http://localhost:8080/api/projects/assign \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"project_id":1,"user_id":2}'
```

### 8. Consultar la salud del sistema

```bash
curl -i http://localhost:8080/api/health
curl -i http://localhost:8080/api/health/live
```

## Pruebas automatizadas

| Script | Qué demuestra |
| --- | --- |
| `scripts/prueba_isolation.sh` | Aislamiento ACID con dos `PATCH` concurrentes (requiere `TOKEN` y `TASK_ID`) |
| `scripts/prueba_cola.sh` | Queue-Based Load Leveling: 10 × `202`, 10 trabajos `done`, casos de fallo |
| `scripts/prueba-health.sh` | Health Endpoint Monitoring: seis pruebas de réplica sana, BD caída, restauración, réplica detenida y ambas detenidas |

Las salidas de las corridas se guardan en `evidencia/`.

## Limitaciones y líneas de mejora

SQLite compartido, Redis y Nginx son componentes únicos de los que dependen varias funciones. Como mejoras se identifican:

- Un motor de base de datos independiente de las réplicas.
- Un balanceador redundante con verificaciones activas de salud.
- Una instancia de Redis redundante.
- Un Gatekeeper desplegado como componente separado.

## Notas

- Los JWT expiran a la hora (`expiresIn: "1h"`), por si la demo se extiende.
- La base SQLite vive en el volumen `dbdata`, compartido por ambas réplicas y por el worker.
- Los patrones están documentados con diagramas UML (componentes, secuencia y despliegue) y pruebas empíricas en el informe del trabajo.
