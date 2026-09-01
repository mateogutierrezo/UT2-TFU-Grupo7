const { z } = require("zod");

const createTaskSchema = z.object({
  title: z.string().min(1, "El título es obligatorio"),
  description: z.string().optional(),
});

module.exports = { createTaskSchema };