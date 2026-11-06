const tasksService = require("./tasks.service");

const instance = () => process.env.INSTANCE_ID || "desconocida";

function isUnavailable(err) {
  return err && err.code === "PROJECTS_UNAVAILABLE";
}

async function getTasks(req, res) {
  try {
    const tasks = await tasksService.getAllTasks(req.user.id);
    return res.status(200).json({
      tasks,
      service: process.env.SERVICE_NAME || "tasks-service",
      instance: instance(),
    });
  } catch (err) {
    if (isUnavailable(err)) {
      return res.status(503).json({
        message: "Servicio de proyectos no disponible (temporal)",
      });
    }
    throw err;
  }
}

async function createTask(req, res) {
  const { title, project_id, state, description } = req.body;
  try {
    const accessError = await tasksService.checkCreateAccess(
      req.user.id,
      project_id,
    );
    if (accessError) {
      return res.status(400).json({ message: accessError });
    }
    const task = tasksService.createTask(
      req.user.id,
      title,
      project_id,
      state,
      description,
    );
    return res.status(201).json({
      message: "Tarea creada correctamente",
      task,
      service: process.env.SERVICE_NAME || "tasks-service",
      instance: instance(),
    });
  } catch (err) {
    if (isUnavailable(err)) {
      return res.status(503).json({
        message: "Servicio de proyectos no disponible (temporal)",
      });
    }
    throw err;
  }
}

async function updateTask(req, res) {
  const taskId = parseInt(req.params.id, 10);
  try {
    const result = await tasksService.updateTask(req.user.id, taskId, req.body);
    if (result.error) {
      return res.status(400).json({ message: result.error });
    }
    return res.status(200).json({
      message: "Tarea editada correctamente",
      task: result,
      service: process.env.SERVICE_NAME || "tasks-service",
      instance: instance(),
    });
  } catch (err) {
    if (isUnavailable(err)) {
      return res.status(503).json({
        message: "Servicio de proyectos no disponible (temporal)",
      });
    }
    throw err;
  }
}

async function deleteTask(req, res) {
  const taskId = parseInt(req.params.id, 10);
  try {
    const result = await tasksService.deleteTask(req.user.id, taskId);
    if (result.error) {
      return res.status(400).json({ message: result.error });
    }
    return res.status(200).json({
      message: "Tarea eliminada correctamente",
      task: result,
      service: process.env.SERVICE_NAME || "tasks-service",
      instance: instance(),
    });
  } catch (err) {
    if (isUnavailable(err)) {
      return res.status(503).json({
        message: "Servicio de proyectos no disponible (temporal)",
      });
    }
    throw err;
  }
}

module.exports = { getTasks, createTask, updateTask, deleteTask };
