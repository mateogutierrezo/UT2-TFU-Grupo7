const express = require("express");
const router = express.Router();

router.get("/", (req, res) => {
  const shouldFail = req.query.fail === "true";

  if (shouldFail) {
    return res.status(500).json({
      error: "Fallo simulado en esta instancia",
      instance: process.env.INSTANCE_ID || "desconocida",
    });
  }

  return res.status(200).json({
    message: "Solicitud atendida correctamente",
    instance: process.env.INSTANCE_ID || "desconocida",
  });
});

module.exports = router;
