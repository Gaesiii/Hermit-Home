# 🦀 Smart Terrarium Monorepo (Hermit Home)

An intelligent, event-driven IoT system for monitoring and controlling a Hermit Crab terrarium. This project uses a microservices architecture (Monorepo) combining Edge computing (ESP32), Cloud messaging (MQTT), Serverless APIs (Vercel), and an autonomous AI Agent.

## 🏗️ System Architecture

The system operates on a Tiered Priority Control model (User > AI > Local Failsafe) and consists of the following core components:

* **Hardware (ESP32):** Reads sensors (DHT22, BH1750, Soil Moisture), executes local hysteresis logic, and controls relays (Mist, Fan, Light, Heater).
* **MQTT Worker (Node.js):** A background daemon that subscribes to HiveMQ, processes real-time telemetry, and persists data to MongoDB.
* **REST API (Vercel Serverless):** The gateway for frontend apps and AI agents to fetch device status and send manual override commands.
* **AI Agent (Python):** A Tier-2 autonomous controller that periodically polls the API, evaluates environmental conditions, and triggers actions.
* **Mobile App (Flutter - Planned):** The Tier-1 user interface for real-time monitoring and manual overrides.

## 📂 Monorepo Structure

```text
smart-terrarium/
├── hardware/esp32/            # PlatformIO C++ project (Edge Device)
├── packages/shared-types/     # Shared TS interfaces (Single Source of Truth)
├── services/
│   ├── api/                   # Serverless REST API (Vercel/Node.js)
│   ├── mqtt-worker/           # Telemetry consumer daemon (Node.js)
│   └── ai-agent/              # Autonomous decision logic (Python)
├── apps/mobile/               # Flutter mobile application
└── infra/                     # Docker and infrastructure configs

Getting Started
1. Install Dependencies (Workspaces)
This project uses NPM Workspaces. Run the install command from the root directory to install all Node.js dependencies across packages and services.

Bash
# At the root directory (smart-terrarium/)
npm install
2. Build Shared Packages
Before running the services, compile the shared TypeScript definitions.

Bash
cd packages/shared-types
npm run build
cd ../..

3. Environment Variables (.env)
You need to configure .env files for each service to maintain the principle of least privilege.

For services/mqtt-worker/.env and services/api/.env:

Đoạn mã
MONGODB_URI="mongodb+srv://<user>:<password>@cluster.mongodb.net/?retryWrites=true&w=majority"
MONGODB_DB_NAME="hermit-home"
MQTT_BROKER="<your-cluster>.hivemq.cloud"
MQTT_PORT=8883
MQTT_USER="<username>"
MQTT_PASS="<password>"
For services/ai-agent/.env:

Đoạn mã
API_BASE_URL="http://localhost:3000"
DEVICE_ID="<your_device_id_from_mongodb>"
🏃‍♂️ Running the System Locally
To test the complete Sense-Think-Act loop locally, you must run the following services concurrently in separate terminal windows:

Terminal 1: Start the REST API

Bash
cd services/api
vercel dev
# Runs on http://localhost:3000
Terminal 2: Start the MQTT Worker

Bash
cd services/mqtt-worker
npm run dev
# Connects to HiveMQ and MongoDB
Terminal 3: Start the AI Agent

Bash
cd services/ai-agent
python -m venv venv
# Activate venv: `.\venv\Scripts\activate` (Windows) or `source venv/bin/activate` (Mac/Linux)
pip install -r requirements.txt
python src/main.py
# Executes the control loop every 60 seconds
📡 API Endpoints (Local)
Get Status: GET http://localhost:3000/api/devices/{deviceId}/status

Send Command: POST http://localhost:3000/api/devices/{deviceId}/override

JSON
{
  "user_override": true,
  "devices": {
    "mist": true,
    "light": false
  }
}


## 🛠️ Step-by-Step Setup Guide

**1. Clone the repository**
```bash
git clone [https://github.com/your-username/smart-terrarium.git](https://github.com/your-username/smart-terrarium.git)
cd smart-terrarium


2. Install all Node.js dependencies (Workspaces)

Bash
npm install
3. Configure Environment Variables
Copy the template to create actual .env files for each service:

Copy .env.example to services/api/.env

Copy .env.example to services/mqtt-worker/.env

Copy .env.example to services/ai-agent/.env
(Fill in your own MongoDB and HiveMQ credentials in these new .env files).

4. Hardware Setup (ESP32)

Open the hardware/esp32 folder in VS Code.

Install the PlatformIO extension.

Rename include/config.example.h to include/config.h and add your WiFi credentials.

Click the Upload button in PlatformIO to flash the ESP32.


---

