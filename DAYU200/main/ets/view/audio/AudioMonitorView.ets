@Component
export struct AudioMonitorView {
  // 模拟数据填充，防止空数组导致无画面
  @StorageLink('audioSpectrum') audioSpectrum: number[] = [10, 30, 85, 40, 60, 95, 20, 15, 70, 50, 30, 80];
  @StorageLink('audioLowEnv') audioLowEnv: number[] = [20, 40, 35, 50, 45, 60, 55, 40, 30, 45, 25, 30];

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Text("听音：双频分离声纹分析台")
            .fontSize(20).fontColor('#191C1F').fontWeight(FontWeight.Bold).fontFamily('HarmonyOS Sans')
        }.width('100%').padding({ left: 4, bottom: 8 })

        // 1. 高频分析卡片 (锐利的柱状体，突出异响)
        Column() {
          Text("高频驻极体切片").fontColor('#191C1F').fontSize(16).fontWeight(FontWeight.Bold).margin({bottom:4})
          Text("捕获极高频的摩擦、爆音与机械异响").fontColor('#8A8F99').fontSize(13).margin({bottom:20})

          Row({space: 6}) {
            ForEach(this.audioSpectrum, (val: number, idx: number) => {
              HighFreqBar({ val: val })
            }, (item: number, index: number) => index.toString())
          }.width('100%').height(140).backgroundColor('#F8F9FA').padding(16).borderRadius(16)
        }
        .width('100%').backgroundColor('#FFFFFF').padding(24).borderRadius(24).alignItems(HorizontalAlign.Start)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 })

        // 2. 低频分离卡片 (柔和的连续波浪/面积图，代表环境底噪)
        Column() {
          Text("环境低频底噪分离").fontColor('#191C1F').fontSize(16).fontWeight(FontWeight.Bold).margin({bottom:4})
          Text("设备常规运行声浪，包络线形态").fontColor('#8A8F99').fontSize(13).margin({bottom:20})

          // 使用 Stack + 倒影 模拟出低频的包络线体积感
          Stack({ alignContent: Alignment.Bottom }) {
            Row({space: 2}) {
              ForEach(this.audioLowEnv, (val: number, idx: number) => {
                Column() {
                  Row().width('100%').height(`${val}%`).backgroundColor('#B7EB8F').borderRadius({topLeft: 8, topRight: 8})
                }.layoutWeight(1).height('100%').justifyContent(FlexAlign.End)
              }, (item: number, index: number) => index.toString())
            }.width('100%').height('100%')

            // 底部基准线
            Row().width('100%').height(2).backgroundColor('#52C41A').opacity(0.5)
          }
          .width('100%').height(90).backgroundColor('#F8F9FA').padding({left: 16, right: 16, top: 16}).borderRadius(16).clip(true)

          Row() {
            Row() {
              Circle({width: 6, height: 6}).fill('#FAAD14').margin({right: 6})
              Text("预警阈值：开启动态拦截").fontColor('#FAAD14').fontSize(12).fontWeight(FontWeight.Medium)
            }.padding({left: 8, right: 10, top: 4, bottom: 4}).backgroundColor('#FFFBE6').borderRadius(12)
          }.width('100%').justifyContent(FlexAlign.End).margin({top: 16})

        }
        .width('100%').backgroundColor('#FFFFFF').padding(24).borderRadius(24).alignItems(HorizontalAlign.Start)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 })

      }.padding(20).alignItems(HorizontalAlign.Start).width('100%')
    }
  }
}

// 提取的子组件：高频动态频柱
@Component
struct HighFreqBar {
  @Prop val: number;

  // 根据数值动态计算颜色等级：极高为红，中高为黄，正常为蓝
  get barColor(): string {
    if (this.val > 85) return '#FF4D4F'; // 爆红预警
    if (this.val > 65) return '#FAAD14'; // 橙黄警告
    return '#1677FF'; // 正常蓝色
  }

  build() {
    Column() {
      Row()
        .width('100%')
        .height(`${Math.max(this.val, 5)}%`) // 保底5%高度
        .backgroundColor(this.barColor)
        .borderRadius({ topLeft: 4, topRight: 4 })
        // 添加轻微的发光阴影提升高级感
        .shadow({ radius: 6, color: `${this.barColor}66`, offsetY: 2 })
    }.height('100%').layoutWeight(1).justifyContent(FlexAlign.End)
  }
}