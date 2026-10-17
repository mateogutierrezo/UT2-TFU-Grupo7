const Queue = require("bull");

const redisUrl = `redis://${process.env.REDIS_HOST || "localhost"}:${process.env.REDIS_PORT || 6379}`;

const taskQueue = new Queue("tasks", redisUrl);

module.exports = taskQueue;
