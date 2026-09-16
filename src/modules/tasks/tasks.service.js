const db = require("../../db/database");

function getAllTasks(userId) {
  const stmt = db.prepare(`
    SELECT t.*
    FROM tasks t
    JOIN users_projects up ON up.project_id = t.project_id
    WHERE up.user_id = ?
  `);
  return stmt.all(userId);
}

function createTask(userId, title, projectId) {
  const project = db.prepare("SELECT * FROM projects WHERE id = ?").get(projectId);
  if (!project) {
    return { error: "El proyecto no existe" };
  }
  if (project.owner !== userId) {
    return { error: "No tienes permiso para crear tareas en este proyecto" };
  }
  const stmt = db.prepare(
    "INSERT INTO tasks (title, user_id, project_id) VALUES (?, ?, ?)"
  );
  const result = stmt.run(title, userId, projectId);
  return { id: result.lastInsertRowid, user_id: userId, title, project_id: projectId };
}

module.exports = { getAllTasks, createTask };