@Component
export struct VibrationMonitorView {
  @StorageLink('accDataX') accX: number = 0;
  @StorageLink('accDataY') accY: number = 0;
  @StorageLink('accDataZ') accZ: number = 9.81;
  @StorageLink('statusColor') statusColor: string = '#00E676';

  build() {
    Scroll() {
      Column() {
        Text("切脉：高频微米级振动感知").fontSize(18).fontColor('#00E676').fontWeight(FontWeight.Bold).margin({ bottom: 20 })
        
        Column({space: 20}) {
          this.AxisRow("X 轴 (转子水平)", this.accX, '#29B6F6', 15)
          this.AxisRow("Y 轴 (轨道纵深)", this.accY, '#AB47BC', 15)
          this.AxisRow("Z 轴 (垂直落差)", this.accZ - 9.81, '#FFA726', 15) // 展示去重力后的波动
        }.width('100%').backgroundColor('#22242D').padding(25).borderRadius(8)
        
        Text("三维空间扰动能量估算 (伪时域 FFT)").fontColor('#FFFFFF').fontSize(14).margin({top:25, bottom:10})
        Row() {
           ForEach([1,2,3,4,5,6,7,8,9,10,11,12], (dummy: number) => {
              Column().width('6%')
                .height(Math.abs(this.accX) > 1.5 ? (Math.random()*80 + 20) : (Math.random()*25 + 5))
                .backgroundColor(this.statusColor).borderRadius(2)
           })
        }.width('100%').height(120).backgroundColor('#22242D').padding(15).borderRadius(8).justifyContent(FlexAlign.SpaceEvenly).alignItems(VerticalAlign.Bottom)

      }.padding(20).alignItems(HorizontalAlign.Start).width('100%')
    }
  }

  @Builder AxisRow(name: string, val: number, color: string, scaleLimit: number) {
    Row() {
      Text(name).fontSize(14).fontColor('#AAAAAA').width('25%').textAlign(TextAlign.Start)
      Stack({alignContent: Alignment.Start}) {
         // 背景槽底槽含报警线
         Rect().width('100%').height(10).fill('#111111').radius(5)
         // 当到达报警阈值标红
         Progress({ value: Math.abs(val)*10, total: scaleLimit, type: ProgressType.Linear }).width('100%').color(Math.abs(val)*10 > scaleLimit*0.8 ? '#FF5252' : color)
      }.width('50%').margin({ left: 10, right: 10 })
      Text(`${(val).toFixed(2)} g`).fontSize(14).fontColor('#FFFFFF').width('20%').textAlign(TextAlign.End)
    }.width('100%')
  }
}
