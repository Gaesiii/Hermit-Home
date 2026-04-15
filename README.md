<div align="center">

<img width="100%" src="https://capsule-render.vercel.app/api?type=waving&height=220&text=Smart%20Terrarium%20%7C%20Hermit%20Home&fontSize=38&fontAlignY=40&desc=Autonomous%20IoT%20Habitat%20for%20Hermit%20Crabs&descAlignY=60" />

<img src="https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=22&pause=1000&center=true&vCenter=true&width=900&lines=Event-driven+IoT+system+for+Hermit+Crab+care;ESP32+%2B+MQTT+%2B+Vercel+API+%2B+AI+Agent;Tiered+Priority+Control%3A+User+%3E+AI+%3E+Local+Failsafe" />

<br/>

<img src="https://img.shields.io/badge/ESP32-Edge%20Device-blue?style=for-the-badge" />
<img src="https://img.shields.io/badge/MQTT-HiveMQ-green?style=for-the-badge" />
<img src="https://img.shields.io/badge/API-Vercel-black?style=for-the-badge" />
<img src="https://img.shields.io/badge/AI-Python-red?style=for-the-badge" />
<img src="https://img.shields.io/badge/Mobile-Flutter-02569B?style=for-the-badge" />
<img src="https://img.shields.io/badge/Architecture-Monorepo-orange?style=for-the-badge" />

</div>

---

## 🦀 About The Project

**Smart Terrarium — Hermit Home** is an intelligent, event-driven IoT ecosystem designed to monitor and autonomously control a hermit crab habitat.

It combines:

- **ESP32 edge hardware** for real-time sensing and actuation
- **MQTT messaging** for telemetry flow
- **Serverless REST APIs** for device interaction
- **An autonomous AI Agent** for decision-making
- **A Flutter mobile app** for user control and monitoring

---

## 🎯 Tiered Priority Control

<!-- <div align="center"> -->

```text
User Override
   ↓
AI Agent
   ↓
Local Failsafe (ESP32)
```
<!-- </div> -->

This system follows a tiered control architecture:

Tier 1 — User: highest priority manual override
Tier 2 — AI Agent: autonomous optimization logic
Tier 3 — Local Failsafe: on-device safety control when cloud is unavailable
🏗️ System Architecture

<div align="center">

         ┌────────────────────┐
         │   Flutter Mobile   │
         │       App          │
         └─────────┬──────────┘
                   │ REST API
                   ▼
        ┌───────────────────────┐
        │  Vercel Serverless API│
        └─────────┬─────────────┘
                  │
                  ▼
           ┌──────────────┐
           │   MongoDB    │
           └──────┬───────┘
                  │
                  ▼
        ┌───────────────────────┐
        │   MQTT Worker (Node)  │
        └─────────┬─────────────┘
                  │ MQTT
                  ▼
             ┌───────────┐
             │  HiveMQ   │
             └────┬──────┘
                  │
                  ▼
           ┌──────────────┐
           │    ESP32     │
           └──────────────┘

</div>

✨ Key Features
🌡️ Real-time environmental monitoring
💧 Automated mist, fan, light, and heater control
🤖 AI-assisted habitat optimization
📡 MQTT-based telemetry pipeline
☁️ Cloud-connected control with local fallback logic
📱 Mobile app integration for live monitoring and overrides

🧩 Tech Stack
<div align="center">
Layer	Technology
Hardware	ESP32, DHT22, BH1750, Soil Moisture
Messaging	MQTT, HiveMQ
Backend	Node.js, TypeScript, Vercel
Database	MongoDB Atlas
AI	Python
Mobile	Flutter
</div>

📂 Monorepo Structure
smart-terrarium/
├── hardware/esp32/            # PlatformIO project for ESP32 firmware
├── packages/shared-types/     # Shared TypeScript interfaces
├── services/
│   ├── api/                   # Vercel serverless REST API
│   ├── mqtt-worker/           # MQTT consumer daemon
│   └── ai-agent/              # Autonomous AI controller
├── apps/mobile/               # Flutter mobile application
└── infra/                     # Docker / infra config

🚀 Getting Started
1. Clone the repository
git clone https://github.com/your-username/smart-terrarium.git
cd smart-terrarium
2. Install dependencies
npm install
3. Build shared packages
cd packages/shared-types
npm run build
cd ../..
🔐 Environment Variables
services/api/.env and services/mqtt-worker/.env
MONGODB_URI="mongodb+srv://<user>:<password>@cluster.mongodb.net/?retryWrites=true&w=majority"
MONGODB_DB_NAME="hermit-home"
MQTT_BROKER="<your-cluster>.hivemq.cloud"
MQTT_PORT=8883
MQTT_USER="<username>"
MQTT_PASS="<password>"
services/ai-agent/.env
API_BASE_URL="http://localhost:3000"
DEVICE_ID="<your_device_id_from_mongodb>"
🏃 Running Locally
Terminal 1 — REST API
cd services/api
vercel dev
Terminal 2 — MQTT Worker
cd services/mqtt-worker
npm run dev
Terminal 3 — AI Agent
cd services/ai-agent
python -m venv venv
.\venv\Scripts\activate
pip install -r requirements.txt
python src/main.py
📡 API Endpoints
Get device status
GET /api/devices/{deviceId}/status
Send override command
POST /api/devices/{deviceId}/override
{
  "user_override": true,
  "devices": {
    "mist": true,
    "light": false
  }
}
Auth endpoints
POST /api/users/forgot-password
POST /api/users/reset-password
🔌 Hardware Responsibilities
Read sensors:
DHT22
BH1750
Soil Moisture
Execute local hysteresis / failsafe logic
Control relays for:
Mist
Fan
Light
Heater
🤖 AI Agent Responsibilities
Poll current terrarium state from API
Evaluate environmental conditions
Trigger device actions when needed
Act as Tier-2 autonomous controller
📱 Mobile App

Planned mobile app features:

Real-time telemetry monitoring
Manual override controls
Device history
AI chat-style interaction
User authentication
🛣️ Roadmap
 ESP32 telemetry publishing
 MQTT worker persistence
 REST API control endpoints
 AI-based decision loop
 Flutter mobile UI completion
 Push notifications
 Device onboarding flow
 Multi-device support
 Analytics dashboard
📖 Expand for More Details
<details> <summary><b>Sense → Think → Act Flow</b></summary>
Sense

ESP32 reads data from habitat sensors and publishes telemetry via MQTT.

Think

MQTT Worker stores telemetry in MongoDB, while the AI Agent polls device state from the API and evaluates whether environmental adjustment is needed.

Act

Commands are issued either by the user or the AI agent, then propagated back to the ESP32 for relay control.

</details> <details> <summary><b>Priority Rules</b></summary>
User manual override always wins
AI only acts when manual override is not active
ESP32 local failsafe protects habitat when network/cloud is unavailable
</details>
👨‍💻 Author

Built with passion for IoT, automation, and intelligent habitat systems.

<div align="center"> <img width="100%" src="https://capsule-render.vercel.app/api?type=waving&section=footer&height=120" /> </div> ```
