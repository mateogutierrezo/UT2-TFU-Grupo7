const Queue = require('bull');

// Usa la URL de Redis 
const taskQueue = new Queue('task-processing', process.env.REDIS_URL || 'redis://127.0.0.1:6379');

module.exports = taskQueue;