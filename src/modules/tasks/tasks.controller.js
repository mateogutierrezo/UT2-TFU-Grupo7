const tasksService = require("./tasks.service");
const taskQueue = require("../../queues/taskQueue"); // <--- 1. Importa la cola que creaste

function getTasks(req, res) {
  const tasks = tasksService.getAllTasks(req.user.id);
  return res
    .status(200)
    .json({ tasks, instance: process.env.INSTANCE_ID || "desconocida" });
}

//  implementacion Queue-Based Load Leveling
async function createTask(req, res) {
  const { title, project_id, state, description } = req.body;
  
  try {
    // en lugar de llamar directo al servicio de la BD, encolamos la tarea en Redis
    const job = await taskQueue.add({
      userId: req.user.id,
      title,
      project_id,
      state,
      description
    }, {
      attempts: 3,
      backoff: 3000
    });

    // Respondemos inmediatamente al cliente con un estado 202 (Aceptado para procesamiento asíncrono)
    return res.status(202).json({
      message: "Tarea recibida y encolada correctamente para su procesamiento",
      jobId: job.id,
      instance: process.env.INSTANCE_ID || "desconocida",
    });
  } catch (error) {
    return res.status(500).json({ message: "Error al encolar la tarea: " + error.message });
  }
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