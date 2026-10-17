#!/usr/bin/env python3
"""等待并检测本地 Codex 会话是否完成某一轮任务。

原理：Codex 每轮结束都会在 rollout 事件流里写一条 `event_msg`/`task_complete`
（另外可选按期望产物文件是否出现双重判定）。rollout 文件路径由线程 UUID
在 ~/.codex/sessions/ 下 glob 得到，不需要读 sqlite，避免被 app 写锁干扰。

用法：
  # 单次查询（不等待）
  python3 wait_for_codex.py --thread <UUID> --status

  # 轮询等待，直到出现新的 task_complete 且期望产物齐备
  python3 wait_for_codex.py --thread <UUID> \
      --expect docs/素材设计/29-M1制作回报-第二批.md \
      --expect art_source/environment/map_m1/M1-1b_wet_grass_160.png \
      --interval 20 --timeout 3600

退出码：0 = 完成；2 = 超时；3 = 疑似停滞（长时间无任何 rollout 写入）。
"""

import argparse
import glob
import json
import os
import sys
import time

SESSIONS = os.path.expanduser("~/.codex/sessions")


def find_rollout(thread: str) -> str | None:
    """按线程 UUID 或名称在 sessions 目录下定位 rollout 文件。"""
    hits = glob.glob(os.path.join(SESSIONS, "**", f"*{thread}*.jsonl"), recursive=True)
    if hits:
        return max(hits, key=os.path.getmtime)
    # UUID 不在文件名里时，回退：扫最近 40 个 rollout，按 id 字段匹配
    recent = sorted(
        glob.glob(os.path.join(SESSIONS, "**", "*.jsonl"), recursive=True),
        key=os.path.getmtime,
        reverse=True,
    )[:40]
    for path in recent:
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                for line in f:
                    if thread in line:
                        return path
        except OSError:
            continue
    return None


class Stream:
    """增量读取 rollout，统计 task_complete 次数并抓取最后一条助手正文。"""

    def __init__(self, path: str):
        self.path = path
        self.pos = 0            # 已消费到的字节偏移
        self._tail = b""        # 未成行的残留
        self.completions = 0
        self.last_message = ""
        self.last_ts = ""
        self._scan(initial=True)

    def _scan(self, initial: bool = False) -> None:
        try:
            size = os.path.getsize(self.path)
        except OSError:
            return
        if size < self.pos:
            # 文件被轮转/重写，重置
            self.pos, self._tail = 0, b""
        if size == self.pos and not initial:
            return
        with open(self.path, "rb") as f:
            f.seek(self.pos)
            chunk = self._tail + f.read()
        cut = chunk.rfind(b"\n")
        if cut == -1:
            self._tail = chunk
            return
        self._tail = chunk[cut + 1:]
        self.pos += cut + 1
        for raw in chunk[:cut].split(b"\n"):
            if b"task_complete" in raw:
                self.completions += 1
            if b'"message"' not in raw:
                continue
            try:
                obj = json.loads(raw.decode("utf-8", "replace"))
            except ValueError:
                continue
            if obj.get("type") != "response_item":
                continue
            p = obj.get("payload") or {}
            if p.get("type") != "message" or p.get("role") != "assistant":
                continue
            text = "".join(c.get("text", "") for c in (p.get("content") or []))
            if text.strip():
                self.last_message = text.strip()
                self.last_ts = obj.get("timestamp", "")

    def refresh(self) -> None:
        self._scan()


def age(path: str) -> float:
    try:
        return time.time() - os.path.getmtime(path)
    except OSError:
        return -1.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--thread", required=True, help="会话 UUID（优先）或名称片段")
    ap.add_argument("--expect", action="append", default=[], help="期望出现的产物文件，可重复")
    ap.add_argument("--interval", type=float, default=20.0)
    ap.add_argument("--timeout", type=float, default=1800.0)
    ap.add_argument("--stall", type=float, default=300.0, help="rollout 静默多久算停滞")
    ap.add_argument("--status", action="store_true", help="只查一次，不等待")
    args = ap.parse_args()

    rollout = find_rollout(args.thread)
    if not rollout:
        print(f"[err] 找不到线程 {args.thread} 的 rollout 文件", file=sys.stderr)
        return 1
    print(f"[info] rollout: {rollout}")

    st = Stream(rollout)
    base = st.completions
    print(f"[info] 基线 task_complete = {base}；静默 {age(rollout):.0f}s")

    def missing() -> list[str]:
        return [p for p in args.expect if not os.path.exists(p)]

    def announce(why: str) -> None:
        print(f"[done] {why}")
        if st.last_ts:
            print(f"[done] 最后一条助手消息 @ {st.last_ts}")
        if st.last_message:
            tail = st.last_message if len(st.last_message) < 800 else st.last_message[:800] + " …"
            print("-" * 60)
            print(tail)
            print("-" * 60)

    if args.status:
        miss = missing()
        print(f"[status] task_complete={st.completions} 新增={st.completions - base}")
        print(f"[status] 期望产物缺失: {miss or '无'}")
        return 0

    deadline = time.time() + args.timeout
    new_turn = False
    while time.time() < deadline:
        time.sleep(args.interval)
        st.refresh()
        if st.completions > base and not new_turn:
            new_turn = True
            print(f"[evt] 检测到新一轮完成 (task_complete={st.completions})")
        miss = missing()
        idle = age(rollout)
        if new_turn and not miss:
            announce("新一轮已完成，且期望产物齐备")
            return 0
        if new_turn and miss:
            print(f"[wait] 完成信号已到，仍缺产物: {len(miss)} 项 {miss[:3]}；静默 {idle:.0f}s")
            # 已完成但产物长期不出现，10 分钟后放弃
            if idle > args.stall:
                announce("新一轮已完成，但期望产物未出现（请人工检查）")
                return 2
            continue
        print(f"[wait] 尚无完成信号；rollout 静默 {idle:.0f}s")
        if idle > args.stall:
            print(f"[warn] rollout 静默超过 {args.stall:.0f}s，疑似停滞或队列未送达")
            return 3
    print("[timeout] 超时未等到完成信号")
    return 2


if __name__ == "__main__":
    sys.exit(main())
