@Component
export struct SensorsMonitorView {
  @StorageLink('audioSpectrum') audioSpectrum: number[] = [12, 45, 60, 30, 80, 55, 20, 15, 65, 40, 25, 70, 50, 10];
  @StorageLink('accDataX') accX: number = 0.5;
  @StorageLink('accDataY') accY: number = -1.2;
  @StorageLink('accDataZ') accZ: number = 9.81;
  @StorageLink('tempHistory') tempHistory: number[] = [42, 43.5, 45, 48, 52, 56, 59, 58, 61, 62];
  @StorageLink('statusColor') statusColor: string = '#52C41A';

  private baseFftPattern: number[] = [20, 35, 60, 85, 100, 75, 45, 80, 55, 30, 40, 15];

  build() {
    Scroll() {
      Column({ space: 16 }) {

        // ！！！用于验证缓存是否刷新的红色标记！！！
        Text("如果看到这行红字，说明新UI已生效！(V2.0)")
          .fontColor(Color.Red).fontSize(12).margin({bottom: 10}).fontWeight(FontWeight.Bold)

        // ==========================================
        // 1. 振荡捕捉 (切脉)
        // ==========================================
        Column() {
          Row() {
            Text("切脉：高频微米级振动感知").fontSize(18).fontWeight(FontWeight.Bold).fontFamily('HarmonyOS Sans').fontColor('#191C1F')
            Blank()
            Row() {
              Circle({width: 6, height: 6}).fill('#52C41A').margin({right: 4})
              Text("实时遥测").fontSize(12).fontColor('#52C41A').fontWeight(FontWeight.Medium)
            }.padding({left: 8, right: 10, top: 4, bottom: 4}).backgroundColor('#F6FFED').borderRadius(12)
          }.width('100%').margin({bottom: 24})

          TelemetryBarView({ name: "X 轴 (转子水平)", val: this.accX, barThemeColor: '#1677FF' })
          Divider().strokeWidth(1).color('#F4F5F7').margin({top:16, bottom:16})
          TelemetryBarView({ name: "Y 轴 (轨道纵深)", val: this.accY, barThemeColor: '#722ED1' })
          Divider().strokeWidth(1).color('#F4F5F7').margin({top:16, bottom:16})
          TelemetryBarView({ name: "Z 轴 (垂直落差)", val: this.accZ - 9.81, barThemeColor: '#FAAD14' })

          Text("三维空间扰动能量估算 (伪时域 FFT)").fontColor('#191C1F').fontSize(14).fontWeight(FontWeight.Bold).margin({ top: 24, bottom: 16 })
          Row({ space: 4 }) {
            ForEach(this.baseFftPattern, (baseVal: number, idx: number) => {
              Column() {
                Row()
                  .width('100%')
                  .height(`${Math.min(Math.max(baseVal * (1 + Math.abs(this.accX) * 0.5), 10), 100)}%`)
                  .backgroundColor(this.statusColor)
                  .borderRadius({ topLeft: 4, topRight: 4 })
                  .opacity(0.8)
              }
              .layoutWeight(1).height('100%').justifyContent(FlexAlign.End)
            }, (item: number, index: number) => index.toString())
          }
          .width('100%').height(80).backgroundColor('#F8F9FA').padding(12).borderRadius(12)

        }
        .width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 })

        // ==========================================
        // 2. 声浪特征 (听音)
        // ==========================================
        Column() {
          Text("听音：双频分离声纹分析台").fontSize(18).fontWeight(FontWeight.Bold).fontFamily('HarmonyOS Sans').fontColor('#191C1F').margin({bottom: 20})

          Text("高频驻极体切片").fontColor('#191C1F').fontSize(14).fontWeight(FontWeight.Bold).margin({bottom:4})
          Text("捕获极高频的摩擦、爆音与机械异响").fontColor('#8A8F99').fontSize(12).margin({bottom:16})
          Row({space: 6}) {
            ForEach(this.audioSpectrum, (val: number, idx: number) => {
              HighFreqBar({ val: val })
            }, (item: number, index: number) => index.toString())
          }.width('100%').height(100).backgroundColor('#F8F9FA').padding(16).borderRadius(16)

          Text("环境低频底噪分离").fontColor('#191C1F').fontSize(14).fontWeight(FontWeight.Bold).margin({top: 24, bottom:4})
          Text("设备常规运行声浪，包络线形态").fontColor('#8A8F99').fontSize(12).margin({bottom:16})
          Stack({ alignContent: Alignment.Bottom }) {
            Row({space: 2}) {
              ForEach(this.audioSpectrum, (val: number, idx: number) => {
                Column() {
                  Row().width('100%').height(`${Math.max(100 - val, 10)}%`).backgroundColor('#B7EB8F').borderRadius({topLeft: 6, topRight: 6})
                }.layoutWeight(1).height('100%').justifyContent(FlexAlign.End)
              }, (item: number, index: number) => index.toString())
            }.width('100%').height('100%')
            Row().width('100%').height(2).backgroundColor('#52C41A').opacity(0.5)
          }
          .width('100%').height(60).backgroundColor('#F8F9FA').padding({left: 16, right: 16, top: 16}).borderRadius(16).clip(true)

        }
        .width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24).alignItems(HorizontalAlign.Start)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 })

        // ==========================================
        // 3. 热力监测 (诊热)
        // ==========================================
        Column() {
          Row() {
            Text("热力与温升趋势 (诊热)").fontSize(18).fontWeight(FontWeight.Bold).fontFamily('HarmonyOS Sans').fontColor('#191C1F')
            Blank()
            Text(`当前: ${this.tempHistory.length > 0 ? this.tempHistory[this.tempHistory.length - 1].toFixed(1) : '--'}°C`)
              .fontSize(16).fontColor('#FF4D4F').fontWeight(FontWeight.Bold).fontFamily('HarmonyOS Sans')
          }.width('100%').margin({bottom: 20})

          Stack({alignContent: Alignment.Bottom}) {
            Row().width('100%').height('100%')
              .linearGradient({
                direction: GradientDirection.Top,
                colors: [['rgba(255, 77, 79, 0.25)', 0.0], ['rgba(255, 77, 79, 0.0)', 1.0]]
              })

            Polyline()
              .width('100%')
              .height('100%')
              .points(this.tempHistory.map((val, idx) => [idx * (280 / Math.max(1, this.tempHistory.length - 1)), 120 - ((val - 40) * 4)] as [number, number]))
              .fillOpacity(0)
              .stroke('#FF4D4F')
              .strokeWidth(3)
              .strokeLineJoin(LineJoinStyle.Round)

            if (this.tempHistory.length > 0) {
              Circle({width: 10, height: 10})
                .fill('#FFFFFF')
                .stroke('#FF4D4F')
                .strokeWidth(3)
                .shadow({radius: 8, color: 'rgba(255, 77, 79, 0.6)', offsetY: 0})
                .position({
                  x: 280,
                  y: 120 - ((this.tempHistory[this.tempHistory.length - 1] - 40) * 4) - 5
                })
            }

            Stack({ alignContent: Alignment.End }) {
              Line().width('100%').height(1).backgroundColor('rgba(255, 77, 79, 0.4)').strokeDashArray([6, 4])
              Text("预警阈值 60°C")
                .fontSize(10)
                .fontColor('#FF4D4F')
                .backgroundColor('#FFF1F0')
                .padding({left: 6, right: 6, top: 2, bottom: 2})
                .borderRadius(4)
                .offset({ y: -10 })
            }.width('100%').position({x: 0, y: 120 - ((60 - 40) * 4)})

          }
          .width('100%').height(120).backgroundColor('#F8F9FA').borderRadius(16).clip(true)

          Row() {
            Text("采集频率 30Hz · 1D 时序").fontSize(12).fontColor('#8A8F99')
          }.width('100%').margin({top: 12}).justifyContent(FlexAlign.End)
        }
        .width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24).alignItems(HorizontalAlign.Start)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 })

      }.width('100%').padding({top: 20, bottom: 40, left: 20, right: 20})
    }
  }
}

@Component
struct TelemetryBarView {
  @Prop name: string;
  @Prop val: number;
  @Prop barThemeColor: string;
  maxG: number = 4.0;

  get percent(): number { return Math.min(Math.abs(this.val) / this.maxG, 1.0) * 50; }
  get isPositive(): boolean { return this.val >= 0; }
  get dynamicColor(): string { return Math.abs(this.val) > 2.5 ? '#FF4D4F' : this.barThemeColor; }

  build() {
    Row() {
      Text(this.name).fontSize(14).fontColor('#8A8F99').width('25%').fontWeight(FontWeight.Medium)

      Stack({alignContent: Alignment.Center}) {
        Row().width('100%').height(6).backgroundColor('#E5E6EB').borderRadius(3)

        if (!this.isPositive) {
          Row() {
            Row().width(`${this.percent}%`).height(6).backgroundColor(this.dynamicColor)
              .borderRadius({topLeft: 3, bottomLeft: 3})
              .shadow({radius: 4, color: `${this.dynamicColor}4D`, offsetY: 0})
          }.width('100%').justifyContent(FlexAlign.Center).padding({right: '50%'})
        }

        if (this.isPositive) {
          Row() {
            Row().width(`${this.percent}%`).height(6).backgroundColor(this.dynamicColor)
              .borderRadius({topRight: 3, bottomRight: 3})
              .shadow({radius: 4, color: `${this.dynamicColor}4D`, offsetY: 0})
          }.width('100%').justifyContent(FlexAlign.Center).padding({left: '50%'})
        }

        Row().width(2).height(14).backgroundColor('#8A8F99').borderRadius(1)
      }
      .width('45%').margin({ left: 10, right: 10 }).height(24)

      Text(`${(this.val > 0 ? '+' : '')}${(this.val).toFixed(2)} g`)
        .fontSize(15).fontColor(this.dynamicColor).layoutWeight(1)
        .textAlign(TextAlign.End).fontWeight(FontWeight.Bold).fontFamily('HarmonyOS Sans')
    }.width('100%')
  }
}

@Component
struct HighFreqBar {
  @Prop val: number;

  get barColor(): string {
    if (this.val > 85) return '#FF4D4F';
    if (this.val > 65) return '#FAAD14';
    return '#1677FF';
  }

  build() {
    Column() {
      Row()
        .width('100%')
        .height(`${Math.max(this.val, 5)}%`)
        .backgroundColor(this.barColor)
        .borderRadius({ topLeft: 4, topRight: 4 })
        .shadow({ radius: 6, color: `${this.barColor}66`, offsetY: 2 })
    }.height('100%').layoutWeight(1).justifyContent(FlexAlign.End)
  }
}