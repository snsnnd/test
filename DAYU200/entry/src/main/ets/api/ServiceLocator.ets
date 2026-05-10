import { USE_HTTP_BACKEND } from './BackendConfig';
import { DeviceService } from './DeviceService';
import { HttpDeviceServiceImpl } from './HttpDeviceServiceImpl';
import { MockDeviceServiceImpl } from './MockDeviceServiceImpl';

export const deviceService: DeviceService = USE_HTTP_BACKEND
  ? new HttpDeviceServiceImpl()
  : new MockDeviceServiceImpl();
