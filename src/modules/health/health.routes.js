const express = require("express");
const fs = require("fs");
const db = require("../../db/database");

const router = express.Router();
const instanceId = () => process.env.INSTANCE_ID || "desconocida";

function checkDatabase() {
  const start = Date.now();
  try {
    // Hook de prueba para simular una BD caída en una sola réplica
    if (process.env.FORCE_DB_FAIL === "true") {
      throw new Error("falla simulada (FORCE_DB_FAIL)");
    }
    if (!db.open) throw new Error("conexión cerrada");
    fs.accessSync(db.name, fs.constants.R_OK | fs.constants.W_OK);
    db.prepare("SELECT COUNT(*) AS n FROM task_states").get();
    return { status: "up", responseTimeMs: Date.now() - start };
  } catch (err) {
    console.error(`[health] ${instanceId()} - fallo de BD: ${err.message}`);
    return { status: "down" };
  }
}

// Liveness: el proceso responde (no toca la BD)
router.get("/live", (req, res) => {
  res.status(200).json({ instance: instanceId(), status: "ok" });
});

// Readiness: la instancia puede atender (verifica la BD)
router.get("/", (req, res) => {
  const database = checkDatabase();
  const healthy = database.status === "up";

  res.status(healthy ? 200 : 503).json({
    instance: instanceId(),
    status: healthy ? "ok" : "degraded",
    uptimeSeconds: Math.floor(process.uptime()),
    timestamp: new Date().toISOString(),
    checks: { database },
  });
});

module.exports = router;