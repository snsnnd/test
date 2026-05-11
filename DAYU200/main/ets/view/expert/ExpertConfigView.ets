import { deviceService } from '../../api/ServiceLocator';

@Component
export struct ExpertConfigView {
  @State aiSensitivity: number = 80;
  @State aggressiveMode: boolean = false;
  @StorageLink('currentInferenceMs') currentInferenceMs: number = 0;
  @StorageLink('averageFps') averageFps: number = 0;
  @StorageLink('connectedSources') connectedSources: number = 0;
  @StorageLink('activeAlerts') activeAlerts: number = 0;

  aboutToAppear() {
    this.aiSensitivity = AppStorage.get<number>('aiSensitivity') ?? 80;
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Column() {
          Text('模型观察参数')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1C1C1E')
            .margin({ bottom: 10 })
          Text('该参数会提交到后端调参接口，用于记录前端观察策略；当前代码不直接控制物理设备。')
            .fontSize(14)
            .fontColor('#8E8E93')
            .margin({ bottom: 24 })
            .lineHeight(20)

          Row() {
            Text('低敏观察').fontColor('#8E8E93').fontSize(14)
            Slider({ value: this.aiSensitivity, min: 0, max: 100, step: 1 })
              .layoutWeight(1)
              .selectedColor('#007AFF')
              .onChange((value: number) => {
                this.aiSensitivity = value;
                AppStorage.setOrCreate('aiSensitivity', value);
                deviceService.updateExpertSettings(value, this.aggressiveMode);
              })
            Text('高敏观察').fontColor('#8E8E93').fontSize(14)
          }.width('100%')

          Text(`当前观察灵敏度：${this.aiSensitivity}`)
            .fontSize(16)
            .fontColor('#007AFF')
            .fontWeight(FontWeight.Bold)
            .margin({ top: 10 })
        }
        .width('100%')
        .padding(24)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .alignItems(HorizontalAlign.Start)
        .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })

        Column() {
          Text('告警观察模式')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1C1C1E')
            .margin({ bottom: 24 })

          Row() {
            Column() {
              Text('启用高敏告警观察')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1C1C1E')
                .margin({ bottom: 6 })
              Text('仅调整前端提交给后端的观察参数，不等同于停机、急停或物理闭锁。')
                .fontSize(13)
                .fontColor('#8E8E93')
                .lineHeight(18)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.aggressiveMode })
              .selectedColor('#34C759')
              .onChange((isOn: boolean) => {
                this.aggressiveMode = isOn;
                deviceService.updateExpertSettings(this.aiSensitivity, isOn);
              })
          }.width('100%').justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
        .padding(24)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .alignItems(HorizontalAlign.Start)
        .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })

        Column() {
          Text('后端状态快照')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1C1C1E')
            .margin({ bottom: 16 })

          this.InfoRow('连接节点', `${this.connectedSources}`)
          Divider().strokeWidth(1).color('#F4F5F7').margin({ top: 12, bottom: 12 })
          this.InfoRow('活跃告警', `${this.activeAlerts}`)
          Divider().strokeWidth(1).color('#F4F5F7').margin({ top: 12, bottom: 12 })
          this.InfoRow('当前推理耗时', `${this.currentInferenceMs.toFixed(1)} ms`)
          Divider().strokeWidth(1).color('#F4F5F7').margin({ top: 12, bottom: 12 })
          this.InfoRow('平均 FPS', `${this.averageFps.toFixed(1)}`)

          Button('记录当前调参快照')
            .width('100%')
            .height(50)
            .backgroundColor('#F2F2F7')
            .fontColor('#1C1C1E')
            .fontWeight(FontWeight.Medium)
            .borderRadius(16)
            .margin({ top: 18 })
            .onClick(() => {
              deviceService.submitLogAction(`调参快照：灵敏度=${this.aiSensitivity}，高敏观察=${this.aggressiveMode ? '开启' : '关闭'}，推理=${this.currentInferenceMs.toFixed(1)}ms，FPS=${this.averageFps.toFixed(1)}`);
            })
        }
        .width('100%')
        .padding(24)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .alignItems(HorizontalAlign.Start)
        .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })
      }
      .width('100%')
      .padding(20)
    }
  }

  @Builder InfoRow(label: string, value: string) {
    Row() {
      Text(label).fontColor('#8E8E93').fontSize(14)
      Blank()
      Text(value).fontColor('#1C1C1E').fontSize(14).fontWeight(FontWeight.Medium)
    }.width('100%')
  }
}
