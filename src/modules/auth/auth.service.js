const bcrypt = require("bcryptjs");
const db = require("../../db/database");

const SALT_ROUNDS = 10;

function findUserByEmail(email) {
  const stmt = db.prepare("SELECT * FROM users WHERE email = ?");
  return stmt.get(email);
}

function createUser(email, password) {
  const hashedPassword = bcrypt.hashSync(password, SALT_ROUNDS);

  const stmt = db.prepare("INSERT INTO users (email, password) VALUES (?, ?)");
  const result = stmt.run(email, hashedPassword);

  return { id: result.lastInsertRowid, email };
}

module.exports = {
  findUserByEmail,
  createUser,
};
