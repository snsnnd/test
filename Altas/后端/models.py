from pydantic import BaseModel
from typing import List, Optional

class DeviceOverview(BaseModel):
    id: int
    sourceId: int
    name: str
    healthScore: int
    statusColor: str
    motorRpm: int
    motorTemp: float
    predictedClass: Optional[int] = None
    classLabel: Optional[str] = None
    alertLevel: Optional[str] = None
    alertLabel: Optional[str] = None
    inferenceLatencyMs: Optional[float] = None
    remainingLifeDays: Optional[int] = None
    maintenanceDueText: Optional[str] = None
    diagnosisSummary: Optional[str] = None

class DeviceTelemetry(BaseModel):
    id: int
    sourceId: int
    healthHistory: List[int]
    systemStatus: str
    tempHistory: List[float]
    audioSpectrum: List[float]
    accX: float
    accY: float
    accZ: float
    envHumidity: int
    predictedClass: Optional[int] = None
    classProbabilities: Optional[List[float]] = None
    inferenceLatencyMs: Optional[float] = None
    classLabel: Optional[str] = None
    alertLevel: Optional[str] = None
    alertLabel: Optional[str] = None
    remainingLifeDays: Optional[int] = None
    maintenanceDueText: Optional[str] = None
    diagnosisSummary: Optional[str] = None
    maintenanceAdvice: Optional[str] = None
    currentPreprocessMs: Optional[float] = None
    currentInferenceMs: Optional[float] = None
    currentTotalMs: Optional[float] = None
    currentFps: Optional[float] = None
    averagePreprocessMs: Optional[float] = None
    averageInferenceMs: Optional[float] = None
    averageTotalMs: Optional[float] = None
    averageFps: Optional[float] = None

class ClusterStatus(BaseModel):
    logs: List[str]
    nearlinkLatency: float
    edgeTemp: float
    scanPosition: int
    connectedSources: int
    activeAlerts: int
    currentPreprocessMs: Optional[float] = None
    currentInferenceMs: Optional[float] = None
    currentTotalMs: Optional[float] = None
    currentFps: Optional[float] = None
    averagePreprocessMs: Optional[float] = None
    averageInferenceMs: Optional[float] = None
    averageTotalMs: Optional[float] = None
    averageFps: Optional[float] = None

class SelectDeviceRequest(BaseModel):
    device_id: int

class LogActionRequest(BaseModel):
    message: str

class ExpertSettingsRequest(BaseModel):
    aiSensitivity: int
    aggressiveMode: bool
