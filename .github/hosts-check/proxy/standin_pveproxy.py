"""Stand-in pveproxy for role proxmox_proxy's test: TLS on 127.0.0.1:8006 with the web UI certificate.

GET /                        200, or the status in /run/standin/front_status; waits the seconds in
                             /run/standin/front_delay first (so a test can stop the move during its proofs)
GET /api2/json/version       401, as pveproxy answers without a ticket
Upgrade to .../vncwebsocket  401 with vncticket=none, as pveproxy answers a console without a ticket
Upgrade to /ws-echo          101, then echoes every byte back until the client closes (an open console)
"""
import os
import socket
import ssl
import threading
import time


def setting(name, default):
    try:
        with open(f"/run/standin/{name}") as f:
            return f.read().strip() or default
    except OSError:
        return default


def reply(conn, status, reason, body=b""):
    conn.sendall(f"HTTP/1.1 {status} {reason}\r\nContent-Length: {len(body)}\r\nConnection: close\r\n\r\n".encode() + body)


def handle(conn):
    try:
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                return
            data += chunk
        head = data.split(b"\r\n\r\n", 1)[0].decode("latin-1")
        path = head.split("\r\n", 1)[0].split(" ")[1]
        upgrade = "upgrade: websocket" in head.lower()
        if upgrade and path.startswith("/ws-echo"):
            conn.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                         b"Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n")
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    return
                conn.sendall(chunk)
        if upgrade or path.startswith("/api2/"):
            reply(conn, 401, "No ticket")
            return
        if path == "/":
            time.sleep(float(setting("front_delay", "0")))
            status = int(setting("front_status", "200"))
            reply(conn, status, "OK" if status == 200 else "Stand-in", b"stand-in front page")
            return
        reply(conn, 404, "Not Found")
    except OSError:
        pass
    finally:
        conn.close()


def main():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain("/etc/pve/local/pveproxy-ssl.pem", "/etc/pve/local/pveproxy-ssl.key")
    os.makedirs("/run/standin", exist_ok=True)
    srv = socket.create_server(("127.0.0.1", 8006), reuse_port=True)
    with ctx.wrap_socket(srv, server_side=True) as tls:
        while True:
            try:
                conn, _ = tls.accept()
            except (OSError, ssl.SSLError):
                continue
            threading.Thread(target=handle, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()
