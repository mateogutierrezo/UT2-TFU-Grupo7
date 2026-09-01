const express = require("express");
const authController = require("./auth.controller");
const validate = require("../../middlewares/validate");
const { registerSchema } = require("./auth.schema");

const router = express.Router();

router.post("/register", validate(registerSchema), authController.register);

module.exports = router;
