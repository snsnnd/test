from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from typing import List
from models import DeviceOverview, DeviceTelemetry, ClusterStatus, SelectDeviceRequest, LogActionRequest, ExpertSettingsRequest
from atlas_runtime import atlas_runtime

app = FastAPI(title="Ascend IIoT Central Hub", version="2.2", description="企业级边缘通信管理后端核心总线接口 API（Atlas 本地推理结果驱动，支持多设备扩展）")

# 调试阶段允许跨域，便于 DAYU200、浏览器面板或局域网设备联调。
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup_event():
    atlas_runtime.start()

@app.get("/api/fleet", response_model=List[DeviceOverview], summary="可选设备列表")
async def get_fleet_overview():
    """获取全部可连接设备的基础信息，当前由 Atlas 本地推理结果流驱动。"""
    return [
        DeviceOverview(
            id=d.id,
            sourceId=d.source_id,
            name=d.name,
            healthScore=d.healthScore,
            statusColor=d.statusColor,
            motorRpm=int(d.motorRpm),
            motorTemp=d.motorTemp,
            predictedClass=d.predictedClass,
            classLabel=d.classLabel,
            alertLevel=d.alertLevel,
            alertLabel=d.alertLabel,
            inferenceLatencyMs=d.inferenceLatencyMs,
            remainingLifeDays=d.remainingLifeDays,
            maintenanceDueText=d.maintenanceDueText,
            diagnosisSummary=d.diagnosisSummary,
        ) for d in atlas_runtime.device_list
    ]

@app.post("/api/device/select", summary="切换监测目标设备")
async def select_device(req: SelectDeviceRequest):
    success = atlas_runtime.select_device(req.device_id)
    if success:
        return {"success": True, "active_device_id": atlas_runtime.active_device_id}
    return {"success": False, "message": "设备 ID 超出范围或目标切换未被网关确认"}

@app.get("/api/telemetry/{device_id}", response_model=DeviceTelemetry, summary="设备遥测与模型推理结果")
async def get_telemetry(device_id: int):
    d = next((x for x in atlas_runtime.device_list if x.id == device_id), atlas_runtime.active_device)
    return DeviceTelemetry(
        id=d.id,
        sourceId=d.source_id,
        healthHistory=list(d.healthHistory),
        systemStatus=d.systemStatus,
        tempHistory=list(d.tempHistory),
        audioSpectrum=list(d.audioSpectrum),
        accX=d.accX,
        accY=d.accY,
        accZ=d.accZ,
        envHumidity=d.envHumidity,
        predictedClass=d.predictedClass,
        classProbabilities=list(d.classProbabilities),
        inferenceLatencyMs=d.inferenceLatencyMs,
        classLabel=d.classLabel,
        alertLevel=d.alertLevel,
        alertLabel=d.alertLabel,
        remainingLifeDays=d.remainingLifeDays,
        maintenanceDueText=d.maintenanceDueText,
        diagnosisSummary=d.diagnosisSummary,
        maintenanceAdvice=d.maintenanceAdvice,
        currentPreprocessMs=atlas_runtime.performance["currentPreprocessMs"],
        currentInferenceMs=atlas_runtime.performance["currentInferenceMs"],
        currentTotalMs=atlas_runtime.performance["currentTotalMs"],
        currentFps=atlas_runtime.performance["currentFps"],
        averagePreprocessMs=atlas_runtime.performance["averagePreprocessMs"],
        averageInferenceMs=atlas_runtime.performance["averageInferenceMs"],
        averageTotalMs=atlas_runtime.performance["averageTotalMs"],
        averageFps=atlas_runtime.performance["averageFps"],
    )

@app.get("/api/cluster", response_model=ClusterStatus, summary="集控通信状况与日志")
async def get_cluster_status():
    """返回后端日志、连接节点数、告警数量与推理性能，不再返回无真实来源的节点温度字段。"""
    return ClusterStatus(
        logs=list(atlas_runtime.logs),
        nearlinkLatency=atlas_runtime.nearlinkLatency,
        scanPosition=atlas_runtime.scanPosition,
        connectedSources=len(atlas_runtime.device_list),
        activeAlerts=len([d for d in atlas_runtime.device_list if d.alertLevel in ("warning", "critical")]),
        currentPreprocessMs=atlas_runtime.performance["currentPreprocessMs"],
        currentInferenceMs=atlas_runtime.performance["currentInferenceMs"],
        currentTotalMs=atlas_runtime.performance["currentTotalMs"],
        currentFps=atlas_runtime.performance["currentFps"],
        averagePreprocessMs=atlas_runtime.performance["averagePreprocessMs"],
        averageInferenceMs=atlas_runtime.performance["averageInferenceMs"],
        averageTotalMs=atlas_runtime.performance["averageTotalMs"],
        averageFps=atlas_runtime.performance["averageFps"],
    )

@app.post("/api/action/log", summary="追加前端审计事件")
async def submit_log_action(req: LogActionRequest):
    atlas_runtime.add_log(req.message)
    return {"success": True}

@app.post("/api/action/expert", summary="更新前端调参参数")
async def update_expert_settings(req: ExpertSettingsRequest):
    atlas_runtime.aiSensitivity = req.aiSensitivity
    atlas_runtime.add_log("前端调参：启用高敏告警观察模式" if req.aggressiveMode else "前端调参：恢复标准告警观察模式")
    return {"success": True}
