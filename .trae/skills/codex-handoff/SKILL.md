---
name: codex-handoff
description: Send tasks to a local Codex session through its bundled CLI and review the results. Use when the user asks to 与 Codex 对话, 把任务交给 Codex, 让 Codex 生成素材, queue a message to a Codex session, or hand off work to Codex. Do not use for general automation.
---

# Local Codex Handoff

Relay work to the Codex desktop app's session, then review what it returns. Do not re-analyze the channel each time — follow this.

## Locate the CLI

The Codex CLI ships inside the ChatGPT desktop app and is **not** on `PATH`:

```bash
CODEX="/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
"$CODEX" --version
```

If that path is gone, locate the bundle and the CLI inside it:

```bash
mdfind "kMDItemCFBundleIdentifier == 'com.openai.codex'"
find /Applications/ChatGPT.app/Contents -maxdepth 5 -iname "*codex*" -type f
```

## Find the target session

`codex agents` browses all sessions, but it is an interactive TUI. In a script, read the app state instead. `~/.codex/.codex-global-state.json` holds `electron-persisted-atom-state["thread-descriptions-v1"]`, a map of thread UUID to its description string.

```bash
python3 .trae/skills/codex-handoff/scripts/list_codex_sessions.py [keyword]
```

Match the session by description, then use its **UUID** for sending. The UUID is stable; display names drift.

## Send a message to an existing session

```bash
CODEX="/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
MSG=$(cat <<'EOF'
...multi-line message, Chinese is fine...
EOF
)
"$CODEX" queue --thread <UUID-or-exact-session-name> --message "$MSG"
```

Learned the hard way:

- `codex queue` does **not** accept image attachments — `-i` fails. Put file paths in the message text and let the session load them itself.
- Always build the message with a heredoc (`<<'EOF'`). Inline quoting breaks on multi-line Chinese text.
- `--thread` accepts a UUID or an exact session name. Prefer the UUID.

Other subcommands: `codex exec` (non-interactive run in a workspace), `codex resume`, `codex archive --thread ...`.

## Wait for completion (do not idle)

Never block the turn on "user will tell me when it's done". Codex writes one `task_complete` event per turn into its rollout stream, so completion is machine-detectable — and often finishes sooner than expected. Always poll:

```bash
python3 .trae/skills/codex-handoff/scripts/wait_for_codex.py --thread <UUID> \
  --expect docs/素材设计/<NN>-<name>.md \
  --expect art_source/environment/<...>.png \
  --interval 20 --timeout 3600
```

- One-shot check: add `--status`.
- Exit 0 = turn finished and all `--expect` files exist; 2 = timeout / finished but artifacts missing; 3 = stalled (rollout silent past `--stall`, e.g. the queue never got picked up).
- Rollout path is globbed from `~/.codex/sessions/**/*<UUID>*.jsonl`. Do **not** read `~/.codex/*.sqlite` in the poll loop — the app holds write locks.
- Pass `--expect` for the artifacts the task is supposed to produce; a chat reply alone is not proof.

Note: `codex queue` returns immediately after the message is enqueued. An empty `queued_items` row plus no new turn means the app has not started the turn yet.

## Judge what came back

A `task_complete` event plus a friendly reply is not verification. Open the artifacts, measure them (seams, density, palette, naming, location), and write an independent review doc. Two traps seen in practice:

- Verifying ground tiles with a square `tile:` repeat plus hard-pasted characters produces a fake "wallpaper / characters hung on a wall" result. Warp to the real 2:1 diamond first, add edge relief, and give characters a contact shadow.
- Building a blank base with `xc:none` in ImageMagick 7 collapses composites to grayscale (the result inherits the destination colorspace). Use `xc:"#010000" -alpha set -channel A -evaluate set 0 +channel`.

## Handoff pattern

1. **Write the task as a workspace Markdown doc.** Project rule: cross-AI collaboration goes through Markdown documents, not chat. Put prompts and specs in a numbered doc (this repo: `docs/素材设计/<NN>-<name>.md`).
2. **Queue a short pointer message, not the whole spec.** State: which docs to read, exactly what to produce this round, output paths, verification steps, and hard constraints.
3. **Always state the hard constraints.** Do not modify `assets/`, `data/`, any `.gd` code, or existing docs; write source assets to `art_source/...`; write a short report doc when done.
4. **Wait, then review.** When the session reports done, verify the deliverable against the spec — seamless tiling, pixel density, palette match, naming and location — and write an independent review doc. Do not trust its report alone.
5. **One round, one item.** Dispatch a single item, review it, then continue. Bulk-generation requests produce unverifiable batches.

## Project session registry

| Session | Role | Thread UUID |
|---|---|---|
| 制图大师 | 地图 / 图片素材制作 | `01a1455b-aa43-7473-ae0b-a64888788392` |

Re-resolve the UUID from the state file if the session is recreated.
