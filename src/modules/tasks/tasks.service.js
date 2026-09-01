const db = require("../../db/database");

function getAllTasks(userId) {
  const stmt = db.prepare("SELECT * FROM tasks WHERE userId = ?");
  return stmt.all(userId);
}

function createTask(userId, title, description) {
  const stmt = db.prepare(
    "INSERT INTO tasks (userId, title, description) VALUES (?, ?, ?)"
  );
  const result = stmt.run(userId, title, description || null);
  return { id: result.lastInsertRowid, userId, title, description };
}

module.exports = { getAllTasks, createTask };