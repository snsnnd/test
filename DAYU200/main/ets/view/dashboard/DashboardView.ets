@Component
export struct DashboardView {
  @StorageLink('healthScore') healthScore: number = 98;
  @StorageLink('systemStatus') systemStatus: string = '';
  @StorageLink('statusColor') statusColor: string = '#34C759';
  @StorageLink('nearlinkLatency') nearlinkLatency: number = 1.0;
  @StorageLink('edgeTemp') edgeTemp: number = 42.0;
  @StorageLink('classLabel') classLabel: string = '待判定';
  @StorageLink('alertLabel') alertLabel: string = '绿区监测';

  @StorageLink('motorTemp') motorTemp: number = 56.4;
  @StorageLink('motorRpm') motorRpm: number = 1450;
  @StorageLink('envHumidity') envHumidity: number = 45;

  build() {
    Scroll() {
      Column() {
        // 1. 大面积留白的主健康卡片
        Column() {
           Text("当前单点节点画像")
             .fontSize(18)
             .fontWeight(FontWeight.Bold)
             .fontFamily('HarmonyOS Sans')
             .fontColor('#191C1F')
             .margin({bottom: 30})
           
           Stack() {
              // 添加动画属性，使进度条改变时具有平滑过渡
              Progress({ value: this.healthScore, total: 100, type: ProgressType.Ring })
                .width(190)
                .color(this.statusColor)
                .style({ strokeWidth: 15 })
                .animation({ duration: 800, curve: Curve.FastOutSlowIn })
              
              Column() {
                Text(`${this.healthScore}`)
                  .fontSize(68)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#191C1F')
                  .fontFamily('HarmonyOS Sans')
                Text("分").fontSize(15).fontColor('#8A8F99')
              }
           }
           
           // 专业级状态徽章 (替代单纯的文本)
           Row() {
              Circle({ width: 8, height: 8 }).fill(this.statusColor).margin({ right: 8 })
              Text(this.systemStatus).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.statusColor)
           }
           .padding({ left: 12, right: 16, top: 6, bottom: 6 })
           .backgroundColor(`${this.statusColor}1A`) // 1A 表示 10% 透明度的柔和底色
           .borderRadius(16)
           .margin({ top: 24 })

           Text(`${this.alertLabel} · ${this.classLabel}`)
             .fontSize(13)
             .fontColor('#8A8F99')
             .margin({ top: 12 })
         }
        .width('100%').padding(32).backgroundColor('#FFFFFF').borderRadius(24)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 }).margin({bottom: 16})
        .stateStyles({
          pressed: { .scale({ x: 0.98, y: 0.98 }) },
          normal: { .scale({ x: 1, y: 1 }) }
        })
        .animation({ duration: 300, curve: Curve.Friction })

        // 2. 物理设备实时工况参数面板
        Column() {
           Text("外围部件瞬态感知").fontSize(18).fontWeight(FontWeight.Bold).fontColor('#191C1F').margin({bottom: 20})
           
           this.InfoRow("主轴马达转矩转速", `${this.motorRpm} RPM`, this.healthScore < 60 ? '#FF4D4F' : '#191C1F')
           Divider().strokeWidth(1).color('#F4F5F7').margin({top:14, bottom:14})
           this.InfoRow("机舱全密闭环境温湿", `${this.motorTemp.toFixed(1)}°C / ${this.envHumidity}%RH`, this.motorTemp > 75 ? '#FAAD14' : '#8A8F99')
        }
        .width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24).alignItems(HorizontalAlign.Start)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 }).margin({bottom: 16})
        .stateStyles({
          pressed: { .scale({ x: 0.98, y: 0.98 }) },
          normal: { .scale({ x: 1, y: 1 }) }
        })
        .animation({ duration: 300, curve: Curve.Friction })

        // 3. 微处理节点信息详情面板
        Column() {
           Text("星闪算力端通信参数").fontSize(18).fontWeight(FontWeight.Bold).fontColor('#191C1F').margin({bottom: 20})
           
            this.InfoRow("处理分发框架", "Ascend CoreNPU")
            Divider().strokeWidth(1).color('#F4F5F7').margin({top:14, bottom:14})
            this.InfoRow("模型诊断标签", this.classLabel, this.statusColor)
            Divider().strokeWidth(1).color('#F4F5F7').margin({top:14, bottom:14})
            this.InfoRow("边缘握手层指令时延", `${this.nearlinkLatency.toFixed(1)} ms`, this.nearlinkLatency > 1.2 ? '#FAAD14' : '#8A8F99')
            Divider().strokeWidth(1).color('#F4F5F7').margin({top:14, bottom:14})
            this.InfoRow("硅片光刻核温感知", `${this.edgeTemp.toFixed(1)} °C`, this.edgeTemp > 43 ? '#FF4D4F' : '#8A8F99')
        }
        .width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24).alignItems(HorizontalAlign.Start)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 }).margin({bottom: 20})
        .stateStyles({
          pressed: { .scale({ x: 0.98, y: 0.98 }) },
          normal: { .scale({ x: 1, y: 1 }) }
        })
        .animation({ duration: 300, curve: Curve.Friction })
        
      }.width('100%').padding(20)
    }
  }

  @Builder InfoRow(label: string, value: string, valColor: string = '#191C1F') {
    Row() {
      Text(label).fontColor('#8A8F99').fontSize(15).fontWeight(FontWeight.Medium)
      Blank()
      Text(value).fontColor(valColor).fontSize(15).fontWeight(FontWeight.Medium).fontFamily('HarmonyOS Sans')
    }.width('100%')
  }
}