const db = require("../db/database");
const { userExists } = require("../clients/identity.client");

function getProjects(userId) {
  const stmt = db.prepare(`
    SELECT p.id, p.name, p.created_at, p.owner
    FROM users_projects up
    JOIN projects p ON p.id = up.project_id
    WHERE up.user_id = ?
  `);
  return stmt.all(userId);
}

function getProjectIdsForUser(userId) {
  const rows = db
    .prepare("SELECT project_id FROM users_projects WHERE user_id = ?")
    .all(userId);
  return rows.map((r) => Number(r.project_id));
}

function checkMembership(userId, projectId) {
  const project = db
    .prepare("SELECT id FROM projects WHERE id = ?")
    .get(projectId);
  if (!project) {
    return { projectExists: false, isMember: false };
  }
  const membership = db
    .prepare(
      "SELECT user_id, project_id FROM users_projects WHERE user_id = ? AND project_id = ?",
    )
    .get(userId, projectId);
  return { projectExists: true, isMember: !!membership };
}

function createProject(ownerId, name) {
  const createProjectTx = db.transaction(() => {
    const stmt = db.prepare("INSERT INTO projects (name, owner) VALUES (?, ?)");
    const result = stmt.run(name, ownerId);
    const assignStmt = db.prepare(
      "INSERT INTO users_projects (user_id, project_id) VALUES (?, ?)",
    );
    assignStmt.run(ownerId, result.lastInsertRowid);
    return { id: result.lastInsertRowid, name, owner: ownerId };
  });
  return createProjectTx();
}

async function assignUser(ownerId, projectId, userId) {
  const project = db
    .prepare("SELECT * FROM projects WHERE id = ?")
    .get(projectId);
  if (!project) {
    return { error: "El proyecto no existe" };
  }
  if (project.owner !== ownerId) {
    return {
      error: "No tienes permiso para asignar usuarios a este proyecto",
    };
  }
  const exists = await userExists(userId);
  if (!exists) {
    return { error: "El usuario no existe" };
  }
  const existing = db
    .prepare(
      "SELECT * FROM users_projects WHERE user_id = ? AND project_id = ?",
    )
    .get(userId, projectId);
  if (existing) {
    return { error: "El usuario ya está asignado a este proyecto" };
  }
  db.prepare(
    "INSERT INTO users_projects (user_id, project_id) VALUES (?, ?)",
  ).run(userId, projectId);
  return { user_id: userId, project_id: projectId };
}

module.exports = {
  getProjects,
  getProjectIdsForUser,
  checkMembership,
  createProject,
  assignUser,
};
