from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from typing import List
from models import DeviceOverview, DeviceTelemetry, ClusterStatus, SelectDeviceRequest, LogActionRequest, ExpertSettingsRequest
from atlas_runtime import atlas_runtime

app = FastAPI(title="Ascend IIoT Central Hub", version="2.2", description="企业级边缘通信管理后端核心总线接口 API（Atlas 本地推理结果驱动，支持多设备扩展）")

# 无脑容忍全局跨域调校 (为了方便不同厂牌面板调试抓包连接)
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
    return {"success": False, "message": "设备 ID 超出范围"}

@app.get("/api/telemetry/{device_id}", response_model=DeviceTelemetry, summary="深度探测遥传")
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

@app.get("/api/cluster", response_model=ClusterStatus, summary="集控通信状况日志")
async def get_cluster_status():
    """抛出服务器本身运转心跳、握手延时参数与共享日志池。"""
    return ClusterStatus(
        logs=list(atlas_runtime.logs), nearlinkLatency=atlas_runtime.nearlinkLatency,
        edgeTemp=atlas_runtime.edgeTemp, scanPosition=atlas_runtime.scanPosition,
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

@app.post("/api/action/log", summary="透明化审计事件透传")
async def submit_log_action(req: LogActionRequest):
    atlas_runtime.add_log(req.message)
    return {"success": True}

@app.post("/api/action/expert", summary="覆盖安全接管门槛")
async def update_expert_settings(req: ExpertSettingsRequest):
    atlas_runtime.aiSensitivity = req.aiSensitivity
    atlas_runtime.add_log("防卫模型极重度：已由云端强令进入阻断级防火墙" if req.aggressiveMode else "柔性云端智控恢复：撤回强制保护并恢复自检阈值")
    return {"success": True}
