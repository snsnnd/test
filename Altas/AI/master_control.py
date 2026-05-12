import json
import socket
import struct
import threading


BRIDGE_CTRL_MAGIC = 0x434D
BRIDGE_CTRL_VERSION = 1

BRIDGE_CTRL_TYPE_DISCOVERY_STATUS = 1
BRIDGE_CTRL_TYPE_SELECT_TARGET = 2
BRIDGE_CTRL_TYPE_SWITCH_ACK = 3

CTRL_HEADER_STRUCT = struct.Struct("<HBBH")
DISCOVERY_NODE_STRUCT = struct.Struct("<32sbBBB")
DISCOVERY_PAYLOAD_HEAD_STRUCT = struct.Struct("<32sBBH")
SELECT_TARGET_STRUCT = struct.Struct("<32s")
SWITCH_ACK_STRUCT = struct.Struct("<B3x32s64s")

DISCOVERY_NODE_MAX = 8
LOCAL_CONTROL_HOST = "127.0.0.1"
LOCAL_CONTROL_PORT = 19002


def _debug(message: str):
    print(f"[Atlas Control] {message}")


def _decode_c_string(raw: bytes) -> str:
    return raw.split(b"\0", 1)[0].decode("utf-8", errors="ignore")


def _hex_preview(data: bytes, limit: int = 16) -> str:
    if not data:
        return "<empty>"
    preview = data[:limit]
    suffix = " ..." if len(data) > limit else ""
    return " ".join(f"{byte:02X}" for byte in preview) + suffix


def build_select_target_frame(target_name: str) -> bytes:
    target_bytes = target_name.encode("utf-8")[:31]
    payload = SELECT_TARGET_STRUCT.pack(target_bytes + b"\0" * (32 - len(target_bytes)))
    header = CTRL_HEADER_STRUCT.pack(BRIDGE_CTRL_MAGIC, BRIDGE_CTRL_VERSION, BRIDGE_CTRL_TYPE_SELECT_TARGET, len(payload))
    frame = header + payload
    _debug(
        f"build SELECT_TARGET target={target_name!r} payload_len={len(payload)} "
        f"frame_len={len(frame)} head={_hex_preview(frame)}"
    )
    return frame


class BridgeControlParser:
    def __init__(self):
        self.buffer = bytearray()
        self.magic_le = struct.pack("<H", BRIDGE_CTRL_MAGIC)
        self.feed_count = 0
        self.decoded_count = 0
        self.dropped_bytes = 0

    def feed(self, chunk: bytes):
        events = []
        if not chunk:
            return events

        self.feed_count += 1
        if self.feed_count <= 10 or self.feed_count % 100 == 0:
            _debug(
                f"feed control bytes len={len(chunk)} buffer_before={len(self.buffer)} "
                f"head={_hex_preview(chunk)}"
            )

        self.buffer.extend(chunk)

        while True:
            if len(self.buffer) < CTRL_HEADER_STRUCT.size:
                break

            if self.buffer[0:2] != self.magic_le:
                magic_offset = self.buffer.find(self.magic_le, 1)
                if magic_offset < 0:
                    self.dropped_bytes += max(0, len(self.buffer) - 1)
                    self.buffer[:] = self.buffer[-1:]
                    if self.dropped_bytes <= 64 or self.dropped_bytes % 512 == 0:
                        _debug(f"control magic not found, dropped_bytes={self.dropped_bytes}")
                    break
                self.dropped_bytes += magic_offset
                if self.dropped_bytes <= 64 or self.dropped_bytes % 512 == 0:
                    _debug(f"skip {magic_offset} bytes before control magic, dropped_bytes={self.dropped_bytes}")
                del self.buffer[:magic_offset]
                if len(self.buffer) < CTRL_HEADER_STRUCT.size:
                    break

            magic, version, frame_type, payload_len = CTRL_HEADER_STRUCT.unpack(self.buffer[:CTRL_HEADER_STRUCT.size])
            total_len = CTRL_HEADER_STRUCT.size + payload_len
            if len(self.buffer) < total_len:
                break

            payload = bytes(self.buffer[CTRL_HEADER_STRUCT.size:total_len])
            del self.buffer[:total_len]

            if magic != BRIDGE_CTRL_MAGIC or version != BRIDGE_CTRL_VERSION:
                _debug(f"ignore invalid control frame magic=0x{magic:04X} version={version}")
                continue

            decoded = self._decode_frame(frame_type, payload)
            if decoded is not None:
                self.decoded_count += 1
                _debug(
                    f"decoded control frame type={frame_type} payload_len={payload_len} "
                    f"message_type={decoded.get('message_type')} decoded_count={self.decoded_count}"
                )
                events.append(decoded)
            else:
                _debug(f"unsupported/invalid control frame type={frame_type} payload_len={payload_len}")

        return events

    def _decode_frame(self, frame_type: int, payload: bytes):
        if frame_type == BRIDGE_CTRL_TYPE_DISCOVERY_STATUS:
            return self._decode_discovery(payload)
        if frame_type == BRIDGE_CTRL_TYPE_SWITCH_ACK:
            return self._decode_ack(payload)
        return None

    @staticmethod
    def _decode_discovery(payload: bytes):
        head_size = DISCOVERY_PAYLOAD_HEAD_STRUCT.size
        if len(payload) < head_size:
            _debug(f"discovery payload too short len={len(payload)} expect>={head_size}")
            return None

        active_target_raw, target_connected, node_count, _ = DISCOVERY_PAYLOAD_HEAD_STRUCT.unpack(payload[:head_size])
        nodes = []
        offset = head_size
        for _index in range(min(node_count, DISCOVERY_NODE_MAX)):
            if offset + DISCOVERY_NODE_STRUCT.size > len(payload):
                _debug(
                    f"discovery node truncated index={_index} offset={offset} "
                    f"payload_len={len(payload)}"
                )
                break
            node_raw = DISCOVERY_NODE_STRUCT.unpack(payload[offset:offset + DISCOVERY_NODE_STRUCT.size])
            offset += DISCOVERY_NODE_STRUCT.size
            nodes.append({
                "name": _decode_c_string(node_raw[0]),
                "rssi": int(node_raw[1]),
                "hasService": bool(node_raw[2]),
                "isSelected": bool(node_raw[3]),
                "isConnected": bool(node_raw[4]),
            })

        active_target = _decode_c_string(active_target_raw)
        _debug(
            f"DISCOVERY_STATUS active_target={active_target or '<none>'} "
            f"connected={bool(target_connected)} node_count={node_count} parsed={len(nodes)} "
            f"nodes={[node.get('name') for node in nodes]}"
        )

        return {
            "message_type": "bridge_status",
            "active_target": active_target,
            "target_connected": bool(target_connected),
            "nodes": nodes,
        }

    @staticmethod
    def _decode_ack(payload: bytes):
        if len(payload) != SWITCH_ACK_STRUCT.size:
            _debug(f"switch ack invalid size len={len(payload)} expect={SWITCH_ACK_STRUCT.size}")
            return None
        accepted, active_target_raw, message_raw = SWITCH_ACK_STRUCT.unpack(payload)
        active_target = _decode_c_string(active_target_raw)
        message = _decode_c_string(message_raw)
        _debug(f"SWITCH_ACK accepted={bool(accepted)} active_target={active_target} message={message}")
        return {
            "message_type": "bridge_ack",
            "accepted": bool(accepted),
            "active_target": active_target,
            "message": message,
        }


class LocalControlServer:
    def __init__(self, on_select_target, host=LOCAL_CONTROL_HOST, port=LOCAL_CONTROL_PORT):
        self.host = host
        self.port = port
        self.on_select_target = on_select_target
        self.running = False
        self.server_socket = None
        self.thread = None

    def start(self):
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(5)
        self.running = True
        self.thread = threading.Thread(target=self._serve_forever, daemon=True, name="atlas_control_server")
        self.thread.start()
        _debug(f"local control server started at {self.host}:{self.port}")

    def _serve_forever(self):
        while self.running:
            try:
                client_socket, client_addr = self.server_socket.accept()
                _debug(f"local control client connected {client_addr[0]}:{client_addr[1]}")
            except OSError:
                break

            worker = threading.Thread(target=self._handle_client, args=(client_socket,), daemon=True)
            worker.start()

    def _handle_client(self, client_socket):
        with client_socket:
            try:
                with client_socket.makefile("r", encoding="utf-8") as stream:
                    for line in stream:
                        line = line.strip()
                        if not line:
                            continue
                        _debug(f"local control raw line={line}")
                        payload = json.loads(line)
                        if payload.get("action") == "select_target":
                            target_name = payload.get("target_name", "")
                            _debug(f"local control select_target target={target_name!r}")
                            self.on_select_target(target_name)
                        else:
                            _debug(f"ignore unknown local control action payload={payload}")
            except Exception as exc:
                _debug(f"local control client error: {exc}")
                return

    def close(self):
        self.running = False
        if self.server_socket is not None:
            try:
                self.server_socket.close()
            except OSError:
                pass
            self.server_socket = None
        _debug("local control server closed")
