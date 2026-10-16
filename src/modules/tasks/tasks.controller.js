const tasksService = require("./tasks.service");
const taskQueue = require("../../queue/taskQueue");

function getTasks(req, res) {
  const tasks = tasksService.getAllTasks(req.user.id);
  return res
    .status(200)
    .json({ tasks, instance: process.env.INSTANCE_ID || "desconocida" });
}

async function createTask(req, res) {
  const { title, project_id, state, description } = req.body;

  const accessError = tasksService.checkCreateAccess(req.user.id, project_id);
  if (accessError) {
    return res.status(400).json({ message: accessError });
  }

  try {
    const job = await taskQueue.add(
      {
        userId: req.user.id,
        title,
        project_id,
        state,
        description,
      },
      {
        attempts: 3,
        backoff: 3000,
      },
    );

    return res.status(202).json({
      message: "Tarea recibida y encolada correctamente para su procesamiento",
      jobId: job.id,
      instance: process.env.INSTANCE_ID || "desconocida",
    });
  } catch (error) {
    return res.status(503).json({
      message: "Cola no disponible, intente de nuevo: " + error.message,
    });
  }
}

async function getJobStatus(req, res) {
  const job = await taskQueue.getJob(req.params.id);
  if (!job) {
    return res.status(404).json({ message: "Job no encontrado" });
  }
  const state = await job.getState();
  if (state === "completed") {
    return res.status(200).json({
      status: "done",
      jobId: job.id,
      task: job.returnvalue,
      instance: process.env.INSTANCE_ID || "desconocida",
    });
  }
  if (state === "failed") {
    return res.status(200).json({
      status: "failed",
      jobId: job.id,
      error: job.failedReason,
      instance: process.env.INSTANCE_ID || "desconocida",
    });
  }
  return res.status(200).json({
    status: "pending",
    jobId: job.id,
    queueState: state,
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

module.exports = { getTasks, createTask, getJobStatus, updateTask, deleteTask };
