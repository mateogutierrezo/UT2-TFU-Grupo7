const { z } = require("zod");

const noHtmlChars = (val) => !/[<>]/.test(val);
const noHtmlMessage = "El campo contiene caracteres no permitidos";

const registerSchema = z
  .object({
    email: z
      .string()
      .email("Email inválido")
      .refine(noHtmlChars, noHtmlMessage),
    password: z
      .string()
      .min(6, "La contraseña debe tener al menos 6 caracteres")
      .refine(noHtmlChars, noHtmlMessage),
  })
  .strict();

const loginSchema = z
  .object({
    email: z
      .string()
      .email("Email inválido")
      .refine(noHtmlChars, noHtmlMessage),
    password: z
      .string()
      .min(1, "La contraseña es requerida")
      .refine(noHtmlChars, noHtmlMessage),
  })
  .strict();

module.exports = {
  registerSchema,
  loginSchema,
};
