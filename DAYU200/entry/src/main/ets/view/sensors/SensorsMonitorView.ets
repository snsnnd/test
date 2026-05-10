@Component
export struct SensorsMonitorView {
  @StorageLink('audioSpectrum') audioSpectrum: number[] = [];
  @StorageLink('accDataX') accX: number = 0;
  @StorageLink('accDataY') accY: number = 0;
  @StorageLink('accDataZ') accZ: number = 9.81;
  @StorageLink('tempHistory') tempHistory: number[] = [];
  @StorageLink('statusColor') statusColor: string = '#34C759';

  build() {
    Scroll() {
      Column({ space: 16 }) {
         // 切脉 X, Y, Z
         Column() {
           Row() {
              Text("振荡捕捉 (切脉)").fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1C1C1E')
              Blank()
              Text("正常波段").fontSize(14).fontColor('#34C759')
           }.width('100%').margin({bottom: 24})
           
           this.AxisRow("X 轴心", this.accX, '#007AFF', 15)
           Divider().strokeWidth(1).color('#F2F2F7').margin({top:14, bottom:14})
           this.AxisRow("Y 纵深", this.accY, '#5856D6', 15)
           Divider().strokeWidth(1).color('#F2F2F7').margin({top:14, bottom:14})
           this.AxisRow("Z 垂直", this.accZ - 9.81, '#FF9500', 15)
         }.width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24)
         .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })

         // 声纹
         Column() {
           Text("微高频声浪特征 (听音)").fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1C1C1E').margin({bottom: 24})
           Stack({alignContent: Alignment.Center}) {
              Polyline()
                .width(280)
                .height(80)
                .points(this.audioSpectrum.map((val, idx) => [idx * 20, 80 - val * 0.8] as [number, number]))
                .fillOpacity(0)
                .stroke(this.statusColor)
                .strokeWidth(3)
           }.width('100%').backgroundColor('#F9F9F9').padding(16).borderRadius(16)
         }.width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24).alignItems(HorizontalAlign.Start)
         .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })

         // 热学
         Column() {
           Text("热力与温升趋势监测 (诊热)").fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1C1C1E').margin({bottom: 24})
           Stack({alignContent: Alignment.Center}) {
              Polyline()
                .width(280)
                .height(120)
                .points(this.tempHistory.map((val, idx) => [idx * (280/60), 120 - ((val - 40) * 4)] as [number, number]))
                .fillOpacity(0)
                .stroke('#FF2D55')
                .strokeWidth(3)
              
              // 绘制阈值预警线 (例如 60度)
              Line().width('100%').height(1).backgroundColor('rgba(255, 59, 48, 0.3)')
                 .strokeDashArray([4, 4]).position({x: 0, y: 120 - ((60 - 40) * 4)})
           }.width('100%').backgroundColor('#F9F9F9').padding(16).borderRadius(16)
           
           Row() {
              Text(`当前: ${this.tempHistory.length > 0 ? this.tempHistory[this.tempHistory.length - 1].toFixed(1) : '--'}°C`).fontSize(14).fontColor('#FF2D55').fontWeight(FontWeight.Bold)
              Blank()
              Text("采集频率 30Hz · 1D 时序").fontSize(12).fontColor('#8E8E93')
           }.width('100%').margin({top: 16})
         }.width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24).alignItems(HorizontalAlign.Start)
         .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })

      }.width('100%').padding(20)
    }
  }

  @Builder AxisRow(name: string, val: number, color: string, scaleLimit: number) {
    Row() {
      Text(name).fontSize(16).fontColor('#8E8E93').width('20%').fontWeight(FontWeight.Medium)
      Stack({alignContent: Alignment.Center}) {
         Rect().width('100%').height(4).fill('#F2F2F7').radius(2)
         Rect().width(2).height(16).fill('#D1D1D6') // 标定中轴
         Circle({width: 14, height: 14})
           .fill(Math.abs(val) > 2.0 ? '#FF3B30' : color)
           .offset({x: val * 40, y: 0}) 
           .shadow({radius: 4, color: 'rgba(0,0,0,0.2)', offsetY: 2})
      }.width('55%').margin({ left: 16, right: 16 }).height(24)
      Text(`${(val).toFixed(2)} g`).fontSize(16).fontColor('#1C1C1E').layoutWeight(1).textAlign(TextAlign.End).fontWeight(FontWeight.Medium)
    }.width('100%')
  }
}
