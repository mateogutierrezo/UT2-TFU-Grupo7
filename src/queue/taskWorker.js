const taskQueue = require('./taskQueue');

// Procesa con concurrencia controlada 
taskQueue.process(2, async (job) => {
    console.log(`Procesando tarea ID: ${job.id}`);
    
    await new Promise((resolve) => setTimeout(resolve, 3000));
    
    console.log(`Tarea ${job.id} finalizada con éxito.`);
});