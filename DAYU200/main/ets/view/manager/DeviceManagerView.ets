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
  @State isChecking: boolean = false;
  @State checkResult: string = "";
  
  build() {
    Scroll() {
      Column({space: 16}) {
        // AI 体检卡片
        Column() {
           Text("智能全模态体检").fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1C1C1E').margin({bottom: 10})
           Text("由昇腾处理器提供算力，深度侦测内部件不可见磨损及性能状态。").fontSize(14).fontColor('#8E8E93').margin({bottom: 24}).lineHeight(20)
           
           Button(this.isChecking ? "底盘诊断与特征映射中..." : "一键体检")
             .width('100%')
             .height(55)
             .backgroundColor(this.isChecking ? '#E5E5EA' : '#007AFF')
             .fontColor(this.isChecking ? '#8E8E93' : '#FFFFFF')
             .fontWeight(FontWeight.Bold)
             .borderRadius(16)
             .onClick(() => {
                if(this.isChecking) return;
                this.isChecking = true;
                this.checkResult = "";
                setTimeout(() => {
                   this.isChecking = false;
                    this.checkResult = this.diagnosisSummary;
                 }, 2000);
              })

            if (this.checkResult !== "") {
               Text(this.checkResult).fontSize(13).fontColor(this.statusColor).fontWeight(FontWeight.Bold).margin({top: 16})
            }

            Text(`当前模型标签：${this.classLabel} / ${this.alertLabel}`).fontSize(13).fontColor('#8E8E93').margin({top: 12})

         }.width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24).alignItems(HorizontalAlign.Start)
          .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })

        // 寿命预测卡片
        Column() {
           Text("可用周期预判").fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1C1C1E').margin({bottom: 24})
           
            Row() {
               Column() {
                  Text("核心组件剩余期限").fontSize(13).fontColor('#8E8E93').margin({bottom:8})
                  Text(this.remainingLifeDays > 0 ? `${this.remainingLifeDays} 天` : "评估中").fontSize(26).fontColor('#1C1C1E').fontWeight(FontWeight.Bold)
               }.alignItems(HorizontalAlign.Start).layoutWeight(1)
               
               Column() {
                  Text("建议阻断保养节点").fontSize(13).fontColor('#8E8E93').margin({bottom:8})
                  Text(this.maintenanceDueText).fontSize(26).fontColor('#1C1C1E').fontWeight(FontWeight.Bold)
               }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            }.width('100%')

            Text(this.maintenanceAdvice).fontSize(14).fontColor('#8E8E93').lineHeight(20).margin({top: 18})
        }.width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24).alignItems(HorizontalAlign.Start)
          .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })

        // 快捷控制指令
        Column() {
           Text("设备快捷干预终端").fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1C1C1E').margin({bottom: 24})
           
           Row({space: 12}) {
             Button("平滑降力运作")
               .layoutWeight(1)
               .height(50)
               .backgroundColor('#FFF5E5')
               .fontColor('#FF9500')
               .fontWeight(FontWeight.Medium)
               .borderRadius(16)
               .onClick(() => { deviceService.submitLogAction("指令透传：机组转入降力阻断模式持续30m"); })
             
             Button("物理急停控制")
               .layoutWeight(1)
               .height(50)
               .backgroundColor('#FFEBEA')
               .fontColor('#FF3B30')
               .fontWeight(FontWeight.Medium)
               .borderRadius(16)
               .onClick(() => { deviceService.submitLogAction("🚨 全局红牌告警：客户端已触发红色紧急按钮物理关停！"); })
           }.width('100%').margin({bottom: 12})
           
           Button("提交维护工单至后端组")
              .width('100%')
              .height(50)
              .backgroundColor('#E8F2FF')
              .fontColor('#007AFF')
              .fontWeight(FontWeight.Medium)
              .borderRadius(16)
              .onClick(() => { deviceService.submitLogAction("ERP协测：维保急报已经推送至云端审批管道"); })
        }.width('100%').padding(24).backgroundColor('#FFFFFF').borderRadius(24).alignItems(HorizontalAlign.Start)
         .shadow({ radius: 15, color: 'rgba(0,0,0,0.03)', offsetY: 6 })

      }.width('100%').padding(20)
    }
  }
}
