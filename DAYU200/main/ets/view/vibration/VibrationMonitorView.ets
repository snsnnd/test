@Component
export struct VibrationMonitorView {
  @StorageLink('accDataX') accX: number = 0.5;
  @StorageLink('accDataY') accY: number = -1.2;
  @StorageLink('accDataZ') accZ: number = 9.81;
  @StorageLink('statusColor') statusColor: string = '#52C41A';

  // 模拟一组FFT基础频段分布，配合当前振幅动态缩放
  private baseFftPattern: number[] = [20, 35, 60, 85, 100, 75, 45, 80, 55, 30, 40, 15];

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Text("切脉：高频微米级振动感知")
            .fontSize(20).fontColor('#191C1F').fontWeight(FontWeight.Bold).fontFamily('HarmonyOS Sans')
        }.width('100%').padding({ left: 4, bottom: 8 })

        // 1. 三轴实时监测卡片
        Column() {
          VibAxisItem({ name: "X 轴 (转子水平)", val: this.accX, barTheme: '#1677FF' })
          Divider().strokeWidth(1).color('#F4F5F7').margin({top: 16, bottom: 16})
          VibAxisItem({ name: "Y 轴 (轨道纵深)", val: this.accY, barTheme: '#722ED1' })
          Divider().strokeWidth(1).color('#F4F5F7').margin({top: 16, bottom: 16})
          VibAxisItem({ name: "Z 轴 (垂直落差)", val: this.accZ - 9.81, barTheme: '#FAAD14' })
        }
        .width('100%').backgroundColor('#FFFFFF').padding(24).borderRadius(24)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 })

        // 2. 空间扰动能量估算 (FFT) 卡片
        Column() {
          Row() {
            Text("三维空间扰动能量估算 (伪时域 FFT)").fontColor('#191C1F').fontSize(16).fontWeight(FontWeight.Bold)
          }.width('100%').margin({ bottom: 20 })

          // 能量图谱可视化
          Row({ space: 4 }) {
            ForEach(this.baseFftPattern, (baseVal: number, idx: number) => {
              Column() {
                // 结合X轴当前绝对值动态计算高度，避免使用 random 导致重绘闪烁
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
          .width('100%').height(120).backgroundColor('#F8F9FA').padding(16).borderRadius(16)

        }
        .width('100%').backgroundColor('#FFFFFF').padding(24).borderRadius(24)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 })

      }.padding(20).alignItems(HorizontalAlign.Start).width('100%')
    }
  }
}

// 提取的子组件：双向振动遥测条
@Component
struct VibAxisItem {
  @Prop name: string;
  @Prop val: number;
  @Prop barTheme: string;
  maxLimit: number = 5.0; // 最大量程

  get isPositive(): boolean { return this.val >= 0; }
  get absPercent(): number { return Math.min(Math.abs(this.val) / this.maxLimit, 1.0) * 50; }
  get color(): string { return Math.abs(this.val) > this.maxLimit * 0.8 ? '#FF4D4F' : this.barTheme; }

  build() {
    Row() {
      Text(this.name).fontSize(14).fontColor('#8A8F99').width('30%').textAlign(TextAlign.Start).fontWeight(FontWeight.Medium)

      // 中心零点轨道
      Stack({ alignContent: Alignment.Center }) {
        Row().width('100%').height(6).backgroundColor('#E5E6EB').borderRadius(3)

        if (this.isPositive) {
          Row() {
            Row().width(`${this.absPercent}%`).height(6).backgroundColor(this.color).borderRadius({ topRight: 3, bottomRight: 3 })
          }.width('100%').justifyContent(FlexAlign.Center).padding({ left: '50%' })
        } else {
          Row() {
            Row().width(`${this.absPercent}%`).height(6).backgroundColor(this.color).borderRadius({ topLeft: 3, bottomLeft: 3 })
          }.width('100%').justifyContent(FlexAlign.Center).padding({ right: '50%' })
        }

        // 零点刻度
        Row().width(2).height(12).backgroundColor('#C9CDD4').borderRadius(1)
      }.width('45%').margin({ left: 10, right: 10 })

      Text(`${(this.val > 0 ? '+' : '')}${(this.val).toFixed(2)} g`)
        .fontSize(15).fontColor(this.color).layoutWeight(1).textAlign(TextAlign.End).fontFamily('HarmonyOS Sans').fontWeight(FontWeight.Bold)
    }.width('100%')
  }
}