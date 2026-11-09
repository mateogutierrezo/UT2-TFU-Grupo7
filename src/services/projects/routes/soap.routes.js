const express = require("express");
const fs = require("fs");
const path = require("path");
const projectsService = require("../modules/projects.service");

const router = express.Router();
const wsdlPath = path.join(__dirname, "../soap/projects.wsdl");

function escapeXml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function extractInt(xml, tag) {
  const normalized = String(xml ?? "");
  const match = normalized.match(new RegExp(`<[^>]*${tag}>([^<]+)</[^>]*${tag}>`));
  if (!match) return null;
  const num = Number(match[1].trim());
  return Number.isInteger(num) ? num : null;
}

function extractBool(xml, tag) {
  const normalized = String(xml ?? "");
  const match = normalized.match(new RegExp(`<[^>]*${tag}>([^<]+)</[^>]*${tag}>`));
  if (!match) return null;
  return match[1].trim().toLowerCase() === "true";
}

function buildEnvelope(inner) {
  return `<?xml version="1.0" encoding="UTF-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tns="http://projects.tfu.example/soap"><soap:Body>${inner}</soap:Body></soap:Envelope>`;
}

function buildFault(message) {
  return `<?xml version="1.0" encoding="UTF-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><soap:Fault><faultcode>soap:Server</faultcode><faultstring>${escapeXml(message)}</faultstring></soap:Fault></soap:Body></soap:Envelope>`;
}

function detectOperation(xml) {
  if (/AssignUserToProject/.test(String(xml ?? ""))) return "AssignUserToProject";
  if (/CheckMembership/.test(String(xml ?? ""))) return "CheckMembership";
  if (/GetProjectIdsForUser/.test(String(xml ?? ""))) return "GetProjectIdsForUser";
  return null;
}

router.get("/", (req, res) => {
  if (req.query.wsdl === undefined) {
    return res.status(400).send("SOAP endpoint. Use ?wsdl for the contract.");
  }
  const wsdl = fs.readFileSync(wsdlPath, "utf8");
  res.type("application/xml");
  res.send(wsdl);
});

router.post("/", async (req, res) => {
  const xml = typeof req.body === "string" ? req.body : "";
  const op = detectOperation(xml);
  res.type("application/xml; charset=utf-8");
  if (!op) {
    return res.status(400).send(buildFault("Operación no reconocida"));
  }
  try {
    if (op === "AssignUserToProject") {
      const actorId = extractInt(xml, "actorId");
      const projectId = extractInt(xml, "projectId");
      const userId = extractInt(xml, "userId");
      if (actorId === null || projectId === null || userId === null) {
        return res.status(400).send(buildFault("Parámetros inválidos: actorId, projectId, userId requeridos"));
      }
      const result = await projectsService.assignUser(actorId, projectId, userId);
      if (result.error) {
        return res.send(buildEnvelope(`<tns:AssignUserToProjectResponse><success>false</success><error>${escapeXml(result.error)}</error><user_id>0</user_id><project_id>0</project_id></tns:AssignUserToProjectResponse>`));
      }
      return res.send(buildEnvelope(`<tns:AssignUserToProjectResponse><success>true</success><error></error><user_id>${result.user_id}</user_id><project_id>${result.project_id}</project_id></tns:AssignUserToProjectResponse>`));
    }
    if (op === "CheckMembership") {
      const userId = extractInt(xml, "userId");
      const projectId = extractInt(xml, "projectId");
      if (userId === null || projectId === null) {
        return res.status(400).send(buildFault("Parámetros inválidos: userId, projectId requeridos"));
      }
      const out = projectsService.checkMembership(userId, projectId);
      return res.send(buildEnvelope(`<tns:CheckMembershipResponse><projectExists>${out.projectExists}</projectExists><isMember>${out.isMember}</isMember></tns:CheckMembershipResponse>`));
    }
    if (op === "GetProjectIdsForUser") {
      const userId = extractInt(xml, "userId");
      if (userId === null) {
        return res.status(400).send(buildFault("Parámetro inválido: userId requerido"));
      }
      const ids = projectsService.getProjectIdsForUser(userId);
      const inner = ids.map((id) => `<projectId>${id}</projectId>`).join("");
      return res.send(buildEnvelope(`<tns:GetProjectIdsForUserResponse>${inner}</tns:GetProjectIdsForUserResponse>`));
    }
    return res.status(400).send(buildFault("Operación no soportada"));
  } catch (err) {
    return res.status(500).send(buildFault(err.message || "Error interno"));
  }
});

module.exports = router;
