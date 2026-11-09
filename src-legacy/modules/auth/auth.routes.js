const express = require("express");
const authController = require("./auth.controller");
const validate = require("../../middlewares/validate");
const { registerSchema, loginSchema } = require("./auth.schema");

const router = express.Router();

router.post("/register", validate(registerSchema), authController.register);
router.post("/login", validate(loginSchema), authController.login);

module.exports = router;
