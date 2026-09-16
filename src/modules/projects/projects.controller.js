const projectsService = require("./projects.service");

function getProjects(req, res) {
  const projects = projectsService.getProjects(req.user.id);
  return res
    .status(200)
    .json({ projects, instance: process.env.INSTANCE_ID || "desconocida" });
}

function createProject(req, res) {
  const { name } = req.body;
  const project = projectsService.createProject(req.user.id, name);
  return res.status(201).json({
    message: "Proyecto creado correctamente",
    project,
    instance: process.env.INSTANCE_ID || "desconocida",
  });
}

function assignUser(req, res) {
  const { project_id, user_id } = req.body;
  const result = projectsService.assignUser(req.user.id, project_id, user_id);
  if (result.error) {
    return res.status(400).json({ message: result.error });
  }
  return res.status(200).json({
    message: "Usuario asignado al proyecto correctamente",
    result,
    instance: process.env.INSTANCE_ID || "desconocida",
  });
}

module.exports = { getProjects, createProject, assignUser };