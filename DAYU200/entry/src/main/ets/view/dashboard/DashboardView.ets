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

        // 大面积留白的苹果风主健康卡片 (当前选中设备的健康度)
        Column() {
           Text("当前单点节点画像").fontSize(18).fontWeight(FontWeight.Medium).fontColor('#1C1C1E').margin({bottom: 30})
           
           Stack() {
              Progress({ value: this.healthScore, total: 100, type: ProgressType.Ring })
                .width(190)
                .color(this.statusColor)
                .style({ strokeWidth: 15 })
              
              Column() {
                Text(`${this.healthScore}`)
                  .fontSize(68).fontWeight(FontWeight.Bold).fontColor('#1C1C1E').fontFamily('Helvetica')
                Text("分").fontSize(15).fontColor('#8E8E93')
              }
           }
           Text(this.systemStatus).fontSize(16).fontColor(this.statusColor).margin({ top: 20 }).fontWeight(FontWeight.Medium)
           Text(`${this.alertLabel} · ${this.classLabel}`).fontSize(13).fontColor('#8E8E93').margin({ top: 8 })
         }
        .width('100%').padding(40).backgroundColor('#FFFFFF').borderRadius(24)
        .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 }).margin({bottom: 16})

        // 物理设备实时工况参数面板
        Column() {
           Text("外围部件瞬态感知").fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1C1C1E').margin({bottom: 20})
           
           this.InfoRow("主轴马达转矩转速", `${this.motorRpm} RPM`, this.healthScore < 60 ? '#FF3B30' : '#1C1C1E')
           Divider().strokeWidth(1).color('#F2F2F7').margin({top:14, bottom:14})
           this.InfoRow("机舱全密闭环境温湿", `${this.motorTemp.toFixed(1)}°C / ${this.envHumidity}%RH`, this.motorTemp > 75 ? '#FF9500' : '#8E8E93')
        }
        .width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24).alignItems(HorizontalAlign.Start)
        .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 }).margin({bottom: 16})

        // 微处理节点信息详情面板
        Column() {
           Text("星闪算力端通信参数").fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1C1C1E').margin({bottom: 20})
           
            this.InfoRow("处理分发框架", "Ascend CoreNPU")
            Divider().strokeWidth(1).color('#F2F2F7').margin({top:14, bottom:14})
            this.InfoRow("模型诊断标签", this.classLabel, this.statusColor)
            Divider().strokeWidth(1).color('#F2F2F7').margin({top:14, bottom:14})
            this.InfoRow("边缘握手层指令时延", `${this.nearlinkLatency.toFixed(1)} 毫秒`, this.nearlinkLatency > 1.2 ? '#FF9500' : '#8E8E93')
            Divider().strokeWidth(1).color('#F2F2F7').margin({top:14, bottom:14})
            this.InfoRow("硅片光刻核温感知", `${this.edgeTemp.toFixed(1)} °C`, this.edgeTemp > 43 ? '#FF3B30' : '#8E8E93')
        }
        .width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24).alignItems(HorizontalAlign.Start)
        .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 }).margin({bottom: 20})
        
      }.width('100%').padding(20)
    }
  }

  @Builder InfoRow(label: string, value: string, valColor: string = '#1C1C1E') {
    Row() {
      Text(label).fontColor('#8E8E93').fontSize(16).fontWeight(FontWeight.Medium)
      Blank()
      Text(value).fontColor(valColor).fontSize(16).fontWeight(FontWeight.Medium)
    }.width('100%')
  }
}
