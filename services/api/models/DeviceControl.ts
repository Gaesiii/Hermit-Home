import mongoose from 'mongoose';

const DeviceControlSchema = new mongoose.Schema({
  userId: { type: String, required: true },
  device: { type: String, required: true }, // 'light', 'fan',...
  status: { type: String, required: true }, // 'ON', 'OFF'
  mode: { type: String, default: 'MANUAL' },
  lastUpdate: { type: Date, default: Date.now }
});

export const DeviceControl = mongoose.models.DeviceControl || mongoose.model('DeviceControl', DeviceControlSchema);