🦀 Smart Terrarium — Hermit Home

An Intelligent IoT Ecosystem for Autonomous Hermit Crab Habitat Management












🚀 Overview

Smart Terrarium (Hermit Home) là một hệ thống IoT thông minh, tự động giám sát và điều khiển môi trường sống cho ốc mượn hồn, được xây dựng theo kiến trúc event-driven microservices.

Hệ thống kết hợp:

⚡ Edge Computing (ESP32)
☁️ Cloud Messaging (MQTT - HiveMQ)
🔗 Serverless APIs (Vercel)
🤖 Autonomous AI Agent
📱 Mobile App (Flutter)

👉 Mục tiêu: tạo ra một hệ sinh thái tự động hóa hoàn toàn (Sense → Think → Act)

🧠 Core Concept
🎯 Tiered Priority Control Model
User (Highest Priority)
   ↓
AI Agent (Autonomous Decisions)
   ↓
Local Failsafe (ESP32 - Safety Logic)

✔️ Người dùng override được mọi thứ
✔️ AI tự động tối ưu môi trường
✔️ ESP32 đảm bảo an toàn ngay cả khi mất mạng

🏗️ System Architecture
         ┌──────────────┐
         │  Mobile App  │
         └──────┬───────┘
                │ REST API
                ▼
        ┌───────────────┐
        │   Vercel API  │
        └──────┬────────┘
               │
       ┌───────▼────────┐
       │   MongoDB      │
       └──────┬────────┘
               │
       ┌───────▼────────┐
       │ MQTT Worker    │
       └──────┬────────┘
               │ MQTT
        ┌──────▼──────┐
        │   HiveMQ    │
        └──────┬──────┘
               │
        ┌──────▼──────┐
        │   ESP32     │
        └─────────────┘
⚙️ Components
🔌 Hardware (ESP32)
Sensors: DHT22, BH1750, Soil Moisture
Actuators:
💧 Mist
🌬️ Fan
💡 Light
🔥 Heater
Local logic:
Hysteresis control
Failsafe system
🌐 MQTT Worker (Node.js)
Subscribe telemetry từ HiveMQ
Xử lý real-time data
Persist vào MongoDB
🔗 REST API (Vercel)
Serverless architecture
Gateway cho:
Mobile App
AI Agent
Hỗ trợ:
Authentication
Device control
Override commands
🤖 AI Agent (Python)
Poll API theo chu kỳ
Phân tích môi trường
Tự động điều chỉnh thiết bị
📱 Mobile App (Flutter - Planned)
Realtime monitoring
Manual override
Chat-like AI interaction
📂 Monorepo Structure
smart-terrarium/
├── hardware/esp32/
├── packages/shared-types/
├── services/
│   ├── api/
│   ├── mqtt-worker/
│   └── ai-agent/
├── apps/mobile/
└── infra/
🛠️ Getting Started
1️⃣ Clone Repository
git clone https://github.com/your-username/smart-terrarium.git
cd smart-terrarium
2️⃣ Install Dependencies
npm install
3️⃣ Build Shared Types
cd packages/shared-types
npm run build
cd ../..
4️⃣ Environment Setup
🔹 API & MQTT Worker
MONGODB_URI=
MONGODB_DB_NAME=hermit-home
MQTT_BROKER=
MQTT_PORT=8883
MQTT_USER=
MQTT_PASS=
🔹 AI Agent
API_BASE_URL=http://localhost:3000
DEVICE_ID=your_device_id
🏃 Run Locally
🧩 Start All Services

Terminal 1 — API

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
📡 API Reference
📥 Get Device Status
GET /api/devices/{deviceId}/status
📤 Send Override Command
POST /api/devices/{deviceId}/override
{
  "user_override": true,
  "devices": {
    "mist": true,
    "light": false
  }
}
🔐 Authentication APIs
POST /api/users/forgot-password
POST /api/users/reset-password
🔌 Hardware Setup (ESP32)
Open hardware/esp32 in VS Code
Install PlatformIO
Rename:
config.example.h → config.h
Add WiFi credentials
Click Upload
🧪 Features
✅ Real-time telemetry (MQTT)
✅ AI-based automation
✅ Manual override system
✅ Tiered control architecture
✅ Cloud-native + Edge hybrid
🚧 Mobile app (in progress)
🔮 Roadmap
 Flutter App hoàn chỉnh
 AI learning (adaptive environment)
 Notification system
 Dashboard web
 Multi-device support
📜 License

MIT License © 2026

💡 Author

Hermit Home Project
Built with ❤️ using IoT + AI
