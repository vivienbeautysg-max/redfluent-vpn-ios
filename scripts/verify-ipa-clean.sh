#!/usr/bin/env bash
# 发版闸：拒绝任何混入了源码 / 备份 / 临时文件、共用凭据配置或白名单外 .json 的 IPA。
#
# 背景：project.yml 的 sources 会把目录里 Xcode 不认识的文件当资源原样打进 .app。
# 2026-08-28 因此把 12 个 .swift 备份打进了 build 35/36/37 并上传 App Store。
# 这道闸让同类问题在上传前就失败，而不是事后才发现。
#
# 用法: verify-ipa-clean.sh <path-to-ipa>

set -euo pipefail

IPA="${1:?usage: verify-ipa-clean.sh <path-to-ipa>}"
[ -f "$IPA" ] || { echo "IPA not found: $IPA" >&2; exit 2; }

# IPA 内全部条目，一行一个完整路径（-Z1：不截断，带空格的文件名也完整）。
entries="$(unzip -Z1 "$IPA")"

# 只看文件名；匹配源码后缀与常见备份/临时后缀（不分大小写）。
leaked="$(printf '%s\n' "$entries" \
  | grep -iE '\.(swift|m|mm|c|cpp|h)($|\.)|\.bak|\.orig$|\.rej$|\.tmp($|\.)|\.swp$|~$' \
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

# 全员共用的旧凭据配置：扩展早已不再读取（只用服务器发给本设备的配置），出现在 IPA 里就等于把凭据随包分发。
# 不分大小写，也拦改名变体（Review-Tunnel.json、"review-tunnel copy.json"）。
shared_config="$(printf '%s\n' "$entries" | grep -iE 'review[-_ ]?tunnel' || true)"
if [ -n "$shared_config" ]; then
  echo "" >&2
  echo "🔴 发版闸拦截：IPA 里带着 review-tunnel 配置（共用 VPN 凭据），已中止。" >&2
  echo "" >&2
  printf '%s\n' "$shared_config" | sed 's/^/    /' >&2
  echo "" >&2
  echo "修法：确认 project.yml 的 RedFluentVPNTunnel 没有把 Tunnel/Resources 当资源打包，重新 xcodegen generate。" >&2
  echo "" >&2
  exit 1
fi

# 任何 .json 都不许进包，除非在白名单里：sing-box 配置就是 JSON，换个文件名（如 split-v3.json）照样是凭据。
# 白名单 = 正式构建里本来就有的 .json，写成匹配完整路径的正则，多条用 | 连接。
# 1.2 (43) 的正式 IPA 里唯一的 .json 就是 review-tunnel.json，所以目前为空：任何 .json 都拦。
JSON_ALLOW_RE=''
stray_json="$(printf '%s\n' "$entries" | grep -iE '\.json$' || true)"
if [ -n "$stray_json" ] && [ -n "$JSON_ALLOW_RE" ]; then
  stray_json="$(printf '%s\n' "$stray_json" | grep -viE "$JSON_ALLOW_RE" || true)"
fi
if [ -n "$stray_json" ]; then
  echo "" >&2
  echo "🔴 发版闸拦截：IPA 里有不在白名单的 .json 文件（可能是 VPN 配置/凭据），已中止。" >&2
  echo "" >&2
  printf '%s\n' "$stray_json" | sed 's/^/    /' >&2
  echo "" >&2
  echo "修法：查清它是怎么进包的并移出 App/ 和 Tunnel/；确实该发布的，加进本脚本的 JSON_ALLOW_RE。" >&2
  echo "" >&2
  exit 1
fi

echo "    ✅ 发版闸通过：IPA 内无源码/备份文件，无共用凭据配置，无白名单外的 .json"
