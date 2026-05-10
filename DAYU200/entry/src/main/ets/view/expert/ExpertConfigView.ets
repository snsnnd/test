import { deviceService } from '../../api/ServiceLocator';

@Component
export struct ExpertConfigView {
  @State aiSensitivity: number = 80;
  @State aggressiveMode: boolean = false;

  aboutToAppear() {
    this.aiSensitivity = AppStorage.get<number>('aiSensitivity') ?? 80;
  }

  build() {
    Scroll() {
      Column({space: 16}) {
        // AI 灵敏度调参
        Column() {
           Text("算力降噪与侦测敏感度").fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1C1C1E').margin({bottom: 10})
           Text("提高此值会极低程度消除白噪音，放大极微弱的波段尖峰引发 AI 预警算法的过敏感判定。").fontSize(14).fontColor('#8E8E93').margin({bottom: 24}).lineHeight(20)
           
           Row() {
              Text("柔性过滤").fontColor('#8E8E93').fontSize(14)
              Slider({ value: this.aiSensitivity, min: 0, max: 100, step: 1 })
                .layoutWeight(1)
                .selectedColor('#007AFF')
                .onChange((value: number) => {
                   this.aiSensitivity = value;
                   AppStorage.setOrCreate('aiSensitivity', value);
                   deviceService.updateExpertSettings(value, this.aggressiveMode);
                })
              Text("硬核透传").fontColor('#8E8E93').fontSize(14)
           }.width('100%')
           
           Text(`当前引擎波形放大倍率系数: ${(this.aiSensitivity/20).toFixed(2)} X`).fontSize(16).fontColor('#007AFF').fontWeight(FontWeight.Bold).margin({top: 10})
        }.width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24).alignItems(HorizontalAlign.Start)
         .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })

        // 强干预模式
        Column() {
           Text("自愈防火墙与降级规程").fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1C1C1E').margin({bottom: 24})
           
           Row() {
             Column() {
               Text("启用严苛极速阻断保护").fontSize(16).fontWeight(FontWeight.Medium).fontColor('#1C1C1E').margin({bottom: 6})
               Text("系统一旦探测小范围轻微异响立刻物理锁死").fontSize(13).fontColor('#8E8E93')
             }.alignItems(HorizontalAlign.Start).layoutWeight(1)
             
             Toggle({ type: ToggleType.Switch, isOn: this.aggressiveMode })
               .selectedColor('#34C759')
               .onChange((isOn: boolean) => {
                  this.aggressiveMode = isOn;
                  deviceService.updateExpertSettings(this.aiSensitivity, isOn);
               })
           }.width('100%').justifyContent(FlexAlign.SpaceBetween)
        }.width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24).alignItems(HorizontalAlign.Start)
         .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })

        // 离线日志倾倒
        Column() {
           Text("总共离线链路数据操作").fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1C1C1E').margin({bottom: 16})
           
           Button("导出原生抓包到外挂 U 盘")
             .width('100%')
             .height(55)
             .backgroundColor('#F2F2F7')
             .fontColor('#1C1C1E')
             .fontWeight(FontWeight.Medium)
             .borderRadius(16)
             .onClick(() => { deviceService.submitLogAction("内核级 I/O：离线全量封包成功"); })
        }.width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24).alignItems(HorizontalAlign.Start)
         .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })

      }.width('100%').padding(20)
    }
  }
}
