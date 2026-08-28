#!/usr/bin/env bash
# 发版闸：拒绝任何混入了源码 / 备份 / 临时文件的 IPA。
#
# 背景：project.yml 的 sources 会把目录里 Xcode 不认识的文件当资源原样打进 .app。
# 2026-08-28 因此把 12 个 .swift 备份打进了 build 35/36/37 并上传 App Store。
# 这道闸让同类问题在上传前就失败，而不是事后才发现。
#
# 用法: verify-ipa-clean.sh <path-to-ipa>

set -euo pipefail

IPA="${1:?usage: verify-ipa-clean.sh <path-to-ipa>}"
[ -f "$IPA" ] || { echo "IPA not found: $IPA" >&2; exit 2; }

# 只看 Payload 内的文件名；匹配源码后缀与常见备份/临时后缀。
leaked="$(unzip -l "$IPA" \
  | awk '{ $1=$2=$3=""; sub(/^ +/,""); print }' \
  | grep -E '\.(swift|m|mm|c|cpp|h)($|\.)|\.bak|\.orig$|\.rej$|\.tmp($|\.)|\.swp$|~$' \
  || true)"

if [ -n "$leaked" ]; then
  echo "" >&2
  echo "🔴 发版闸拦截：IPA 里混入了不该出现的源码/备份文件，已中止。" >&2
  echo "" >&2
  printf '%s\n' "$leaked" | sed 's/^/    /' >&2
  echo "" >&2
  echo "修法：把这些文件移出 App/ 和 Tunnel/（例如放到项目根的 .backups/），" >&2
  echo "      并确认 project.yml 两个 target 的 sources.excludes 仍然生效。" >&2
  echo "" >&2
  exit 1
fi

echo "    ✅ 发版闸通过：IPA 内无源码/备份文件"
