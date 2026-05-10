import http from '@ohos.net.http';

import { DeviceService } from './DeviceService';
import { DeviceOverview, DeviceTelemetry, ClusterStatus } from './models/DeviceModels';
import { BACKEND_BASE_URL } from './BackendConfig';

type HttpMethod = 'GET' | 'POST';

// --- 新增：为兼容 ArkTS 的强类型规则，显式定义接口和类 ---
interface SuccessResponse {
  success: boolean;
}

class SelectDeviceReq {
  device_id: number;
  constructor(id: number) { this.device_id = id; }
}

class LogActionReq {
  message: string;
  constructor(message: string) { this.message = message; }
}

class ExpertReq {
  aiSensitivity: number;
  aggressiveMode: boolean;
  constructor(aiSensitivity: number, aggressiveMode: boolean) {
    this.aiSensitivity = aiSensitivity;
    this.aggressiveMode = aggressiveMode;
  }
}
// ----------------------------------------------------

export class HttpDeviceServiceImpl implements DeviceService {
  // 注意：将 'body?: object' 修改为 'body?: Object'（大写O），在 ArkTS 中更安全
  private async request<T>(path: string, method: HttpMethod, body?: Object): Promise<T> {
    const httpRequest = http.createHttp();
    const url = `${BACKEND_BASE_URL}${path}`;

    try {
      const response = await new Promise<http.HttpResponse>((resolve, reject) => {
        httpRequest.request(
          url,
          {
            method: method === 'GET' ? http.RequestMethod.GET : http.RequestMethod.POST,
            header: {
              'Content-Type': 'application/json'
            },
            expectDataType: http.HttpDataType.STRING,
            readTimeout: 10000,
            connectTimeout: 10000,
            extraData: body ? JSON.stringify(body) : undefined,
          },
          (err, data) => {
            if (err) {
              reject(err);
              return;
            }
            resolve(data);
          }
        );
      });

      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`HTTP ${response.responseCode}: ${response.result}`);
      }

      const raw = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      return JSON.parse(raw) as T;
    } finally {
      httpRequest.destroy();
    }
  }

  async scanNearbyDevices(): Promise<DeviceOverview[]> {
    return this.fetchFleetOverview();
  }

  async fetchFleetOverview(): Promise<DeviceOverview[]> {
    return this.request<DeviceOverview[]>('/api/fleet', 'GET');
  }

  // 修复：使用 <SuccessResponse> 替代 <{ success: boolean }>，并传入实例化的类对象
  async selectDevice(id: number): Promise<boolean> {
    const result = await this.request<SuccessResponse>('/api/device/select', 'POST', new SelectDeviceReq(id));
    return !!result.success;
  }

  async fetchDeviceTelemetry(id: number): Promise<DeviceTelemetry> {
    return this.request<DeviceTelemetry>(`/api/telemetry/${id}`, 'GET');
  }

  async fetchClusterStatus(): Promise<ClusterStatus> {
    return this.request<ClusterStatus>('/api/cluster', 'GET');
  }

  // 修复：显式响应类型 + 实例化请求类
  async submitLogAction(message: string): Promise<boolean> {
    const result = await this.request<SuccessResponse>('/api/action/log', 'POST', new LogActionReq(message));
    return !!result.success;
  }

  // 修复：显式响应类型 + 实例化请求类
  async updateExpertSettings(aiSensitivity: number, aggressiveMode: boolean): Promise<boolean> {
    const reqBody = new ExpertReq(aiSensitivity, aggressiveMode);
    const result = await this.request<SuccessResponse>('/api/action/expert', 'POST', reqBody);
    return !!result.success;
  }
}