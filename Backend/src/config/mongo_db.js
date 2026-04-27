const { MongoClient } = require('mongodb');

const mongoClient = new MongoClient(process.env.MONGO_URI);

let mongoDb = null;

async function getMongoDb() {
  if (!mongoDb) {
    await mongoClient.connect();
    mongoDb = mongoClient.db(process.env.MONGO_DB_NAME || 'animap');
    console.log('MongoDB conectado');
  }

  return mongoDb;
}

module.exports = {
  getMongoDb,
};