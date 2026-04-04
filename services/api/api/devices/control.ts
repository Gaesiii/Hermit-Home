import { VercelRequest, VercelResponse } from '@vercel/node';
import { connectToDatabase } from '../../lib/mongodb'; // Sử dụng lại kết nối có sẵn
import { DeviceControl } from '../../models/DeviceControl'; // Model anh tạo ở dưới

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // Chỉ chấp nhận phương thức POST (giống register.ts)
  if (req.method !== 'POST') {
    return res.status(405).json({ message: 'Method not allowed' });
  }

  try {
    await connectToDatabase();

    const { userId, device, status } = req.body;

    // Ghi vào Database: Nếu đã có thì cập nhật, chưa có thì tạo mới
    const result = await DeviceControl.findOneAndUpdate(
      { userId, device }, 
      { 
        status, 
        lastUpdate: new Date(),
        mode: 'MANUAL' 
      },
      { upsert: true, new: true }
    );

    return res.status(200).json({
      success: true,
      message: `Đã ghi nhận trạng thái ${status} cho ${device}`,
      data: result
    });
  } catch (error) {
    return res.status(500).json({ success: false, error: (error as Error).message });
  }
}