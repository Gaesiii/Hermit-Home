"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.publishCommand = publishCommand;
const mqtt_1 = __importDefault(require("mqtt"));
const dotenv_1 = __importDefault(require("dotenv"));
dotenv_1.default.config();
async function publishCommand(userId, payload) {
    const host = process.env.MQTT_BROKER || '';
    const port = process.env.MQTT_PORT || '8883';
    const username = process.env.MQTT_USER || '';
    const password = process.env.MQTT_PASS || '';
    const client = mqtt_1.default.connect(`mqtts://${host}:${port}`, {
        username,
        password,
        clientId: `api-publisher-${Math.random().toString(16).substring(2, 8)}`,
        rejectUnauthorized: false
    });
    return new Promise((resolve, reject) => {
        client.on('connect', () => {
            const topic = `terrarium/commands/${userId}`;
            const message = JSON.stringify(payload);
            client.publish(topic, message, { qos: 1 }, (err) => {
                client.end();
                if (err)
                    reject(err);
                else
                    resolve();
            });
        });
        client.on('error', (err) => {
            client.end();
            reject(err);
        });
        // Timeout if connection takes too long
        setTimeout(() => {
            client.end();
            reject(new Error('MQTT publish timeout'));
        }, 5000);
    });
}
