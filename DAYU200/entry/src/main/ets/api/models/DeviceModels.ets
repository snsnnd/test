/**
 * 这是您将会传给后端工程师的标注核心接口模型文件
 * 所有的 UI 控制都与此解耦绑定
 */

export interface DeviceOverview {
   id: number;
   sourceId?: number;
   name: string;
   healthScore: number;
   statusColor: string;
   motorRpm: number;
   motorTemp: number;
   predictedClass?: number;
   classLabel?: string;
   alertLevel?: string;
   alertLabel?: string;
   inferenceLatencyMs?: number;
   remainingLifeDays?: number;
   maintenanceDueText?: string;
   diagnosisSummary?: string;
}

export interface DeviceTelemetry {
   id: number;
   sourceId?: number;
   healthHistory: number[];
   systemStatus: string;
   tempHistory: number[];
   audioSpectrum: number[];
   accX: number;
   accY: number;
   accZ: number;
   envHumidity: number;
   predictedClass?: number;
   classProbabilities?: number[];
   inferenceLatencyMs?: number;
    classLabel?: string;
    alertLevel?: string;
    alertLabel?: string;
    remainingLifeDays?: number;
    maintenanceDueText?: string;
    diagnosisSummary?: string;
    maintenanceAdvice?: string;
}

export interface ClusterStatus {
   logs: string[];
   nearlinkLatency: number;
   edgeTemp: number;
   scanPosition: number;
   connectedSources?: number;
   activeAlerts?: number;
}
