"""Local WSL build helper: reuse Windows loopback proxy over WSL stdio.

Never installed in product images or NAS bundles. No Docker API is exposed.
"""
import argparse
import os
import socket
import socketserver
import subprocess
import sys
import threading


def windows_stdio(port):
    import msvcrt
    for stream in (sys.stdin, sys.stdout):
        msvcrt.setmode(stream.fileno(), os.O_BINARY)
    with socket.create_connection(("127.0.0.1", port), timeout=15) as upstream:
        upstream.settimeout(180)
        def send():
            try:
                while chunk := sys.stdin.buffer.read1(65536):
                    upstream.sendall(chunk)
            except OSError:
                pass
            finally:
                try:
                    upstream.shutdown(socket.SHUT_WR)
                except OSError:
                    pass
        threading.Thread(target=send, daemon=True).start()
        try:
            while chunk := upstream.recv(65536):
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
        except OSError:
            pass


def linux_relay(args):
    class Relay(socketserver.BaseRequestHandler):
        def handle(self):
            with subprocess.Popen([args.windows_python, "-u", args.windows_script, "stdio",
                                   "--proxy-port", str(args.proxy_port)], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE) as child:
                self.request.settimeout(180)
                def send():
                    try:
                        while chunk := self.request.recv(65536):
                            child.stdin.write(chunk)
                            child.stdin.flush()
                    except OSError:
                        pass
                    finally:
                        child.stdin.close()
                threading.Thread(target=send, daemon=True).start()
                try:
                    while chunk := child.stdout.read1(65536):
                        self.request.sendall(chunk)
                except OSError:
                    pass
                finally:
                    child.terminate()
                    child.wait(timeout=5)
    class Server(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
        daemon_threads = True
        # Bound the number of Windows helper processes during a stalled build.
        slots = threading.BoundedSemaphore(32)
        def process_request(self, request, client_address):
            if not self.slots.acquire(blocking=False):
                self.shutdown_request(request)
                return
            try:
                super().process_request(request, client_address)
            except BaseException:
                self.slots.release()
                raise
        def process_request_thread(self, request, client_address):
            try:
                super().process_request_thread(request, client_address)
            finally:
                self.slots.release()
    # Bind only WSL loopback and the private Docker bridge, never the WSL LAN IP.
    with Server(("127.0.0.1", args.listen_port), Relay) as local, Server((args.bridge, args.listen_port), Relay) as bridge:
        threading.Thread(target=bridge.serve_forever, daemon=True).start()
        local.serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("stdio", "relay"))
    parser.add_argument("--proxy-port", type=int, default=7890)
    parser.add_argument("--listen-port", type=int, default=18080)
    parser.add_argument("--windows-python")
    parser.add_argument("--windows-script")
    parser.add_argument("--bridge", default="172.17.0.1")
    arguments = parser.parse_args()
    if arguments.mode == "stdio":
        if os.name != "nt":
            parser.error("stdio mode requires Windows")
        windows_stdio(arguments.proxy_port)
    else:
        if os.name != "posix" or not arguments.windows_python or not arguments.windows_script:
            parser.error("relay mode requires WSL and Windows helper paths")
        linux_relay(arguments)
