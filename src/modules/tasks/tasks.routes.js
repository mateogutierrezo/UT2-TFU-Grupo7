const express = require("express");
const tasksController = require("./tasks.controller");
const validate = require("../../middlewares/validate");
const authenticate = require("../../middlewares/authenticate");
const { createTaskSchema, updateTaskSchema } = require("./tasks.schema");

const router = express.Router();

router.get("/", authenticate, tasksController.getTasks);
router.post("/", authenticate, validate(createTaskSchema), tasksController.createTask);
router.patch("/:id", authenticate, validate(updateTaskSchema), tasksController.updateTask);
router.delete("/:id", authenticate, tasksController.deleteTask);

module.exports = router;