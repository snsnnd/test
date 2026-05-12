import argparse
import json
import socket
import struct
import threading
import time
import traceback
from dataclasses import dataclass

import acl
import numpy as np

from master_control import (
    BridgeControlParser,
    LocalControlServer,
    build_select_target_frame,
)
from perf_metrics import PerfTracker


MODEL_PACKET_MAGIC = 0x4A53
MODEL_PACKET_VERSION = 1
MODEL_PACKET_TYPE_META = 1
MODEL_PACKET_TYPE_AUDIO = 2
MODEL_PACKET_TYPE_VIBRATION = 3
MODEL_PACKET_TYPE_TEMPERATURE = 4
MODEL_PACKET_TYPE_END = 5

MODEL_AUDIO_SAMPLES = 32000
MODEL_VIBRATION_CHANNELS = 3
MODEL_VIBRATION_SAMPLES = 2000
MODEL_TEMPERATURE_SAMPLES = 60

MODEL_PACKET_HEADER = struct.Struct("<HBBHHHH")
MODEL_META_STRUCT = struct.Struct("<HHIIIHHHBBBBBBBhhhhhh")


class Net:
    ACL_MEM_MALLOC_NORMAL_ONLY = 0
    ACL_MEMCPY_HOST_TO_DEVICE = 1
    ACL_MEMCPY_DEVICE_TO_HOST = 2
    ACL_FLOAT = 11

    def __init__(self, model_path, device_id=0):
        self.device_id = device_id
        self.released = False
        self.context = None
        self.stream = None
        self.model_id = None
        self.model_desc = None
        self.input_dataset = None
        self.output_dataset = None
        self.model_path = model_path
        self.input_buffers = []
        self.output_buffers = []

        self._init_acl()
        self._load_model()
        self._alloc_model_io()

    @staticmethod
    def _check_ret(ret, message):
        if ret != 0:
            raise RuntimeError(f"{message} failed, ret={ret}")

    def _init_acl(self):
        ret = acl.init()
        self._check_ret(ret, "acl.init")

        ret = acl.rt.set_device(self.device_id)
        self._check_ret(ret, "acl.rt.set_device")

        self.context, ret = acl.rt.create_context(self.device_id)
        self._check_ret(ret, "acl.rt.create_context")

        if hasattr(acl.rt, "set_context"):
            ret = acl.rt.set_context(self.context)
            self._check_ret(ret, "acl.rt.set_context")

        self.stream, ret = acl.rt.create_stream()
        self._check_ret(ret, "acl.rt.create_stream")

    def _load_model(self):
        self.model_id, ret = acl.mdl.load_from_file(self.model_path)
        self._check_ret(ret, "acl.mdl.load_from_file")

        self.model_desc = acl.mdl.create_desc()
        ret = acl.mdl.get_desc(self.model_desc, self.model_id)
        self._check_ret(ret, "acl.mdl.get_desc")

    def _alloc_model_io(self):
        self.input_dataset = acl.mdl.create_dataset()
        input_count = acl.mdl.get_num_inputs(self.model_desc)
        for index in range(input_count):
            size = acl.mdl.get_input_size_by_index(self.model_desc, index)
            dev_ptr, ret = acl.rt.malloc(size, self.ACL_MEM_MALLOC_NORMAL_ONLY)
            self._check_ret(ret, f"acl.rt.malloc input[{index}]")

            data_buffer = acl.create_data_buffer(dev_ptr, size)
            _, ret = acl.mdl.add_dataset_buffer(self.input_dataset, data_buffer)
            self._check_ret(ret, f"acl.mdl.add_dataset_buffer input[{index}]")

            self.input_buffers.append({
                "size": size,
                "dev_ptr": dev_ptr,
                "data_buffer": data_buffer,
            })

        self.output_dataset = acl.mdl.create_dataset()
        output_count = acl.mdl.get_num_outputs(self.model_desc)
        for index in range(output_count):
            size = acl.mdl.get_output_size_by_index(self.model_desc, index)
            dev_ptr, ret = acl.rt.malloc(size, self.ACL_MEM_MALLOC_NORMAL_ONLY)
            self._check_ret(ret, f"acl.rt.malloc output[{index}]")

            host_ptr, ret = acl.rt.malloc_host(size)
            self._check_ret(ret, f"acl.rt.malloc_host output[{index}]")

            data_buffer = acl.create_data_buffer(dev_ptr, size)
            _, ret = acl.mdl.add_dataset_buffer(self.output_dataset, data_buffer)
            self._check_ret(ret, f"acl.mdl.add_dataset_buffer output[{index}]")

            self.output_buffers.append({
                "size": size,
                "dev_ptr": dev_ptr,
                "host_ptr": host_ptr,
                "data_buffer": data_buffer,
            })

    def release(self):
        if self.released:
            return

        for buffer_info in self.input_buffers:
            if buffer_info.get("data_buffer") is not None:
                acl.destroy_data_buffer(buffer_info["data_buffer"])
                buffer_info["data_buffer"] = None
            if buffer_info.get("dev_ptr") is not None:
                acl.rt.free(buffer_info["dev_ptr"])
                buffer_info["dev_ptr"] = None
        self.input_buffers.clear()

        for buffer_info in self.output_buffers:
            if buffer_info.get("data_buffer") is not None:
                acl.destroy_data_buffer(buffer_info["data_buffer"])
                buffer_info["data_buffer"] = None
            if buffer_info.get("host_ptr") is not None:
                acl.rt.free_host(buffer_info["host_ptr"])
                buffer_info["host_ptr"] = None
            if buffer_info.get("dev_ptr") is not None:
                acl.rt.free(buffer_info["dev_ptr"])
                buffer_info["dev_ptr"] = None
        self.output_buffers.clear()

        if self.input_dataset is not None:
            acl.mdl.destroy_dataset(self.input_dataset)
            self.input_dataset = None

        if self.output_dataset is not None:
            acl.mdl.destroy_dataset(self.output_dataset)
            self.output_dataset = None

        if self.model_desc is not None:
            acl.mdl.destroy_desc(self.model_desc)
            self.model_desc = None

        if self.model_id is not None:
            acl.mdl.unload(self.model_id)
            self.model_id = None

        if self.stream is not None:
            acl.rt.destroy_stream(self.stream)
            self.stream = None

        if self.context is not None:
            acl.rt.destroy_context(self.context)
            self.context = None

        acl.rt.reset_device(self.device_id)
        acl.finalize()
        self.released = True

    def __del__(self):
        try:
            self.release()
        except Exception:
            pass

    def run(self, audio_data, vibration_data, temp_data):
        input_list = [audio_data, vibration_data, temp_data]
        if len(input_list) != len(self.input_buffers):
            raise ValueError("Input count does not match model input count")

        for index, data in enumerate(input_list):
            contiguous = np.ascontiguousarray(data)
            buffer_info = self.input_buffers[index]
            if contiguous.nbytes != buffer_info["size"]:
                raise ValueError(
                    f"Input[{index}] byte size mismatch: expect {buffer_info['size']}, got {contiguous.nbytes}"
                )

            ret = acl.rt.memcpy(
                buffer_info["dev_ptr"],
                buffer_info["size"],
                acl.util.numpy_to_ptr(contiguous),
                buffer_info["size"],
                self.ACL_MEMCPY_HOST_TO_DEVICE,
            )
            self._check_ret(ret, f"acl.rt.memcpy H2D input[{index}]")

        if hasattr(acl.mdl, "execute_async"):
            ret = acl.mdl.execute_async(self.model_id, self.input_dataset, self.output_dataset, self.stream)
            self._check_ret(ret, "acl.mdl.execute_async")
            ret = acl.rt.synchronize_stream(self.stream)
            self._check_ret(ret, "acl.rt.synchronize_stream")
        else:
            ret = acl.mdl.execute(self.model_id, self.input_dataset, self.output_dataset)
            self._check_ret(ret, "acl.mdl.execute")

        results = []
        for index, buffer_info in enumerate(self.output_buffers):
            ret = acl.rt.memcpy(
                buffer_info["host_ptr"],
                buffer_info["size"],
                buffer_info["dev_ptr"],
                buffer_info["size"],
                self.ACL_MEMCPY_DEVICE_TO_HOST,
            )
            self._check_ret(ret, f"acl.rt.memcpy D2H output[{index}]")

            result = acl.util.ptr_to_numpy(
                buffer_info["host_ptr"],
                (buffer_info["size"] // 4,),
                self.ACL_FLOAT,
            )
            results.append(np.array(result, copy=True))

        return results


@dataclass
class FrameMeta:
    source_id: int
    device_id: int
    capture_timestamp_us: int
    audio_target_rate_hz: int
    audio_valid_samples: int
    vib_valid_samples: int
    temp_valid_samples: int
    vib_sample_interval_us: int
    imu_ready: int
    mic_ready: int
    temperature_ready: int
    audio_format: int
    vibration_layout: int
    temperature_format: int
    reserved: int
    last_accel_x: int
    last_accel_y: int
    last_accel_z: int
    last_gyro_x: int
    last_gyro_y: int
    last_gyro_z: int

    @classmethod
    def from_bytes(cls, payload):
        if len(payload) != MODEL_META_STRUCT.size:
            raise ValueError(f"Invalid meta payload size: {len(payload)}")
        return cls(*MODEL_META_STRUCT.unpack(payload))

    def to_dict(self):
        return {
            "source_id": self.source_id,
            "device_id": self.device_id,
            "capture_timestamp_us": self.capture_timestamp_us,
            "audio_target_rate_hz": self.audio_target_rate_hz,
            "audio_valid_samples": self.audio_valid_samples,
            "vib_valid_samples": self.vib_valid_samples,
            "temp_valid_samples": self.temp_valid_samples,
            "vib_sample_interval_us": self.vib_sample_interval_us,
            "imu_ready": self.imu_ready,
            "mic_ready": self.mic_ready,
            "temperature_ready": self.temperature_ready,
            "audio_format": self.audio_format,
            "vibration_layout": self.vibration_layout,
            "temperature_format": self.temperature_format,
            "last_accel": [self.last_accel_x, self.last_accel_y, self.last_accel_z],
            "last_gyro": [self.last_gyro_x, self.last_gyro_y, self.last_gyro_z],
        }


class AudioModelPreprocessor:
    def __init__(self):
        import torch
        import torchaudio.transforms as T

        self.torch = torch
        self.mel_spectrogram = T.MelSpectrogram(
            sample_rate=16000,
            n_fft=400,
            hop_length=160,
            n_mels=64,
            power=2.0,
            window_fn=torch.hamming_window,
        )
        self.amplitude_to_db = T.AmplitudeToDB()

    def process(self, pcm_samples, valid_samples):
        waveform = np.asarray(pcm_samples, dtype=np.float32)
        valid_samples = min(max(int(valid_samples), 0), waveform.size)

        if valid_samples > 0:
            waveform = waveform[:valid_samples]
        if waveform.size < MODEL_AUDIO_SAMPLES:
            waveform = np.pad(waveform, (0, MODEL_AUDIO_SAMPLES - waveform.size), mode="constant")
        elif waveform.size > MODEL_AUDIO_SAMPLES:
            waveform = waveform[:MODEL_AUDIO_SAMPLES]

        waveform = waveform / 32768.0
        waveform = self.torch.from_numpy(waveform).unsqueeze(0)
        waveform = self.torch.cat(
            (waveform[:, :1], waveform[:, 1:] - 0.97 * waveform[:, :-1]),
            dim=1,
        )

        mel_spec = self.mel_spectrogram(waveform)
        log_mel = self.amplitude_to_db(mel_spec)
        if log_mel.shape[2] < 200:
            log_mel = self.torch.nn.functional.pad(log_mel, (0, 200 - log_mel.shape[2]))
        elif log_mel.shape[2] > 200:
            log_mel = log_mel[:, :, :200]

        return log_mel.unsqueeze(0).cpu().numpy().astype(np.float32)


class VibrationModelPreprocessor:
    def process(self, vibration_channel_major, valid_samples):
        vibration = np.asarray(vibration_channel_major, dtype=np.float32).reshape(
            MODEL_VIBRATION_CHANNELS,
            MODEL_VIBRATION_SAMPLES,
        )
        valid_samples = min(max(int(valid_samples), 0), MODEL_VIBRATION_SAMPLES)

        if valid_samples > 0:
            valid_part = vibration[:, :valid_samples]
            if valid_samples < MODEL_VIBRATION_SAMPLES:
                pad_value = valid_part[:, -1:]
                vibration[:, valid_samples:] = np.repeat(pad_value, MODEL_VIBRATION_SAMPLES - valid_samples, axis=1)
        else:
            vibration[:, :] = 0.0

        mean = np.mean(vibration, axis=1, keepdims=True)
        vibration = (vibration - mean) / 5.0
        return np.expand_dims(vibration.astype(np.float32), axis=0)


class TemperatureModelPreprocessor:
    def process(self, temperature_deci_c, valid_samples):
        temperature = np.asarray(temperature_deci_c, dtype=np.float32).reshape(MODEL_TEMPERATURE_SAMPLES) / 10.0
        valid_samples = min(max(int(valid_samples), 0), MODEL_TEMPERATURE_SAMPLES)

        if valid_samples > 0:
            valid_part = temperature[:valid_samples]
            if valid_samples < MODEL_TEMPERATURE_SAMPLES:
                temperature[valid_samples:] = valid_part[-1]
        elif temperature.size > 0:
            temperature[:] = temperature[0]

        smooth = np.convolve(temperature, np.ones(3, dtype=np.float32) / 3.0, mode="valid")
        smooth = np.pad(smooth, (0, MODEL_TEMPERATURE_SAMPLES - smooth.size), mode="edge")
        smooth = smooth / 100.0
        return np.expand_dims(np.expand_dims(smooth.astype(np.float32), axis=0), axis=0)


class ModelPacketStreamParser:
    def __init__(self):
        self.buffer = bytearray()
        self.magic_le = struct.pack("<H", MODEL_PACKET_MAGIC)

    def feed(self, chunk):
        packets = []
        self.buffer.extend(chunk)

        while True:
            if len(self.buffer) < MODEL_PACKET_HEADER.size:
                break

            if self.buffer[0:2] != self.magic_le:
                magic_offset = self.buffer.find(self.magic_le, 1)
                if magic_offset < 0:
                    self.buffer[:] = self.buffer[-1:]
                    break
                del self.buffer[:magic_offset]
                if len(self.buffer) < MODEL_PACKET_HEADER.size:
                    break

            header = MODEL_PACKET_HEADER.unpack(self.buffer[:MODEL_PACKET_HEADER.size])
            _, version, packet_type, frame_id, chunk_index, chunk_total, payload_len = header
            total_len = MODEL_PACKET_HEADER.size + payload_len
            if len(self.buffer) < total_len:
                break

            payload = bytes(self.buffer[MODEL_PACKET_HEADER.size:total_len])
            del self.buffer[:total_len]

            packets.append({
                "version": version,
                "type": packet_type,
                "frame_id": frame_id,
                "chunk_index": chunk_index,
                "chunk_total": chunk_total,
                "payload": payload,
            })

        return packets


class ModelFrameReassembler:
    def __init__(self):
        self.frames = {}

    def add_packet(self, packet):
        frame_id = packet["frame_id"]
        frame = self.frames.setdefault(frame_id, {
            "meta": None,
            "audio": {"expected_total": None, "chunks": {}},
            "vibration": {"expected_total": None, "chunks": {}},
            "temperature": {"expected_total": None, "chunks": {}},
            "end_received": False,
            "updated_at": time.time(),
        })
        frame["updated_at"] = time.time()

        packet_type = packet["type"]
        if packet_type == MODEL_PACKET_TYPE_META:
            frame["meta"] = FrameMeta.from_bytes(packet["payload"])
        elif packet_type == MODEL_PACKET_TYPE_AUDIO:
            self._store_chunk(frame["audio"], packet)
        elif packet_type == MODEL_PACKET_TYPE_VIBRATION:
            self._store_chunk(frame["vibration"], packet)
        elif packet_type == MODEL_PACKET_TYPE_TEMPERATURE:
            self._store_chunk(frame["temperature"], packet)
        elif packet_type == MODEL_PACKET_TYPE_END:
            frame["end_received"] = True
        else:
            raise ValueError(f"Unsupported packet type: {packet_type}")

        if self._is_complete(frame):
            completed = self._build_completed_frame(frame_id, frame)
            del self.frames[frame_id]
            return completed
        return None

    @staticmethod
    def _store_chunk(target, packet):
        if target["expected_total"] is None:
            target["expected_total"] = packet["chunk_total"]
        elif target["expected_total"] != packet["chunk_total"]:
            raise ValueError("Chunk total mismatch in frame reassembly")

        target["chunks"][packet["chunk_index"]] = packet["payload"]

    @staticmethod
    def _chunks_complete(target):
        expected_total = target["expected_total"]
        if expected_total is None:
            return False
        return len(target["chunks"]) == expected_total

    def _is_complete(self, frame):
        return (
            frame["meta"] is not None and
            frame["end_received"] and
            self._chunks_complete(frame["audio"]) and
            self._chunks_complete(frame["vibration"]) and
            self._chunks_complete(frame["temperature"])
        )

    @staticmethod
    def _join_chunks(target):
        return b"".join(target["chunks"][index] for index in range(target["expected_total"]))

    def _build_completed_frame(self, frame_id, frame):
        audio_bytes = self._join_chunks(frame["audio"])
        vibration_bytes = self._join_chunks(frame["vibration"])
        temperature_bytes = self._join_chunks(frame["temperature"])

        audio_pcm = np.frombuffer(audio_bytes, dtype="<i2")
        vibration = np.frombuffer(vibration_bytes, dtype="<i2")
        temperature = np.frombuffer(temperature_bytes, dtype="<i2")

        if audio_pcm.size < MODEL_AUDIO_SAMPLES:
            audio_pcm = np.pad(audio_pcm, (0, MODEL_AUDIO_SAMPLES - audio_pcm.size), mode="constant")
        else:
            audio_pcm = audio_pcm[:MODEL_AUDIO_SAMPLES]

        expected_vibration_values = MODEL_VIBRATION_CHANNELS * MODEL_VIBRATION_SAMPLES
        if vibration.size < expected_vibration_values:
            vibration = np.pad(vibration, (0, expected_vibration_values - vibration.size), mode="constant")
        else:
            vibration = vibration[:expected_vibration_values]
        vibration = vibration.reshape(MODEL_VIBRATION_CHANNELS, MODEL_VIBRATION_SAMPLES)

        if temperature.size < MODEL_TEMPERATURE_SAMPLES:
            temperature = np.pad(temperature, (0, MODEL_TEMPERATURE_SAMPLES - temperature.size), mode="edge")
        else:
            temperature = temperature[:MODEL_TEMPERATURE_SAMPLES]

        return {
            "frame_id": frame_id,
            "meta": frame["meta"],
            "audio_pcm": audio_pcm,
            "vibration": vibration,
            "temperature": temperature,
        }

    def purge_stale(self, timeout_seconds=5.0):
        now = time.time()
        stale_keys = [frame_id for frame_id, frame in self.frames.items() if now - frame["updated_at"] > timeout_seconds]
        for frame_id in stale_keys:
            del self.frames[frame_id]


class ResultTcpPublisher:
    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.server_socket = None
        self.clients = []
        self.lock = threading.Lock()
        self.running = False
        self.accept_thread = None

    def start(self):
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(5)
        self.running = True
        self.accept_thread = threading.Thread(target=self._accept_loop, name="result_tcp_accept", daemon=True)
        self.accept_thread.start()
        print(f"[Atlas] 结果 TCP 发布服务已启动: {self.host}:{self.port}")

    def _accept_loop(self):
        while self.running:
            try:
                client_socket, client_addr = self.server_socket.accept()
                client_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                with self.lock:
                    self.clients.append(client_socket)
                print(f"[Atlas] 应用端已连接: {client_addr[0]}:{client_addr[1]}")
            except OSError:
                break

    def broadcast(self, payload_dict):
        payload = (json.dumps(payload_dict, ensure_ascii=False) + "\n").encode("utf-8")
        stale_clients = []
        with self.lock:
            for client_socket in self.clients:
                try:
                    client_socket.sendall(payload)
                except OSError:
                    stale_clients.append(client_socket)

            for client_socket in stale_clients:
                self.clients.remove(client_socket)
                try:
                    client_socket.close()
                except OSError:
                    pass

    def close(self):
        self.running = False
        if self.server_socket is not None:
            try:
                self.server_socket.close()
            except OSError:
                pass
            self.server_socket = None

        with self.lock:
            for client_socket in self.clients:
                try:
                    client_socket.close()
                except OSError:
                    pass
            self.clients.clear()


class AtlasInferenceGateway:
    def __init__(self, model_path, ingress_host, ingress_port, result_host, result_port,
                 device_id=0, ingress_mode="serial", serial_port="/dev/ttyUSB0", serial_baudrate=115200):
        self.model = Net(model_path, device_id=device_id)
        self.audio_preprocessor = AudioModelPreprocessor()
        self.vibration_preprocessor = VibrationModelPreprocessor()
        self.temperature_preprocessor = TemperatureModelPreprocessor()
        self.publisher = ResultTcpPublisher(result_host, result_port)
        self.ingress_host = ingress_host
        self.ingress_port = ingress_port
        self.ingress_mode = ingress_mode
        self.serial_port = serial_port
        self.serial_baudrate = serial_baudrate
        self.ingress_socket = None
        self.running = False
        self.infer_lock = threading.Lock()
        self.serial_lock = threading.Lock()
        self.serial_device = None
        self.control_server = LocalControlServer(self._handle_local_select_target)
        self.perf_tracker = PerfTracker(window_size=120)

    # def _handle_local_select_target(self, target_name):
    #     if (self.ingress_mode != "serial") or (self.serial_device is None) or (not target_name):
    #         return
    #     frame = build_select_target_frame(target_name)
    #     with self.serial_lock:
    #         self.serial_device.write(frame)
    #         self.serial_device.flush()
    def _handle_local_select_target(self, target_name):
        print(f"[Atlas] 收到后端选择目标请求 target={target_name!r}")

        if not target_name:
            print("[Atlas] SELECT_TARGET 忽略：target_name 为空")
            return

        if self.ingress_mode != "serial":
            print(f"[Atlas] SELECT_TARGET 忽略：当前 ingress_mode={self.ingress_mode}")
            return

        if self.serial_device is None:
            print("[Atlas] SELECT_TARGET 忽略：串口尚未连接")
            return

        frame = build_select_target_frame(target_name)
        with self.serial_lock:
            self.serial_device.write(frame)
            self.serial_device.flush()

        print(
            f"[Atlas] 已向 Master 下发 SELECT_TARGET target={target_name} "
            f"frame_len={len(frame)} head={frame[:16].hex(' ')}"
        )

    @staticmethod
    def _softmax(values):
        values = np.asarray(values, dtype=np.float32)
        values = values - np.max(values)
        exp_values = np.exp(values)
        return exp_values / np.sum(exp_values)

    @staticmethod
    def _build_audio_spectrum(audio_pcm):
        spectrum_bins = []
        waveform = np.asarray(audio_pcm, dtype=np.float32)
        if waveform.size == 0:
            return [0.0] * 15

        fft_magnitude = np.abs(np.fft.rfft(waveform))
        for split in np.array_split(fft_magnitude, 15):
            mean_value = float(np.mean(split)) if split.size > 0 else 0.0
            scaled_value = min(max(20.0 * np.log10(mean_value + 1.0), 0.0), 100.0)
            spectrum_bins.append(round(scaled_value, 2))
        return spectrum_bins

    @staticmethod
    def _telemetry_summary(frame):
        meta = frame["meta"]
        temperature_history_c = (np.asarray(frame["temperature"], dtype=np.float32) / 10.0).tolist()
        accel_scale = 16384.0
        gyro_scale = 131.0

        return {
            "temperature_history_c": [round(float(value), 2) for value in temperature_history_c],
            "audio_spectrum": AtlasInferenceGateway._build_audio_spectrum(frame["audio_pcm"]),
            "last_accel_raw": [meta.last_accel_x, meta.last_accel_y, meta.last_accel_z],
            "last_accel_g": [
                round(float(meta.last_accel_x) / accel_scale, 4),
                round(float(meta.last_accel_y) / accel_scale, 4),
                round(float(meta.last_accel_z) / accel_scale, 4),
            ],
            "last_gyro_raw": [meta.last_gyro_x, meta.last_gyro_y, meta.last_gyro_z],
            "last_gyro_dps": [
                round(float(meta.last_gyro_x) / gyro_scale, 4),
                round(float(meta.last_gyro_y) / gyro_scale, 4),
                round(float(meta.last_gyro_z) / gyro_scale, 4),
            ],
            "temperature_avg_c": round(float(np.mean(frame["temperature"])) / 10.0, 2),
            "temperature_max_c": round(float(np.max(frame["temperature"])) / 10.0, 2),
        }

    def _run_inference(self, frame):
        meta = frame["meta"]
        frame_start = self.perf_tracker.start()
        preprocess_start = time.time()
        audio_input = self.audio_preprocessor.process(frame["audio_pcm"], meta.audio_valid_samples)
        vibration_input = self.vibration_preprocessor.process(frame["vibration"], meta.vib_valid_samples)
        temp_input = self.temperature_preprocessor.process(frame["temperature"], meta.temp_valid_samples)
        preprocess_latency_ms = (time.time() - preprocess_start) * 1000.0

        start_time = time.time()
        with self.infer_lock:
            outputs = self.model.run(audio_input, vibration_input, temp_input)
        inference_latency_ms = (time.time() - start_time) * 1000.0
        total_latency_ms = (time.time() - frame_start) * 1000.0
        perf_snapshot = self.perf_tracker.finish(preprocess_latency_ms, inference_latency_ms, total_latency_ms)

        class_logits = outputs[0].reshape(-1)
        class_probabilities = self._softmax(class_logits)
        health_score = float(outputs[1].reshape(-1)[0]) if len(outputs) > 1 and outputs[1].size > 0 else None
        predicted_class = int(np.argmax(class_probabilities))

        return {
            "frame_id": frame["frame_id"],
            "source_id": meta.source_id,
            "device_id": meta.device_id,
            "capture_timestamp_us": meta.capture_timestamp_us,
            "predicted_class": predicted_class,
            "class_logits": class_logits.tolist(),
            "class_probabilities": class_probabilities.tolist(),
            "health_score": health_score,
            "inference_latency_ms": inference_latency_ms,
            "preprocess_latency_ms": preprocess_latency_ms,
            "total_latency_ms": total_latency_ms,
            "meta": meta.to_dict(),
            "telemetry": self._telemetry_summary(frame),
            "performance": perf_snapshot,
            "message_type": "inference_result",
        }

    def _handle_completed_frame(self, frame):
        try:
            result = self._run_inference(frame)
            print(
                f"[Atlas] source={result.get('source_id')} device={result.get('device_id')} "
                f"frame={result['frame_id']} class={result['predicted_class']} "
                f"health={result['health_score']} latency={result['inference_latency_ms']:.2f}ms"
            )
            self.publisher.broadcast(result)
        except Exception as exc:
            error_payload = {
                "frame_id": frame["frame_id"],
                "source_id": getattr(frame.get("meta"), "source_id", 0),
                "device_id": getattr(frame.get("meta"), "device_id", 0),
                "error": str(exc),
                "traceback": traceback.format_exc(),
            }
            print(f"[Atlas] 推理失败 frame={frame['frame_id']} err={exc}")
            self.publisher.broadcast(error_payload)

    # def _consume_payload(self, parser, reassembler, payload):
    #     for packet in parser.feed(payload):
    #         frame = reassembler.add_packet(packet)
    #         if frame is None:
    #             continue
    #         self._handle_completed_frame(frame)
    #     reassembler.purge_stale()

    def _consume_payload(self, parser, reassembler, payload):
        packets = parser.feed(payload)

        if packets:
            print(f"[Atlas] 本次解析到模型包数量: {len(packets)}")

        for packet in packets:
            print(
                f"[Atlas] MODEL_PACKET "
                f"type={packet['type']} "
                f"frame={packet['frame_id']} "
                f"chunk={packet['chunk_index'] + 1}/{packet['chunk_total']} "
                f"payload={len(packet['payload'])}"
            )

            frame = reassembler.add_packet(packet)
            if frame is None:
                continue

            print(
                f"[Atlas] 模型帧重组完成 frame={frame['frame_id']}，"
                f"准备推理"
            )
            self._handle_completed_frame(frame)

        reassembler.purge_stale()

    def _handle_ingress_client(self, client_socket, client_addr):
        parser = ModelPacketStreamParser()
        reassembler = ModelFrameReassembler()

        print(f"[Atlas] 数据源已连接: {client_addr[0]}:{client_addr[1]}")
        with client_socket:
            client_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            while self.running:
                try:
                    payload = client_socket.recv(4096)
                    if not payload:
                        break
                    self._consume_payload(parser, reassembler, payload)
                except OSError:
                    break
                except Exception as exc:
                    print(f"[Atlas] 数据接收异常: {exc}")
                    break

        print(f"[Atlas] 数据源已断开: {client_addr[0]}:{client_addr[1]}")

    def _serve_tcp_forever(self):
        self.ingress_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.ingress_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.ingress_socket.bind((self.ingress_host, self.ingress_port))
        self.ingress_socket.listen(5)
        self.running = True

        print(f"[Atlas] TCP 模型包接收服务已启动: {self.ingress_host}:{self.ingress_port}")

        while self.running:
            client_socket, client_addr = self.ingress_socket.accept()
            worker = threading.Thread(
                target=self._handle_ingress_client,
                args=(client_socket, client_addr),
                daemon=True,
            )
            worker.start()

    def _serve_serial_forever(self):
        try:
            import serial
        except ImportError as exc:
            raise RuntimeError("Serial ingress requires pyserial, please run 'pip install pyserial'") from exc

        self.running = True
        print(f"[Atlas] 串口模型包接收已启动: {self.serial_port} @ {self.serial_baudrate}")

        while self.running:
            parser = ModelPacketStreamParser()
            reassembler = ModelFrameReassembler()
            control_parser = BridgeControlParser()
            try:
                with serial.Serial(self.serial_port, self.serial_baudrate, timeout=1) as ser:
                    self.serial_device = ser
                    print(f"[Atlas] 串口数据源已连接: {self.serial_port}")
                    while self.running:
                        payload = ser.read(4096)
                        if not payload:
                            reassembler.purge_stale()
                            continue
                        for event in control_parser.feed(payload):
                            self.publisher.broadcast(event)
                        self._consume_payload(parser, reassembler, payload)
                self.serial_device = None
            except KeyboardInterrupt:
                raise
            except Exception as exc:
                self.serial_device = None
                print(f"[Atlas] 串口数据接收异常: {exc}")
                time.sleep(2.0)

    def serve_forever(self):
        self.publisher.start()
        self.control_server.start()

        try:
            if self.ingress_mode == "serial":
                self._serve_serial_forever()
            else:
                self._serve_tcp_forever()
        except KeyboardInterrupt:
            print("[Atlas] 收到停止信号，准备退出")
        finally:
            self.close()

    def close(self):
        self.running = False
        if self.ingress_socket is not None:
            try:
                self.ingress_socket.close()
            except OSError:
                pass
            self.ingress_socket = None

        self.control_server.close()
        self.publisher.close()
        self.model.release()


def run_demo_client(host, port):
    print(f"[DUYU200 Demo] 连接 Atlas 结果服务: {host}:{port}")
    with socket.create_connection((host, port)) as sock:
        with sock.makefile("r", encoding="utf-8") as stream:
            for line in stream:
                line = line.strip()
                if not line:
                    continue
                try:
                    print(json.dumps(json.loads(line), ensure_ascii=False, indent=2))
                except json.JSONDecodeError:
                    print(line)


def build_arg_parser():
    parser = argparse.ArgumentParser(description="Atlas 200I 多模态模型接收/重组/推理/输出服务")
    subparsers = parser.add_subparsers(dest="command", required=True)

    serve_parser = subparsers.add_parser("serve", help="启动 Atlas 在线推理网关")
    serve_parser.add_argument("--model-path", default="./industrial_hybrid_final.om")
    serve_parser.add_argument("--device-id", type=int, default=0)
    serve_parser.add_argument("--ingress-mode", choices=["serial", "tcp"], default="serial")
    serve_parser.add_argument("--ingress-host", default="0.0.0.0")
    serve_parser.add_argument("--ingress-port", type=int, default=19000)
    serve_parser.add_argument("--serial-port", default="/dev/ttyUSB0")
    serve_parser.add_argument("--serial-baudrate", type=int, default=115200)
    serve_parser.add_argument("--result-host", default="0.0.0.0")
    serve_parser.add_argument("--result-port", type=int, default=19001)

    client_parser = subparsers.add_parser("demo-client", help="启动 DUYU200 结果接收示例")
    client_parser.add_argument("--host", default="127.0.0.1")
    client_parser.add_argument("--port", type=int, default=19001)
    return parser


def main():
    parser = build_arg_parser()
    args = parser.parse_args()

    if args.command == "serve":
        gateway = AtlasInferenceGateway(
            model_path=args.model_path,
            ingress_host=args.ingress_host,
            ingress_port=args.ingress_port,
            result_host=args.result_host,
            result_port=args.result_port,
            device_id=args.device_id,
            ingress_mode=args.ingress_mode,
            serial_port=args.serial_port,
            serial_baudrate=args.serial_baudrate,
        )
        gateway.serve_forever()
        return

    if args.command == "demo-client":
        run_demo_client(args.host, args.port)


if __name__ == "__main__":
    main()
