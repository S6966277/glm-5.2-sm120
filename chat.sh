#!/usr/bin/env bash
# Talk to the running GLM-5.2 endpoint. Just works:
#   ./chat.sh "write a haiku about GPUs"
#   ./chat.sh --think "prove sqrt(2) is irrational"   # full chain-of-thought
#   echo "summarize this" | ./chat.sh
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] && { set -a; . ./.env; set +a; }
PORT="${PORT:-8000}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-glm-5.2}"

THINK=0
if [ "${1:-}" = "--think" ]; then THINK=1; shift; fi
PROMPT="${*:-}"
[ -z "${PROMPT}" ] && PROMPT="$(cat)"   # allow piping

PROMPT="${PROMPT}" THINK="${THINK}" PORT="${PORT}" MODEL="${SERVED_MODEL_NAME}" python3 - <<'PY'
import json, os, sys, urllib.request
prompt=os.environ["PROMPT"]; think=os.environ["THINK"]=="1"
url=f"http://localhost:{os.environ['PORT']}/v1/chat/completions"
payload={"model":os.environ["MODEL"],"messages":[{"role":"user","content":prompt}],
         "temperature":0.6,"stream":True,"stream_options":{"include_usage":True}}
# thinking on -> let the model reason and give it room; off -> snappy direct answer
if think:
    payload["chat_template_kwargs"]={"enable_thinking":True}
    payload["max_tokens"]=8000
else:
    payload["max_tokens"]=2000
req=urllib.request.Request(url,data=json.dumps(payload).encode(),headers={"Content-Type":"application/json"})
in_think=False
with urllib.request.urlopen(req,timeout=1800) as r:
    for raw in r:
        line=raw.decode("utf-8","ignore").strip()
        if not line.startswith("data:"): continue
        line=line[5:].strip()
        if line=="[DONE]": break
        try: obj=json.loads(line)
        except Exception: continue
        for ch in obj.get("choices",[]):
            d=ch.get("delta",{}) or {}
            rt=d.get("reasoning") or d.get("reasoning_content")
            if rt:
                if not in_think: sys.stderr.write("\033[2m[thinking] "); in_think=True
                sys.stderr.write(rt); sys.stderr.flush()
            c=d.get("content")
            if c:
                if in_think: sys.stderr.write("\033[0m\n\n"); in_think=False
                sys.stdout.write(c); sys.stdout.flush()
print()
PY
