const db = require("../../db/database");

function getProjects(userId) {
  const stmt = db.prepare(`
    SELECT p.id, p.name, p.created_at, p.owner, u.email AS owner_email
    FROM users_projects up
    JOIN projects p ON p.id = up.project_id
    JOIN users u ON u.id = p.owner
    WHERE up.user_id = ?
  `);
  return stmt.all(userId);
}

function createProject(ownerId, name) {
  const stmt = db.prepare(
    "INSERT INTO projects (name, owner) VALUES (?, ?)"
  );
  const result = stmt.run(name, ownerId);

  const assignStmt = db.prepare(
    "INSERT INTO users_projects (user_id, project_id) VALUES (?, ?)"
  );
  assignStmt.run(ownerId, result.lastInsertRowid);

  return { id: result.lastInsertRowid, name, owner: ownerId };
}

function assignUser(ownerId, projectId, userId) {
  const project = db.prepare("SELECT * FROM projects WHERE id = ?").get(projectId);
  if (!project) {
    return { error: "El proyecto no existe" };
  }
  if (project.owner !== ownerId) {
    return { error: "No tienes permiso para asignar usuarios a este proyecto" };
  }

  const user = db.prepare("SELECT * FROM users WHERE id = ?").get(userId);
  if (!user) {
    return { error: "El usuario no existe" };
  }

  const existing = db
    .prepare("SELECT * FROM users_projects WHERE user_id = ? AND project_id = ?")
    .get(userId, projectId);
  if (existing) {
    return { error: "El usuario ya está asignado a este proyecto" };
  }

  db.prepare("INSERT INTO users_projects (user_id, project_id) VALUES (?, ?)").run(
    userId,
    projectId
  );

  return { user_id: userId, project_id: projectId };
}

module.exports = { getProjects, createProject, assignUser };