const express = require("express");
const authController = require("../controllers/authController");
const validate = require("../middleware/validate");
const { registerSchema } = require("../schemas/authSchemas");

const router = express.Router();

router.post("/register", validate(registerSchema), authController.register);

module.exports = router;
