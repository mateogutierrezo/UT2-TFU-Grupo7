const db = require("../db/database");
const { TASK_STATES } = require("./tasks.constants");
const projectsSoap = require("../clients/projects.soap.client");

async function getAllTasks(userId) {
  const projectIds = await projectsSoap.getProjectIdsForUser(userId);
  if (projectIds.length === 0) return [];
  const placeholders = projectIds.map(() => "?").join(", ");
  const stmt = db.prepare(
    `SELECT * FROM tasks WHERE project_id IN (${placeholders})`,
  );
  return stmt.all(...projectIds);
}

async function checkCreateAccess(userId, projectId) {
  const { projectExists, isMember } = await projectsSoap.checkMembership(
    userId,
    projectId,
  );
  if (!projectExists) return "El proyecto no existe";
  if (!isMember) return "No tienes permiso para crear tareas en este proyecto";
  return null;
}

function createTask(
  userId,
  title,
  projectId,
  state = TASK_STATES.TODO,
  description = "",
) {
  const stmt = db.prepare(
    "INSERT INTO tasks (title, user_id, project_id, state, description) VALUES (?, ?, ?, ?, ?)",
  );
  const result = stmt.run(title, userId, projectId, state, description);
  return {
    id: result.lastInsertRowid,
    user_id: userId,
    title,
    project_id: projectId,
    state,
    description,
  };
}

async function updateTask(userId, taskId, fields) {
  const task = db.prepare("SELECT * FROM tasks WHERE id = ?").get(taskId);
  if (!task) return { error: "La tarea no existe" };
  const { isMember } = await projectsSoap.checkMembership(
    userId,
    task.project_id,
  );
  if (!isMember) return { error: "No tienes permiso para editar esta tarea" };
  const sets = [];
  const values = [];
  if (fields.title !== undefined) {
    sets.push("title = ?");
    values.push(fields.title);
  }
  if (fields.description !== undefined) {
    sets.push("description = ?");
    values.push(fields.description);
  }
  if (fields.state !== undefined) {
    sets.push("state = ?");
    values.push(fields.state);
  }
  values.push(taskId);
  db.prepare(`UPDATE tasks SET ${sets.join(", ")} WHERE id = ?`).run(...values);
  return db.prepare("SELECT * FROM tasks WHERE id = ?").get(taskId);
}

async function deleteTask(userId, taskId) {
  const task = db.prepare("SELECT * FROM tasks WHERE id = ?").get(taskId);
  if (!task) return { error: "La tarea no existe" };
  const { isMember } = await projectsSoap.checkMembership(
    userId,
    task.project_id,
  );
  if (!isMember) return { error: "No tienes permiso para eliminar esta tarea" };
  db.prepare("DELETE FROM tasks WHERE id = ?").run(taskId);
  return { id: taskId, project_id: task.project_id };
}

module.exports = {
  getAllTasks,
  checkCreateAccess,
  createTask,
  updateTask,
  deleteTask,
};
