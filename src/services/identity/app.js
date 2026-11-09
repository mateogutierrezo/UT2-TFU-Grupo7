const express = require("express");
require("dotenv").config();

require("./db/database");
const authRoutes = require("./routes/auth.routes");
const internalRoutes = require("./routes/internal.routes");
const healthRoutes = require("./routes/health.routes");

const app = express();

app.use(express.json());

// Rutas internas de salud (no ruteadas por el gateway): readiness + liveness.
app.use("/api/health", healthRoutes);

// Rutas públicas del dominio Identidad (mismo contrato que el monolito).
app.use("/api/auth", authRoutes);

// Rutas INTERNAS /api/internal/* — NO ruteadas por Nginx. Solo los servicios
// en la red Docker pueden llamarlas
app.use("/api/internal", internalRoutes);

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`[identity-service] running on port ${PORT}`);
});
