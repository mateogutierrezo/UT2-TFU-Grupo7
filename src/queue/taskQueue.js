const taskQueue = require('../../queues/taskQueue'); 

const TaskModel = require('../modules/tasks/tasks.schema'); 


taskQueue.process(2, async (job) => {
    const taskData = job.data;
    
    try {
        console.log(`[Worker] Procesando tarea de la cola ID: ${job.id} hacia la base de datos...`);
        
        const newTask = await TaskModel.create(taskData);
        
        console.log(`[Worker] Tarea ${job.id} guardada exitosamente en la base de datos.`);
        return newTask;
    } catch (error) {
        console.error(`[Worker] Error al guardar la tarea ${job.id} en la base de datos:`, error.message);
        throw error; 
    }
});