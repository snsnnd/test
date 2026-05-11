@Component
export struct DashboardView {
  @StorageLink('healthScore') healthScore: number = 98;
  @StorageLink('systemStatus') systemStatus: string = '';
  @StorageLink('statusColor') statusColor: string = '#34C759';
  @StorageLink('nearlinkLatency') nearlinkLatency: number = 0.0;
  @StorageLink('classLabel') classLabel: string = '待判定';
  @StorageLink('alertLabel') alertLabel: string = '绿区监测';
  @StorageLink('motorRpm') motorRpm: number = 0;
  @StorageLink('accDataX') accX: number = 0;
  @StorageLink('accDataY') accY: number = 0;
  @StorageLink('accDataZ') accZ: number = 9.81;
  @StorageLink('connectedSources') connectedSources: number = 0;
  @StorageLink('activeAlerts') activeAlerts: number = 0;
  @StorageLink('currentInferenceMs') currentInferenceMs: number = 0;
  @StorageLink('currentTotalMs') currentTotalMs: number = 0;
  @StorageLink('currentFps') currentFps: number = 0;
  @StorageLink('averageFps') averageFps: number = 0;

  private getZDynamic(): number {
    return this.accZ - 9.81;
  }

  private getVibrationMagnitude(): number {
    let zDynamic = this.getZDynamic();
    return Math.sqrt(this.accX * this.accX + this.accY * this.accY + zDynamic * zDynamic);
  }

  private getVibrationColor(): string {
    let magnitude = this.getVibrationMagnitude();
    if (magnitude > 2.5) {
      return '#FF4D4F';
    }
    if (magnitude > 1.2) {
      return '#FAAD14';
    }
    return this.statusColor;
  }

  private getVibrationText(): string {
    let magnitude = this.getVibrationMagnitude();
    if (magnitude > 2.5) {
      return '异常扰动';
    }
    if (magnitude > 1.2) {
      return '轻微波动';
    }
    return '稳定波段';
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          Text('当前单点节点画像')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily('HarmonyOS Sans')
            .fontColor('#191C1F')
            .margin({ bottom: 30 })

          Stack() {
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
              Text('分').fontSize(15).fontColor('#8A8F99')
            }
          }

          Row() {
            Circle({ width: 8, height: 8 }).fill(this.statusColor).margin({ right: 8 })
            Text(this.systemStatus).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.statusColor)
          }
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .backgroundColor(`${this.statusColor}1A`)
          .borderRadius(16)
          .margin({ top: 24 })

          Text(`${this.alertLabel} · ${this.classLabel}`)
            .fontSize(13)
            .fontColor('#8A8F99')
            .margin({ top: 12 })
        }
        .width('100%')
        .padding(32)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 })
        .margin({ bottom: 16 })
        .stateStyles({
          pressed: { .scale({ x: 0.98, y: 0.98 }) },
          normal: { .scale({ x: 1, y: 1 }) }
        })
        .animation({ duration: 300, curve: Curve.Friction })

        Column() {
          Text('设备实时状态')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#191C1F')
            .margin({ bottom: 20 })

          this.InfoRow('转速估算', `${this.motorRpm} RPM`, this.healthScore < 60 ? '#FF4D4F' : '#191C1F')
          Divider().strokeWidth(1).color('#F4F5F7').margin({ top: 14, bottom: 14 })
          this.InfoRow('三轴合成扰动', `${this.getVibrationMagnitude().toFixed(2)} g · ${this.getVibrationText()}`, this.getVibrationColor())
          Divider().strokeWidth(1).color('#F4F5F7').margin({ top: 14, bottom: 14 })
          this.InfoRow('连接节点数', `${this.connectedSources}`, '#8A8F99')
          Divider().strokeWidth(1).color('#F4F5F7').margin({ top: 14, bottom: 14 })
          this.InfoRow('活跃告警数', `${this.activeAlerts}`, this.activeAlerts > 0 ? '#FF4D4F' : '#8A8F99')
        }
        .width('100%')
        .padding(24)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .alignItems(HorizontalAlign.Start)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 })
        .margin({ bottom: 16 })
        .stateStyles({
          pressed: { .scale({ x: 0.98, y: 0.98 }) },
          normal: { .scale({ x: 1, y: 1 }) }
        })
        .animation({ duration: 300, curve: Curve.Friction })

        Column() {
          Text('模型推理与通信状态')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#191C1F')
            .margin({ bottom: 20 })

          this.InfoRow('模型诊断标签', this.classLabel, this.statusColor)
          Divider().strokeWidth(1).color('#F4F5F7').margin({ top: 14, bottom: 14 })
          this.InfoRow('单帧推理耗时', `${this.currentInferenceMs.toFixed(1)} ms`, this.currentInferenceMs > 20 ? '#FAAD14' : '#8A8F99')
          Divider().strokeWidth(1).color('#F4F5F7').margin({ top: 14, bottom: 14 })
          this.InfoRow('端到端处理耗时', `${this.currentTotalMs.toFixed(1)} ms`, this.currentTotalMs > 30 ? '#FAAD14' : '#8A8F99')
          Divider().strokeWidth(1).color('#F4F5F7').margin({ top: 14, bottom: 14 })
          this.InfoRow('当前 / 平均 FPS', `${this.currentFps.toFixed(1)} / ${this.averageFps.toFixed(1)}`, '#8A8F99')
        }
        .width('100%')
        .padding(24)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .alignItems(HorizontalAlign.Start)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 })
        .margin({ bottom: 20 })
        .stateStyles({
          pressed: { .scale({ x: 0.98, y: 0.98 }) },
          normal: { .scale({ x: 1, y: 1 }) }
        })
        .animation({ duration: 300, curve: Curve.Friction })
      }
      .width('100%')
      .padding(20)
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
