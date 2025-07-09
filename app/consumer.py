from kafka import KafkaConsumer
import json
import os
from pymongo import MongoClient
from pymongo.errors import PyMongoError

# Kafka Configs
KAFKA_BROKER = os.getenv('KAFKA_BROKER', 'kafka:9092')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'data_topic')

# MongoDB Configs
MONGO_URI = os.getenv('MONGO_URI', 'mongodb://localhost:27017/')
MONGO_DB = os.getenv('MONGO_DB', 'kafka_data')
MONGO_COLLECTION = os.getenv('MONGO_COLLECTION', 'items')

# MongoDB Connection
client = MongoClient(MONGO_URI)
db = client[MONGO_DB]
collection = db[MONGO_COLLECTION]

def consume_messages():
    # Kafka Consumer
    consumer = KafkaConsumer(
        KAFKA_TOPIC,
        bootstrap_servers=[KAFKA_BROKER],
        auto_offset_reset='earliest',
        enable_auto_commit=True,
        group_id='my-group',
        value_deserializer=lambda x: json.loads(x.decode('utf-8'))
    )
    
    print("Consumer started. Waiting for messages...")
    
    for message in consumer:
        try:
            data = message.value
            print(f"Received message: {data}")
            
            # Data Store in MongoDB
            result = collection.insert_one(data)
            print(f"Data saved to MongoDB with id: {result.inserted_id}")
            
        except PyMongoError as e:
            print(f"Error saving to MongoDB: {e}")
        except Exception as e:
            print(f"Error processing message: {e}")

if __name__ == "__main__":
    consume_messages()