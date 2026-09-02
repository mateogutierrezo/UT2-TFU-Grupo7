const express = require("express");
require("dotenv").config();

require("./db/database");
const authRoutes = require("./modules/auth/auth.routes");
const tasksRoutes = require("./modules/tasks/tasks.routes");
const unstableRoutes = require("./routes/unstable.routes");

const app = express();

app.use(express.json());

app.get("/api/health", (req, res) => {
  res.json({
    instance: process.env.INSTANCE_ID || "desconocida",
    status: "ok",
  });
});

app.use("/api/auth", authRoutes);
app.use("/api/tasks", tasksRoutes);
app.use("/api/unstable", unstableRoutes);

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`API running on port ${PORT}`);
});
