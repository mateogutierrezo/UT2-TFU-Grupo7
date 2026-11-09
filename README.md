# Universidad Católica del Uruguay

## Trabajo Final de Unidad 5 — Estilos Arquitectónicos — Grupo 7

## Introducción

### Objetivo

Este trabajo corresponde a la **Unidad Temática 5 (Estilos Arquitectónicos)**. Evoluciona la aplicación de la unidad anterior, una API REST para la gestión de usuarios, proyectos y tareas, construida con **Node.js y Express**, con **SQLite** y autenticación con **tokens JWT**, desde un monolito en capas replicado hacia una **arquitectura de microservicios**.

La solución se compone de tres servicios de negocio independientes (**Identidad**, **Proyectos** y **Tareas**) y de un **API Gateway** (Nginx) que es el único punto de entrada al sistema (puerto `8080`). Cada servicio tiene su propio contenedor, su propia base SQLite y su propio volumen de datos, y ningún servicio accede a la base de otro.

La consigna exige implementar el nuevo estilo arquitectónico, migrar al menos una operación de REST a SOAP con contrato WSDL, aplicar al menos un patrón que aborde las falacias de la computación distribuida, y validar el atributo de calidad priorizado: **disponibilidad**.

### Qué cambia respecto a la Unidad 4

| Aspecto | Unidad 4 (monolito en capas) | Unidad 5 (microservicios) |
| --- | --- | --- |
| Organización | Una aplicación con módulos `auth`, `projects` y `tasks` | Tres servicios: Identidad, Proyectos y Tareas |
| Datos | Una SQLite compartida (`dbdata`) | Una SQLite por servicio (`identity-data`, `projects-data`, `tasks-data`) |
| Comunicación entre módulos | Llamadas a funciones y consultas SQL | REST/JSON hacia el Gateway; SOAP/XML de Tareas a Proyectos; REST interno de Proyectos a Identidad |
| Punto de entrada | Nginx como balanceador de dos réplicas | Nginx como API Gateway que enruta por ruta |
| Tolerancia a fallas | Réplicas y *health checks* | Aislamiento de fallas entre servicios y Circuit Breaker en Tareas |

### Conceptos que se conservan de las unidades anteriores

- Componentes e interfaces
- Contenedores
- ACID mediante transacciones (dentro de cada servicio)
- Servicios sin estado
- Patrones de la Unidad 4 que siguen vigentes: Rate Limiting, Gateway Offloading, Gatekeeper, Health Endpoint Monitoring y External Configuration Store

### Patrón de la Unidad 5

| Grupo | Patrón | Qué hace en el sistema | Dónde vive |
| --- | --- | --- | --- |
| Disponibilidad | **Circuit Breaker** | Protege a Tareas de la indisponibilidad de Proyectos: abre el circuito ante un porcentaje alto de fallas y rechaza de inmediato las solicitudes, sin esperar el *timeout* | `src/services/tasks/patron/circuitBreaker.js` y `src/services/tasks/clients/projects.soap.client.js` |

### Patrones de la Unidad 4 que se mantienen

| Grupo | Patrón | Qué hace en el sistema | Dónde vive |
| --- | --- | --- | --- |
| Disponibilidad | **Rate Limiting** | Limita solicitudes por IP y rechaza el exceso con `429` | `nginx/nginx.conf` |
| Disponibilidad | **Health Endpoint Monitoring** | Cada servicio informa su estado, incluida su base de datos | `/api/health` de cada servicio, *healthchecks* de Docker |
| Seguridad | **Gatekeeper** | Autenticación y validación previas a la lógica de negocio | Middlewares de cada servicio |
| Seguridad | **Gateway Offloading** | Traslada al Gateway el control del tráfico y la entrada única | `nginx/nginx.conf`, `docker-compose.yaml` |
| Facilidad de modificación y despliegue | **External Configuration Store** | Separa del código y de la imagen los parámetros de ejecución | `.env`, `docker-compose.yaml` |

## Estructura del proyecto

```
.
├── Dockerfile
├── docker-compose.yaml
├── .env
├── .env.example
├── evidencia/                         # salidas de las corridas de prueba
├── nginx/
│   └── nginx.conf                     # API Gateway: enrutamiento, rate limiting y 503 controlado
├── scripts/                           # validaciones de los patrones seleccionados
└── src/
    └── services/
        ├── identity/                  # Servicio de Identidad
        │   ├── app.js
        │   └── db/database.js
        ├── projects/                  # Servicio de Proyectos
        │   ├── app.js
        │   ├── clients/
        │   │   └── identity.client.js # cliente REST interno hacia Identidad
        │   ├── routes/
        │   │   └── soap.routes.js     # endpoint SOAP (/soap/projects)
        │   ├── soap/
        │   │   └── projects.wsdl      # contrato WSDL
        │   └── db/database.js
        └── tasks/                     # Servicio de Tareas
            ├── app.js
            ├── clients/
            │   └── projects.soap.client.js  # cliente SOAP + Circuit Breaker
            ├── patron/
            │   └── circuitBreaker.js        # implementación del patrón
            ├── modules/                     # controlador y servicio de tareas
            └── db/database.js
```

## Arquitectura

La solución sigue una arquitectura de microservicios con una puerta de entrada única:

```
┌──────────────────────────────────────┐
│               Cliente                │
│           Postman / curl             │
└──────────────────┬───────────────────┘
                   ▼
┌──────────────────────────────────────┐
│     API Gateway (Nginx, :8080)       │
└───────┬──────────┬──────────┬────────┘
        ▼          ▼          ▼
   Identidad    Proyectos    Tareas
        ▲          ▲  ▲         │
        │          │  └─────────┘
        │          │   SOAP/XML (con Circuit Breaker)
        └──────────┘
      REST interno
```

### Arquitectura de despliegue

```
Cliente (curl/Postman)
        │
        ▼
 API Gateway (nginx, puerto 8080)     ← único puerto publicado en el host
        │
   ┌────┼────────────┐
   ▼    ▼            ▼
 identity-service  projects-service  tasks-service     (Express, puerto 3000, misma imagen)
   │                 │   ▲              │
   │                 │   └── SOAP ──────┘
   └── REST interno ◄┘
   │                 │                  │
   ▼                 ▼                  ▼
identity-data    projects-data      tasks-data         (volúmenes Docker con SQLite)
```

| Servicio | Imagen | Rol | Base de datos |
| --- | --- | --- | --- |
| `gateway` | `nginx:alpine` | Único punto de entrada (`8080`), rate limiting y enrutamiento por ruta | — |
| `identity-service` | `build: .` | Registro y autenticación de usuarios | `identity.sqlite` (`identity-data`) |
| `projects-service` | `build: .` | Proyectos, propietarios y membresías; proveedor SOAP | `projects.sqlite` (`projects-data`) |
| `tasks-service` | `build: .` | Ciclo de vida de las tareas; consumidor SOAP con Circuit Breaker | `tasks.sqlite` (`tasks-data`) |

Los puertos de los servicios **no se publican** en el host: todo acceso externo pasa por el Gateway. El Gateway solo arranca cuando los tres servicios están `healthy`. En cambio, `tasks-service` **no** declara dependencia de arranque hacia `projects-service`, de modo que puede iniciar y responder aunque Proyectos esté caído (aislamiento de fallas).

## Componentes e interfaces

Los clientes interactúan con la API HTTP a través del Gateway, que enruta cada solicitud al servicio correspondiente según el prefijo de la ruta: `/api/auth` a Identidad, `/api/projects` a Proyectos y `/api/tasks` a Tareas.

### Interfaz HTTP (REST/JSON)

| Método | Ruta | Servicio | Protegido | Descripción |
| --- | --- | --- | --- | --- |
| POST | `/api/auth/register` | Identidad | No | Registra un usuario (email + password) |
| POST | `/api/auth/login` | Identidad | No | Autentica un usuario y devuelve un JWT |
| POST | `/api/projects` | Proyectos | Sí (JWT) | Crea un proyecto |
| GET | `/api/projects` | Proyectos | Sí (JWT) | Lista los proyectos del usuario |
| POST | `/api/projects/assign` | Proyectos | Sí (JWT) | Asigna un usuario a un proyecto (solo el propietario) |
| GET | `/api/tasks` | Tareas | Sí (JWT) | Lista las tareas de los proyectos del usuario |
| POST | `/api/tasks` | Tareas | Sí (JWT) | Crea una tarea (`201`); verifica membresía con Proyectos |
| PATCH | `/api/tasks/:id` | Tareas | Sí (JWT) | Modifica una tarea |
| DELETE | `/api/tasks/:id` | Tareas | Sí (JWT) | Elimina una tarea |
| GET | `/api/health` | Gateway | No | Estado del propio Gateway |

Cada servicio expone además su propio `GET /api/health` (estado e información de su base de datos), usado por los *healthchecks* de Docker dentro de la red interna.

Las operaciones protegidas requieren `Authorization: Bearer <token>`. Las solicitudes con datos usan `Content-Type: application/json`.

### Códigos de respuesta relevantes de Tareas

| Código | Situación |
| --- | --- |
| `201` | Tarea creada: el usuario es miembro del proyecto |
| `400` | El proyecto no existe o el usuario no es miembro (respuesta de negocio, no cuenta como falla del Circuit Breaker) |
| `503` | Proyectos no disponible: *timeout*, `Fault` SOAP, error HTTP o circuito abierto (`PROJECTS_UNAVAILABLE`). No se escribe ningún dato |

### Interfaces internas (no publicadas en el Gateway)

| Interfaz | Proveedor | Consumidor | Protocolo |
| --- | --- | --- | --- |
| `/soap/projects` (`?wsdl` para el contrato) | Proyectos | Tareas | SOAP 1.1 / XML, WSDL 1.1, *document/literal* |
| `/api/internal/users/:id/exists` | Identidad | Proyectos | REST/JSON, *timeout* de 2 s |

El contrato SOAP, descrito en `src/services/projects/soap/projects.wsdl`, define tres operaciones: `CheckMembership`, `GetProjectIdsForUser` y `AssignUserToProject`. Las rutas `/soap/*` y `/api/internal/*` solo son accesibles dentro de la red de Docker: el Gateway responde `404` ante cualquier solicitud externa.

### Interfaz de acceso a datos

Cada servicio accede **únicamente** a su propia base SQLite, mediante `better-sqlite3` y consultas con parámetros preparados.

| Servicio | Datos que administra |
| --- | --- |
| Identidad | Usuarios y hashes de contraseñas |
| Proyectos | Proyectos y relaciones usuario-proyecto |
| Tareas | Tareas y estados (`project_id` es solo una referencia a Proyectos, sin clave foránea) |

---

# Estilo arquitectónico

## Microservicios

Cada capacidad de negocio se ejecuta como un proceso independiente, con su contenedor, su configuración y su volumen persistente. Un cambio interno en un servicio puede desplegarse sin modificar a los demás, siempre que se conserven sus contratos.

**Demostración:**

1. Levantar el sistema y verificar con `docker compose ps` que `gateway`, `identity-service`, `projects-service` y `tasks-service` figuren como `healthy`.
2. Intentar acceder a `localhost:3000`: no debe responder, porque los servicios no publican puertos. El acceso previsto es por `localhost:8080`.
3. Verificar en `docker volume ls` que existen `identity-data`, `projects-data` y `tasks-data`, uno por servicio.

## Comunicación entre servicios (REST y SOAP)

La comunicación entre el cliente y el Gateway usa REST/JSON. Entre servicios, Tareas consume el contrato SOAP de Proyectos para verificar membresías (`CheckMembership`) y obtener los proyectos accesibles de un usuario (`GetProjectIdsForUser`). En el monolito esas verificaciones eran consultas SQL locales; ahora son llamadas remotas.

**Demostración:**

1. Registrar un usuario, iniciar sesión y crear un proyecto.
2. Crear una tarea en ese proyecto: responde `201`, lo que confirma que Tareas completó la llamada SOAP a Proyectos.
3. Consultar el contrato desde dentro de la red de Docker:
   ```bash
   docker compose exec tasks-service node -e "fetch('http://projects-service:3000/soap/projects?wsdl').then(r=>r.text()).then(console.log)"
   ```
4. Intentar acceder a `http://localhost:8080/soap/projects?wsdl`: el Gateway responde `404`.

---

# Patrones

## Disponibilidad

### Circuit Breaker

Tareas depende de Proyectos para verificar membresías. Si Proyectos falla o se demora, cada solicitud a Tareas esperaría el *timeout* y consumiría recursos. El Circuit Breaker detecta la indisponibilidad y, una vez que se abre el circuito, rechaza las solicitudes de inmediato, sin contactar al servicio caído. Aborda las falacias *"la red es confiable"* y *"la latencia es cero"*.

| Estado | Comportamiento |
| --- | --- |
| `CLOSED` (cerrado) | Las llamadas se realizan normalmente y se registra su resultado en una ventana móvil |
| `OPEN` (abierto) | Las llamadas se rechazan de inmediato (`PROJECTS_UNAVAILABLE`) hasta que vence el tiempo de reset |
| `HALF_OPEN` (semiabierto) | Se permite una única llamada de prueba: si tiene éxito el circuito se cierra; si falla, se abre nuevamente |

- **Apertura por porcentaje:** el circuito se abre cuando el porcentaje de fallas alcanza el **50 %** con al menos **5 solicitudes** dentro de una ventana móvil de **10 s**.
- **Tiempo de reset:** **10 s** antes de pasar a semiabierto. La transición ocurre con la siguiente solicitud que llega luego de ese plazo.
- **Fallas técnicas vs. respuestas de negocio:** *timeout* (2 s en la llamada SOAP; 2,5 s en el breaker), `Fault` SOAP y errores HTTP cuentan como fallas. Que el proyecto no exista o que el usuario no sea miembro es una respuesta válida y **no** cuenta como falla.
- **Seguridad ante la duda:** si no se puede verificar la membresía, la operación falla con `503`; nunca se concede acceso por defecto.
- **Observabilidad:** cada transición se registra en el log de Tareas con el formato `[circuit:projects] <estado anterior> -> <estado nuevo> (<motivo>)`.
- **Contrapartida:** los valores de configuración son iniciales y no están optimizados; las solicitudes que llegan antes de que se abra el circuito igualmente esperan el *timeout*.

**Demostración automática:**

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\prueba-disponibilidad.ps1
```

El script verifica el estado inicial, detiene únicamente `projects-service`, comprueba que Identidad y Tareas siguen respondiendo, envía cinco solicitudes concurrentes a `GET /api/tasks`, verifica que el circuito pase a `OPEN` y que la solicitud siguiente sea rechazada rápidamente. Luego reinicia Proyectos y comprueba que el circuito vuelva a `CLOSED`. Guarda las mediciones (`.csv`) y las transiciones del circuito (`-circuitos.txt`) en `evidencia/`.

**Demostración manual:**

```bash
# Detener solo Proyectos
docker compose stop projects-service

# Varias solicitudes: las primeras esperan ~2 s y devuelven 503
curl -i http://localhost:8080/api/tasks -H "Authorization: Bearer <TOKEN>"

# Una vez abierto el circuito, la respuesta 503 es inmediata
curl -i http://localhost:8080/api/tasks -H "Authorization: Bearer <TOKEN>"

# Ver las transiciones del circuito
docker compose logs tasks-service | findstr circuit      # PowerShell
docker compose logs tasks-service | grep circuit         # bash

# Recuperación: reiniciar Proyectos, esperar ~10 s y repetir la solicitud
docker compose start projects-service
curl -i http://localhost:8080/api/tasks -H "Authorization: Bearer <TOKEN>"
```

### Rate Limiting

Limita la cantidad de solicitudes por cliente en un intervalo de tiempo. Se aplica en el Gateway con `ngx_http_limit_req_module`.

| Zona | Rutas | Tasa | Ráfaga | Respuesta al exceder |
| --- | --- | --- | --- | --- |
| `auth_zone` | `/api/auth/*` | 1 solicitud/min por IP | 5 (con `nodelay`) | `429` |
| `api_zone` | `/api/tasks` y `/api/projects` (comparten zona) | 7 solicitudes/min por IP | 100 (con `nodelay`) | `429` |

- Los contadores viven en memoria compartida de Nginx; el límite es **global por cliente**.
- El rechazo ocurre antes de que la solicitud llegue a cualquier servicio.
- `/api/health` y el resto de las rutas no tienen límite.
- **Contrapartida:** el límite por IP puede afectar a usuarios legítimos detrás de un mismo NAT, y los clientes con `429` deben reintentar más tarde.

> **Atención al probar:** la zona de autenticación es muy restrictiva (1/min). Si se repite el flujo de prueba varias veces seguidas, `register` y `login` pueden recibir `429`. Esperar unos minutos o reiniciar el Gateway (`docker compose restart gateway`) para reiniciar los contadores.

### Health Endpoint Monitoring

Cada servicio expone `GET /api/health`, que informa su estado real, incluida la disponibilidad de su base de datos. Responde `200` (`ok`) o `503` (`degraded`).

- **Healthcheck de Docker:** cada contenedor consulta su propio `/api/health` cada 5 s y pasa a `unhealthy` tras dos fallas consecutivas. Se ve con `docker compose ps`.
- **Simulación de fallas:** la variable `FORCE_DB_FAIL` simula que la base no está disponible en un servicio, sin modificar imagen ni código. Es una simulación del comportamiento del endpoint, no una corrupción real del archivo.
- **Reinicio automático:** los servicios usan `restart: unless-stopped`.
- **Límite declarado:** cada servicio tiene una única instancia, por lo que su caída deja sin servicio a la capacidad que ofrece (se mitiga con el aislamiento de fallas y el Circuit Breaker).

## Seguridad

### Gatekeeper

Controles obligatorios previos a la lógica de negocio, implementados como **middlewares** de Express en cada servicio:

- **Autenticación:** exige `Authorization: Bearer <token>`, verifica firma y vencimiento con `JWT_SECRET` y guarda la identidad en `req.user`. Si falta o es inválido, responde `401` sin ejecutar el controlador.
- **Validación:** valida el cuerpo con esquemas Zod y responde `400` con los campos erróneos.
- **Rutas públicas:** `register` y `login` no requieren token, pero validan el cuerpo. `/api/health` queda fuera del Gatekeeper.
- **Autorización sobre recursos:** permanece en los servicios, porque depende del recurso. En Tareas, la pertenencia al proyecto se consulta a Proyectos mediante SOAP.

**Demostración (Postman o curl):**

1. `GET /api/tasks` sin `Authorization` → `401`.
2. Con un token alterado o vencido → `401`.
3. Con un token válido → `200`.
4. `POST /api/tasks` con token válido y cuerpo vacío → `400` con los errores de validación.
5. Crear una tarea en un proyecto al que el usuario no pertenece → `400`, sin insertar.

### Gateway Offloading

Se traslada al Gateway el control de la frecuencia de solicitudes y la entrada única. *Rate Limiting* define la política; *Gateway Offloading* decide que se ejecute en Nginx, antes de que las solicitudes lleguen a los servicios.

- **Control centralizado** en `nginx/nginx.conf`.
- **Punto de entrada único:** los servicios no publican puertos en el host; solo `8080` es accesible.
- **Enrutamiento por ruta:** `/api/auth`, `/api/projects` y `/api/tasks` se dirigen al servicio correspondiente.
- **Resolución dinámica por DNS de Docker:** el Gateway arranca y sigue funcionando aunque un servicio esté caído o cambie de IP.
- **Error controlado:** si el servicio destino no responde (`502`, `503` o `504`), el Gateway devuelve un `503` en JSON.
- **Rutas no publicadas:** `/soap/*`, `/api/internal/*` y cualquier otra ruta no declarada responden `404`.
- **Contexto del cliente:** Nginx agrega `Host`, `X-Real-IP`, `X-Forwarded-For` y `X-Forwarded-Proto`.

**Demostración:**

1. Intentar acceder a `localhost:3000`: no debe responder.
2. Consultar `http://localhost:8080/api/health`: responde el estado del propio Gateway.
3. Consultar `http://localhost:8080/soap/projects?wsdl`: responde `404`.
4. Superar el límite en `/api/auth/login`: Nginx responde `429` sin que la solicitud llegue a Identidad.

## Facilidad de modificación y despliegue

### External Configuration Store

Los parámetros se separan del código y de la imagen y se suministran desde el exterior mediante `process.env`.

- **Configuración compartida:** `env_file` entrega los valores de `.env` a los tres servicios.
- **Configuración por servicio:** `docker-compose.yaml` define `SERVICE_NAME`, `INSTANCE_ID` y `DB_PATH` de cada uno.
- **Dependencias entre servicios:** `IDENTITY_SERVICE_URL` e `IDENTITY_TIMEOUT_MS` (Proyectos); `PROJECTS_SOAP_URL` y `PROJECTS_SOAP_TIMEOUT_MS` (Tareas).
- **Circuit Breaker:** los umbrales se ajustan con variables `PROJECTS_CB_*`, con valores predeterminados en el código.
- **Una misma imagen, distintos roles:** los tres servicios usan la misma imagen; cada uno ejecuta su propio `app.js` mediante el `command` de Compose.
- `.env.example` actúa como plantilla libre de credenciales; a partir de él se genera `.env`.

**Demostración:**

1. Cambiar `PROJECTS_CB_RESET_TIMEOUT_MS` en `.env` y recrear `tasks-service` **sin reconstruir la imagen**: el circuito pasa a semiabierto en el nuevo plazo.
2. Comparar los identificadores de imagen antes y después del cambio: deben ser iguales aunque el contenedor se haya recreado.
3. Modificar `.env` sin recrear el servicio: conserva los valores anteriores. Después de recrearlo, adopta los nuevos.

---

## Requisitos

- Docker y Docker Compose
- Docker Desktop (levantado antes de correr el proyecto)
- `curl` o Postman
- PowerShell (para `scripts/prueba-disponibilidad.ps1`)

## Variables de entorno

Configurar `.env` a partir de `.env.example`:

```env
PORT=3000
JWT_SECRET=cambiar_por_un_secreto_seguro
```

`DB_PATH`, `SERVICE_NAME`, `INSTANCE_ID` y las URL entre servicios se definen por servicio en `docker-compose.yaml`.

| Variable | Uso | Valor predeterminado |
| --- | --- | --- |
| `PORT` | Puerto interno de cada servicio | `3000` |
| `JWT_SECRET` | Firma y verificación de tokens | — |
| `DB_PATH` | Ubicación del archivo SQLite de cada servicio | Definida en Compose |
| `INSTANCE_ID`, `SERVICE_NAME` | Identificación de cada servicio | Definidas en Compose |
| `FORCE_DB_FAIL` | Simula base no disponible en un servicio | — |
| `IDENTITY_SERVICE_URL` | Dirección de Identidad usada por Proyectos | `http://identity-service:3000` |
| `IDENTITY_TIMEOUT_MS` | *Timeout* de Proyectos hacia Identidad | `2000` |
| `PROJECTS_SOAP_URL` | Dirección del SOAP de Proyectos usada por Tareas | `http://projects-service:3000/soap/projects` |
| `PROJECTS_SOAP_TIMEOUT_MS` | *Timeout* de la llamada SOAP | `2000` |
| `PROJECTS_CB_TIMEOUT_MS` | *Timeout* del Circuit Breaker | `2500` |
| `PROJECTS_CB_VOLUME_THRESHOLD` | Mínimo de solicitudes para evaluar la apertura | `5` |
| `PROJECTS_CB_ERROR_THRESHOLD_PERCENTAGE` | Porcentaje de fallas que abre el circuito | `50` |
| `PROJECTS_CB_ROLLING_COUNT_TIMEOUT_MS` | Ventana de medición | `10000` |
| `PROJECTS_CB_RESET_TIMEOUT_MS` | Espera antes de pasar a semiabierto | `10000` |

## Cómo levantar la demo

1. Crear `.env` a partir de la plantilla:
   ```bash
   cp .env.example .env          # bash
   copy .env.example .env        # PowerShell
   ```

2. Levantar todo:
   ```bash
   docker compose up --build
   ```

3. Confirmar que los servicios estén corriendo y figuren como `healthy`:
   ```bash
   docker compose ps
   ```
   Se deberían observar `identity-service`, `projects-service`, `tasks-service` y `gateway`.

Todas las pruebas se hacen contra el Gateway: `http://localhost:8080`.

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

### 5. Crear una tarea (verifica membresía mediante SOAP)

```bash
# Responde 201 si el usuario es miembro del proyecto
curl -X POST http://localhost:8080/api/tasks \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"title":"Preparar demo","project_id":1}'
```

### 6. Listar tareas

```bash
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
```

### 9. Simular la caída de Proyectos

```bash
docker compose stop projects-service
curl -i http://localhost:8080/api/tasks -H "Authorization: Bearer <TOKEN>"   # 503
docker compose start projects-service
```

## Pruebas automatizadas

| Script | Qué demuestra |
| --- | --- |
| `scripts/prueba-disponibilidad.ps1` | Aislamiento de la falla de Proyectos, apertura del Circuit Breaker, rechazo rápido y recuperación a `CLOSED` |

Las salidas de las corridas se guardan en `evidencia/`.

## Limitaciones y líneas de mejora

- Cada servicio tiene una única instancia, por lo que la caída de uno deja sin servicio a su capacidad. Como mejora, replicar los servicios detrás del Gateway.
- SQLite con un archivo por servicio es adecuado para la demostración; con múltiples escritores o varias máquinas habría que usar un motor de base de datos independiente.
- No existe una transacción distribuida: entre la verificación de membresía y la escritura de la tarea hay una ventana de tiempo, compromiso aceptado al separar los datos entre servicios.
- La red interna de Docker no reemplaza la autenticación entre servicios; una mejora sería proteger también las interfaces internas (SOAP y REST interno).
- Los parámetros del Circuit Breaker son valores iniciales, no optimizados.
- El Gateway es un componente único (Nginx de código abierto, sin verificaciones activas de salud).

## Notas

- Los JWT expiran a la hora (`expiresIn: "1h"`), por si la demo se extiende.
- Cada base SQLite vive en el volumen de su servicio (`identity-data`, `projects-data`, `tasks-data`).
- Los estados del Circuit Breaker se llaman `CLOSED`, `OPEN` y `HALF_OPEN` en el código y en los logs.
- Los estilos y patrones están documentados con diagramas UML (componentes, despliegue y secuencia) y pruebas empíricas en el informe del trabajo.