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

module.exports = {
  register,
};
