import { deviceService } from '../../api/ServiceLocator';
import { DeviceOverview } from '../../api/models/DeviceModels';

@Component
export struct DeviceSelectorView {
  @StorageLink('deviceList') deviceList: DeviceOverview[] = [];
  @State isScanning: boolean = false;

  public onDeviceSelect: (id: number) => void = (id: number) => {};

  private deviceIcons: string[] = ['⚙️', '🔩', '📦'];

  aboutToAppear() {
     // 延迟 500ms 自动触发一次初始扫描，增加“智能”感
     setTimeout(() => {
        this.startScan();
     }, 500);
  }

  async startScan() {
     if (this.isScanning) return;
     this.isScanning = true;
     
     // 调用后端模拟扫描接口
      const devices = await deviceService.scanNearbyDevices();
      AppStorage.setOrCreate('deviceList', devices);
     
     this.isScanning = false;
  }

  build() {
    Column() {
      // 沉浸式大标题 + 扫描动作条
      Row() {
        Column() {
          Text("设备监测").fontSize(34).fontColor('#1C1C1E').fontWeight(FontWeight.Bolder).fontFamily('Helvetica')
          Text(this.isScanning ? "正在探测近场设备..." : "选择一台设备以开始实时监测").fontSize(16).fontColor('#8E8E93').margin({top: 8})
        }.alignItems(HorizontalAlign.Start)

        Blank()

        // 扫描按钮/动画
        if (this.isScanning) {
           LoadingProgress().width(32).height(32).color('#007AFF')
        } else {
           Button({ type: ButtonType.Capsule }) {
              Row() {
                 Text("📡 扫描附近").fontSize(14).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
              }.padding({ left: 12, right: 12 })
           }
           .height(36)
           .backgroundColor('#007AFF')
           .onClick(() => {
              this.startScan();
           })
        }
      }.width('100%').padding({left: 24, right: 24, top: 40, bottom: 28})

      Scroll() {
        Column({space: 14}) {
          if (this.deviceList.length === 0 && !this.isScanning) {
             // 无设备提示
             Column() {
                Text("📭 未发现可用设备").fontSize(16).fontColor('#C7C7CC').margin({top: 100})
                Text("点击右上角重新扫描").fontSize(14).fontColor('#C7C7CC').margin({top: 8})
             }.width('100%').alignItems(HorizontalAlign.Center)
          } else {
              ForEach(this.deviceList, (device: DeviceOverview) => {
                 this.DeviceSelectCard(device)
              }, (device: DeviceOverview) => device.id.toString())
          }
          
          // 底部提示
          if (!this.isScanning && this.deviceList.length > 0) {
            Column() {
              Text("💡 近场 Nearlink 通信已加密加密").fontSize(12).fontColor('#C7C7CC')
            }.width('100%').padding({top: 24, bottom: 40}).alignItems(HorizontalAlign.Center)
          }
        }.padding({left: 20, right: 20}).width('100%')
      }.scrollable(ScrollDirection.Vertical).scrollBar(BarState.Off).layoutWeight(1)
    }.width('100%').height('100%').backgroundColor('#F2F2F7')
  }

  @Builder DeviceSelectCard(device: DeviceOverview) {
     Column() {
        Row() {
           // 设备图标
           Text(device.id < this.deviceIcons.length ? this.deviceIcons[device.id] : '🔧')
             .fontSize(28).margin({right: 16})
            
           Column() {
             Text(device.name).fontSize(19).fontWeight(FontWeight.Medium).fontColor('#1C1C1E')
             Text(`${device.alertLabel ?? '绿区监测'} · ${device.classLabel ?? '待判定'} · 健康度 ${device.healthScore}`)
               .fontSize(13).fontColor('#8E8E93').margin({top: 6})
             Text(`温度 ${device.motorTemp.toFixed(1)}°C · 时延 ${(device.inferenceLatencyMs ?? 0).toFixed(1)}ms`)
               .fontSize(13).fontColor('#8E8E93').margin({top: 6})
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)

            // 箭头指示
            Text("›").fontSize(26).fontColor('#C7C7CC').fontWeight(FontWeight.Medium)
         }.width('100%').alignItems(VerticalAlign.Center)
     }
      .width('100%').padding(22).backgroundColor('#FFFFFF').borderRadius(18)
      .shadow({ radius: 12, color: 'rgba(0,0,0,0.03)', offsetY: 4 })
      .onClick(() => {
          this.onDeviceSelect(device.id);
      })
   }
}
