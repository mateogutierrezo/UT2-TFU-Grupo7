const tasksService = require("./tasks.service");
const cache = require("../../cache");

const instance = () => process.env.INSTANCE_ID || "desconocida";

async function invalidateProjectCache(projectId) {
  const memberIds = tasksService.getProjectMemberIds(projectId);
  await cache.invalidateUsers(memberIds);
}

async function getTasks(req, res) {
  const cached = await cache.getTasks(req.user.id);
  
  if (cached) {
    res.set("X-Cache", "HIT");
    return res.status(200).json({ tasks: cached, instance: instance() });
  }

  const tasks = tasksService.getAllTasks(req.user.id);
  await cache.setTasks(req.user.id, tasks);
  res.set("X-Cache", "MISS");
  return res.status(200).json({ tasks, instance: instance() });
}

async function createTask(req, res) {
  const { title, project_id, state, description } = req.body;
  const result = tasksService.createTask(
    req.user.id,
    title,
    project_id,
    state,
    description
  );

  if (result.error) {
    return res.status(400).json({ message: result.error });
  }

  await invalidateProjectCache(result.project_id);
  return res.status(201).json({
    message: "Tarea creada correctamente",
    task: result,
    instance: instance(),
  });
}

async function updateTask(req, res) {
  const taskId = parseInt(req.params.id, 10);
  const result = tasksService.updateTask(req.user.id, taskId, req.body);
  
  if (result.error) {
    return res.status(400).json({ message: result.error });
  }

  await invalidateProjectCache(result.project_id);
  return res.status(200).json({
    message: "Tarea editada correctamente",
    task: result,
    instance: instance(),
  });
}

async function deleteTask(req, res) {
  const taskId = parseInt(req.params.id, 10);
  const result = tasksService.deleteTask(req.user.id, taskId);
  
  if (result.error) {
    return res.status(400).json({ message: result.error });
  }
  
  await invalidateProjectCache(result.project_id);
  return res.status(200).json({
    message: "Tarea eliminada correctamente",
    task: result,
    instance: instance(),
  });
}

module.exports = { getTasks, createTask, updateTask, deleteTask };