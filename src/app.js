const authRouter = require("./modules/auth/auth.routes");
const tasksRouter = require("./modules/tasks/tasks.routes");
const errorHandler = require("./middlewares/errorHandler");

app.use("/auth", authRouter);
app.use("/tasks", tasksRouter);
app.use(errorHandler); 