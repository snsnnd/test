import torch
import os
from .fusion_model import LateFusionHybridModel

def create_ascend_compatible_onnx(save_path="ascend_industrial_hybrid.onnx"):
    print("==================================================")
    print("💠 [昇腾芯片适配预压机制] 开始进入 ONNX 网络图结构导出...")
    print("==================================================")
    
    model = LateFusionHybridModel(num_classes=3)
    
    # 加载刚刚训练好的全量融合模型权重 (包含训练过的 Transformer 部分)
    fusion_weights = "d:/deveco-studio/model/multimodal_model/multimodal_fusion.pth"
    if os.path.exists(fusion_weights):
        model.load_state_dict(torch.load(fusion_weights, map_location='cpu'))
        print("💎 [Success] 已载入训练好的 1.0 F1 级多模态全量融合权重")
    else:
        print("⚠️ [Warning] 未找到全量权重，将使用随机初始化的 Fusion 层进行导出")
        
    model.eval()

    # 全静态 batch=1 输入（方案A：ATC 兼容性最强、边缘推理延迟最低）
    dummy_audio = torch.randn(1, 1, 64, 200)
    dummy_vibration = torch.randn(1, 3, 2000)
    dummy_temp = torch.randn(1, 1, 60) # 替换原来的 vision (224x224 RGB image) 成为高效的一维序列

    torch.onnx.export(
        model, 
        (dummy_audio, dummy_vibration, dummy_temp), 
        save_path,
        export_params=True,
        opset_version=14,               # Opset 14 对于部分 LayerNorm 具有更好的后端底层算子支持
        do_constant_folding=True,
        input_names=['input_audio', 'input_vibration', 'input_temp'],
        output_names=['out_classification', 'out_regression'],
        # 方案A：不设置 dynamic_axes，导出纯静态 shape
        # 边缘端推理场景为逐条处理 (batch=1)，无需动态 batch
    )
    
    # 导出后执行基本合规性校验
    try:
        import onnx
        from onnx import checker
        model_proto = onnx.load(save_path)
        checker.check_model(model_proto)
        print("✅ ONNX 合规性校验通过")
    except ImportError:
        print("⚠️ 未安装 onnx 包，跳过合规性校验（pip install onnx）")
    except Exception as e:
        print(f"❌ ONNX 校验异常: {e}")

    print(f"✅ ONNX 模型静态网络图已安全落地至 -> {save_path}")
    print("\n[ATC 转换指令（方案A：纯静态，无需动态参数）]")
    print("请使用终端连入编译环境后，执行：")
    print(f"atc --model={save_path} --framework=5 --output=ascend_deploy_model --soc_version=Ascend310")
    print("\n[可选] 使用 onnxsim 简化导出图，提升 ATC 转换成功率：")
    print(f"python -m onnxsim {save_path} {save_path.replace('.onnx', '_sim.onnx')}")

if __name__ == "__main__":
    create_ascend_compatible_onnx()
