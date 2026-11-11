#!/usr/bin/env python3
"""复核本地文章交付；只读正文和图片，不启动游戏、不访问线上账号。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import struct
import subprocess

HERE = Path(__file__).resolve().parent
BLOGS = HERE.parents[2]
ROOT = BLOGS.parents[1]


def read_json(path):
    """读取 UTF-8 制作记录。"""
    return json.loads(path.read_text(encoding="utf-8"))


def digest(path):
    """计算文件完整内容的 SHA-256。"""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prose_count(text):
    """正文汉字：排除标题、代码、图片、链接地址和文末相关内容。"""
    text = text.split("### 相关内容", 1)[0]
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    text = re.sub(r"```[^\n]*\n.*?```", "", text, flags=re.S)
    text = re.sub(r"`[^`]*`", "", text)
    text = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", text)
    text = re.sub(r"\{\{IMG:[^}]+\}\}", "", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"^#{1,6} .*?$", "", text, flags=re.M)
    text = re.sub(r"^> 本文回顾.*?$", "", text, flags=re.M)
    return len(re.findall(r"[\u4e00-\u9fff]", text))


def validate(require_ready=False):
    """逐篇检查结构、资源和代码原样保留，并输出可定位的错误。"""
    baseline = read_json(HERE / "baseline.json")
    changes = {x["id"]: x for x in read_json(HERE / "article_changes.json")}
    links = {x["id"]: x for x in read_json(HERE / "series_links.json")}
    diagrams = {x["path"]: x for x in read_json(HERE / "diagram_render_results.json")}
    errors, rows, all_images = [], [], set()
    code_counts = {}

    def check(ok, message):
        if not ok:
            errors.append(message)

    check(len(baseline["articles"]) == 80, "基线必须有 80 篇")
    check(len(list(BLOGS.glob("[0-9][0-9]-*.publish.json"))) == 80, "配置必须有 80 份")
    for a in baseline["articles"]:
        ident = a["id"]
        p = BLOGS / a["file"]
        t = p.read_text(encoding="utf-8")
        config = read_json(p.with_suffix(".publish.json"))
        check(config["id"] == ident and config["title"] == a["title"] == t.splitlines()[0][2:], ident + " 标题/ID")
        check(config["schemaVersion"] == 2 and config["platform"] == "csdn", ident + " 配置版本")
        check(config["categoryNames"] == ["末法纪元", "Godot"] and "categoryName" not in config, ident + " 双分类")
        check(config["articleType"] == "original", ident + " 原创类型")
        check(0 < len(config["description"]) <= 250 and len(config["tags"]) == 5, ident + " 简介/标签")
        check(isinstance(config["ready"], bool) and (config["ready"] or not require_ready), ident + " 本地就绪状态")
        check(not re.search(r"PUBLISH_ASSIST|\{\{(?:IMG|LINK):", t), ident + " 发布占位残留")
        check(t.count("```") % 2 == 0, ident + " 代码围栏不成对")
        blocks = re.findall(r"```([^\n]*)\n(.*?)```", t, re.S)
        check(blocks == re.findall(r"```([^\n]*)\n(.*?)```", a["body"], re.S), ident + " 代码被改写")
        for index, (language, code) in enumerate(blocks):
            code_counts[language] = code_counts.get(language, 0) + 1
            if language == "sh":
                result = subprocess.run(["sh", "-n"], input=code, text=True, capture_output=True)
                check(result.returncode == 0, f"{ident} shell 段 {index}: {result.stderr}")
            elif language == "python":
                try:
                    compile(code, f"{ident}-block-{index}", "exec")
                except SyntaxError as e:
                    check(False, f"{ident} Python 段 {index}: {e}")
            elif language == "json":
                try:
                    json.loads(code)
                except json.JSONDecodeError as e:
                    check(False, f"{ident} JSON 段 {index}: {e}")
        paths = re.findall(r"!\[[^\]]*\]\(([^)]+)\)", t)
        check(len(paths) == 3 and len(set(paths)) == 3, ident + " 必须有三张不同配图")
        check(config["cover"] in paths, ident + " 封面未引用")
        image_rows = []
        for relative in paths:
            image_path = BLOGS / relative
            check(relative.startswith("./assets/game/" + ident + "/"), ident + " 图片路径越界")
            check(image_path.is_file(), ident + " 缺少图片 " + relative)
            if not image_path.is_file():
                continue
            data = image_path.read_bytes()
            check(data[:8] == b"\x89PNG\r\n\x1a\n", ident + " 非 PNG")
            width, height = struct.unpack(">II", data[16:24])
            is_cover = image_path.name == "封面.png"
            ratio = 16 / 9 if is_cover else 3 / 2
            check(abs(width / height - ratio) < 0.01, ident + " 图片比例 " + relative)
            check(width >= 1400, ident + " 图片清晰度 " + relative)
            sha = digest(image_path)
            key = relative.removeprefix("./")
            if not is_cover:
                check(key in diagrams and diagrams[key]["sha256"] == sha, ident + " 图解制作记录校验")
            all_images.add(key)
            image_rows.append({"path": key, "width": width, "height": height, "sha256": sha})
        check(digest(p) == changes[ident]["finalSha256"], ident + " 正文变更记录哈希")
        source = subprocess.check_output(["git", "show", f"6c7aa51b:docs/blogs/{a['file']}"], cwd=ROOT)
        check(hashlib.sha256(source).hexdigest() == a["sha256"], ident + " 历史审阅基线不一致")
        for ref in links[ident]["references"]:
            check(int(ref["target"][-2:]) < int(a["number"]), ident + " 引用了后文")
            check(ref["replacement"] in t, ident + " 系列引用记录不一致")
        before, after = prose_count(a["body"]), prose_count(t)
        check(2200 <= after <= 3000, ident + f" 正文篇幅 {after}")
        rows.append({"id": ident, "file": a["file"], "beforeChineseCharacters": before,
                     "afterChineseCharacters": after, "images": image_rows,
                     "codeBlocks": len(blocks), "seriesReferences": len(links[ident]["references"]),
                     "ready": config["ready"], "sha256": digest(p)})
    check(len(all_images) == 240, "必须引用 240 张不同图片")
    check(len(list((BLOGS / "assets/game").glob("GAME-*/*.png"))) == 240, "配图目录必须有 240 张 PNG")
    diff = subprocess.run(["git", "diff", "--check"], cwd=ROOT, text=True, capture_output=True)
    check(diff.returncode == 0, "git diff --check: " + diff.stdout + diff.stderr)
    changed = subprocess.check_output(["git", "diff", "--name-only", "-z"], cwd=ROOT, text=True).strip("\0").split("\0")
    check(all(p.startswith("docs/blogs/") for p in changed), "存在博客目录外的已跟踪修改")
    return {"date": "2026-11-10", "passed": not errors, "errors": errors,
            "scope": "本地文章/发布配置/配图静态检查；不代表线上发布或游戏测试通过",
            "sourceAuditCommit": "6c7aa51b", "sourceHead": baseline["commit"],
            "articleCount": len(rows), "imageCount": len(all_images), "codeBlocks": code_counts,
            "seriesReferences": sum(r["seriesReferences"] for r in rows), "articles": rows}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-ready", action="store_true", help="同时要求配置 ready=true")
    parser.add_argument("--output", type=Path, help="把检查结果写入指定 JSON；省略则只打印摘要")
    args = parser.parse_args()
    report = validate(args.require_ready)
    if args.output:
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "articles"}, ensure_ascii=False, indent=2))
    raise SystemExit(0 if report["passed"] else 1)
