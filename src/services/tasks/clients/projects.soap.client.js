const SOAP_URL =
  process.env.PROJECTS_SOAP_URL || "http://localhost:3001/soap/projects";
const TIMEOUT_MS = Number(process.env.PROJECTS_SOAP_TIMEOUT_MS) || 2000;

function extractInt(xml, tag) {
  const match = String(xml ?? "").match(
    new RegExp(`<[^>]*${tag}>([^<]+)</[^>]*${tag}>`),
  );
  if (!match) return null;
  const num = Number(match[1].trim());
  return Number.isInteger(num) ? num : null;
}

function extractBool(xml, tag) {
  const match = String(xml ?? "").match(
    new RegExp(`<[^>]*${tag}>([^<]+)</[^>]*${tag}>`),
  );
  if (!match) return null;
  return match[1].trim().toLowerCase() === "true";
}

function extractText(xml, tag) {
  const match = String(xml ?? "").match(
    new RegExp(`<[^>]*${tag}>([^<]*)</[^>]*${tag}>`),
  );
  return match ? match[1].trim() : "";
}

function unavailable(message) {
  const err = new Error(message || "Servicio de proyectos no disponible");
  err.code = "PROJECTS_UNAVAILABLE";
  return err;
}

async function callSoap(operation, innerBody) {
  const envelope = `<?xml version="1.0" encoding="UTF-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tns="http://projects.tfu.example/soap"><soap:Body><tns:${operation}>${innerBody}</tns:${operation}></soap:Body></soap:Envelope>`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  let res;
  try {
    res = await fetch(SOAP_URL, {
      method: "POST",
      headers: {
        "Content-Type": "text/xml; charset=utf-8",
        SOAPAction: `"urn:${operation}"`,
      },
      body: envelope,
      signal: controller.signal,
    });
  } catch (err) {
    throw unavailable(err.message);
  } finally {
    clearTimeout(timer);
  }
  const text = await res.text();
  if (/<soap:Fault|<Fault>/.test(text)) {
    const fault = extractText(text, "faultstring") || "Fault SOAP";
    throw unavailable(fault);
  }
  if (!res.ok) {
    throw unavailable(`HTTP ${res.status}`);
  }
  return text;
}

async function checkMembership(userId, projectId) {
  const xml = await callSoap(
    "CheckMembership",
    `<userId>${userId}</userId><projectId>${projectId}</projectId>`,
  );
  return {
    projectExists: extractBool(xml, "projectExists") ?? false,
    isMember: extractBool(xml, "isMember") ?? false,
  };
}

async function getProjectIdsForUser(userId) {
  const xml = await callSoap(
    "GetProjectIdsForUser",
    `<userId>${userId}</userId>`,
  );
  const ids = [];
  const re = /<[^>]*projectId>([^<]+)<\/[^>]*projectId>/g;
  let m;
  while ((m = re.exec(xml)) !== null) {
    const n = Number(m[1].trim());
    if (Number.isInteger(n)) ids.push(n);
  }
  return ids;
}

async function assignUserToProject(actorId, projectId, userId) {
  const xml = await callSoap(
    "AssignUserToProject",
    `<actorId>${actorId}</actorId><projectId>${projectId}</projectId><userId>${userId}</userId>`,
  );
  const success = extractBool(xml, "success") ?? false;
  const error = extractText(xml, "error");
  return {
    success,
    error: error || null,
    user_id: extractInt(xml, "user_id"),
    project_id: extractInt(xml, "project_id"),
  };
}

module.exports = {
  checkMembership,
  getProjectIdsForUser,
  assignUserToProject,
  SOAP_URL,
};
