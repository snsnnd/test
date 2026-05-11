import { DeviceService } from './DeviceService';
import { DeviceOverview, DeviceTelemetry, ClusterStatus } from './models/DeviceModels';

class InternalDevice {
  id: number = 0;
  name: string = '';
  healthScore: number = 98;
  healthHistory: number[] = new Array(30).fill(98);
  statusColor: string = '#34C759';
  systemStatus: string = '生产平稳执行中';
  audioSpectrum: number[] = new Array(15).fill(20);
  accX: number = 0.05;
  accY: number = -0.02;
  accZ: number = 9.81;
  tempHistory: number[] = new Array(60).fill(55.0);
  motorTemp: number = 55.0;
  motorRpm: number = 1450;
  envHumidity: number = 45;
}

export class MockDeviceServiceImpl implements DeviceService {
  private devices: InternalDevice[] = [];
  private logs: string[] = ['[Mock] 本地演示数据源已启动，当前未连接真实后端'];
  private nearlinkLatency: number = 0.9;
  private scanPosition: number = 0;
  private aiSensitivity: number = 80;
  private activeDeviceId: number = 0;

  constructor() {
    this.devices.push(this.createDevice(0, '一号冲压主轴 (Node A)', 64.2, 1850));
    this.devices.push(this.createDevice(1, '二号履带马达 (Node B)', 52.8, 1200));
    this.devices.push(this.createDevice(2, '三号封箱阵列 (Node C)', 58.1, 3400));

    setInterval(() => { this.simulateBackendTick(); }, 600);
    setInterval(() => { this.scanPosition = (this.scanPosition + 5) % 100; }, 100);
  }

  private createDevice(id: number, name: string, motorTemp: number, motorRpm: number): InternalDevice {
    let dev = new InternalDevice();
    dev.id = id;
    dev.name = name;
    dev.motorTemp = motorTemp;
    dev.motorRpm = motorRpm;
    return dev;
  }

  public async scanNearbyDevices(): Promise<DeviceOverview[]> {
    this.submitLogAction('正在刷新本地演示设备列表');
    await new Promise<void>((resolve) => setTimeout(resolve, 800));
    this.submitLogAction(`演示扫描完成：发现 ${this.devices.length} 个节点`);
    return this.fetchFleetOverview();
  }

  public async fetchFleetOverview(): Promise<DeviceOverview[]> {
    let arr: DeviceOverview[] = [];
    for (let i = 0; i < this.devices.length; i++) {
      let d = this.devices[i];
      let predictedClass = d.healthScore >= 80 ? 0 : (d.healthScore >= 60 ? 1 : 2);
      let alertLevel = d.healthScore >= 80 ? 'normal' : (d.healthScore >= 60 ? 'warning' : 'critical');
      let alertLabel = alertLevel === 'normal' ? '绿区监测' : (alertLevel === 'warning' ? '橙色预警' : '红色告警');
      let classLabel = predictedClass === 0 ? '正常工况' : (predictedClass === 1 ? '早期异常' : '高风险异常');
      let remainingLifeDays = predictedClass === 0 ? 112 : (predictedClass === 1 ? 36 : 8);

      let item: DeviceOverview = {
        id: d.id,
        sourceId: d.id,
        name: d.name,
        healthScore: d.healthScore,
        statusColor: d.statusColor,
        motorRpm: Math.floor(d.motorRpm),
        motorTemp: d.motorTemp,
        predictedClass: predictedClass,
        classLabel: classLabel,
        alertLevel: alertLevel,
        alertLabel: alertLabel,
        inferenceLatencyMs: this.nearlinkLatency,
        remainingLifeDays: remainingLifeDays,
        maintenanceDueText: predictedClass === 0 ? '10月8日' : (predictedClass === 1 ? '3天内' : '24小时内'),
        diagnosisSummary: predictedClass === 0 ? '正常工况：设备当前处于绿区，可继续运行。' : (predictedClass === 1 ? '早期异常：建议尽快安排点检与复测。' : '高风险异常：建议立即降载并安排检修。')
      };
      arr.push(item);
    }
    return arr;
  }

  public async selectDevice(id: number): Promise<boolean> {
    if (id >= 0 && id < this.devices.length) {
      let oldName = this.devices[this.activeDeviceId].name;
      this.activeDeviceId = id;
      let newName = this.devices[this.activeDeviceId].name;
      this.submitLogAction(`监测目标切换：[${oldName}] → [${newName}]`);
      return true;
    }
    return false;
  }

  public async fetchDeviceTelemetry(id: number): Promise<DeviceTelemetry> {
    let d = this.devices.find((x: InternalDevice) => x.id === id) || this.devices[0];
    let predictedClass = d.healthScore >= 80 ? 0 : (d.healthScore >= 60 ? 1 : 2);
    let alertLevel = d.healthScore >= 80 ? 'normal' : (d.healthScore >= 60 ? 'warning' : 'critical');
    let alertLabel = alertLevel === 'normal' ? '绿区监测' : (alertLevel === 'warning' ? '橙色预警' : '红色告警');
    let classLabel = predictedClass === 0 ? '正常工况' : (predictedClass === 1 ? '早期异常' : '高风险异常');
    let probabilities: number[] = predictedClass === 0 ? [0.92, 0.06, 0.02] : (predictedClass === 1 ? [0.18, 0.68, 0.14] : [0.05, 0.15, 0.80]);

    let telemetry: DeviceTelemetry = {
      id: d.id,
      sourceId: d.id,
      healthHistory: [...d.healthHistory],
      systemStatus: d.systemStatus,
      tempHistory: [...d.tempHistory],
      audioSpectrum: [...d.audioSpectrum],
      accX: d.accX,
      accY: d.accY,
      accZ: d.accZ,
      envHumidity: d.envHumidity,
      predictedClass: predictedClass,
      classProbabilities: probabilities,
      inferenceLatencyMs: this.nearlinkLatency,
      classLabel: classLabel,
      alertLevel: alertLevel,
      alertLabel: alertLabel,
      remainingLifeDays: predictedClass === 0 ? 112 : (predictedClass === 1 ? 36 : 8),
      maintenanceDueText: predictedClass === 0 ? '10月8日' : (predictedClass === 1 ? '3天内' : '24小时内'),
      diagnosisSummary: predictedClass === 0 ? '正常工况：设备当前处于绿区，可继续运行。' : (predictedClass === 1 ? '早期异常：建议尽快安排点检与复测。' : '高风险异常：建议立即降载并安排检修。'),
      maintenanceAdvice: predictedClass === 0 ? '建议保持常规巡检节奏。' : (predictedClass === 1 ? '建议 3 天内安排维保窗口。' : '建议 24 小时内完成停机检查。'),
      currentPreprocessMs: 1.8,
      currentInferenceMs: this.nearlinkLatency,
      currentTotalMs: this.nearlinkLatency + 1.8,
      currentFps: 24.0,
      averagePreprocessMs: 1.9,
      averageInferenceMs: 4.6,
      averageTotalMs: 6.5,
      averageFps: 22.0
    };
    return telemetry;
  }

  public async fetchClusterStatus(): Promise<ClusterStatus> {
    let status: ClusterStatus = {
      logs: [...this.logs],
      nearlinkLatency: this.nearlinkLatency,
      scanPosition: this.scanPosition,
      connectedSources: this.devices.length,
      activeAlerts: this.devices.filter((d: InternalDevice) => d.healthScore < 80).length,
      currentPreprocessMs: 1.8,
      currentInferenceMs: this.nearlinkLatency,
      currentTotalMs: this.nearlinkLatency + 1.8,
      currentFps: 24.0,
      averagePreprocessMs: 1.9,
      averageInferenceMs: 4.6,
      averageTotalMs: 6.5,
      averageFps: 22.0
    };
    return status;
  }

  public async submitLogAction(message: string): Promise<boolean> {
    this.logs.unshift(`[前端事件] ${message}`);
    if (this.logs.length > 50) {
      this.logs.pop();
    }
    return true;
  }

  public async updateExpertSettings(aiSensitivity: number, aggressiveMode: boolean): Promise<boolean> {
    this.aiSensitivity = aiSensitivity;
    this.submitLogAction(aggressiveMode ? '高敏观察模式已启用' : '标准观察模式已恢复');
    return true;
  }

  private simulateBackendTick() {
    this.nearlinkLatency = 3.5 + Math.random() * 4.0;

    let dev = this.devices[this.activeDeviceId];
    if (!dev) {
      return;
    }

    let event = Math.random();
    if (event > 0.98) {
      dev.healthScore -= Math.floor(Math.random() * 6 + 3);
      this.submitLogAction(`演示告警：[${dev.name}] 振动与声纹特征出现异常波动`);
    } else if (event > 0.9) {
      dev.healthScore -= 1;
    } else if (dev.healthScore < 98) {
      dev.healthScore += 1;
    }

    if (dev.healthScore > 100) {
      dev.healthScore = 100;
    }
    if (dev.healthScore < 0) {
      dev.healthScore = 0;
    }

    dev.healthHistory.push(dev.healthScore);
    dev.healthHistory.shift();

    dev.statusColor = '#34C759';
    dev.systemStatus = '通信链路平稳维系';
    if (dev.healthScore < 60) {
      dev.statusColor = '#FF3B30';
      dev.systemStatus = '模型判定高风险异常，建议停机检查';
      dev.motorRpm = dev.motorRpm * 0.6 + Math.random() * 50;
    } else if (dev.healthScore < 80) {
      dev.statusColor = '#FF9500';
      dev.systemStatus = '模型发现潜在异常，建议安排点检';
    }

    dev.motorTemp += (Math.random() - 0.5) * 0.4;
    dev.tempHistory.push(Number(dev.motorTemp.toFixed(2)));
    dev.tempHistory.shift();
    dev.motorRpm += (Math.random() - 0.5) * 15;

    for (let j = 0; j < 15; j++) {
      let val = Math.random() * 80;
      if (dev.healthScore < 70 && Math.random() > (1 - this.aiSensitivity / 200)) {
        val = 80 + Math.random() * 20;
      }
      dev.audioSpectrum[j] = val;
    }

    let noiseLevel = dev.healthScore < 70 ? 2.5 : 0.2;
    dev.accX = (Math.random() - 0.5) * noiseLevel * 2;
    dev.accY = (Math.random() - 0.5) * noiseLevel;
    dev.accZ = 9.81 + (Math.random() - 0.5) * noiseLevel;
  }
}

export const deviceService = new MockDeviceServiceImpl();
