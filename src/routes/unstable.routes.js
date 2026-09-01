const express = require("express");
const router = express.Router();

router.get("/", (req, res) => {
  const shouldFail = Math.random() < 0.5;

  if (shouldFail) {
    return res.status(500).json({ error: "Fallo simulado en esta instancia" });
  }

  return res.status(200).json({
    message: "Solicitud atendida correctamente",
    instance: process.env.INSTANCE_NAME || "desconocida",
  });
});

module.exports = router;