const express = require("express");
const authService = require("../modules/auth.service");

const router = express.Router();

router.get("/users/:id/exists", (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ error: "Id de usuario inválido" });
  }
  const exists = authService.existsUser(id);
  return res
    .status(200)
    .json({ exists, service: process.env.SERVICE_NAME || "identity-service" });
});

router.get("/users/:id", (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ error: "Id de usuario inválido" });
  }
  const user = authService.findUserById(id);
  if (!user) {
    return res.status(404).json({ error: "El usuario no existe" });
  }
  return res
    .status(200)
    .json({ user, service: process.env.SERVICE_NAME || "identity-service" });
});

module.exports = router;
