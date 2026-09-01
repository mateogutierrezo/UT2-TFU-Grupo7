const express = require("express");
const tasksController = require("./tasks.controller");
const validate = require("../../middlewares/validate");
const authenticate = require("../../middlewares/authenticate");
const { createTaskSchema } = require("./tasks.schema");

const router = express.Router();

router.get("/", authenticate, tasksController.getTasks);
router.post("/", authenticate, validate(createTaskSchema), tasksController.createTask);

module.exports = router;