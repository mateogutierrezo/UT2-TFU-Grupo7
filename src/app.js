const express = require("express");
require("dotenv").config();

require("./db/database");
const authRoutes = require("./modules/auth/auth.routes");
const tasksRoutes = require("./modules/tasks/tasks.routes");
const projectsRoutes = require("./modules/projects/projects.routes");
const unstableRoutes = require("./routes/unstable.routes");
const healthRoutes = require("./modules/health/health.routes");

const app = express();

app.use(express.json());

app.use("/api/auth", authRoutes);
app.use("/api/tasks", tasksRoutes);
app.use("/api/projects", projectsRoutes);
app.use("/api/unstable", unstableRoutes);
app.use("/api/health", healthRoutes);

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`API running on port ${PORT}`);
});
