# Universidad Católica del Uruguay

## Trabajo Final de Unidad 2 — Tácticas arquitectónicas - Grupo 7

## Introducción

### Objetivo:

Desarrollar una API REST sencilla de gestión
de tareas para demostrar la aplicación de diferentes tácticas de arquitectura
orientadas a mejorar la disponibilidad y la seguridad del sistema.

Las tácticas seleccionadas son **replicación** y **re-intentos** para mejorar la
disponibilidad, junto con **autenticar actores** y **validar la entrada** como
tácticas para resistir ataques. La aplicación contará con dos instancias de la
API, permitiendo que el servicio continúe funcionando ante la caída de una de
ellas. Además, se utilizará autenticación mediante JWT y validación de los
datos recibidos para proteger los recursos del sistema.

La aplicación será ejecutada mediante Docker Compose y podrá ser probada
utilizando herramientas como curl o Postman, permitiendo demostrar de forma
práctica el funcionamiento de las tácticas seleccionadas.

La funcionalidad de negocio (crear tareas) no es el foco: la aplicación existe
para hacer visibles las tácticas arquitectónicas seleccionadas.

## Estructura del proyecto

```
.
├── Dockerfile
├── docker-compose.yaml
├── .env
├── nginx/
│   └── nginx.conf
└── src/
    ├── app.js
    ├── db/
    │   └── database.js
    ├── middlewares/
    │   ├── validate.js          # valida el body con Zod
    │   └── authenticate.js      # valida el JWT del header
    ├── routes/
    │   └── unstable.routes.js   # endpoint que falla a propósito
    └── modules/
        ├── auth/
        │   ├── auth.routes.js
        │   ├── auth.controller.js
        │   ├── auth.service.js
        │   └── auth.schema.js
        └── tasks/
            ├── tasks.routes.js
            ├── tasks.controller.js
            ├── tasks.service.js
            └── tasks.schema.js
```

## Arquitectura conceptual

```
Cliente (curl/Postman)
        │
        ▼
 Load Balancer (nginx, puerto 8080)
        │
   ┌────┴────┐
   ▼         ▼
 API #1    API #2   (Express, mismo código, INSTANCE_ID distinto)
   │         │
   └────┬────┘
        ▼
  SQLite compartida (volumen db-data)
```

- **nginx** distribuye las solicitudes entre `api1` y `api2` (`upstream tfu_api`).
- Si una réplica falla o no responde, nginx reintenta automáticamente contra la
  otra (`proxy_next_upstream`), sin que el cliente lo note.
- Ambas réplicas comparten la misma base SQLite para que el login y las tareas
  sean consistentes sin importar a qué instancia caiga cada request.

## Endpoints

| Método | Ruta             | Protegido | Descripción                                                                                                          |
| ------ | ---------------- | --------- | -------------------------------------------------------------------------------------------------------------------- |
| POST   | `/auth/register` | No        | Registra un usuario (email + password)                                                                               |
| POST   | `/auth/login`    | No        | Autentica al usuario y devuelve un JWT                                                                               |
| GET    | `/tasks`         | Sí (JWT)  | Lista las tareas del usuario autenticado                                                                             |
| POST   | `/tasks`         | Sí (JWT)  | Crea una tarea, validando el body (`title` obligatorio)                                                              |
| GET    | `/unstable`      | No        | Si recibe `?fail=true`, la instancia elegida responde 500 para simular una falla controlada y demostrar re-intentos. |

## Requisitos

- Docker y Docker Compose
- Docker Desktop (levantado antes de correr el proyecto)
- curl o Postman

## Cómo levantar la demo

1. Verificar que `.env` tenga `PORT`, `JWT_SECRET` y `DB_PATH`.

   `.env`

   ```python
   PORT=3000
   JWT_SECRET=un_secreto_muy_seguro
   DB_PATH=/app/data/database.sqlite
   ```

2. Levantar todo:
   ```bash
   docker compose up --build
   ```
3. Confirmar que las dos réplicas y el load balancer estén corriendo:
   ```bash
   docker compose ps
   ```
   Se debería observar `tfu-api-1`, `tfu-api-2` y `tfu-lb`.

Todas las pruebas se hacen contra el load balancer: `http://localhost:8080`.

## Flujo de prueba sugerido

### 1. Seguridad — autenticación y validación

```bash
# Registro
curl.exe -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@ucu.edu.uy","password":"123456"}'

# Login -> guardar el token que devuelve
curl.exe -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@ucu.edu.uy","password":"123456"}'

# Sin token -> 401 (demuestra "autenticar actores")
curl.exe http://localhost:8080/api/tasks

# Con token -> 200
curl.exe http://localhost:8080/api/tasks \
  -H "Authorization: Bearer <TOKEN>"

# Body inválido -> 400 (demuestra "validar la entrada")
curl.exe -X POST http://localhost:8080/api/tasks \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{}'

# Body válido -> 201
curl.exe -X POST http://localhost:8080/api/tasks \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"title":"Terminar la demo"}'
```

### 2. Disponibilidad — replicación

Con **ambas réplicas arriba**:

1. Repetir un par de veces `GET /unstable` y anotar el campo `instance` de cada
   respuesta exitosa (200): debería alternar entre `api-1` y `api-2`.
2. Dar de baja una réplica:
   ```bash
   docker compose stop api1
   ```
3. Repetir `GET /unstable`: el servicio sigue respondiendo, y ahora el campo
   `instance` va a mostrar siempre `api-2` — así se demuestra que la caída de una instancia no deja el servicio indisponible.
4. Volver a levantarla si se quiere seguir probando:
   ```bash
   docker compose start api1
   ```

### 3. Disponibilidad — re-intentos y caídas controladas

El endpoint inestable se comporta de forma controlada para poder demostrar la táctica de disponibilidad en vivo.

- Sin query param: responde 200 y muestra la instancia que atendió la petición.
- Con `?fail=true`: la instancia elegida por nginx responde 500 para simular
  que una réplica cayó.

Ejemplos:

```bash
# responde OK
curl.exe -i http://localhost:8080/api/unstable

# fuerza una falla controlada en la instancia elegida por nginx
curl.exe -i "http://localhost:8080/api/unstable?fail=true"
```

La clave es que nginx está configurado con `max_fails=1` y `fail_timeout=5s`:

```nginx
upstream tfu_api {
    server api1:3000 max_fails=1 fail_timeout=5s;
    server api2:3000 max_fails=1 fail_timeout=5s;
}
```

Esto significa que, si una instancia responde 500 o deja de atender, nginx la
marcará como fallida durante 5 segundos. Durante ese tiempo, el balanceador
intentará enviar la siguiente solicitud a la otra réplica. Si ambas instancias
quedan marcadas como no disponibles, la respuesta final puede ser 502.

Esto permite demostrar en vivo que:

1. una réplica puede fallar sin que el servicio deje de responder en general,
2. nginx reintenta en la otra réplica,
3. si ambas están caídas temporalmente, aparece 502 como señal de que no hay
   backend sano disponible.

El campo `instance` en la respuesta ayuda a evidenciar qué réplica atendió cada
solicitud y hace la demo mucho más clara para la clase.

## Notas

- Los JWT expiran a la hora (`expiresIn: "1h"`), por si la demo se extiende.
- La base SQLite vive en el volumen `db-data`, compartido por ambas réplicas.
