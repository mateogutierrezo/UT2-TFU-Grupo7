const tasksService = require("./tasks.service");

function getTasks(req, res) {
  const tasks = tasksService.getAllTasks(req.user.id);
  return res.status(200).json({ tasks });
}

function createTask(req, res) {
  const { title, description } = req.body;
  const task = tasksService.createTask(req.user.id, title, description);
  return res.status(201).json({
    message: "Tarea creada correctamente",
    task,
  });
}

module.exports = { getTasks, createTask };