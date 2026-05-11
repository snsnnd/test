import { deviceService } from '../../api/ServiceLocator';

@Component
export struct DeviceManagerView {
  @StorageLink('healthScore') healthScore: number = 98;
  @StorageLink('diagnosisSummary') diagnosisSummary: string = '等待模型输出';
  @StorageLink('remainingLifeDays') remainingLifeDays: number = 0;
  @StorageLink('maintenanceDueText') maintenanceDueText: string = '--';
  @StorageLink('maintenanceAdvice') maintenanceAdvice: string = '等待模型输出';
  @StorageLink('classLabel') classLabel: string = '待判定';
  @StorageLink('alertLabel') alertLabel: string = '绿区监测';
  @StorageLink('statusColor') statusColor: string = '#34C759';
  @StorageLink('currentInferenceMs') currentInferenceMs: number = 0;
  @StorageLink('averageFps') averageFps: number = 0;
  @StorageLink('activeAlerts') activeAlerts: number = 0;
  @State isChecking: boolean = false;
  @State checkResult: string = '';

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Column() {
          Text('模型诊断快照')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1C1C1E')
            .margin({ bottom: 10 })
          Text('展示后端模型当前诊断摘要、告警标签与推理状态；本页不直接执行停机或物理控制。')
            .fontSize(14)
            .fontColor('#8E8E93')
            .margin({ bottom: 24 })
            .lineHeight(20)

          Button(this.isChecking ? '正在读取后端诊断快照...' : '刷新诊断快照')
            .width('100%')
            .height(55)
            .backgroundColor(this.isChecking ? '#E5E5EA' : '#007AFF')
            .fontColor(this.isChecking ? '#8E8E93' : '#FFFFFF')
            .fontWeight(FontWeight.Bold)
            .borderRadius(16)
            .onClick(() => {
              if (this.isChecking) {
                return;
              }
              this.isChecking = true;
              this.checkResult = '';
              setTimeout(() => {
                this.isChecking = false;
                this.checkResult = this.diagnosisSummary;
                deviceService.submitLogAction(`诊断快照刷新：${this.classLabel} / ${this.alertLabel} / 健康度=${this.healthScore}`);
              }, 600);
            })

          if (this.checkResult !== '') {
            Text(this.checkResult)
              .fontSize(13)
              .fontColor(this.statusColor)
              .fontWeight(FontWeight.Bold)
              .margin({ top: 16 })
          }

          Text(`当前模型标签：${this.classLabel} / ${this.alertLabel}`)
            .fontSize(13)
            .fontColor('#8E8E93')
            .margin({ top: 12 })
        }
        .width('100%')
        .padding(24)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .alignItems(HorizontalAlign.Start)
        .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })

        Column() {
          Text('维护建议')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1C1C1E')
            .margin({ bottom: 24 })

          Row() {
            Column() {
              Text('估算可用周期')
                .fontSize(13)
                .fontColor('#8E8E93')
                .margin({ bottom: 8 })
              Text(this.remainingLifeDays > 0 ? `${this.remainingLifeDays} 天` : '评估中')
                .fontSize(26)
                .fontColor('#1C1C1E')
                .fontWeight(FontWeight.Bold)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)

            Column() {
              Text('建议处理窗口')
                .fontSize(13)
                .fontColor('#8E8E93')
                .margin({ bottom: 8 })
              Text(this.maintenanceDueText)
                .fontSize(26)
                .fontColor('#1C1C1E')
                .fontWeight(FontWeight.Bold)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }.width('100%')

          Text(this.maintenanceAdvice)
            .fontSize(14)
            .fontColor('#8E8E93')
            .lineHeight(20)
            .margin({ top: 18 })
        }
        .width('100%')
        .padding(24)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .alignItems(HorizontalAlign.Start)
        .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })

        Column() {
          Text('后端记录操作')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1C1C1E')
            .margin({ bottom: 12 })
          Text('以下按钮只向后端审计日志写入建议，不代表已经完成物理降载、急停或 ERP 工单流转。')
            .fontSize(13)
            .fontColor('#8E8E93')
            .lineHeight(18)
            .margin({ bottom: 20 })

          Row({ space: 12 }) {
            Button('记录降载建议')
              .layoutWeight(1)
              .height(50)
              .backgroundColor('#FFF5E5')
              .fontColor('#FF9500')
              .fontWeight(FontWeight.Medium)
              .borderRadius(16)
              .onClick(() => {
                deviceService.submitLogAction(`维护建议记录：建议对当前设备进行降载观察，模型标签=${this.classLabel}`);
              })

            Button('记录高风险提醒')
              .layoutWeight(1)
              .height(50)
              .backgroundColor('#FFEBEA')
              .fontColor('#FF3B30')
              .fontWeight(FontWeight.Medium)
              .borderRadius(16)
              .onClick(() => {
                deviceService.submitLogAction(`高风险提醒记录：当前告警=${this.alertLabel}，活跃告警数=${this.activeAlerts}`);
              })
          }.width('100%').margin({ bottom: 12 })

          Button('记录维护建议摘要')
            .width('100%')
            .height(50)
            .backgroundColor('#E8F2FF')
            .fontColor('#007AFF')
            .fontWeight(FontWeight.Medium)
            .borderRadius(16)
            .onClick(() => {
              deviceService.submitLogAction(`维护建议摘要：${this.maintenanceAdvice}；推理=${this.currentInferenceMs.toFixed(1)}ms，平均FPS=${this.averageFps.toFixed(1)}`);
            })
        }
        .width('100%')
        .padding(24)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .alignItems(HorizontalAlign.Start)
        .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })
      }
      .width('100%')
      .padding(20)
    }
  }
}
