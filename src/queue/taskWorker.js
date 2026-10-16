require("dotenv").config();

const taskQueue = require("./taskQueue");
const tasksService = require("../modules/tasks/tasks.service");
const cache = require("../cache");

taskQueue.process(1, async (job) => {
  const { userId, title, project_id, state, description } = job.data;
  const instance = process.env.INSTANCE_ID || "worker";
  console.log(
    `[${instance}] Procesando job ${job.id} (crear tarea "${title}")...`,
  );

  const result = tasksService.createTask(
    userId,
    title,
    project_id,
    state,
    description,
  );

  if (result && result.error) {
    console.error(`[${instance}] Job ${job.id} fallido: ${result.error}`);
    throw new Error(result.error);
  }

  console.log(`[${instance}] Job ${job.id} completado: tarea id=${result.id}.`);

  const memberIds = tasksService.getProjectMemberIds(result.project_id);
  await cache.invalidateUsers(memberIds);

  return result;
});

console.log(
  `[${process.env.INSTANCE_ID || "worker"}] Worker de tareas escuchando la cola...`,
);
