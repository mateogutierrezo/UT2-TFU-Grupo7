const db = require("../../db/database");
const { TASK_STATES } = require("./tasks.constants");

function getAllTasks(userId) {
  const stmt = db.prepare(`
    SELECT t.*
    FROM tasks t
    JOIN users_projects up ON up.project_id = t.project_id
    WHERE up.user_id = ?
  `);
  return stmt.all(userId);
}

function createTask(userId, title, projectId, state = TASK_STATES.TODO, description = "") {
  const project = db.prepare("SELECT * FROM projects WHERE id = ?").get(projectId);
  if (!project) {
    return { error: "El proyecto no existe" };
  }
  const isMember = db
    .prepare("SELECT * FROM users_projects WHERE user_id = ? AND project_id = ?")
    .get(userId, projectId);
  if (!isMember) {
    return { error: "No tienes permiso para crear tareas en este proyecto" };
  }
  const stmt = db.prepare(
    "INSERT INTO tasks (title, user_id, project_id, state, description) VALUES (?, ?, ?, ?, ?)"
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

function updateTask(userId, taskId, fields) {
  const task = db.prepare("SELECT * FROM tasks WHERE id = ?").get(taskId);
  if (!task) {
    return { error: "La tarea no existe" };
  }

  const hasAccess = db
    .prepare("SELECT * FROM users_projects WHERE user_id = ? AND project_id = ?")
    .get(userId, task.project_id);
  if (!hasAccess) {
    return { error: "No tienes permiso para editar esta tarea" };
  }

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

function deleteTask(userId, taskId) {
  const task = db.prepare("SELECT * FROM tasks WHERE id = ?").get(taskId);
  if (!task) {
    return { error: "La tarea no existe" };
  }

  const hasAccess = db
    .prepare("SELECT * FROM users_projects WHERE user_id = ? AND project_id = ?")
    .get(userId, task.project_id);
  if (!hasAccess) {
    return { error: "No tienes permiso para eliminar esta tarea" };
  }

  db.prepare("DELETE FROM tasks WHERE id = ?").run(taskId);
  return { id: taskId };
}

module.exports = { getAllTasks, createTask, updateTask, deleteTask };