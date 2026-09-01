const { z } = require("zod");

const createTaskSchema = z.object({
  title: z.string().min(1, "El título es obligatorio"),
});

module.exports = { createTaskSchema };