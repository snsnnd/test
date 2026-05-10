import asyncio
import random

class InternalDevice:
    def __init__(self, dev_id: int, name: str, motorTemp: float, motorRpm: float):
        self.id = dev_id
        self.name = name
        self.healthScore = 98
        self.healthHistory = [98] * 30
        self.statusColor = '#34C759'
        self.systemStatus = '通信链路平稳维系'
        self.audioSpectrum = [20.0] * 15
        self.accX = 0.05
        self.accY = -0.02
        self.accZ = 9.81
        self.motorTemp = motorTemp
        self.tempHistory = [motorTemp] * 60
        self.motorRpm = motorRpm
        self.envHumidity = 45

class BackendSimulator:
    def __init__(self):
        # 预定义可选设备列表（后续将改为自动检测可连接设备）
        self.devices = [
            InternalDevice(0, '一号冲压主轴 (Node A)', 64.2, 1850.0),
            InternalDevice(1, '二号履带马达 (Node B)', 52.8, 1200.0),
            InternalDevice(2, '三号封箱阵列 (Node C)', 58.1, 3400.0),
        ]
        
        # 当前选中的监测目标设备 ID
        self.active_device_id = 0
        
        self.logs = ["[真实微服务层] 云端服务器主节点的引擎大动脉挂载成功"]
        self.nearlinkLatency = 0.9
        self.edgeTemp = 38.5
        self.scanPosition = 0
        self.aiSensitivity = 80
        
        self.running = False

    @property
    def active_device(self) -> InternalDevice:
        """获取当前选中的活跃设备"""
        return self.devices[self.active_device_id]

    def select_device(self, device_id: int) -> bool:
        """切换当前监测的目标设备"""
        if 0 <= device_id < len(self.devices):
            old_name = self.active_device.name
            self.active_device_id = device_id
            new_name = self.active_device.name
            self.add_log(f"🔄 监测目标切换：[{old_name}] → [{new_name}]")
            return True
        return False

    def add_log(self, message: str):
        self.logs.insert(0, f"[底层微服务透传] {message}")
        if len(self.logs) > 50:
            self.logs.pop()

    async def tick_loop(self):
        while self.running:
            self.nearlinkLatency = 0.8 + random.random() * 0.4
            self.edgeTemp += (random.random() - 0.5) * 0.2
            self.scanPosition = (self.scanPosition + 5) % 100

            # 只模拟当前选中的设备（单设备模式）
            dev = self.active_device

            evt = random.random()
            if evt > 0.98:
                dev.healthScore -= int(random.random() * 6 + 3)
                self.add_log(f"⚠️ [服务端雷达] 阻尼识别：[{dev.name}] 发现底层震荡畸变波点")
            elif evt > 0.9:
                dev.healthScore -= 1
            else:
                if dev.healthScore < 98:
                    dev.healthScore += 1

            if dev.healthScore > 100: dev.healthScore = 100
            if dev.healthScore < 0: dev.healthScore = 0

            dev.healthHistory.append(dev.healthScore)
            dev.healthHistory.pop(0)

            dev.statusColor = '#34C759'
            dev.systemStatus = '设备正常运行预测周期中'

            if dev.healthScore < 60:
                dev.statusColor = '#FF3B30'
                dev.systemStatus = '深层物理故障锁死保护触发'
                dev.motorTemp += 2.5
                dev.motorRpm = dev.motorRpm * 0.6 + random.random() * 50
            elif dev.healthScore < 80:
                dev.statusColor = '#FF9500'
                dev.systemStatus = '防卫系统：高频杂音频变研判中'

            dev.motorTemp += (random.random() - 0.5) * 0.4
            
            # 推移温度历史序列（用于前端大屏斜率绘制图）
            dev.tempHistory.append(round(dev.motorTemp, 2))
            dev.tempHistory.pop(0)
            
            dev.motorRpm += (random.random() - 0.5) * 15
            dev.envHumidity += int((random.random() - 0.5) * 2)

            for j in range(15):
                val = random.random() * 80
                # 高端判定：健康度极低状态极容易受 AI 滤波器抑制率影响
                if dev.healthScore < 70 and random.random() > (1.0 - self.aiSensitivity / 200.0):
                    val = 80 + random.random() * 20
                dev.audioSpectrum[j] = round(val, 2)

            noiseLevel = 2.5 if dev.healthScore < 70 else 0.2
            dev.accX = (random.random() - 0.5) * noiseLevel * 2
            dev.accY = (random.random() - 0.5) * noiseLevel
            dev.accZ = 9.81 + (random.random() - 0.5) * noiseLevel

            # Python 后端引擎独立执行频率 (模拟极其昂贵强大的服务器计算)
            await asyncio.sleep(0.6)

    def start(self):
        if not self.running:
            self.running = True
            asyncio.create_task(self.tick_loop())

simulator = BackendSimulator()
