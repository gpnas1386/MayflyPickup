#!/bin/sh
# 一次性:建仓库 + 推代码 + 触发云构建
# 前置:export GH_TOKEN=...  (fine-grained PAT 需 Contents:write + Workflows:write + Administration:write)
set -e
cd "$(dirname "$0")/.."
: "${GH_TOKEN:?缺少 GH_TOKEN}"
OWNER=${OWNER:-$(curl -s -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/user | python3 -c 'import sys,json;print(json.load(sys.stdin)["login"])')}
REPO=${REPO:-MayflyPickup}
api() { curl -s -X "$1" -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" "https://api.github.com$2" ${3:+-d "$3"}; }

echo "[1/3] 创建仓库 $OWNER/$REPO"
api POST /user/repos "{\"name\":\"$REPO\",\"private\":false,\"auto_init\":false}" | head -c 200; echo

echo "[2/3] 推送"
git init -q 2>/dev/null || true
git add -A
git -c user.email=minis@local -c user.name=minis commit -q -m "MayflyPickup: 重写" || true
git branch -M main
git remote remove origin 2>/dev/null || true
git remote add origin "https://x-access-token:$GH_TOKEN@github.com/$OWNER/$REPO.git"
git push -q -f origin main
echo "pushed"

echo "[3/3] 等待 Actions"
sleep 20
RUN=$(curl -s -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/repos/$OWNER/$REPO/actions/runs?per_page=1" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["workflow_runs"][0]["id"] if d.get("workflow_runs") else "")')
echo "run=$RUN"
echo "https://github.com/$OWNER/$REPO/actions/runs/$RUN"
echo "$RUN" > /tmp/build_run_id
