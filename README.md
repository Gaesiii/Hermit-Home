🦀 Smart Terrarium Monorepo (Hermit Home)<p align="center"><img src="https://img.shields.io/badge/Status-Active-brightgreen?style=for-the-badge&logo=github" /><img src="https://img.shields.io/badge/Architecture-Monorepo-orange?style=for-the-badge&logo=architecture" /><img src="https://img.shields.io/badge/Stack-ESP32%20|%20Node.js%20|%20Python%20|%20Flutter-blue?style=for-the-badge" /><img src="https://img.shields.io/badge/Infrastructure-Docker%20|%20Vercel-black?style=flat-square&logo=docker" /><img src="https://img.shields.io/badge/Database-MongoDB-green?style=flat-square&logo=mongodb" /><img src="https://img.shields.io/badge/Cloud-HiveMQ-yellow?style=flat-square&logo=mqtt" /></p>✨ OverviewAn intelligent, event-driven IoT system designed for monitoring and controlling a Hermit Crab terrarium. This project implements a Tiered Priority Control model, ensuring your pet is always in the perfect environment.[!TIP]Control Priority: User (Override) > AI Agent (Optimization) > Local ESP32 (Safety Failsafe)🏗️ System ArchitectureĐoạn mãgraph TD
    A[ESP32 Edge] <-->|MQTT| B(HiveMQ Cloud)
    B <--> C[Node.js Worker]
    C <--> D[(MongoDB Atlas)]
    E[Vercel API] <--> D
    F[AI Agent Python] <-->|REST| E
    G[Flutter App] <-->|REST| E
    style A fill:#f9f,stroke:#333,stroke-width:2px
    style F fill:#00ff00,stroke:#333,stroke-width:2px
📡 Hardware (ESP32): The "Muscle". Handles sensors (DHT22, BH1750) and local hysteresis logic.⚙️ MQTT Worker (Node.js): The "Nervous System". Processes telemetry and persists data.🌐 REST API (Vercel): The "Gatekeeper". Serverless gateway for status and commands.🧠 AI Agent (Python): The "Brain". Periodically evaluates conditions and triggers autonomous actions.📱 Mobile App (Flutter): The "Command Center". Real-time monitoring (In development).📂 Project StructureDirectoryStackResponsibilityhardware/esp32C++ / PIOEdge computing & Sensor pollingpackages/sharedTypeScriptSingle Source of Truth (Interfaces)services/apiNode.jsServerless backendservices/workerNode.jsReal-time MQTT processingservices/aiPythonAutonomous decision logicapps/mobileFlutterCross-platform UI🚀 Quick Start1️⃣ Clone & InstallBashgit clone https://github.com/your-username/smart-terrarium.git
cd smart-terrarium
npm install  # Powered by NPM Workspaces
2️⃣ Build Shared CoreBashcd packages/shared-types && npm run build && cd ../..
3️⃣ Environment SetupCopy .env.example to .env in each service directory.Bashcp .env.example services/api/.env
cp .env.example services/mqtt-worker/.env
🏃‍♂️ Running LocallyTo engage the Sense-Think-Act loop, fire up these terminals:StepActionCommand01Backendcd services/api && vercel dev02Telemetrycd services/mqtt-worker && npm run dev03Braincd services/ai-agent && python src/main.py📡 API ReferenceDevice ControlPOST /api/devices/{deviceId}/overrideJSON{
  "user_override": true,
  "devices": {
    "mist": true,
    "light": false
  }
}
🛠️ Hardware FlashingOpen hardware/esp32 in VS Code.Ensure PlatformIO extension is installed.Config WiFi in include/config.h.Press CTRL+ALT+U to flash ⚡.<p align="center">Made with ❤️ for 🦀 by [Your Name]<b>"Automating the crustacean life, one byte at a time."</b></p>
