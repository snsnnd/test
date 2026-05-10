@Component
export struct AudioMonitorView {
  @StorageLink('audioSpectrum') audioSpectrum: number[] = [];
  @StorageLink('audioLowEnv') audioLowEnv: number[] = [];

  build() {
    Scroll() {
      Column() {
        Text("听音：双频分离声纹分析台").fontSize(18).fontColor('#00E676').fontWeight(FontWeight.Bold).margin({ bottom: 20 })
        
        // 高频部分
        Text("高频驻极体切片 (捕获如摩擦、爆音异响)").fontColor('#FFFFFF').fontSize(14).margin({bottom:10})
        Row({space: 4}) {
          ForEach(this.audioSpectrum, (val: number, idx: number) => {
             Column() {
                Rect().width('100%').height(`${val}%`).fill(val > 80 ? '#FF5252' : (val > 60 ? '#FFCA28' : '#29B6F6')).radius(4)
             }.height(160).layoutWeight(1).justifyContent(FlexAlign.End)
          })
        }.width('100%').backgroundColor('#22242D').padding(15).borderRadius(8).margin({bottom: 25})

        // 低频分离部分
        Text("环境低频底噪分离 (常规运行声)").fontColor('#FFFFFF').fontSize(14).margin({bottom:10})
        Row({space: 4}) {
          ForEach(this.audioLowEnv, (val: number, idx: number) => {
             Column() {
                Rect().width('100%').height(`${val}%`).fill('#00E676').opacity(0.6).radius(2)
             }.height(80).layoutWeight(1).justifyContent(FlexAlign.End)
          })
        }.width('100%').backgroundColor('#22242D').padding(15).borderRadius(8)

        Row() {
          Text("预警阈值：").fontColor('#888888').fontSize(12)
          Text("开启动态拦截").fontColor('#00E676').fontSize(12)
        }.width('100%').justifyContent(FlexAlign.SpaceBetween).margin({top: 15})
      }.padding(20).alignItems(HorizontalAlign.Start).width('100%')
    }
  }
}
