#!/usr/bin/env python3
"""A stand-in for the AI providers' streaming APIs, on 127.0.0.1, for the tests: never a paid API.

It answers as the real ones stream (server-sent events), in each one's own format:

- the Claude API: POST /v1/messages (x-api-key), content_block_delta events, then message_delta's stop_reason;
- OpenAI-compatible: POST .../chat/completions (Authorization: Bearer), choices[0].delta.content, then [DONE];
- Gemini: POST /v1beta/models/<model>:streamGenerateContent?alt=sse (x-goog-api-key), candidates[0].content.parts.

What it answers is the core's level-two format, one "EN:" line per version (`CandidateParser`), sent in small pieces a
few milliseconds apart so that the engine sees a stream. Each request is logged as one JSON line to --log: the path, the
key header it came with, the model, the last message's length (never the key itself: only whether it is the expected
one).

    python stub-provider.py [--port N] [--port-file FILE] [--log FILE] [--key KEY]
                            [--versions "Hello there.|Hi!|Greetings."] [--status 200] [--lifetime 900]

--key: the key a request must carry (else 401, as the real APIs answer). --status: answer every request with this
status and an error body instead. It exits after --lifetime seconds, so a test that died never leaves it running.
"""
import argparse
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=0)
    p.add_argument("--port-file")
    p.add_argument("--log")
    p.add_argument("--key", default="stub-key")
    p.add_argument("--versions", default="Hello there.|Hi!|Greetings.")
    p.add_argument("--status", type=int, default=200)
    p.add_argument("--delay-ms", type=int, default=30)
    p.add_argument("--lifetime", type=float, default=900)
    return p.parse_args()


ARGS = parse_args()
LOG_LOCK = threading.Lock()


def log(entry):
    if not ARGS.log:
        return
    with LOG_LOCK:
        with open(ARGS.log, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def answer_text():
    return "".join("EN: %s\n" % v for v in ARGS.versions.split("|") if v)


def pieces(text, size=6):
    return [text[i:i + size] for i in range(0, len(text), size)]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # quiet: the JSON log has what matters
        pass

    def do_POST(self):
        raw = self.read_body()
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except ValueError:
            body = {}
        path = self.path
        if path.endswith("/v1/messages"):
            kind, key = "anthropic", self.headers.get("x-api-key")
        elif path.endswith("/chat/completions"):
            auth = self.headers.get("Authorization") or ""
            kind, key = "openai", auth[7:] if auth.startswith("Bearer ") else None
        elif ":streamGenerateContent" in path:
            kind, key = "gemini", self.headers.get("x-goog-api-key")
        else:
            self.send_error_json(404, "not_found", "no such endpoint")
            return
        messages = body.get("messages") or body.get("contents") or []
        last = messages[-1] if messages else {}
        content = last.get("content") if isinstance(last, dict) else None
        if content is None and isinstance(last, dict):
            content = "".join(part.get("text", "") for part in last.get("parts", []))
        log({"kind": kind, "path": path, "keyOk": key == ARGS.key, "model": body.get("model"),
             "stream": body.get("stream"), "lastMessageLength": len(content or ""), "bodyLength": len(raw),
             "chunked": "chunked" in (self.headers.get("Transfer-Encoding") or ""), "time": time.time(),
             "headers": {k: v for k, v in self.headers.items()
                         if k.lower() not in ("x-api-key", "authorization", "x-goog-api-key")}})
        if key != ARGS.key:
            self.send_error_json(401, "authentication_error", "invalid x-api-key")
            return
        if ARGS.status != 200:
            self.send_error_json(ARGS.status, "overloaded_error", "the stub was told to fail")
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        text = answer_text()
        try:
            if kind == "anthropic":
                self.event("message_start", {"type": "message_start", "message": {"id": "msg_stub", "type": "message",
                                                                                    "role": "assistant", "content": []}})
                self.event("content_block_start", {"type": "content_block_start", "index": 0,
                                                   "content_block": {"type": "text", "text": ""}})
                for piece in pieces(text):
                    self.event("content_block_delta", {"type": "content_block_delta", "index": 0,
                                                       "delta": {"type": "text_delta", "text": piece}})
                self.event("content_block_stop", {"type": "content_block_stop", "index": 0})
                self.event("message_delta", {"type": "message_delta", "delta": {"stop_reason": "end_turn"}})
                self.event("message_stop", {"type": "message_stop"})
            elif kind == "openai":
                for piece in pieces(text):
                    self.data({"choices": [{"index": 0, "delta": {"content": piece}}]})
                self.data({"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]})
                self.raw_data("[DONE]")
            else:
                for piece in pieces(text):
                    self.data({"candidates": [{"content": {"parts": [{"text": piece}], "role": "model"}}]})
                self.data({"candidates": [{"content": {"parts": [], "role": "model"}, "finishReason": "STOP"}]})
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass  # the engine stopped reading (Esc)
        time.sleep(0.05)
        self.close_connection = True

    def read_body(self):
        """The request's body: by its Content-Length, or chunk by chunk (Transfer-Encoding: chunked)."""
        if "chunked" in (self.headers.get("Transfer-Encoding") or "").lower():
            data = b""
            while True:
                size = int(self.rfile.readline().split(b";")[0].strip() or b"0", 16)
                if size == 0:
                    self.rfile.readline()  # the empty line after the last chunk (no trailers)
                    return data
                data += self.rfile.read(size)
                self.rfile.readline()
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def event(self, name, payload):
        self.wfile.write(("event: %s\n" % name).encode("utf-8"))
        self.data(payload)

    def data(self, payload):
        self.raw_data(json.dumps(payload, ensure_ascii=False))

    def raw_data(self, text):
        self.wfile.write(("data: %s\n\n" % text).encode("utf-8"))
        self.wfile.flush()
        time.sleep(ARGS.delay_ms / 1000.0)

    def send_error_json(self, status, kind, message):
        body = json.dumps({"type": "error", "error": {"type": kind, "message": message}}).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.wfile.flush()
        # Closed a moment later: on Windows a socket closed at once can reset the connection before the client has
        # read the answer.
        time.sleep(0.05)
        self.close_connection = True


def main():
    server = ThreadingHTTPServer(("127.0.0.1", ARGS.port), Handler)
    port = server.server_address[1]
    if ARGS.port_file:
        with open(ARGS.port_file, "w", encoding="utf-8") as f:
            f.write(str(port))
    print("stub-provider: listening on 127.0.0.1:%d" % port, flush=True)
    timer = threading.Timer(ARGS.lifetime, server.shutdown)
    timer.daemon = True
    timer.start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    sys.exit(0)


if __name__ == "__main__":
    main()
