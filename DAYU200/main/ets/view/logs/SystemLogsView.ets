@Component
export struct SystemLogsView {
  @StorageLink('logs') logs: string[] = [];

  build() {
    Column() {
      Row() {
        Text("审计运转动态流")
          .fontSize(22)
          .fontColor('#191C1F')
          .fontWeight(FontWeight.Bold)
          .fontFamily('HarmonyOS Sans')
      }.width('100%').padding({left: 24, top: 16, bottom: 20})

      List({ space: 14 }) {
        ForEach(this.logs, (log: string) => {
          ListItem() {
            // 改为调用子组件
            LogCardItem({ rawLog: log })
          }
        }, (item: string) => item)
      }.width('100%').layoutWeight(1).padding({left: 20, right: 20})

      Row() {
        Text(`底层引擎已热备份 ${this.logs.length} 条数据，本盘符空余 122GB`)
          .fontSize(12).fontColor('#8A8F99')
      }.width('100%').justifyContent(FlexAlign.Center).padding({top: 20, bottom: 30})
    }.width('100%').height('100%').backgroundColor('#F4F5F7')
  }
}

// ==========================================
// 修复：剥离逻辑运算到独立子组件中
// ==========================================
@Component
struct LogCardItem {
  @Prop rawLog: string;

  // 规避 UI 中编写 let，改用 Getter 计算属性
  get isError(): boolean { return this.rawLog.includes("🛑") || this.rawLog.includes("🚨"); }
  get isWarn(): boolean { return this.rawLog.includes("⚠️"); }
  get themeColor(): string { return this.isError ? '#FF4D4F' : (this.isWarn ? '#FAAD14' : '#52C41A'); }
  get bgColor(): string { return this.isError ? '#FFF1F0' : (this.isWarn ? '#FFFBE6' : '#FFFFFF'); }
  get cleanLog(): string { return this.rawLog.replace(/[⚠️🛑🚨]/g, '').trim(); }

  build() {
    Row() {
      Row().width(4).height(16).backgroundColor(this.themeColor).borderRadius(2).margin({right: 14})

      Text(this.cleanLog)
        .fontSize(14)
        .fontColor('#191C1F')
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .lineHeight(22)
    }
    .width('100%')
    .padding({left: 16, right: 20, top: 18, bottom: 18})
    .backgroundColor(this.bgColor)
    .borderRadius(16)
    .shadow({ radius: 12, color: 'rgba(0,0,0,0.03)', offsetY: 4 })
    .border({width: this.isError ? 1 : 0, color: 'rgba(255, 77, 79, 0.3)'})
    .stateStyles({
      pressed: { .scale({ x: 0.98, y: 0.98 }) },
      normal: { .scale({ x: 1, y: 1 }) }
    })
    .animation({ duration: 300, curve: Curve.Friction })
  }
}