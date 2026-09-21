# Universidad Católica del Uruguay

## Trabajo Final de Unidad 3 — Soluciones de arquitectura - Grupo 7

## Introducción

### Objetivo:

Desarrollar una API REST sencilla para la gestión de usuarios, proyectos y tareas para demostrar la aplicación de diferentes conceptos de arquitectura.

La solución implementa los siguientes conceptos:

- Componentes e interfaces
- Escalabilidad horizontal
- Contenedores
- ACID mediante transacciones
- Servicios sin estado

La aplicación permite registrar y autenticar usuarios, crear proyectos, crear y gestionar tareas y asignar usuarios a proyectos.

La API se ejecuta en dos instancias dentro de contenedores Docker, detrás de un balanceador de carga Nginx. Ambas instancias utilizan el mismo código y pueden atender las solicitudes de los clientes.

La persistencia se realiza mediante SQLite, utilizando transacciones ACID para mantener la integridad y consistencia de los datos.

La aplicación puede probarse mediante Postman o curl.

## Estructura del proyecto

```
.
├── Dockerfile
├── docker-compose.yaml
├── .env
├── nginx/
│   └── nginx.conf
├── scripts/
│   └── prueba_isolation.sh
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
        ├── tasks/
        │   ├── tasks.routes.js
        │   ├── tasks.controller.js
        │   ├── tasks.service.js
        │   └── tasks.schema.js
        └── projects/
            ├── projects.routes.js
            ├── projects.controller.js
            ├── projects.service.js
            └── projects.schema.js
            
```

## Arquitectura

La solución utiliza una partición técnica por responsabilidades, separando los componentes en tres niveles:

```
┌──────────────────────────────────────┐
│            Presentación              │
│                                      │
│               Postman                │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│           Infraestructura            │
│                                      │
│                Nginx                 │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│          Lógica de Negocio           │
│                                      │
│    ModuloAuth / ModuloProyectos /    │
│             ModuloTareas             │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│             Persistencia             │
│                                      │
│              SQLite                  │
└──────────────────────────────────────┘
```

La infraestructura contiene los componentes relacionados con la comunicación y el despliegue, principalmente **Nginx** como balanceador de carga.

La lógica de negocio contiene los módulos de **Usuarios, Proyectos y Tareas**, donde se encuentran las operaciones y reglas del sistema.

La persistencia contiene los componentes responsables del acceso y almacenamiento de los datos mediante **SQLite**.

## Arquitectura de despliegue

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

**Nginx** distribuye las solicitudes entre las dos instancias de la API, permitiendo demostrar la escalabilidad horizontal.

## Componentes e interfaces

La API expone una interfaz HTTP mediante endpoints REST. Los clientes interactúan con esta interfaz a través de **Nginx**, que distribuye las solicitudes entre las instancias disponibles.

La aplicación también utiliza una interfaz de acceso a datos para interactuar con **SQLite** mediante la biblioteca `better-sqlite3`.

### Interfaz HTTP

| Método | Ruta             | Protegido | Descripción                                                                                                          |
| ------ | ---------------- | --------- | -------------------------------------------------------------------------------------------------------------------- |
| POST   | `/api/auth/register` | No        | Registra un usuario (email + password)                                                                               |
| POST   | `/api/auth/login`    | No        | Autentica un usuario y devuelve un JWT                                                                               |
| GET    | `/api/tasks`         | Sí (JWT)  | Lista las tareas de los proyectos del usuario autenticado                                                                             |
| POST   | `/api/tasks`         | Sí (JWT)  | Crea una tarea dentro de un proyecto                                                        |
| PATCH    | `/api/tasks/:id`      | Sí (JWT)        | Modifica una tarea |
| DELETE    | `/api/tasks/:id`      | Sí (JWT)        | Elimina una tarea |
| POST    | `/api/projects`      | Sí (JWT)       | Crea un proyecto |
| GET    | `/api/projects`      | Sí (JWT)       | Lista los proyectos de un usuario |
| POST    | `/api/projects/assign`      | Sí (JWT)       | Asigna un usuario a un proyecto |

Las operaciones protegidas requieren el encabezado:

`Authorization: Bearer <token>`

Las solicitudes que contienen datos utilizan:

`Content-Type: application/json`

### Interfaz de acceso a datos

La persistencia se realiza mediante **SQLite** y la biblioteca `better-sqlite3`.

La base de datos contiene las siguientes tablas principales:

- `users`: usuarios, email y contraseña almacenada como hash.
- `projects`: proyectos, propietario y fecha de creación.
- `tasks`: tareas, usuario creador y proyecto asociado.
- `users_projects`: relaciones entre usuarios y proyectos.

Las consultas utilizan parámetros preparados para interactuar con la base de datos.

## Escalabilidad horizontal

La aplicación implementa escalabilidad horizontal mediante dos instancias de la API REST.

En lugar de aumentar los recursos de una única instancia, se ejecutan múltiples instancias del mismo servicio:

                      Nginx
                     /     \
                 API #1   API #2

Nginx distribuye las solicitudes entre ambas instancias. Esto permite que, ante un aumento de solicitudes, sea posible incorporar nuevas instancias de la API para distribuir la carga.

Para demostrar este concepto, se pueden realizar varias solicitudes y observar que son atendidas por las diferentes instancias.

También es posible detener una de las instancias y comprobar que la otra continúa atendiendo las solicitudes.

## Contenedores

La solución utiliza Docker para ejecutar los componentes de la aplicación.

Los contenedores permiten ejecutar las instancias de la API de forma aislada y reproducible, facilitando el despliegue de múltiples instancias.

Se eligieron contenedores en lugar de máquinas virtuales debido a su menor sobrecarga de recursos y a que permiten iniciar las instancias de forma más rápida.

La utilización de máquinas virtuales implicaría una mayor sobrecarga de infraestructura, ya que cada máquina requiere su propio sistema operativo.

## ACID

La solución utiliza una base de datos relacional **SQLite** con soporte para transacciones ACID.

Las propiedades ACID permiten mantener la integridad y consistencia de los datos relacionados entre usuarios, proyectos y tareas.

### Atomicidad

Una operación compuesta se completa completamente o se revierte.

**Demostración:** crear un proyecto y mostrar en `projects.service.js` que el método `createProject` utiliza una transacción. Si ocurre un error durante las inserciones, se realiza un rollback.

### Consistencia

Las operaciones deben mantener la base de datos en un estado válido.

**Demostración:** intentar crear una tarea sin `project_id` y comprobar que la operación es rechazada.

### Aislamiento

Las transacciones concurrentes no deben interferir incorrectamente entre sí, evitando que una operación observe datos intermedios de otra transacción.

Para comprobar este comportamiento, se incluye el script `scripts/prueba_isolation.sh`, que envía simultáneamente dos solicitudes `PATCH` sobre la misma tarea. Una solicitud modifica el título y la otra modifica la descripción.

Para ejecutar la prueba:

```bash
bash scripts/prueba_isolation.sh
```

Antes de ejecutarlo, se debe reemplazar el valor de `TOKEN` por un JWT válido y verificar que `TASK_ID` corresponda a una tarea existente.

El script utiliza procesos en segundo plano (`&`) para enviar ambas solicitudes de forma concurrente:

```bash
(
  curl -sS -X PATCH \
    "http://localhost:8080/api/tasks/$TASK_ID" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"title":"Título A"}'
) &

(
  curl -sS -X PATCH \
    "http://localhost:8080/api/tasks/$TASK_ID" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"description":"Descripción B"}'
) &

wait
```

De esta forma, se simula el acceso concurrente de distintos clientes sobre el mismo recurso y se puede observar el comportamiento de la API ante solicitudes simultáneas.

### Durabilidad

Una vez realizado el commit, los cambios confirmados permanecen almacenados de forma persistente ante fallos posteriores del sistema.

**Demostración:** crear un usuario, detener los contenedores, volver a levantarlos y comprobar que las credenciales continúan funcionando.

## Servicios sin estado

Las instancias de la API están diseñadas como servicios sin estado (stateless).

La información de autenticación no se almacena en la memoria de una instancia. Luego del login, el servidor devuelve un token JWT, que el cliente debe enviar en cada solicitud protegida:

`Authorization: Bearer <token>`

```
   ┌─────────┐
   ▼         ▼
 API #1    API #2
   │         │
   └─────────┘
```

De esta forma, cualquier instancia de la API puede recibir y procesar una solicitud sin depender de información de sesión almacenada en otra instancia.

Esto permite que el balanceador pueda distribuir las solicitudes entre las diferentes instancias sin necesidad de mantener al usuario asociado a una instancia específica.

**Demostración:**
1. Iniciar sesión y obtener un JWT.
2. Utilizar el mismo JWT para crear dos tareas.
3. Observar en los logs que cada solicitud es procesada por una instancia diferente de la API.

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

### 1. Registrar un usuario

```bash
# Registro
curl.exe -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@ucu.edu.uy","password":"123456"}'
```

### 2. Iniciar sesión

```bash
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

### 5. Crear tarea

```bash
# Crear tarea
curl -X POST http://localhost:8080/api/tasks \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"title":"Preparar demo","project_id":1}'
```

### 6. Listar tareas

```bash
curl http://localhost:8080/api/tasks \
  -H "Authorization: Bearer <TOKEN>"
```

### 7. Asignar un usuario a un proyecto

```bash
curl -X POST http://localhost:8080/api/projects/assign \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"project_id":1,"user_id":2}'
```

### 8. Probar aislamiento

Con una tarea existente y un token válido, ejecutar:

```bash
bash scripts/prueba_isolation.sh
```

El script envía dos solicitudes `PATCH` concurrentes sobre la misma tarea: una modifica el título y otra modifica la descripción.

Esto permite observar el comportamiento de la API cuando existen operaciones concurrentes sobre el mismo recurso.

## Notas

- Los JWT expiran a la hora (`expiresIn: "1h"`), por si la demo se extiende.
- La base SQLite vive en el volumen `db-data`, compartido por ambas réplicas.
