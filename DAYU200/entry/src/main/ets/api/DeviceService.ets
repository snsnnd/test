import { DeviceOverview, DeviceTelemetry, ClusterStatus } from './models/DeviceModels';

/**
 * 前端的通信依赖统一走这个标准的异步接口。
 * 您后续只需用 Axios 或者 Http.request 实现这个 Interface 即可真实接入服务器！
 */
export interface DeviceService {
   // 拉取（扫描）附近设备列表
   scanNearbyDevices(): Promise<DeviceOverview[]>;
   // 获取当前已知设备的基础快照
   fetchFleetOverview(): Promise<DeviceOverview[]>;
   // 选择一台目标监测设备
   selectDevice(id: number): Promise<boolean>;
   // 通过 ID 抓取选中设备的详细探针遥测点
   fetchDeviceTelemetry(id: number): Promise<DeviceTelemetry>;
   // 获取工业网关总线与全局审计日志
   fetchClusterStatus(): Promise<ClusterStatus>;

   // 执行写入/控制动作
   submitLogAction(message: string): Promise<boolean>;
   updateExpertSettings(aiSensitivity: number, aggressiveMode: boolean): Promise<boolean>;
}
