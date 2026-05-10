import json
import socket
import threading
import time
from collections import deque
from datetime import date, timedelta
import zlib
from typing import Optional  # 必须引入 Optional 以兼容 Python 3.9

ATLAS_RESULT_HOST = "127.0.0.1"
ATLAS_RESULT_PORT = 19001
ATLAS_CONTROL_HOST = "127.0.0.1"
ATLAS_CONTROL_PORT = 19002
DEFAULT_ENV_HUMIDITY = 45

CLASS_LABELS = {
    0: "正常工况",
    1: "早期异常",
    2: "高风险异常",
}

ALERT_META = {
    "normal": {"label": "绿区监测", "color": "#34C759"},
    "warning": {"label": "橙色预警", "color": "#FF9500"},
    "critical": {"label": "红色告警", "color": "#FF3B30"},
}

class AtlasRuntimeDevice:
    def __init__(self, device_id: int, source_id: int, name: str):
        self.id = device_id
        self.raw_device_id = device_id
        self.source_id = source_id
        self.name = name
        self.targetName = name
        self.available = True
        self.selectedByMaster = False
        self.connectedToMaster = False
        self.healthScore = 0
        self.healthHistory = deque([0] * 30, maxlen=30)
        self.statusColor = "#8E8E93"
        self.systemStatus = "等待推理结果流"
        self.audioSpectrum = [0.0] * 15
        self.accX = 0.0
        self.accY = 0.0
        self.accZ = 0.0
        self.motorTemp = 0.0
        self.tempHistory = deque([0.0] * 60, maxlen=60)
        self.motorRpm = 0.0
        self.envHumidity = DEFAULT_ENV_HUMIDITY
        self.predictedClass = None
        self.classProbabilities = []
        self.inferenceLatencyMs = 0.0
        self.classLabel = "待判定"
        self.alertLevel = "normal"
        self.alertLabel = ALERT_META["normal"]["label"]
        self.remainingLifeDays = 0
        self.maintenanceDueText = "待模型稳定后更新"
        self.diagnosisSummary = "等待推理结果流"
        self.maintenanceAdvice = "等待推理结果流"

class AtlasRuntimeService:
    def __init__(self):
        self.devices = {}
        self.active_device_id = None
        self.logs = deque(["[Atlas Backend] 等待本地推理结果流连接"], maxlen=50)
        self.nearlinkLatency = 0.0
        self.edgeTemp = 0.0
        self.scanPosition = 0
        self.aiSensitivity = 80
        self.performance = {
            "currentPreprocessMs": 0.0,
            "currentInferenceMs": 0.0,
            "currentTotalMs": 0.0,
            "currentFps": 0.0,
            "averagePreprocessMs": 0.0,
            "averageInferenceMs": 0.0,
            "averageTotalMs": 0.0,
            "averageFps": 0.0,
        }
        self.running = False
        self.connected = False
        self.thread = None
        self.lock = threading.Lock()

    @property
    def device_list(self):
        with self.lock:
            return [self.devices[key] for key in sorted(self.devices.keys())]

    @property
    def active_device(self):
        with self.lock:
            if self.active_device_id in self.devices:
                return self.devices[self.active_device_id]
            if self.devices:
                first_key = sorted(self.devices.keys())[0]
                self.active_device_id = first_key
                return self.devices[first_key]
            return AtlasRuntimeDevice(0, 0, "WS63 Sensor Node")

    def add_log(self, message: str):
        with self.lock:
            self.logs.appendleft(f"[Atlas Backend] {message}")

    @staticmethod
    def _compose_name_id(target_name: str) -> int:
        return 100000 + (zlib.crc32(target_name.encode("utf-8")) & 0x7FFF)

    def _send_select_target(self, target_name: str) -> bool:
        payload = json.dumps({"action": "select_target", "target_name": target_name}, ensure_ascii=False) + "\n"
        try:
            with socket.create_connection((ATLAS_CONTROL_HOST, ATLAS_CONTROL_PORT), timeout=3) as sock:
                sock.sendall(payload.encode("utf-8"))
            self.add_log(f"已向网关下发切换目标指令: {target_name}")
            return True
        except OSError as exc:
            self.add_log(f"下发切换目标指令失败: {exc}")
            return False

    def select_device(self, device_id: int) -> bool:
        with self.lock:
            if device_id in self.devices:
                self.active_device_id = device_id
                target_name = self.devices[device_id].targetName
            else:
                return False

        if self._send_select_target(target_name):
            with self.lock:
                self.logs.appendleft(f"[Atlas Backend] 监测目标切换为 device_id={device_id}")
            return True
        return False

    def start(self):
        if self.running:
            return

        self.running = True
        self.thread = threading.Thread(target=self._result_stream_loop, name="atlas_result_stream", daemon=True)
        self.thread.start()

    def stop(self):
        self.running = False

    @staticmethod
    def _compose_runtime_id(source_id: int, raw_device_id: int) -> int:
        return source_id * 1000 + raw_device_id

    # 修复处 1: 将 int | None 修改为 Optional[int]
    @staticmethod
    def _derive_alert_level(health_score: int, predicted_class: Optional[int]) -> str:
        if predicted_class == 2 or health_score < 60:
            return "critical"
        if predicted_class == 1 or health_score < 80:
            return "warning"
        return "normal"

    # 修复处 2: 将 int | None 修改为 Optional[int]
    @staticmethod
    def _estimate_remaining_life_days(health_score: int, motor_temp: float, predicted_class: Optional[int],
                                      history_values) -> int:
        trend_drop = 0.0
        if len(history_values) >= 2:
            trend_drop = max(0.0, float(history_values[0]) - float(history_values[-1]))

        class_penalty = {0: 0.0, 1: 18.0, 2: 40.0}.get(predicted_class, 10.0)
        temp_penalty = max(0.0, motor_temp - 60.0) * 1.3
        trend_penalty = trend_drop * 2.0
        life_days = int(max(3.0, min(180.0, health_score * 1.6 - class_penalty - temp_penalty - trend_penalty)))
        return life_days

    @staticmethod
    def _format_due_date(days: int) -> str:
        due_date = date.today() + timedelta(days=days)
        return f"{due_date.month}月{due_date.day}日"

    @staticmethod
    def _build_diagnosis(alert_level: str, class_label: str, remaining_days: int) -> tuple:
        if alert_level == "critical":
            return (
                f"{class_label}：模型判定当前设备处于高风险区，建议立即降载并安排检修。",
                f"建议 24 小时内完成停机检查，当前估算剩余安全窗口约 {remaining_days} 天。",
            )
        if alert_level == "warning":
            return (
                f"{class_label}：模型发现潜在异常，建议尽快安排点检与复测。",
                f"建议 3 天内安排维保窗口，当前估算剩余可用周期约 {remaining_days} 天。",
            )
        return (
            f"{class_label}：设备当前处于绿区工况，可继续运行。",
            f"建议保持常规巡检节奏，当前估算剩余可用周期约 {remaining_days} 天。",
        )

    def _get_or_create_device(self, payload: dict):
        raw_device_id = int(payload.get("device_id") or payload.get("source_id") or 0)
        source_id = int(payload.get("source_id") or raw_device_id)
        if self.active_device_id in self.devices:
            device_id = self.active_device_id
        else:
            device_id = self._compose_runtime_id(source_id, raw_device_id)
        device = self.devices.get(device_id)
        if device is None:
            device = AtlasRuntimeDevice(device_id, source_id, f"JS节点 {source_id}-{raw_device_id}")
            device.raw_device_id = raw_device_id
            self.devices[device_id] = device
            if self.active_device_id is None:
                self.active_device_id = device_id
        return device

    def _update_bridge_status(self, payload: dict):
        nodes = payload.get("nodes") or []
        active_target = payload.get("active_target") or ""
        target_connected = bool(payload.get("target_connected"))

        with self.lock:
            seen_ids = set()
            for node in nodes:
                target_name = node.get("name") or "unknown"
                device_id = self._compose_name_id(target_name)
                seen_ids.add(device_id)
                device = self.devices.get(device_id)
                if device is None:
                    device = AtlasRuntimeDevice(device_id, 0, target_name)
                    self.devices[device_id] = device
                device.name = target_name
                device.targetName = target_name
                device.available = True
                device.selectedByMaster = bool(node.get("isSelected"))
                device.connectedToMaster = bool(node.get("isConnected"))
                if device.selectedByMaster:
                    self.active_device_id = device_id

            for device_id, device in self.devices.items():
                if device.targetName and device_id not in seen_ids and device.source_id == 0:
                    device.available = False

            self.logs.appendleft(
                f"[Atlas Backend] 发现 {len(nodes)} 个 JS 节点，当前目标={active_target or '未选择'} 连接={'是' if target_connected else '否'}"
            )

    def _handle_bridge_ack(self, payload: dict):
        with self.lock:
            self.logs.appendleft(
                f"[Atlas Backend] 目标切换{'成功' if payload.get('accepted') else '失败'}: {payload.get('message', '')}"
            )

    def _update_from_result(self, payload: dict):
        telemetry = payload.get("telemetry", {})
        class_probabilities = payload.get("class_probabilities", [])
        health_score = payload.get("health_score")

        with self.lock:
            dev = self._get_or_create_device(payload)

            if health_score is None:
                if class_probabilities:
                    health_score = max(0.0, min(100.0, float(max(class_probabilities)) * 100.0))
                else:
                    health_score = 0.0

            dev.healthScore = int(round(health_score))
            dev.healthHistory.append(dev.healthScore)
            dev.predictedClass = payload.get("predicted_class")
            dev.classProbabilities = [float(value) for value in class_probabilities]
            dev.inferenceLatencyMs = float(payload.get("inference_latency_ms", 0.0))
            dev.classLabel = CLASS_LABELS.get(dev.predictedClass, "待判定")

            audio_spectrum = telemetry.get("audio_spectrum") or []
            if audio_spectrum:
                dev.audioSpectrum = [float(value) for value in audio_spectrum[:15]]
                if len(dev.audioSpectrum) < 15:
                    dev.audioSpectrum.extend([0.0] * (15 - len(dev.audioSpectrum)))

            temperature_history = telemetry.get("temperature_history_c") or []
            if temperature_history:
                dev.tempHistory = deque([float(value) for value in temperature_history[:60]], maxlen=60)
                if len(dev.tempHistory) > 0:
                    dev.motorTemp = float(dev.tempHistory[-1])
                    self.edgeTemp = dev.motorTemp

            accel_g = telemetry.get("last_accel_g") or [0.0, 0.0, 0.0]
            if len(accel_g) >= 3:
                dev.accX = float(accel_g[0])
                dev.accY = float(accel_g[1])
                dev.accZ = float(accel_g[2])

            gyro_dps = telemetry.get("last_gyro_dps") or [0.0, 0.0, 0.0]
            if len(gyro_dps) >= 3:
                dev.motorRpm = abs(float(gyro_dps[2])) / 6.0

            dev.envHumidity = DEFAULT_ENV_HUMIDITY
            dev.alertLevel = self._derive_alert_level(dev.healthScore, dev.predictedClass)
            dev.alertLabel = ALERT_META[dev.alertLevel]["label"]
            dev.statusColor = ALERT_META[dev.alertLevel]["color"]
            dev.remainingLifeDays = self._estimate_remaining_life_days(
                dev.healthScore, dev.motorTemp, dev.predictedClass, list(dev.healthHistory)
            )
            dev.maintenanceDueText = self._format_due_date(dev.remainingLifeDays)
            diagnosis, advice = self._build_diagnosis(dev.alertLevel, dev.classLabel, dev.remainingLifeDays)
            dev.systemStatus = diagnosis
            dev.diagnosisSummary = diagnosis
            dev.maintenanceAdvice = advice

            perf = payload.get("performance") or {}
            current_perf = perf.get("current") or {}
            average_perf = perf.get("average") or {}
            self.performance = {
                "currentPreprocessMs": float(current_perf.get("preprocessMs", 0.0)),
                "currentInferenceMs": float(current_perf.get("inferenceMs", 0.0)),
                "currentTotalMs": float(current_perf.get("totalMs", 0.0)),
                "currentFps": float(current_perf.get("fps", 0.0)),
                "averagePreprocessMs": float(average_perf.get("preprocessMs", 0.0)),
                "averageInferenceMs": float(average_perf.get("inferenceMs", 0.0)),
                "averageTotalMs": float(average_perf.get("totalMs", 0.0)),
                "averageFps": float(average_perf.get("fps", 0.0)),
            }
            self.nearlinkLatency = float(payload.get("inference_latency_ms", 0.0))
            self.scanPosition = int(payload.get("frame_id", 0)) % 100

            frame_id = payload.get("frame_id")
            if dev.alertLevel == "critical":
                self.logs.appendleft(
                    f"🚨 红色告警：[{dev.name}] frame={frame_id} {dev.classLabel}，健康度 {dev.healthScore}"
                )
            elif dev.alertLevel == "warning":
                self.logs.appendleft(
                    f"⚠️ 橙色预警：[{dev.name}] frame={frame_id} {dev.classLabel}，建议安排点检"
                )
            else:
                self.logs.appendleft(
                    f"✅ 绿区监测：[{dev.name}] frame={frame_id} 工况稳定，健康度 {dev.healthScore}"
                )

    def _result_stream_loop(self):
        while self.running:
            try:
                self.add_log(f"尝试连接推理结果流 {ATLAS_RESULT_HOST}:{ATLAS_RESULT_PORT}")
                with socket.create_connection((ATLAS_RESULT_HOST, ATLAS_RESULT_PORT), timeout=5) as sock:
                    self.connected = True
                    self.add_log("推理结果流已连接")
                    with sock.makefile("r", encoding="utf-8") as stream:
                        for line in stream:
                            if not self.running:
                                break
                            line = line.strip()
                            if not line:
                                continue
                            payload = json.loads(line)
                            message_type = payload.get("message_type")
                            if message_type == "bridge_status":
                                self._update_bridge_status(payload)
                                continue
                            if message_type == "bridge_ack":
                                self._handle_bridge_ack(payload)
                                continue
                            if "error" in payload:
                                self.add_log(f"推理错误 frame={payload.get('frame_id')} err={payload['error']}")
                                continue
                            self._update_from_result(payload)
                self.connected = False
                self.add_log("推理结果流已断开，等待重连")
            except OSError as exc:
                self.connected = False
                self.add_log(f"连接推理结果流失败: {exc}")
                time.sleep(2.0)
            except Exception as exc:
                self.connected = False
                self.add_log(f"处理推理结果流异常: {exc}")
                time.sleep(2.0)

atlas_runtime = AtlasRuntimeService()