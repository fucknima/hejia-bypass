#!/bin/sh
# GitHub 发布脚本：建仓 -> 推送 -> 触发 Actions
# 用法： GITHUB_TOKEN=xxx GITHUB_USER=xxx ./push_to_github.sh [仓库名]
set -e

: "${GITHUB_TOKEN:?需要设置 GITHUB_TOKEN}"
: "${GITHUB_USER:?需要设置 GITHUB_USER}"
REPO="${1:-hejia-bypass}"
DIR=$(cd "$(dirname "$0")" && pwd)
API="https://api.github.com"

echo "==> 1/4 校验 token"
WHO=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" "$API/user" | grep '"login"' | head -1 | cut -d'"' -f4)
[ -z "$WHO" ] && { echo "❌ token 无效"; exit 1; }
echo "    已认证：$WHO"

echo "==> 2/4 确保仓库存在"
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $GITHUB_TOKEN" "$API/repos/$GITHUB_USER/$REPO")
if [ "$CODE" = "404" ]; then
  curl -s -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "$API/user/repos" \
    -d "{\"name\":\"$REPO\",\"description\":\"移动爱家检测绕过 tweak (Theos)\",\"private\":false}" \
    | grep -q '"full_name"' && echo "    已创建 $GITHUB_USER/$REPO" || { echo "❌ 建仓失败"; exit 1; }
else
  echo "    仓库已存在"
fi

echo "==> 3/4 推送代码"
cd "$DIR"
git remote remove origin 2>/dev/null || true
git remote add origin "https://x-access-token:$GITHUB_TOKEN@github.com/$GITHUB_USER/$REPO.git"
git branch -M main 2>/dev/null || true
git push -u origin main 2>&1 | tail -5

echo "==> 4/4 触发 Actions"
sleep 3
curl -s -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "$API/repos/$GITHUB_USER/$REPO/actions/workflows/build.yml/dispatches" \
  -d '{"ref":"main"}' -o /dev/null -w "    dispatch: %{http_code}\n"

echo ""
echo "✅ 完成： https://github.com/$GITHUB_USER/$REPO/actions"
