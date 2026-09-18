const tasksService = require("./tasks.service");

function getTasks(req, res) {
  const tasks = tasksService.getAllTasks(req.user.id);
  return res
    .status(200)
    .json({ tasks, instance: process.env.INSTANCE_ID || "desconocida" });
}

function createTask(req, res) {
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
  return res.status(201).json({
    message: "Tarea creada correctamente",
    task: result,
    instance: process.env.INSTANCE_ID || "desconocida",
  });
}

function updateTask(req, res) {
  const taskId = parseInt(req.params.id, 10);
  const result = tasksService.updateTask(req.user.id, taskId, req.body);
  if (result.error) {
    return res.status(400).json({ message: result.error });
  }
  return res.status(200).json({
    message: "Tarea editada correctamente",
    task: result,
    instance: process.env.INSTANCE_ID || "desconocida",
  });
}

function deleteTask(req, res) {
  const taskId = parseInt(req.params.id, 10);
  const result = tasksService.deleteTask(req.user.id, taskId);
  if (result.error) {
    return res.status(400).json({ message: result.error });
  }
  return res.status(200).json({
    message: "Tarea eliminada correctamente",
    task: result,
    instance: process.env.INSTANCE_ID || "desconocida",
  });
}

module.exports = { getTasks, createTask, updateTask, deleteTask };
