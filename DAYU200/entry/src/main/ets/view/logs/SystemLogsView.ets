@Component
export struct SystemLogsView {
  @StorageLink('logs') logs: string[] = [];

  build() {
    Column() {
      // 留白 iOS 大标题
      Row() {
        Text("审计运转动态流").fontSize(18).fontColor('#1C1C1E').fontWeight(FontWeight.Bold)
      }.width('100%').padding({left: 24, top: 10, bottom: 20})

      List({ space: 16 }) {
        ForEach(this.logs, (log: string) => {
          ListItem() {
            Row() {
               Circle({width: 8, height: 8})
                 .fill(log.includes("⚠️") ? '#FF9500' : ((log.includes("🛑") || log.includes("🚨")) ? '#FF3B30' : '#34C759'))
                 .margin({right: 16})
               Text(log)
                 .fontSize(15)
                 .fontColor('#1C1C1E')
                 .fontWeight(FontWeight.Medium)
                 .layoutWeight(1)
                 .lineHeight(20)
            }.width('100%').padding(22).backgroundColor('#FFFFFF')
             .borderRadius(20)
             .shadow({ radius: 10, color: 'rgba(0,0,0,0.03)', offsetY: 4 })
             .border({width: (log.includes("🛑") || log.includes("🚨")) ? 1 : 0, color: '#FF3B30'})
          }
        }, (item: string) => item) 
      }.width('100%').layoutWeight(1).padding({left: 20, right: 20})
      
      Row() {
         Text(`底层引擎已热备份 ${this.logs.length} 条数据，本盘符空余 122GB`).fontSize(12).fontColor('#8E8E93')
      }.width('100%').justifyContent(FlexAlign.Center).padding(20)
    }.width('100%').height('100%')
  }
}
