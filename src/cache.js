const { createClient } = require("redis");

const TTL = Number(process.env.CACHE_TTL_SECONDS) || 60;

const client = createClient({
  url: `redis://${process.env.REDIS_HOST || "redis"}:${process.env.REDIS_PORT || 6379}`,
  disableOfflineQueue: true, // si redis cae, falla rapido en vez de colgar el request
});
client.on("error", () => {}); // evita que un error de redis rompa la app
client.connect().catch(() => {});

const keyForUser = (userId) => `tasks:user:${userId}`;

async function getTasks(userId) {
  try {
    const value = await client.get(keyForUser(userId));
    return value ? JSON.parse(value) : null;
  } catch {
    return null; // redis caido: se trata como MISS
  }
}

async function setTasks(userId, tasks) {
  try {
    await client.set(keyForUser(userId), JSON.stringify(tasks), { EX: TTL });
  } catch {}
}

async function invalidateUsers(userIds) {
  try {
    if (userIds.length > 0) await client.del(userIds.map(keyForUser));
  } catch {}
}

module.exports = { getTasks, setTasks, invalidateUsers };