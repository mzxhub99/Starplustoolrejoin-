#!/data/data/com.termux/files/usr/bin/bash
# ==========================================
#  Star Tool Installer (with loading UI)
#  ดึงไฟล์ zip จาก GitHub Releases
# ==========================================

REPO="mzxhub99/Starplustoolrejoin-"
ZIP_NAME="Star_v7z.zip"            # ชื่อไฟล์ zip ใน Releases
MAIN_FILE="Star_v7z.py"            # ไฟล์หลักที่ใช้เช็คว่าแตกถูก
INSTALL_DIR="$HOME/star-tool"
TMP_DIR="$HOME/.star-tmp"
LOG="$TMP_DIR/install.log"

# ---------- สี ----------
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'
M='\033[1;35m'; C='\033[1;36m'
W='\033[1;37m'; D='\033[2m'; N='\033[0m'

mkdir -p "$TMP_DIR"
: > "$LOG"

TOTAL=7
CURRENT=0

# ---------- UI ----------
banner() {
  clear
  echo -e "${C}"
  echo "  ╔══════════════════════════════╗"
  echo -e "  ║  ${Y}★  S T A R   T O O L  ★${C}      ║"
  echo -e "  ║  ${W}Auto Installer${C}               ║"
  echo "  ╚══════════════════════════════╝"
  echo -e "${N}"
}

# progress bar (ไม่ใช้ seq เพราะ coreutils อาจพังระหว่างอัปเกรด)
bar() {
  local pct=$1 width=12 j
  local filled=$(( pct * width / 100 ))
  local f="" e=""
  for (( j=0; j<filled; j++ )); do f+="█"; done
  for (( j=filled; j<width; j++ )); do e+="░"; done
  printf "${G}%s${D}%s${N} ${W}%3d%%${N}" "$f" "$e" "$pct"
}

run() {
  local msg="$1"; shift
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local base=$(( CURRENT * 100 / TOTAL ))
  local next=$(( (CURRENT + 1) * 100 / TOTAL ))
  local pct=$base i=0

  "$@" >> "$LOG" 2>&1 &
  local pid=$!

  tput civis 2>/dev/null
  while kill -0 $pid 2>/dev/null; do
    if [ $(( i % 10 )) -eq 0 ] && [ $pct -lt $(( next - 1 )) ]; then pct=$(( pct + 1 )); fi
    printf "\r\033[K  ${M}%s${N} %s " "${frames[i % 10]}" "$msg"
    bar $pct
    i=$(( i + 1 ))
    sleep 0.1
  done
  wait $pid
  local rc=$?
  tput cnorm 2>/dev/null

  CURRENT=$(( CURRENT + 1 ))
  if [ $rc -eq 0 ]; then
    printf "\r\033[K  ${G}✔${N} %s " "$msg"
    bar $(( CURRENT * 100 / TOTAL ))
    echo
  else
    printf "\r\033[K  ${R}✘${N} %s ${R}ล้มเหลว${N}\n" "$msg"
    echo -e "\n  ${Y}รายละเอียด (log: $LOG):${N}"
    tail -n 12 "$LOG" | sed 's/^/  /'
    echo
    trap - EXIT
    exit 1
  fi
}

# ---------- งานแต่ละขั้น ----------
step_mirror() {
  local list="$PREFIX/etc/apt/sources.list"
  [ -f "$list.star-bak" ] || cp "$list" "$list.star-bak" 2>/dev/null
  local m
  for m in \
    "https://packages-cf.termux.dev/apt/termux-main" \
    "https://packages.termux.dev/apt/termux-main" \
    "https://grimler.se/termux/termux-main"; do
    echo "deb $m stable main" > "$list"
    rm -rf "$PREFIX/var/lib/apt/lists/"* 2>/dev/null
    if apt-get update -y; then
      echo "mirror ok: $m"
      return 0
    fi
  done
  [ -f "$list.star-bak" ] && cp "$list.star-bak" "$list"
  return 1
}

step_update() {
  export DEBIAN_FRONTEND=noninteractive
  local opt='-o Dpkg::Options::=--force-confnew'
  apt-get $opt -y upgrade || return 1
  # ซ่อมไลบรารีที่หาย (เช่น libpcre2) กรณีอัปเกรดไม่ครบ
  apt-get $opt -y --fix-broken install
  apt-get $opt -y install pcre2 openssl libcurl curl
}

step_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get -o Dpkg::Options=--force-confnew -y install python curl unzip
}

step_find_release() {
  local api="https://api.github.com/repos/$REPO/releases/latest"
  local json url
  json=$(curl -fsSL "$api") || { echo "เรียก GitHub API ไม่ได้"; return 1; }

  echo "assets ใน release ล่าสุด:"
  echo "$json" | grep -o '"browser_download_url": *"[^"]*"' | sed 's/.*"\(https[^"]*\)"/  \1/'

  if [ -n "$ZIP_NAME" ]; then
    url="https://github.com/$REPO/releases/latest/download/$ZIP_NAME"
  else
    url=$(echo "$json" | grep -o '"browser_download_url": *"[^"]*\.zip"' \
          | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/')
    if [ -z "$url" ]; then
      echo "ไม่พบไฟล์ .zip ใน Releases -> ใช้ source zip แทน"
      url=$(echo "$json" | grep -o '"zipball_url": *"[^"]*"' \
            | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/')
    fi
  fi

  [ -z "$url" ] && { echo "หา URL ไม่เจอ (ยังไม่มี Release?)"; return 1; }
  echo "ใช้ไฟล์: $url"
  echo "$url" > "$TMP_DIR/url.txt"
}

step_download() {
  curl -fL --retry 3 -o "$TMP_DIR/release.zip" "$(cat "$TMP_DIR/url.txt")"
}

step_extract() {
  rm -rf "$TMP_DIR/extract" "$INSTALL_DIR"
  mkdir -p "$TMP_DIR/extract" "$INSTALL_DIR"
  echo "ขนาดไฟล์: $(wc -c < "$TMP_DIR/release.zip") bytes"
  unzip -oq "$TMP_DIR/release.zip" -d "$TMP_DIR/extract" || { echo "unzip ล้มเหลว (ไฟล์ไม่ใช่ zip?)"; return 1; }

  # หาไฟล์หลักในทุกชั้นโฟลเดอร์ แล้วใช้โฟลเดอร์นั้นเป็นรากของโปรแกรม
  local main
  main=$(find "$TMP_DIR/extract" -name "$MAIN_FILE" | head -n1)
  if [ -z "$main" ]; then
    echo "ไม่พบ $MAIN_FILE ใน zip นี้ ไฟล์ที่มี:"
    find "$TMP_DIR/extract" | head -n 15
    return 1
  fi
  cp -a "$(dirname "$main")/." "$INSTALL_DIR/"
}

step_pip() {
  cd "$INSTALL_DIR" || return 1
  if [ -f requirements.txt ]; then
    pip install -r requirements.txt
  fi
  return 0
}

cleanup() { rm -rf "$TMP_DIR/extract" "$TMP_DIR/release.zip" "$TMP_DIR/url.txt"; tput cnorm 2>/dev/null; }
trap cleanup EXIT

# ---------- เริ่มทำงาน ----------
banner
echo -e "  ${W}กำลังติดตั้ง อาจใช้เวลา 3-4 นาที...${N}\n"

run "ตั้งค่า mirror"        step_mirror
run "อัปเดตแพ็คเกจ"        step_update
run "ติดตั้ง python/curl"   step_packages
run "ค้นหาเวอร์ชันล่าสุด"   step_find_release
run "ดาวน์โหลดจาก Releases" step_download
run "แตกไฟล์ zip"          step_extract
run "ติดตั้งไลบรารี Python" step_pip

echo
echo -e "  ${G}✔ ติดตั้งเสร็จสมบูรณ์!${N}"
echo
echo -e "  ${W}รันต่อด้วยคำสั่ง:${N}"
echo -e "  ${C}cd ~/star-tool && python $MAIN_FILE${N}"
echo
