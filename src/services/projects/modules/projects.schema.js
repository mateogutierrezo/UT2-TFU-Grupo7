const { z } = require("zod");

const noHtmlChars = (val) => !/[<>]/.test(val);
const noHtmlMessage = "El campo contiene caracteres no permitidos";

const createProjectSchema = z
  .object({
    name: z
      .string()
      .min(1, "El nombre del proyecto es obligatorio")
      .refine(noHtmlChars, noHtmlMessage),
  })
  .strict();

const assignUserSchema = z
  .object({
    project_id: z.number().int().positive("El project_id es obligatorio"),
    user_id: z.number().int().positive("El user_id es obligatorio"),
  })
  .strict();

module.exports = { createProjectSchema, assignUserSchema };