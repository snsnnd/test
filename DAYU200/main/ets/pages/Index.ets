import { SyncManager } from '../utils/SyncManager';
import { deviceService } from '../api/ServiceLocator';
import { DashboardView } from '../view/dashboard/DashboardView';
import { SensorsMonitorView } from '../view/sensors/SensorsMonitorView';
import { DeviceManagerView } from '../view/manager/DeviceManagerView';
import { ExpertConfigView } from '../view/expert/ExpertConfigView';
import { SystemLogsView } from '../view/logs/SystemLogsView';
import { DeviceSelectorView } from '../view/home/DeviceSelectorView';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @StorageLink('deviceSelected') isDeviceSelected: boolean = false;
  @StorageLink('activeDeviceId') activeId: number = 0;
  @StorageLink('activeDeviceName') activeDeviceName: string = "";

  aboutToAppear() {
    SyncManager.start();
  }

  aboutToDisappear() {
    SyncManager.stop();
  }

  @Builder TabBuilder(title: string, targetIndex: number, icon: string) {
    Column() {
      Text(icon).fontSize(22).margin({bottom: 4}).opacity(this.currentIndex === targetIndex ? 1 : 0.5)
      Text(title).fontColor(this.currentIndex === targetIndex ? '#007AFF' : '#8E8E93').fontSize(11).fontWeight(this.currentIndex === targetIndex ? FontWeight.Medium : FontWeight.Regular)
    }.width('100%').height(60).justifyContent(FlexAlign.Center).backgroundColor('#F9F9F9').border({width: {top: 1}, color: '#E5E5EA'})
  }

  build() {
    Column() {
      if (!this.isDeviceSelected) {
        // 设备选择器页面
        DeviceSelectorView({ onDeviceSelect: (id: number) => {
          deviceService.selectDevice(id).then(() => {
            AppStorage.setOrCreate('activeDeviceId', id);
            AppStorage.setOrCreate('deviceSelected', true);
            deviceService.submitLogAction(`[权限下发] 用户选择监测设备 ID=${id}`);
          });
        }})
      } else {
        // 单设备监测工作坊模式
        Column() {
          Row() {
            Row() {
              Text("〈 ").fontSize(20).fontColor('#007AFF').fontWeight(FontWeight.Medium)
              Text("切换设备").fontSize(17).fontColor('#007AFF').fontWeight(FontWeight.Medium)
            }.onClick(() => {
              AppStorage.setOrCreate('deviceSelected', false);
            }).padding({left: 10, right: 10})

            Text(this.activeDeviceName).fontSize(18).fontColor('#1C1C1E').fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)

            Row().width(90) // 右侧留白防止居中偏移
          }.width('100%').padding({top: 30, bottom: 16, left: 14}).backgroundColor('#F2F2F7')

          Tabs({ barPosition: BarPosition.End }) {
            TabContent() { DashboardView() }.tabBar(this.TabBuilder('概览', 0, '🧭'))
            TabContent() { SensorsMonitorView() }.tabBar(this.TabBuilder('探针', 1, '📡'))
            TabContent() { DeviceManagerView() }.tabBar(this.TabBuilder('管家', 2, '⚡'))
            TabContent() { ExpertConfigView() }.tabBar(this.TabBuilder('调优', 3, '🎛️'))
            TabContent() { SystemLogsView() }.tabBar(this.TabBuilder('日志', 4, '📑'))
          }.layoutWeight(1).onChange((index: number) => { this.currentIndex = index; }).backgroundColor('#F2F2F7')
        }.width('100%').height('100%').backgroundColor('#F2F2F7')
      }
    }.width('100%').height('100%').backgroundColor('#F2F2F7')
  }
}