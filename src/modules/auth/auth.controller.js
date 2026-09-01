const jwt = require("jsonwebtoken");
const userService = require("./auth.service");

function register(req, res) {
  const { email, password } = req.body;

  const existingUser = userService.findUserByEmail(email);
  if (existingUser) {
    return res.status(409).json({ error: "El usuario ya existe" });
  }

  const user = userService.createUser(email, password);

  return res.status(201).json({
    message: "Usuario registrado correctamente",
    user: { id: user.id, email: user.email },
  });
}

function login(req, res) {
  const { email, password } = req.body;

  const user = userService.findUserByEmail(email);
  if (!user) {
    return res.status(401).json({ error: "Credenciales inválidas" });
  }

  const isValid = userService.validatePassword(password, user.password);
  if (!isValid) {
    return res.status(401).json({ error: "Credenciales inválidas" });
  }

  const token = jwt.sign(
    { id: user.id, email: user.email },
    process.env.JWT_SECRET,
    { expiresIn: "1h" }
  );

  return res.status(200).json({
    message: "Login exitoso",
    token,
  });
}

module.exports = {
  register,
  login,
};
