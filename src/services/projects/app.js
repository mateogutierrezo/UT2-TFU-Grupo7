const express = require("express");
require("dotenv").config();

require("./db/database");
const projectsRoutes = require("./routes/projects.routes");
const healthRoutes = require("./routes/health.routes");
const soapRoutes = require("./routes/soap.routes");

const app = express();

app.use(express.text({ type: "text/xml" }));
app.use(express.json());

app.use("/api/health", healthRoutes);
app.use("/api/projects", projectsRoutes);
app.use("/soap/projects", soapRoutes);

const PORT = process.env.PORT || 3001;

app.listen(PORT, () => {
  console.log(`[projects-service] running on port ${PORT}`);
});
