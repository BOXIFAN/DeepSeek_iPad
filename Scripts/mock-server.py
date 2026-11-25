#!/usr/bin/env python3
"""离线验证用的假 DeepSeek 服务。

- POST /anthropic/v1/messages：把请求体写到 /tmp/mock-req-<n>.json，回一段 SSE 流
- GET  /user/balance：回一份余额 JSON
用法：python3 Scripts/mock-server.py [port]

排障开关：
  MOCK_BALANCE_FAIL_TIMES=2  前两次余额请求回 503，用来验自动重试
  MOCK_DELAY=0.12            每个 SSE 事件之间的间隔，放慢流式便于截实时速度
"""
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8710
FAIL_TIMES = int(os.environ.get("MOCK_BALANCE_FAIL_TIMES", "0"))
DELAY = float(os.environ.get("MOCK_DELAY", "0.02"))
REQ_DIR = "/tmp/mock-requests"
os.makedirs(REQ_DIR, exist_ok=True)
counter = {"n": 0, "balance_failures": 0}

BALANCE = {
    "is_available": True,
    "balance_infos": [
        {
            "currency": "CNY",
            "total_balance": "14.41",
            "granted_balance": "10.00",
            "topped_up_balance": "4.41",
        }
    ],
}

TEXT = (
    "收到。这条回复来自本地 mock 服务器，用来验证流式解析这条链路。\n\n"
    "## 上游给过的内容\n\n"
    "| 项目 | 值 |\n"
    "| --- | --- |\n"
    "| 事件顺序 | message_start → block → message_delta |\n"
    "| 块类型 | thinking + text |\n\n"
    "如果这段渲染正常，说明 SSE 解析、块拼接、Markdown 排版都通了。"
)

EVENTS = [
    ("message_start", {"type": "message_start",
                       "message": {"id": "msg_mock", "role": "assistant", "model": "deepseek-flash",
                                   "usage": {"input_tokens": 1240,
                                             "cache_read_input_tokens": 8200,
                                             "cache_creation_input_tokens": 0,
                                             "output_tokens": 1}}}),
    ("content_block_start", {"type": "content_block_start", "index": 0,
                             "content_block": {"type": "thinking", "thinking": ""}}),
    ("content_block_delta", {"type": "content_block_delta", "index": 0,
                             "delta": {"type": "thinking_delta",
                                       "thinking": "先确认请求里有没有带上 system。"}}),
    ("content_block_stop", {"type": "content_block_stop", "index": 0}),
    ("content_block_start", {"type": "content_block_start", "index": 1,
                             "content_block": {"type": "text", "text": ""}}),
]
for chunk in [TEXT[i:i + 24] for i in range(0, len(TEXT), 24)]:
    EVENTS.append(("content_block_delta", {"type": "content_block_delta", "index": 1,
                                           "delta": {"type": "text_delta", "text": chunk}}))
EVENTS += [
    ("content_block_stop", {"type": "content_block_stop", "index": 1}),
    # 输入与缓存只在 message_start 给，最终输出只在 message_delta 给，和官方流一致
    ("message_delta", {"type": "message_delta",
                       "delta": {"stop_reason": "end_turn"},
                       "usage": {"output_tokens": 96,
                                 "output_tokens_details": {"thinking_tokens": 28}}}),
    ("message_stop", {"type": "message_stop"}),
]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("[mock] " + (fmt % args) + "\n")

    def do_GET(self):
        if self.path.startswith("/user/balance"):
            if counter["balance_failures"] < FAIL_TIMES:
                counter["balance_failures"] += 1
                sys.stderr.write("[mock] balance 503 #%d\n" % counter["balance_failures"])
                self.send_error(503)
                return
            body = json.dumps(BALANCE).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_error(404)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        counter["n"] += 1
        path = os.path.join(REQ_DIR, f"req-{counter['n']:02d}.json")
        with open(path, "wb") as handle:
            handle.write(raw)
        with open("/tmp/mock-last-request.json", "wb") as handle:
            handle.write(raw)

        if not self.path.startswith("/anthropic/v1/messages"):
            self.send_error(404)
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()

        try:
            for name, payload in EVENTS:
                chunk = f"event: {name}\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"
                self.wfile.write(chunk.encode())
                self.wfile.flush()
                time.sleep(DELAY)
        except BrokenPipeError:
            pass
        self.close_connection = True


if __name__ == "__main__":
    print(f"[mock] listening on 127.0.0.1:{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
