import { deviceService } from '../api/ServiceLocator';
import { DeviceOverview } from '../api/models/DeviceModels';

export class SyncManager {
   private static timer: number = -1;
   
   static start() {
      // 提供防止初始白屏的占位符缓存
      AppStorage.setOrCreate('activeDeviceId', 0);
      AppStorage.setOrCreate('aiSensitivity', 80);
      AppStorage.setOrCreate('logs', ["[UI交互引擎] 正在构建连接管道并执行挂载轮询..."]);
      AppStorage.setOrCreate('classLabel', '待判定');
      AppStorage.setOrCreate('alertLabel', '绿区监测');
      AppStorage.setOrCreate('remainingLifeDays', 0);
      AppStorage.setOrCreate('maintenanceDueText', '--');
      AppStorage.setOrCreate('diagnosisSummary', '等待设备接入');
      AppStorage.setOrCreate('maintenanceAdvice', '等待设备接入');
      AppStorage.setOrCreate('connectedSources', 0);
      AppStorage.setOrCreate('activeAlerts', 0);

      // 设备列表（供选择器使用，只需拉取一次基础信息）
      AppStorage.setOrCreate('deviceList', [] as DeviceOverview[]);
      AppStorage.setOrCreate('deviceSelected', false);

      // 此定时器相当于前端的统一轮询拉取池，而非从底层被动塞入
      SyncManager.timer = setInterval(async () => {
         try {
            let activeId = AppStorage.get<number>('activeDeviceId') || 0;
            let isSelected = AppStorage.get<boolean>('deviceSelected') || false;

            // 始终拉取设备列表（供选择器刷新用）
            let fleet = await deviceService.fetchFleetOverview();
             AppStorage.setOrCreate('deviceList', fleet);

            // 只有在用户已选择设备后，才拉取详细遥测数据
            if (isSelected) {
               let p1 = deviceService.fetchClusterStatus();
               let p2 = deviceService.fetchDeviceTelemetry(activeId);

               let cluster = await p1;
               let telemetry = await p2;

               // 1. 同步环境网关宏观池
               AppStorage.setOrCreate('logs', cluster.logs);
               AppStorage.setOrCreate('nearlinkLatency', cluster.nearlinkLatency);
               AppStorage.setOrCreate('edgeTemp', cluster.edgeTemp);
               AppStorage.setOrCreate('scanPosition', cluster.scanPosition);
               AppStorage.setOrCreate('connectedSources', cluster.connectedSources ?? 0);
               AppStorage.setOrCreate('activeAlerts', cluster.activeAlerts ?? 0);

               // 2. 同步当前选中设备的概览数据
               let matchedDevice = fleet.find(f => f.id === activeId);
               if (matchedDevice) {
                  AppStorage.setOrCreate('healthScore', matchedDevice.healthScore);
                  AppStorage.setOrCreate('systemStatus', telemetry.systemStatus);
                  AppStorage.setOrCreate('statusColor', matchedDevice.statusColor);
                  AppStorage.setOrCreate('motorRpm', matchedDevice.motorRpm);
                  AppStorage.setOrCreate('motorTemp', matchedDevice.motorTemp);
                  AppStorage.setOrCreate('activeDeviceName', matchedDevice.name);
                  AppStorage.setOrCreate('classLabel', matchedDevice.classLabel ?? '待判定');
                  AppStorage.setOrCreate('alertLabel', matchedDevice.alertLabel ?? '绿区监测');
                  AppStorage.setOrCreate('remainingLifeDays', matchedDevice.remainingLifeDays ?? 0);
                  AppStorage.setOrCreate('maintenanceDueText', matchedDevice.maintenanceDueText ?? '--');
                  AppStorage.setOrCreate('diagnosisSummary', matchedDevice.diagnosisSummary ?? telemetry.systemStatus);
                }
                // 3. 同步选中设备的密集阵列数据
                AppStorage.setOrCreate('healthHistory', telemetry.healthHistory);
                AppStorage.setOrCreate('tempHistory', telemetry.tempHistory);
                AppStorage.setOrCreate('envHumidity', telemetry.envHumidity);
                AppStorage.setOrCreate('audioSpectrum', telemetry.audioSpectrum);
                AppStorage.setOrCreate('accDataX', telemetry.accX);
                AppStorage.setOrCreate('accDataY', telemetry.accY);
                AppStorage.setOrCreate('accDataZ', telemetry.accZ);
                AppStorage.setOrCreate('maintenanceAdvice', telemetry.maintenanceAdvice ?? '等待模型输出');
             }
         } catch(e) {
            console.error("HTTP 远端拉取失败：" + e);
         }
      }, 800);
   }

   static stop() {
      clearInterval(SyncManager.timer);
   }
}
