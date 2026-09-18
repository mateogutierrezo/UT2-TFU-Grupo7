const { z } = require("zod");
const { TASK_STATES } = require("./tasks.constants");

const noHtmlChars = (val) => !/[<>]/.test(val);
const noHtmlMessage = "El campo contiene caracteres no permitidos";

const stateIdSchema = z.number().int().refine(
  (val) => Object.values(TASK_STATES).includes(val),
  "Estado inválido"
);

const createTaskSchema = z.object({
  title: z
    .string()
    .min(1, "El título es obligatorio")
    .refine(noHtmlChars, noHtmlMessage),
  project_id: z.number().int().positive("El project_id es obligatorio"),
  state: stateIdSchema.optional(),
  description: z
    .string()
    .refine(noHtmlChars, noHtmlMessage)
    .optional(),
});

const updateTaskSchema = z
  .object({
    title: z
      .string()
      .min(1, "El título es obligatorio")
      .refine(noHtmlChars, noHtmlMessage)
      .optional(),
    description: z
      .string()
      .refine(noHtmlChars, noHtmlMessage)
      .optional(),
    state: stateIdSchema.optional(),
  })
  .refine(
    (data) =>
      data.title !== undefined ||
      data.description !== undefined ||
      data.state !== undefined,
    { message: "Debes enviar al menos un campo (title, description o state)" }
  );

module.exports = { createTaskSchema, updateTaskSchema };
