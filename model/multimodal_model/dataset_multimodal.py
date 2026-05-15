import torch
from torch.utils.data import Dataset
import pandas as pd

# 模块化引入单模态的预处理器 (跨包调用、实现逻辑复用)
from ..single_models.audio.dataset_audio import AudioPreprocessor
from ..single_models.vib.dataset_vib import VibPreprocessor
from ..single_models.temp.dataset_temp import TempPreprocessor

class IndustrialMultiModalDataset(Dataset):
    def __init__(self, metadata_csv=None, is_train=True):
        """
        多模态数据集采集器，负责对齐工业边缘网关传入的时序特征对
        """
        self.is_train = is_train
        if metadata_csv:
            self.data_frame = pd.read_csv(metadata_csv)
        else:
            self.data_frame = None

        # 实例化从单模态拿来的基础处理工具类
        self.audio_processor = AudioPreprocessor(is_train)
        self.vib_processor = VibPreprocessor(is_train)
        self.temp_processor = TempPreprocessor(is_train)

    def __len__(self):
        return len(self.data_frame) if self.data_frame is not None else 100

    def __getitem__(self, idx):
        if self.data_frame is not None:
            row = self.data_frame.iloc[idx]
            
            # 使用高内聚的预处理逻辑清洗数据
            audio = self.audio_processor.process(audio_path=row['audio_path'])
            vibration = self.vib_processor.process(vib_path=row['vib_path'])
            temp = self.temp_processor.process(seq_path=row['temp_path'])
            
            label_class = torch.tensor(row['fault_class'], dtype=torch.long)
            health_score = torch.tensor(row['health_score'], dtype=torch.float32)
        else:
            # 假张量生成，跑通开发管线验证
            audio = self.audio_processor.process()
            vibration = self.vib_processor.process()
            temp = self.temp_processor.process()
            label_class = torch.tensor(torch.randint(0, 4, (1,)).item(), dtype=torch.long)
            health_score = torch.tensor(torch.rand(1).item(), dtype=torch.float32)
            
        return audio, vibration, temp, label_class, health_score
