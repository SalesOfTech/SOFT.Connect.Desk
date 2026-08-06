#!/usr/bin/env python3
import os
import socket
import sqlite3
import sys
import time


def varint(value: int) -> bytes:
    encoded = bytearray()
    while value >= 0x80:
        encoded.append((value & 0x7F) | 0x80)
        value >>= 7
    encoded.append(value)
    return bytes(encoded)


def field(number: int, value: bytes) -> bytes:
    return varint((number << 3) | 2) + varint(len(value)) + value


def register_pk(peer_id: str, uuid: bytes, pk: bytes = b"", old_id: str = "") -> bytes:
    payload = field(1, peer_id.encode()) + field(2, uuid)
    if pk:
        payload += field(3, pk)
    if old_id:
        payload += field(4, old_id.encode())
    return field(15, payload)


def frame(payload: bytes) -> bytes:
    size = len(payload)
    if size <= 0x3F:
        return bytes([size << 2]) + payload
    if size <= 0x3FFF:
        return ((size << 2) | 1).to_bytes(2, "little") + payload
    raise ValueError("test payload is too large")


def read_frame(sock: socket.socket) -> bytes:
    first = sock.recv(1)
    if not first:
        raise RuntimeError("server closed the connection")
    head_len = (first[0] & 0x03) + 1
    header = first + sock.recv(head_len - 1)
    size = int.from_bytes(header, "little") >> 2
    payload = bytearray()
    while len(payload) < size:
        chunk = sock.recv(size - len(payload))
        if not chunk:
            raise RuntimeError("incomplete server response")
        payload.extend(chunk)
    return bytes(payload)


def unframe_datagram(datagram: bytes) -> bytes:
    if not datagram:
        raise RuntimeError("empty UDP response")
    head_len = (datagram[0] & 0x03) + 1
    size = int.from_bytes(datagram[:head_len], "little") >> 2
    payload = datagram[head_len:]
    if len(payload) != size:
        raise RuntimeError("invalid UDP response frame")
    return payload


def response_result(payload: bytes) -> int:
    expected_outer_tag = varint((16 << 3) | 2)
    if not payload.startswith(expected_outer_tag):
        raise AssertionError(f"unexpected response: {payload.hex()}")
    offset = len(expected_outer_tag)
    inner_len = payload[offset]
    inner = payload[offset + 1 : offset + 1 + inner_len]
    if not inner:
        return 0
    if inner[0] != 0x08:
        raise AssertionError(f"unexpected response body: {inner.hex()}")
    return inner[1]


def udp_register(port: int, peer_id: str, uuid: bytes, pk: bytes) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(3)
    sock.sendto(frame(register_pk(peer_id, uuid, pk)), ("127.0.0.1", port))
    datagram, _ = sock.recvfrom(1024)
    if response_result(unframe_datagram(datagram)) != 0:
        raise AssertionError(f"initial registration failed for {peer_id}")


def change_id(port: int, old_id: str, new_id: str, uuid: bytes) -> int:
    with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
        sock.sendall(frame(register_pk(new_id, uuid, old_id=old_id)))
        return response_result(read_frame(sock))


def wait_for_server(port: int) -> None:
    deadline = time.time() + 15
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.25)
    raise RuntimeError("hbbs did not start")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: test_server_custom_id.py PORT DB_PATH")
    port = int(sys.argv[1])
    db_path = sys.argv[2]
    wait_for_server(port)

    uuid_a = b"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    uuid_b = b"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    udp_register(port, "111222333", uuid_a, b"a" * 32)
    udp_register(port, "444555666", uuid_b, b"b" * 32)

    assert change_id(port, "111222333", "Philipp", b"wrong-uuid") == 2
    assert change_id(port, "111222333", "bad", uuid_a) == 5
    assert change_id(port, "111222333", "Philipp", uuid_a) == 0
    assert change_id(port, "444555666", "Philipp", uuid_b) == 3

    with sqlite3.connect(db_path) as connection:
        old_count = connection.execute(
            "select count(*) from peer where id = ?", ("111222333",)
        ).fetchone()[0]
        new_row = connection.execute(
            "select uuid, pk from peer where id = ?", ("Philipp",)
        ).fetchone()
    assert old_count == 0
    assert new_row == (uuid_a, b"a" * 32)
    print("custom ID smoke test passed")


if __name__ == "__main__":
    main()
