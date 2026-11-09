const express = require("express");
require("dotenv").config();

require("./db/database");
const tasksRoutes = require("./routes/tasks.routes");
const healthRoutes = require("./routes/health.routes");

const app = express();

app.use(express.json());

// Rutas internas de salud (no ruteadas por el gateway): readiness + liveness.
app.use("/api/health", healthRoutes);

// Rutas públicas del dominio Tareas (mismo contrato que el monolito).
app.use("/api/tasks", tasksRoutes);

const PORT = process.env.PORT || 3002;

app.listen(PORT, () => {
  console.log(`[tasks-service] running on port ${PORT}`);
});
