#!/bin/bash
# Catalog storage and the interactive checklist (pure bash 3.2, no dependencies).

# Rows shown in the UI, in order. Kind: h = section header, i = item, s = setting.
ROW_KIND=(); ROW_REF=()
H_LABEL=()
I_ID=(); I_LABEL=(); I_DESC=(); I_ACTION=(); I_DEF=(); I_SEL=(); I_SEC=(); I_URL=()
S_KEY=(); S_LABEL=(); S_VAL=(); S_DESC=()
CUR_SEC=-1

section() {
  H_LABEL+=("$1")
  CUR_SEC=$((${#H_LABEL[@]} - 1))
  ROW_KIND+=(h); ROW_REF+=("$CUR_SEC")
}

# item <id> <on|off> <label> <action> [description] [website, used for the icon in the app]
item() {
  local i=${#I_ID[@]} def=0
  [ "$2" = on ] && def=1
  I_ID[i]=$1; I_DEF[i]=$def; I_SEL[i]=$def; I_LABEL[i]=$3; I_ACTION[i]=$4; I_DESC[i]=${5:-}; I_URL[i]=${6:-}; I_SEC[i]=$CUR_SEC
  ROW_KIND+=(i); ROW_REF+=("$i")
}

# run_last <id>…: run these items at the very end, after everything is installed and the Finder
# and Dock have restarted. They still show up in their own section in the checklist.
I_LAST=" "
run_last() { I_LAST="$I_LAST$* "; }
is_last() { case $I_LAST in *" $1 "*) return 0 ;; esac; return 1; }

# setting <key> <default> <label> [description] – overridable with MAC_SETUP_<KEY> env vars.
setting() {
  local i=${#S_KEY[@]} env val
  env="MAC_SETUP_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  eval "val=\${$env-\$2}"
  S_KEY[i]=$1; S_VAL[i]=$val; S_LABEL[i]=$3; S_DESC[i]=${4:-}
  ROW_KIND+=(s); ROW_REF+=("$i")
}

cfg() {
  local i
  for i in "${!S_KEY[@]}"; do [ "${S_KEY[i]}" = "$1" ] && { printf '%s' "${S_VAL[i]}"; return 0; }; done
  return 1
}

item_index() {
  local i
  for i in "${!I_ID[@]}"; do [ "${I_ID[i]}" = "$1" ] && { echo "$i"; return 0; }; done
  return 1
}

selected() {
  local i; i=$(item_index "$1") || return 1
  [ "${I_SEL[i]}" = 1 ]
}

select_only() { # comma separated ids
  local i id
  for i in "${!I_ID[@]}"; do I_SEL[i]=0; done
  for id in $(printf '%s' "$1" | tr ',' ' '); do
    i=$(item_index "$id") || { err "Unknown item: $id"; exit 1; }
    I_SEL[i]=1
  done
}

set_items() { # set_items <ids,…> <0|1>
  local i id
  for id in $(printf '%s' "$1" | tr ',' ' '); do
    i=$(item_index "$id") || { err "Unknown item: $id"; exit 1; }
    I_SEL[i]=$2
  done
}

count_selected() {
  local i n=0
  for i in "${!I_SEL[@]}"; do [ "${I_SEL[i]}" = 1 ] && n=$((n + 1)); done
  echo "$n"
}

print_catalog() {
  local r k ref
  for r in "${!ROW_KIND[@]}"; do
    k=${ROW_KIND[r]}; ref=${ROW_REF[r]}
    case $k in
      h) printf '\n%s\n' "${H_LABEL[ref]}" ;;
      i) printf '  [%s] %-26s %s\n' "$([ "${I_DEF[ref]}" = 1 ] && echo x || echo ' ')" "${I_ID[ref]}" "${I_LABEL[ref]}" ;;
      s) printf '  (setting) %-20s %s = "%s"\n' "${S_KEY[ref]}" "${S_LABEL[ref]}" "${S_VAL[ref]}" ;;
    esac
  done
}

# Catalog as JSON for the desktop app. Rows are dumped tab-separated and escaped by awk
# (bash 3.2 pattern substitution can't be trusted with backslashes).
print_json() {
  local r k ref
  for r in "${!ROW_KIND[@]}"; do
    k=${ROW_KIND[r]}; ref=${ROW_REF[r]}
    case $k in
      h) printf 'h\t%s\n' "${H_LABEL[ref]}" ;;
      i) printf 'i\t%s\t%s\t%s\t%s\t%s\t%s\n' "${I_ID[ref]}" "${I_DEF[ref]}" "${I_LABEL[ref]}" "${I_DESC[ref]}" "${I_URL[ref]}" \
           "$(app_installed_hint "${I_ACTION[ref]}")" ;;
      s) printf 's\t%s\t%s\t%s\t%s\n' "${S_KEY[ref]}" "${S_VAL[ref]}" "${S_LABEL[ref]}" "${S_DESC[ref]}" ;;
    esac
  done | awk -F '\t' '
    function q(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return "\"" s "\"" }
    BEGIN { printf "[" }
    { if (NR > 1) printf "," }
    $1 == "h" { printf "{\"kind\":\"section\",\"title\":%s}", q($2) }
    $1 == "i" { printf "{\"kind\":\"item\",\"id\":%s,\"on\":%s,\"label\":%s,\"desc\":%s,\"url\":%s,\"installed\":%s}",
                q($2), ($3 == 1 ? "true" : "false"), q($4), q($5), q($6), ($7 == 1 ? "true" : "false") }
    $1 == "s" { printf "{\"kind\":\"setting\",\"key\":%s,\"value\":%s,\"label\":%s,\"desc\":%s}", q($2), q($3), q($4), q($5) }
    END { print "]" }'
}

# 1 when an item's action installs an app that is already in /Applications.
app_installed_hint() {
  # Only look at the first command, and split it with xargs: nothing here may ever run it.
  local cmd=${1%%&&*} app old_ifs=$IFS words
  cmd=${cmd%%;*}; cmd=${cmd%%|*}
  case "$cmd" in cask\ *|sparkle_app\ *|appstore\ *) ;; *) echo 0; return ;; esac
  IFS=$'\n'; words=($(printf '%s' "$cmd" | xargs -n1 2>/dev/null)); IFS=$old_ifs
  case ${words[0]} in cask) app=${words[2]:-} ;; sparkle_app) app=${words[1]:-} ;; appstore) app=${words[2]:-} ;; esac
  [ -n "$app" ] && app_exists "$app" && { echo 1; return; }
  echo 0
}

# ------------------------------------------------------------------- TUI ---
UI_CUR=0 UI_TOP=0

ui_cleanup() {
  printf '\e[?25h\e[?1049l' >"$TTY" 2>/dev/null
  stty sane <"$TTY" 2>/dev/null
}

ui_readkey() {
  local k k2 k3
  IFS= read -rsn1 k <"$TTY"
  if [ "$k" = $'\e' ]; then
    IFS= read -rsn1 -t 1 k2 <"$TTY"
    IFS= read -rsn1 -t 1 k3 <"$TTY"
    case "$k2$k3" in
      '[A'|'OA') KEY=up ;;
      '[B'|'OB') KEY=down ;;
      '[5') IFS= read -rsn1 -t 1 _ <"$TTY"; KEY=pgup ;;
      '[6') IFS= read -rsn1 -t 1 _ <"$TTY"; KEY=pgdn ;;
      '[H'|'OH') KEY=home ;;
      '[F'|'OF') KEY=end ;;
      *) KEY=esc ;;
    esac
  elif [ "$k" = " " ]; then KEY=space
  elif [ -z "$k" ]; then KEY=enter
  else KEY=$k
  fi
}

# Section stats: echo "<selected> <total>"
ui_sec_stats() {
  local i s=0 t=0
  for i in "${!I_SEC[@]}"; do
    [ "${I_SEC[i]}" = "$1" ] || continue
    t=$((t + 1)); [ "${I_SEL[i]}" = 1 ] && s=$((s + 1))
  done
  echo "$s $t"
}

ui_toggle_section() {
  local sec=$1 i stats s t v=1
  stats=$(ui_sec_stats "$sec"); s=${stats% *}; t=${stats#* }
  [ "$s" = "$t" ] && v=0
  for i in "${!I_SEC[@]}"; do [ "${I_SEC[i]}" = "$sec" ] && I_SEL[i]=$v; done
}

ui_edit_setting() {
  local ref=$1 rows val
  rows=$(tput lines <"$TTY")
  printf '\e[%d;1H\e[K\e[?25h' "$rows" >"$TTY"
  printf '%s%s%s [%s] (Enter = keep, "-" = empty): ' "$C_BOLD" "${S_LABEL[ref]}" "$C_RESET" "${S_VAL[ref]}" >"$TTY"
  IFS= read -r val <"$TTY"
  printf '\e[?25l' >"$TTY"
  if [ "$val" = "-" ]; then S_VAL[ref]=""
  elif [ -n "$val" ]; then S_VAL[ref]=$val
  fi
}

ui_fit() { # truncate plain text to width
  local s=$1 w=$2
  [ ${#s} -gt "$w" ] && s="${s:0:$((w - 1))}…"
  printf '%s' "$s"
}

ui_draw() {
  local rows cols view r end k ref text line out stats
  rows=$(tput lines <"$TTY"); cols=$(tput cols <"$TTY")
  view=$((rows - 6)); [ $view -lt 3 ] && view=3
  [ $UI_CUR -lt $UI_TOP ] && UI_TOP=$UI_CUR
  [ $UI_CUR -ge $((UI_TOP + view)) ] && UI_TOP=$((UI_CUR - view + 1))
  end=$((UI_TOP + view)); [ $end -gt ${#ROW_KIND[@]} ] && end=${#ROW_KIND[@]}

  out=$'\e[H'
  out+="${C_BOLD}${C_CYAN} Mac Initial Setup${C_RESET}${C_DIM}  —  $(count_selected) of ${#I_ID[@]} selected${C_RESET}"$'\e[K\n'
  out+="${C_DIM}$(ui_fit ' ↑↓ move · space toggle · enter edit/toggle · a all · n none · d defaults · s START · q quit' "$cols")${C_RESET}"$'\e[K\n'
  out+=$'\e[K\n'

  for ((r = UI_TOP; r < end; r++)); do
    k=${ROW_KIND[r]}; ref=${ROW_REF[r]}
    case $k in
      h) stats=$(ui_sec_stats "$ref"); text=" ${H_LABEL[ref]}  (${stats% *}/${stats#* })" ;;
      i) if [ "${I_SEL[ref]}" = 1 ]; then text="   [x] ${I_LABEL[ref]}"; else text="   [ ] ${I_LABEL[ref]}"; fi ;;
      s) text="   ✎  ${S_LABEL[ref]}: ${S_VAL[ref]:-<empty>}" ;;
    esac
    line=$(ui_fit "$text" "$cols")
    if [ $r -eq $UI_CUR ]; then
      out+=$'\e[7m'"$line"$'\e[0m'
    elif [ "$k" = h ]; then
      out+="${C_BOLD}${C_YELLOW}${line}${C_RESET}"
    elif [ "$k" = s ]; then
      out+="${C_CYAN}${line}${C_RESET}"
    elif [ "${I_SEL[ref]}" = 1 ]; then
      out+="${C_GREEN}${line:0:6}${C_RESET}${line:6}"
    else
      out+="${C_DIM}${line}${C_RESET}"
    fi
    out+=$'\e[K\n'
  done
  for ((; r < UI_TOP + view; r++)); do out+=$'\e[K\n'; done

  k=${ROW_KIND[UI_CUR]}; ref=${ROW_REF[UI_CUR]}
  case $k in
    h) text="Section – space/enter toggles every item in this section" ;;
    i) text="${I_DESC[ref]:-${I_LABEL[ref]}}" ;;
    s) text="${S_DESC[ref]:-Press enter to change}" ;;
  esac
  out+=$'\e[K\n'"${C_DIM}$(ui_fit " $text" "$cols")${C_RESET}"$'\e[K\e[J'
  printf '%s' "$out" >"$TTY"
}

# Returns 0 to start, 1 when the user quits.
ui_run() {
  local n=${#ROW_KIND[@]} rows k ref
  trap 'ui_cleanup; exit 130' INT TERM
  printf '\e[?1049h\e[?25l\e[2J' >"$TTY"
  while :; do
    ui_draw
    ui_readkey
    rows=$(tput lines <"$TTY")
    k=${ROW_KIND[UI_CUR]}; ref=${ROW_REF[UI_CUR]}
    case $KEY in
      up|k)   [ $UI_CUR -gt 0 ] && UI_CUR=$((UI_CUR - 1)) ;;
      down|j) [ $UI_CUR -lt $((n - 1)) ] && UI_CUR=$((UI_CUR + 1)) ;;
      pgup)   UI_CUR=$((UI_CUR - rows + 7)); [ $UI_CUR -lt 0 ] && UI_CUR=0 ;;
      pgdn)   UI_CUR=$((UI_CUR + rows - 7)); [ $UI_CUR -ge $n ] && UI_CUR=$((n - 1)) ;;
      home|g) UI_CUR=0 ;;
      end|G)  UI_CUR=$((n - 1)) ;;
      space|enter)
        case $k in
          h) ui_toggle_section "$ref" ;;
          i) if [ "${I_SEL[ref]}" = 1 ]; then I_SEL[ref]=0; else I_SEL[ref]=1; fi ;;
          s) ui_edit_setting "$ref" ;;
        esac ;;
      a) for ref in "${!I_SEL[@]}"; do I_SEL[ref]=1; done ;;
      n) for ref in "${!I_SEL[@]}"; do I_SEL[ref]=0; done ;;
      d) for ref in "${!I_SEL[@]}"; do I_SEL[ref]=${I_DEF[ref]}; done ;;
      s|S) ui_cleanup; trap - INT TERM; return 0 ;;
      q|Q) ui_cleanup; trap - INT TERM; return 1 ;;
    esac
  done
}
