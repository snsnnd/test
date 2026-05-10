@Component
export struct SensorsMonitorView {
  @StorageLink('audioSpectrum') audioSpectrum: number[] = [12, 45, 60, 30, 80, 55, 20, 15, 65, 40, 25, 70, 50, 10];
  @StorageLink('accDataX') accX: number = 0.5;
  @StorageLink('accDataY') accY: number = -1.2;
  @StorageLink('accDataZ') accZ: number = 9.81;
  @StorageLink('tempHistory') tempHistory: number[] = [42, 43.5, 45, 48, 52, 56, 59, 58, 61, 62];
  @StorageLink('statusColor') statusColor: string = '#52C41A';

  // 用于能量分布可视化的权重模板；实际高度由实时三轴振动强度驱动，不再作为伪 FFT 使用。
  private energyDistributionTemplate: number[] = [0.38, 0.52, 0.71, 0.88, 1.00, 0.76, 0.58, 0.82, 0.64, 0.47, 0.55, 0.34];

  private getZDynamic(): number {
    return this.accZ - 9.81;
  }

  private getVibrationMagnitude(): number {
    let zDynamic = this.getZDynamic();
    return Math.sqrt(this.accX * this.accX + this.accY * this.accY + zDynamic * zDynamic);
  }

  private getVibrationStateText(): string {
    let magnitude = this.getVibrationMagnitude();
    if (magnitude > 2.5) {
      return '异常扰动';
    }
    if (magnitude > 1.2) {
      return '轻微波动';
    }
    return '稳定波段';
  }

  private getVibrationStateColor(): string {
    let magnitude = this.getVibrationMagnitude();
    if (magnitude > 2.5) {
      return '#FF4D4F';
    }
    if (magnitude > 1.2) {
      return '#FAAD14';
    }
    return this.statusColor;
  }

  private calcEnergyBarHeight(weight: number, index: number): number {
    let magnitude = this.getVibrationMagnitude();
    let axisBias = index % 3 === 0 ? Math.abs(this.accX) : (index % 3 === 1 ? Math.abs(this.accY) : Math.abs(this.getZDynamic()));
    let height = 18 + weight * 48 + magnitude * 13 + axisBias * 10;
    return Math.min(Math.max(height, 8), 100);
  }

  private getEnergyBarColor(height: number): string {
    if (height > 85) {
      return '#FF4D4F';
    }
    if (height > 65) {
      return '#FAAD14';
    }
    return this.getVibrationStateColor();
  }

  private getLatestTemperature(): number {
    if (this.tempHistory.length === 0) {
      return 0;
    }
    return this.tempHistory[this.tempHistory.length - 1];
  }

  private getAudioPeak(): number {
    if (this.audioSpectrum.length === 0) {
      return 0;
    }
    let peak = 0;
    for (let i = 0; i < this.audioSpectrum.length; i++) {
      peak = Math.max(peak, this.audioSpectrum[i]);
    }
    return peak;
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        // ==========================================
        // 1. 振荡捕捉：真实三轴遥测 + 动态能量分布
        // ==========================================
        Column() {
          Row() {
            Text('切脉：三轴振动实时感知')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontFamily('HarmonyOS Sans')
              .fontColor('#191C1F')
            Blank()
            Row() {
              Circle({ width: 6, height: 6 })
                .fill(this.getVibrationStateColor())
                .margin({ right: 4 })
              Text(this.getVibrationStateText())
                .fontSize(12)
                .fontColor(this.getVibrationStateColor())
                .fontWeight(FontWeight.Medium)
            }
            .padding({ left: 8, right: 10, top: 4, bottom: 4 })
            .backgroundColor(`${this.getVibrationStateColor()}1A`)
            .borderRadius(12)
          }
          .width('100%')
          .margin({ bottom: 24 })

          TelemetryBarView({ name: 'X 轴水平扰动', val: this.accX, barThemeColor: '#1677FF' })
          Divider().strokeWidth(1).color('#F4F5F7').margin({ top: 16, bottom: 16 })
          TelemetryBarView({ name: 'Y 轴纵向扰动', val: this.accY, barThemeColor: '#722ED1' })
          Divider().strokeWidth(1).color('#F4F5F7').margin({ top: 16, bottom: 16 })
          TelemetryBarView({ name: 'Z 轴重力偏移', val: this.getZDynamic(), barThemeColor: '#FAAD14' })

          Text('三轴振动能量分布估算')
            .fontColor('#191C1F')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 24, bottom: 6 })

          Text('由 X/Y/Z 三轴实时加速度合成扰动强度，并按能量权重映射为动态柱状图')
            .fontColor('#8A8F99')
            .fontSize(11)
            .lineHeight(16)
            .margin({ bottom: 14 })

          Row({ space: 4 }) {
            ForEach(this.energyDistributionTemplate, (weight: number, idx: number) => {
              Column() {
                Row()
                  .width('100%')
                  .height(`${this.calcEnergyBarHeight(weight, idx)}%`)
                  .backgroundColor(this.getEnergyBarColor(this.calcEnergyBarHeight(weight, idx)))
                  .borderRadius({ topLeft: 4, topRight: 4 })
                  .opacity(0.88)
                  .animation({ duration: 500, curve: Curve.FastOutSlowIn })
              }
              .layoutWeight(1)
              .height('100%')
              .justifyContent(FlexAlign.End)
            }, (item: number, index: number) => index.toString())
          }
          .width('100%')
          .height(88)
          .backgroundColor('#F8F9FA')
          .padding(12)
          .borderRadius(12)

          Row() {
            Text(`合成扰动强度 ${this.getVibrationMagnitude().toFixed(2)} g`)
              .fontSize(12)
              .fontColor('#8A8F99')
            Blank()
            Text(`X ${this.accX.toFixed(2)} / Y ${this.accY.toFixed(2)} / ZΔ ${this.getZDynamic().toFixed(2)}`)
              .fontSize(12)
              .fontColor(this.getVibrationStateColor())
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .width('100%')
        .padding(24)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 })

        // ==========================================
        // 2. 声浪特征：后端 audioSpectrum 动态输入
        // ==========================================
        Column() {
          Row() {
            Text('听音：声纹能量谱')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontFamily('HarmonyOS Sans')
              .fontColor('#191C1F')
            Blank()
            Text(`峰值 ${this.getAudioPeak().toFixed(0)}`)
              .fontSize(12)
              .fontColor(this.getAudioPeak() > 85 ? '#FF4D4F' : (this.getAudioPeak() > 65 ? '#FAAD14' : '#1677FF'))
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
          .margin({ bottom: 6 })

          Text(`后端实时音频频带能量，当前 ${this.audioSpectrum.length} 个频带点`)
            .fontColor('#8A8F99')
            .fontSize(12)
            .margin({ bottom: 16 })

          Row({ space: 6 }) {
            ForEach(this.audioSpectrum, (val: number, idx: number) => {
              HighFreqBar({ val: val })
            }, (item: number, index: number) => index.toString())
          }
          .width('100%')
          .height(100)
          .backgroundColor('#F8F9FA')
          .padding(16)
          .borderRadius(16)

          Text('声纹能量包络')
            .fontColor('#191C1F')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 24, bottom: 4 })
          Text('用于观察设备运行声纹的能量起伏，不再作为独立低频底噪结论')
            .fontColor('#8A8F99')
            .fontSize(12)
            .margin({ bottom: 16 })

          Stack({ alignContent: Alignment.Bottom }) {
            Row({ space: 2 }) {
              ForEach(this.audioSpectrum, (val: number, idx: number) => {
                Column() {
                  Row()
                    .width('100%')
                    .height(`${Math.max(100 - val, 10)}%`)
                    .backgroundColor('#B7EB8F')
                    .borderRadius({ topLeft: 6, topRight: 6 })
                }
                .layoutWeight(1)
                .height('100%')
                .justifyContent(FlexAlign.End)
              }, (item: number, index: number) => index.toString())
            }
            .width('100%')
            .height('100%')
            Row().width('100%').height(2).backgroundColor('#52C41A').opacity(0.5)
          }
          .width('100%')
          .height(60)
          .backgroundColor('#F8F9FA')
          .padding({ left: 16, right: 16, top: 16 })
          .borderRadius(16)
          .clip(true)
        }
        .width('100%')
        .padding(24)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .alignItems(HorizontalAlign.Start)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 })

        // ==========================================
        // 3. 热力监测：后端 tempHistory 动态输入
        // ==========================================
        Column() {
          Row() {
            Text('诊热：温度时序趋势')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontFamily('HarmonyOS Sans')
              .fontColor('#191C1F')
            Blank()
            Text(this.tempHistory.length > 0 ? `当前 ${this.getLatestTemperature().toFixed(1)}°C` : '等待数据')
              .fontSize(16)
              .fontColor(this.getLatestTemperature() > 60 ? '#FF4D4F' : '#FAAD14')
              .fontWeight(FontWeight.Bold)
              .fontFamily('HarmonyOS Sans')
          }
          .width('100%')
          .margin({ bottom: 8 })

          Text(`后端温度序列样本点 ${this.tempHistory.length} 个，随设备采样窗口动态刷新`)
            .fontSize(12)
            .fontColor('#8A8F99')
            .margin({ bottom: 16 })

          Stack({ alignContent: Alignment.Bottom }) {
            Row()
              .width('100%')
              .height('100%')
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
              Circle({ width: 10, height: 10 })
                .fill('#FFFFFF')
                .stroke('#FF4D4F')
                .strokeWidth(3)
                .shadow({ radius: 8, color: 'rgba(255, 77, 79, 0.6)', offsetY: 0 })
                .position({
                  x: 280,
                  y: 120 - ((this.getLatestTemperature() - 40) * 4) - 5
                })
            }

            Stack({ alignContent: Alignment.End }) {
              Line().width('100%').height(1).backgroundColor('rgba(255, 77, 79, 0.4)').strokeDashArray([6, 4])
              Text('预警阈值 60°C')
                .fontSize(10)
                .fontColor('#FF4D4F')
                .backgroundColor('#FFF1F0')
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(4)
                .offset({ y: -10 })
            }
            .width('100%')
            .position({ x: 0, y: 120 - ((60 - 40) * 4) })
          }
          .width('100%')
          .height(120)
          .backgroundColor('#F8F9FA')
          .borderRadius(16)
          .clip(true)

          Row() {
            Text('数据源：后端 tempHistory 时序窗口')
              .fontSize(12)
              .fontColor('#8A8F99')
            Blank()
            Text(this.getLatestTemperature() > 60 ? '温升预警' : '温度可控')
              .fontSize(12)
              .fontColor(this.getLatestTemperature() > 60 ? '#FF4D4F' : '#52C41A')
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .width('100%')
        .padding(24)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .alignItems(HorizontalAlign.Start)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.04)', offsetY: 8 })
      }
      .width('100%')
      .padding({ top: 20, bottom: 40, left: 20, right: 20 })
    }
  }
}

@Component
struct TelemetryBarView {
  @Prop name: string;
  @Prop val: number;
  @Prop barThemeColor: string;
  maxG: number = 4.0;

  get percent(): number {
    return Math.min(Math.abs(this.val) / this.maxG, 1.0) * 50;
  }

  get isPositive(): boolean {
    return this.val >= 0;
  }

  get dynamicColor(): string {
    return Math.abs(this.val) > 2.5 ? '#FF4D4F' : this.barThemeColor;
  }

  build() {
    Row() {
      Text(this.name)
        .fontSize(14)
        .fontColor('#8A8F99')
        .width('25%')
        .fontWeight(FontWeight.Medium)

      Stack({ alignContent: Alignment.Center }) {
        Row().width('100%').height(6).backgroundColor('#E5E6EB').borderRadius(3)

        if (!this.isPositive) {
          Row() {
            Row()
              .width(`${this.percent}%`)
              .height(6)
              .backgroundColor(this.dynamicColor)
              .borderRadius({ topLeft: 3, bottomLeft: 3 })
              .shadow({ radius: 4, color: `${this.dynamicColor}4D`, offsetY: 0 })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ right: '50%' })
        }

        if (this.isPositive) {
          Row() {
            Row()
              .width(`${this.percent}%`)
              .height(6)
              .backgroundColor(this.dynamicColor)
              .borderRadius({ topRight: 3, bottomRight: 3 })
              .shadow({ radius: 4, color: `${this.dynamicColor}4D`, offsetY: 0 })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ left: '50%' })
        }

        Row().width(2).height(14).backgroundColor('#8A8F99').borderRadius(1)
      }
      .width('45%')
      .margin({ left: 10, right: 10 })
      .height(24)

      Text(`${this.val > 0 ? '+' : ''}${this.val.toFixed(2)} g`)
        .fontSize(15)
        .fontColor(this.dynamicColor)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .fontWeight(FontWeight.Bold)
        .fontFamily('HarmonyOS Sans')
    }
    .width('100%')
  }
}

@Component
struct HighFreqBar {
  @Prop val: number;

  get barColor(): string {
    if (this.val > 85) {
      return '#FF4D4F';
    }
    if (this.val > 65) {
      return '#FAAD14';
    }
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
    }
    .height('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.End)
  }
}
