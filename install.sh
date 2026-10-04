#!/data/data/com.termux/files/usr/bin/bash
# ==========================================
#  Star Tool Installer (with loading UI)
#  ดึงไฟล์ zip จาก GitHub Releases
# ==========================================

REPO="mzxhub99/Starplustoolrejoin-"
ZIP_NAME=""                       # ใส่ชื่อไฟล์ zip ตรงนี้ถ้าอยากระบุเอง เช่น "star-tool.zip" (ว่าง = หา .zip ตัวแรกใน release ล่าสุด)
INSTALL_DIR="$HOME/star-tool"
TMP_DIR="$HOME/.star-tmp"
LOG="$TMP_DIR/install.log"

# ---------- สี ----------
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'
B='\033[1;34m'; M='\033[1;35m'; C='\033[1;36m'
W='\033[1;37m'; D='\033[2m'; N='\033[0m'

mkdir -p "$TMP_DIR"
: > "$LOG"

TOTAL=7
CURRENT=0

# ---------- UI ----------
banner() {
  clear
  echo -e "${C}"
  echo "  ╔══════════════════════════════════════╗"
  echo "  ║                                      ║"
  echo -e "  ║   ${Y}★  S T A R   T O O L  ★${C}              ║"
  echo -e "  ║   ${W}Auto Installer${C}                       ║"
  echo "  ║                                      ║"
  echo "  ╚══════════════════════════════════════╝"
  echo -e "${N}"
}

bar() {
  local pct=$1 width=30
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local f="" e=""
  [ $filled -gt 0 ] && f=$(printf '█%.0s' $(seq 1 $filled))
  [ $empty -gt 0 ] && e=$(printf '░%.0s' $(seq 1 $empty))
  printf "${G}%s${D}%s${N} ${W}%3d%%${N}" "$f" "$e" "$pct"
}

# run "ข้อความ" คำสั่ง...  -> แสดง spinner + progress bar
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
    # ขยับ bar ช้า ๆ ระหว่างรอ (ไม่เกิน next-1)
    if [ $(( i % 8 )) -eq 0 ] && [ $pct -lt $(( next - 1 )) ]; then pct=$(( pct + 1 )); fi
    printf "\r  ${M}%s${N} %-34s " "${frames[i % 10]}" "$msg"
    bar $pct
    i=$(( i + 1 ))
    sleep 0.1
  done
  wait $pid
  local rc=$?
  tput cnorm 2>/dev/null

  CURRENT=$(( CURRENT + 1 ))
  if [ $rc -eq 0 ]; then
    printf "\r  ${G}✔${N} %-34s " "$msg"
    bar $(( CURRENT * 100 / TOTAL ))
    echo
  else
    printf "\r  ${R}✘${N} %-34s ${R}ล้มเหลว${N}\n" "$msg"
    echo -e "\n  ${Y}ดู log ได้ที่:${N} $LOG"
    echo -e "  ${D}$(tail -n 5 "$LOG")${N}\n"
    exit 1
  fi
}

# ---------- งานแต่ละขั้น ----------
step_mirror() {
  # ตั้ง mirror อัตโนมัติ (แทน termux-change-repo) ลองทีละตัวจนกว่าจะใช้ได้
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
  # ทุก mirror ล้มเหลว คืนค่าเดิม
  [ -f "$list.star-bak" ] && cp "$list.star-bak" "$list"
  return 1
}

step_update() {
  export DEBIAN_FRONTEND=noninteractive
  pkg update -y -o Dpkg::Options::="--force-confnew" || return 1
  # อัปเกรดทั้งระบบ กัน curl ใหม่ชนกับ openssl เก่า (partial upgrade)
  pkg upgrade -y -o Dpkg::Options::="--force-confnew"
}

step_packages() {
  export DEBIAN_FRONTEND=noninteractive
  pkg install -y -o Dpkg::Options::="--force-confnew" python curl unzip
}

step_find_release() {
  local api="https://api.github.com/repos/$REPO/releases/latest"
  local json url
  json=$(curl -fsSL "$api") || return 1

  if [ -n "$ZIP_NAME" ]; then
    url="https://github.com/$REPO/releases/latest/download/$ZIP_NAME"
  else
    url=$(echo "$json" | grep -o '"browser_download_url": *"[^"]*\.zip"' \
          | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/')
    # ถ้าไม่มี asset .zip ให้ใช้ source zip ของ release แทน
    [ -z "$url" ] && url=$(echo "$json" | grep -o '"zipball_url": *"[^"]*"' \
          | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/')
  fi

  [ -z "$url" ] && return 1
  echo "$url" > "$TMP_DIR/url.txt"
}

step_download() {
  curl -fL --retry 3 -o "$TMP_DIR/release.zip" "$(cat "$TMP_DIR/url.txt")"
}

step_extract() {
  rm -rf "$TMP_DIR/extract" "$INSTALL_DIR"
  mkdir -p "$TMP_DIR/extract" "$INSTALL_DIR"
  unzip -oq "$TMP_DIR/release.zip" -d "$TMP_DIR/extract" || return 1

  # ถ้า zip มีโฟลเดอร์ชั้นเดียวครอบอยู่ ให้ดึงเนื้อในออกมา
  local count
  count=$(ls -A "$TMP_DIR/extract" | wc -l)
  if [ "$count" -eq 1 ] && [ -d "$TMP_DIR/extract/$(ls -A "$TMP_DIR/extract")" ]; then
    cp -a "$TMP_DIR/extract/$(ls -A "$TMP_DIR/extract")/." "$INSTALL_DIR/"
  else
    cp -a "$TMP_DIR/extract/." "$INSTALL_DIR/"
  fi
  [ -f "$INSTALL_DIR/Star_v4.py" ]
}

step_pip() {
  cd "$INSTALL_DIR" || return 1
  if [ -f requirements.txt ]; then
    pip install -r requirements.txt
  else
    return 0
  fi
}

cleanup() { rm -rf "$TMP_DIR/extract" "$TMP_DIR/release.zip" "$TMP_DIR/url.txt"; tput cnorm 2>/dev/null; }
trap cleanup EXIT

# ---------- เริ่มทำงาน ----------
banner
echo -e "  ${W}กำลังติดตั้ง อาจใช้เวลา 3-4 นาที...${N}\n"

run "ตั้งค่า mirror อัตโนมัติ"   step_mirror
run "อัปเดตแพ็คเกจ"            step_update
run "ติดตั้ง python / curl / unzip" step_packages
run "ค้นหาเวอร์ชันล่าสุด"       step_find_release
run "ดาวน์โหลดจาก Releases"    step_download
run "แตกไฟล์ zip"              step_extract
run "ติดตั้งไลบรารี Python"    step_pip

echo
echo -e "  ${G}╔══════════════════════════════════════╗${N}"
echo -e "  ${G}║${N}   ${Y}★${N} ติดตั้งเสร็จสมบูรณ์!               ${G}║${N}"
echo -e "  ${G}╚══════════════════════════════════════╝${N}"
echo
echo -e "  ${W}รันต่อด้วยคำสั่ง:${N}"
echo -e "  ${C}cd ~/star-tool && python Star_v4.py${N}"
echo
