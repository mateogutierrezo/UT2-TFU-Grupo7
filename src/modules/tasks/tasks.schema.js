const { z } = require("zod");

const noHtmlChars = (val) => !/[<>]/.test(val);
const noHtmlMessage = "El campo contiene caracteres no permitidos";

const createTaskSchema = z.object({
  title: z
    .string()
    .min(1, "El título es obligatorio")
    .refine(noHtmlChars, noHtmlMessage),
});

module.exports = { createTaskSchema };
