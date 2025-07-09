from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from kafka import KafkaProducer
import json
import os

app = FastAPI()

# API Payload Sample
class DataItem(BaseModel):
    name: str
    value: float
    description: str = None

# Kafka Configs
KAFKA_BROKER = os.getenv('KAFKA_BROKER', 'kafka:9092')
KAFKA_TOPIC = os.getenv('KAFKA_TOPIC', 'data_topic')

producer = None

@app.on_event("startup")
def startup_event():
    global producer
    try:
        producer = KafkaProducer(
            bootstrap_servers=[KAFKA_BROKER],
            value_serializer=lambda x: json.dumps(x).encode('utf-8')
        )
        print(f"[Kafka] Connected to broker at {KAFKA_BROKER}")
    except Exception as e:
        print(f"[Kafka] Failed to connect: {e}")
        raise

@app.post("/data/")
async def create_data(item: DataItem):
    try:
        data = item.dict()
        producer.send(KAFKA_TOPIC, value=data)
        producer.flush()
        return {"message": "Data sent to Kafka successfully", "data": data}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/")
async def read_root():
    return {"message": "FastAPI Kafka Producer is running"}

@app.get("/commands/")
async def read_root():
    return {"message": "lsist of commands"}