const IDENTITY_URL =
  process.env.IDENTITY_SERVICE_URL || "http://identity-service:3000";

async function userExists(userId) {
  const controller = new AbortController();
  const timeoutMs = Number(process.env.IDENTITY_TIMEOUT_MS) || 2000;
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(
      `${IDENTITY_URL}/api/internal/users/${userId}/exists`,
      {
        signal: controller.signal,
      },
    );
    if (!res.ok) return false;
    const data = await res.json();
    return !!data.exists;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

module.exports = { userExists, IDENTITY_URL };
