const db = require("../../db/database");

function getAllTasks(userId) {
  const stmt = db.prepare("SELECT * FROM tasks WHERE user_id = ?");
  return stmt.all(userId);
}

function createTask(userId, title) {
  const stmt = db.prepare(
    "INSERT INTO tasks (title, user_id) VALUES (?, ?)"
  );
  const result = stmt.run(title, userId);
  return { id: result.lastInsertRowid, user_id: userId, title };
}

module.exports = { getAllTasks, createTask };