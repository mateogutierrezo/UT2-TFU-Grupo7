const express = require("express");
const projectsController = require("./projects.controller");
const validate = require("../../middlewares/validate");
const authenticate = require("../../middlewares/authenticate");
const { createProjectSchema, assignUserSchema } = require("./projects.schema");

const router = express.Router();

router.get("/", authenticate, projectsController.getProjects);
router.post("/", authenticate, validate(createProjectSchema), projectsController.createProject);
router.post("/assign", authenticate, validate(assignUserSchema), projectsController.assignUser);

module.exports = router;