const projectsService = require("./projects.service");
const projectsSoap = require("../clients/projects.soap.client");

function getProjects(req, res) {
  const projects = projectsService.getProjects(req.user.id);
  return res.status(200).json({
    projects,
    service: process.env.SERVICE_NAME || "projects-service",
    instance: process.env.INSTANCE_ID || "desconocida",
  });
}

function createProject(req, res) {
  const { name } = req.body;
  const project = projectsService.createProject(req.user.id, name);
  return res.status(201).json({
    message: "Proyecto creado correctamente",
    project,
    service: process.env.SERVICE_NAME || "projects-service",
    instance: process.env.INSTANCE_ID || "desconocida",
  });
}

async function assignUser(req, res) {
  const { project_id, user_id } = req.body;
  try {
    const soapResult = await projectsSoap.assignUserToProject(
      req.user.id,
      project_id,
      user_id,
    );
    if (!soapResult.success) {
      return res.status(400).json({ message: soapResult.error });
    }
    return res.status(200).json({
      message: "Usuario asignado al proyecto correctamente",
      result: {
        user_id: soapResult.user_id,
        project_id: soapResult.project_id,
      },
      service: process.env.SERVICE_NAME || "projects-service",
      instance: process.env.INSTANCE_ID || "desconocida",
    });
  } catch (err) {
    if (err && err.code === "PROJECTS_UNAVAILABLE") {
      return res.status(503).json({
        message: "Servicio de proyectos no disponible (temporal)",
      });
    }
    throw err;
  }
}

module.exports = { getProjects, createProject, assignUser };
