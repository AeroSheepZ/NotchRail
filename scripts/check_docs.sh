#!/bin/bash
# NotchRail 文档一致性校验闸门
#
# 依据：AGENTS.md §0「事实唯一归属（Single Home per Fact）」
# 目的：机器化拦截「文档幻觉」——已删符号残留、多屏方向回退（旧双槽位模型符号）、
#       受管数值内联、术语禁用词外泄、ADR 与相对链接失效、版本号口径不一致。
#
# 覆盖 6 类校验，任一类失败即退出码非 0（可直接用于 CI 闸门）。
# 行内出现 `check-docs:allow` 注释的行会被跳过，作为受控逃生舱口。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
pass() { printf '  \033[32m✅\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m❌\033[0m %s\n' "$1"; FAIL=1; }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ---- 受检范围 ---------------------------------------------------------------
# 发布区：随仓库发布、必须严格一致。
PUBLISHED=(README.md AGENTS.md CONTEXT.md)
for f in docs/*.md docs/adr/*.md docs/agents/*.md; do
  [ -f "$f" ] && PUBLISHED+=("$f")
done
# 非发布区（docs/local/、.scratch/）自带「非权威·历史草稿」横幅，不参与强校验。

# 数值校验的范围：ADR 正文不可改写（见 AGENTS.md §0 归属矩阵第 4 行与 Q4 决议），
# 故 docs/adr/ 豁免「受管数值内联」一项，仅其余校验照常适用。
NUMERIC_SCOPE=()
for f in "${PUBLISHED[@]}"; do
  case "$f" in docs/adr/*) ;; *) NUMERIC_SCOPE+=("$f") ;; esac
done

# 过滤：跳过被显式放行的行
scan() { # scan <ERE> <files...>
  local pat="$1"; shift
  grep -nE "$pat" "$@" 2>/dev/null | grep -v 'check-docs:allow'
}

printf '\033[1m🔍 NotchRail 文档一致性校验\033[0m  (%d 份发布区文档)\n' "${#PUBLISHED[@]}"

# ---- 1. 已删符号残留 --------------------------------------------------------
section '1/6 已删符号残留'
DELETED_SYMBOLS=(
  'ignoredBundleIDs'
  'hideItem('
  'unhideItem('
  'toggleIgnored('
  'isItemHidden('
  'clearAllIgnored('
  'DisplayMode.ignored'
  'frontmostAppMenuMaxX'
  'isWithinScreenSpan'
  'APP_MENU_COLLISION_MARGIN'
  'latestSnapshot'
  'allDiscoveredItems'
  'discoveredItemsMap'
)
hit=0
for sym in "${DELETED_SYMBOLS[@]}"; do
  out="$(scan "$(printf '%s' "$sym" | sed 's/[.[\*^$()+?{}|]/\\&/g')" "${PUBLISHED[@]}")"
  if [ -n "$out" ]; then
    hit=1
    printf '     残留符号 `%s`:\n%s\n' "$sym" "$(printf '%s\n' "$out" | sed 's/^/       /')"
  fi
done
[ "$hit" -eq 0 ] && pass '无已删/错名符号残留' || fail '存在已删或错名符号（见上）'

# ---- 2. 旧双槽位模型符号（多屏方向回退） -----------------------------------
# 依据：AGENTS.md §2.1 与 docs/adr/0009 —— 视口与状态机一律按 displayID 注册，
#       屏幕数量不设上限，禁止 primary*/external* 式成对槽位字段。
# 作用域：现状文档。docs/adr/ 正文不可改写、docs/SPEC.md 为历史归档，二者豁免
#       （ADR 0008 正文与 0009 背景必须指名旧模型才能说清「取代了什么」）。
# 注：只拦标识符，不拦「双面板 / 双屏独立」等中文措辞——ADR 标题引用与历史版本
#     描述中它们都是正当用法，强行拦截只会制造大量逃生舱口注释，反而削弱闸门。
section '2/6 旧双槽位模型符号（多屏方向回退）'
HISTORICAL_ONLY_SYMBOLS=(
  'primaryPanel'
  'externalPanel'
  'primaryStateMachine'
  'externalStateMachine'
  'externalOwnedDisplayID'
)
CURRENT_SCOPE=()
for f in "${PUBLISHED[@]}"; do
  case "$f" in docs/adr/*|docs/SPEC.md) ;; *) CURRENT_SCOPE+=("$f") ;; esac
done
hit=0
for sym in "${HISTORICAL_ONLY_SYMBOLS[@]}"; do
  # 标识符用字符边界匹配，避免误伤以它为前缀的更长名字（BSD grep 不支持 \b）。
  out="$(scan "(^|[^A-Za-z0-9_])${sym}([^A-Za-z0-9_]|\$)" "${CURRENT_SCOPE[@]}")"
  if [ -n "$out" ]; then
    hit=1
    printf '     回退符号 `%s` 出现在现状文档:\n%s\n' "$sym" "$(printf '%s\n' "$out" | sed 's/^/       /')"
  fi
done
[ "$hit" -eq 0 ] && pass '现状文档未回退到旧双槽位面板模型' || fail '现状文档出现旧双槽位符号——方向回退（见上）'

# ---- 3. 受管数值内联 --------------------------------------------------------
section '3/6 受管数值内联（文档只准引常量名，禁止写数值）'
# 与代码具名常量一一对应；加非数字边界，避免误伤版本号（如 v0.0.9）。
MANAGED_NUMBERS=(
  '(^|[^0-9.])24(\.0)?pt([^a-zA-Z0-9]|$)'
  '(^|[^0-9.])12(\.0)?pt([^a-zA-Z0-9]|$)'
  '(^|[^0-9.])5\.0pt([^a-zA-Z0-9]|$)'
  '(^|[^0-9.])240(\.0)?pt([^a-zA-Z0-9]|$)'
  '(^|[^0-9.])180(\.0)?pt([^a-zA-Z0-9]|$)'
  '(^|[^0-9.])(2|4)(\.0)?pt([^a-zA-Z0-9]|$)'
  '(^|[^0-9.])(16|120|100)ms([^a-zA-Z0-9]|$)'
  '(^|[^0-9.])300ms([^a-zA-Z0-9]|$)'
  '(^|[^0-9.])(3\.0|2\.0|1\.5)s([^a-zA-Z0-9]|$)'
  '(^|[^0-9.])60s([^a-zA-Z0-9]|$)'
  '300pt/s'
  '(^|[^0-9.])0\.016([^0-9]|$)'
)
hit=0
for pat in "${MANAGED_NUMBERS[@]}"; do
  out="$(scan "$pat" "${NUMERIC_SCOPE[@]}")"
  if [ -n "$out" ]; then
    hit=1
    printf '     命中 /%s/:\n%s\n' "$pat" "$(printf '%s\n' "$out" | sed 's/^/       /')"
  fi
done
[ "$hit" -eq 0 ] && pass '发布区（ADR 除外）无受管数值内联' || fail '存在受管数值内联（见上）'

# ---- 4. 术语禁用词外泄 ------------------------------------------------------
section '4/6 术语禁用词（CONTEXT.md 的 _Avoid_）外泄'
AVOID_TERMS="$(sed -n 's/^_Avoid_:[[:space:]]*//p' CONTEXT.md | tr -d '\r' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$')"
others=()
for f in "${PUBLISHED[@]}"; do [ "$f" != "CONTEXT.md" ] && others+=("$f"); done
hit=0
while IFS= read -r term; do
  [ -z "$term" ] && continue
  # 词边界匹配：只拦「把该词当作术语来用」，不拦它作为更长标识符的一部分
  # （例：禁用词 StatusItem 不应误伤真实类型名 StatusItemManager；StatusWindow 不应误伤 kCGStatusWindowLevel）
  # 注意：不用 \b——BSD grep 的 ERE 不支持它，会导致该项静默「假通过」；改用可移植的字符类边界。
  out="$(scan "(^|[^A-Za-z0-9_])${term}([^A-Za-z0-9_]|\$)" "${others[@]}")"
  if [ -n "$out" ]; then
    hit=1
    printf '     禁用词 `%s` 出现在:\n%s\n' "$term" "$(printf '%s\n' "$out" | sed 's/^/       /')"
  fi
done <<EOF
$AVOID_TERMS
EOF
[ "$hit" -eq 0 ] && pass "无禁用词外泄（已核对 $(printf '%s\n' "$AVOID_TERMS" | grep -c .) 个别名）" || fail '存在禁用词外泄（见上）'

# ---- 5. ADR 与相对路径引用完整性 -------------------------------------------
section '5/6 ADR 编号与相对路径引用完整性'
hit=0
refs="$(grep -ohE '([A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.md' "${PUBLISHED[@]}" 2>/dev/null | sort -u)"
while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  case "$ref" in
    */*) cand="$ref" ;;
    *)   cand="$ref" ;;
  esac
  # 允许裸文件名（如 CONTEXT.md），依次在根 / docs/ / docs/agents/ / docs/adr/ 下寻找
  if [ -e "$cand" ] || [ -e "docs/$cand" ] || [ -e "docs/agents/$cand" ] || [ -e "docs/adr/$cand" ]; then
    continue
  fi
  hit=1
  printf '     失效引用: `%s`\n' "$ref"
done <<EOF
$refs
EOF
# ADR 编号连续性：docs/adr 下编号不得跳号
prev=0
for f in docs/adr/*.md; do
  [ -f "$f" ] || continue
  n="$(basename "$f" | sed -n 's/^\([0-9]\{4\}\)-.*/\1/p')"
  [ -z "$n" ] && { hit=1; printf '     ADR 文件命名不合规: %s\n' "$f"; continue; }
  n10=$((10#$n))
  if [ $((prev + 1)) -ne "$n10" ] && [ "$prev" -ne 0 ]; then
    hit=1; printf '     ADR 编号跳号: 期望 %04d，实得 %s\n' $((prev + 1)) "$n"
  fi
  prev="$n10"
done
[ "$hit" -eq 0 ] && pass 'ADR 编号连续、文档内 .md 引用均可解析' || fail '存在失效引用或 ADR 命名问题（见上）'

# ---- 6. 版本号口径一致 ------------------------------------------------------
section '6/6 版本号口径一致'
CODE_VERSION="$(sed -n 's/^VERSION="\([^"]*\)".*/\1/p' scripts/build_app.sh | head -1)"
if [ -z "$CODE_VERSION" ]; then
  fail '无法从 scripts/build_app.sh 读取 VERSION'
else
  if grep -qE "\*\*v${CODE_VERSION}[：:]" docs/DEVELOPMENT_PLAN.md; then
    pass "代码版本 v${CODE_VERSION} 与 DEVELOPMENT_PLAN 路线图一致"
  else
    fail "代码版本 v${CODE_VERSION} 未出现在 docs/DEVELOPMENT_PLAN.md §5 路线图中"
  fi
fi

# ---- 汇总 -------------------------------------------------------------------
printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32m\033[1m✅ 文档一致性校验全部通过。\033[0m\n'
  exit 0
else
  printf '\033[31m\033[1m❌ 文档一致性校验失败——请按 AGENTS.md §0 归属矩阵修正后重试。\033[0m\n'
  printf '   逃生舱口：确有必要保留的行，可加 `check-docs:allow` 注释放行。\n'
  exit 1
fi
