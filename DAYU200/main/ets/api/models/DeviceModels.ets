/**
 * 前后端统一数据模型。
 * UI 只依赖这些结构，真实数据由 HTTP 后端或 Mock 服务注入。
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
   currentPreprocessMs?: number;
   currentInferenceMs?: number;
   currentTotalMs?: number;
   currentFps?: number;
   averagePreprocessMs?: number;
   averageInferenceMs?: number;
   averageTotalMs?: number;
   averageFps?: number;
}

export interface ClusterStatus {
   logs: string[];
   nearlinkLatency: number;
   scanPosition: number;
   connectedSources?: number;
   activeAlerts?: number;
   currentPreprocessMs?: number;
   currentInferenceMs?: number;
   currentTotalMs?: number;
   currentFps?: number;
   averagePreprocessMs?: number;
   averageInferenceMs?: number;
   averageTotalMs?: number;
   averageFps?: number;
}
