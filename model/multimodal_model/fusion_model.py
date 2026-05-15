import torch
import torch.nn as nn
import math

from ..single_models.audio.audio_model import AudioBackbone
from ..single_models.vib.vib_model import VibBackbone
from ..single_models.temp.temp_model import TempBackbone

class PositionalEncoding(nn.Module):
    def __init__(self, d_model, max_len=5000):
        super().__init__()
        pe = torch.zeros(max_len, d_model)
        position = torch.arange(0, max_len, dtype=torch.float).unsqueeze(1)
        div_term = torch.exp(torch.arange(0, d_model, 2).float() * (-math.log(10000.0) / d_model))
        pe[:, 0::2] = torch.sin(position * div_term)
        pe[:, 1::2] = torch.cos(position * div_term)
        self.register_buffer('pe', pe.unsqueeze(0)) 

    def forward(self, x):
        # 固定序列长度: 1(cls) + 14(audio) + 100(vib) + 15(temp) = 130
        # 避免 x.size(1) 产生数据依赖的动态切片，确保 ONNX 图全静态化
        seq_len = 130
        return x + self.pe[:, :seq_len, :]

class LateFusionHybridModel(nn.Module):
    def __init__(self, num_classes=3, d_model=256, n_heads=8, n_layers=3):
        super().__init__()
        self.d_model = d_model
        
        # ==========================================
        # 1. 挂载抽离好的单模态特征提取主干 (不生成单模分类头)
        # ==========================================
        self.audio_backbone = AudioBackbone(num_classes=None, d_model=d_model)
        self.vib_backbone = VibBackbone(num_classes=None, d_model=d_model)
        self.temp_backbone = TempBackbone(num_classes=None, d_model=d_model)
        
        # ==========================================
        # 2. 多模态 Cross-Attention 融合池 (Transformer)
        # ==========================================
        self.cls_token = nn.Parameter(torch.randn(1, 1, d_model))
        self.pos_encoder = PositionalEncoding(d_model)
        self.modality_emb = nn.Parameter(torch.randn(3, d_model)) 
        
        encoder_layer = nn.TransformerEncoderLayer(d_model=d_model, nhead=n_heads, batch_first=True)
        self.transformer = nn.TransformerEncoder(encoder_layer, num_layers=n_layers)
        
        # ==========================================
        # 3. 推理双头 (回归算分 + 分类报障)
        # ==========================================
        self.classification_head = nn.Linear(d_model, num_classes)
        self.regression_head = nn.Linear(d_model, 1)

        # --- [智力注入] 尝试加载单模态预训练权重 ---
        self._load_pretrained_weights()

    def _load_pretrained_weights(self):
        # 修正为模块化后的正确路径
        weights_map = {
            "audio": "d:/deveco-studio/model/single_models/audio/audio_backbone_pretrained.pth",
            "vib": "d:/deveco-studio/model/single_models/vib/vib_pretrained.pth",
            "temp": "d:/deveco-studio/model/single_models/temp/temp_pretrained.pth"
        }
        
        # 1. 尝试加载听觉权重 (使用 strict=False 忽略预训练时的分类头)
        try:
            state_dict = torch.load(weights_map["audio"], map_location='cpu', weights_only=False)
            self.audio_backbone.load_state_dict(state_dict, strict=False)
            print("🔊 [Loading] 听觉分支预训练权重加载成功")
        except Exception as e:
            print(f"⚠️ [Skip] 听觉权重加载失败: {e}")

        # 2. 尝试加载振动权重
        try:
            state_dict = torch.load(weights_map["vib"], map_location='cpu', weights_only=False)
            self.vib_backbone.load_state_dict(state_dict, strict=False)
            print("📳 [Loading] 振动分支预训练权重加载成功")
        except Exception as e:
            print(f"⚠️ [Skip] 振动权重加载失败: {e}")

        # 3. 尝试加载热学权重
        try:
            state_dict = torch.load(weights_map["temp"], map_location='cpu', weights_only=False)
            self.temp_backbone.load_state_dict(state_dict, strict=False)
            print("🔥 [Loading] 热学分支预训练权重加载成功")
        except Exception as e:
            print(f"⚠️ [Skip] 热学权重加载失败: {e}")


    def forward(self, audio, vibration, temp):
        B = audio.size(0)
        
        # 提取各个模态的 Token 并附加 Modality Embedding
        a_tokens = self.audio_backbone(audio) + self.modality_emb[0]
        v_tokens = self.vib_backbone(vibration) + self.modality_emb[1]
        t_tokens = self.temp_backbone(temp) + self.modality_emb[2]
        
        # 全模态 Token 拼装序列
        cls_tokens = self.cls_token.expand(B, -1, -1)
        x = torch.cat([cls_tokens, a_tokens, v_tokens, t_tokens], dim=1) 
        
        # Transformer 注意力交叉验证与解耦计算
        x = self.pos_encoder(x)
        x = self.transformer(x)
        
        # 强制提取全局提纯的 CLS Token
        cls_out = x[:, 0, :] 
        
        # 数据分流给双任务预测头
        logits = self.classification_head(cls_out)
        health = torch.sigmoid(self.regression_head(cls_out)).reshape(-1)
        
        return logits, health
