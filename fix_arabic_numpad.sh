#!/usr/bin/env bash
#
# fix_arabic_numpad.sh
#
# يجعل لوحة الأرقام الجانبية (Numpad) تكتب أرقامًا إنجليزية 0123456789
# بدلًا من الأرقام العربية-الهندية ٠١٢٣٤٥٦٧٨٩ عند استخدام التخطيط العربي.
#
# السبب: تخطيط XKB العربي (/usr/share/X11/xkb/symbols/ara) يعرّف الكتلة
# "digits_KP" التي تضع الأرقام العربية-الهندية في المستوى الثاني للوحة
# الجانبية وتدفع الأرقام اللاتينية إلى المستوى الثالث (AltGr).
#
# الاستخدام:
#   ./fix_arabic_numpad.sh            # فحص فقط، بدون أي تعديل
#   ./fix_arabic_numpad.sh --apply    # تطبيق الإصلاح

set -uo pipefail

APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

# اختصار تبديل اللغة. غيّره هنا لو رغبت باختصار آخر؛
# القائمة الكاملة: grep 'grp:' /usr/share/X11/xkb/rules/evdev.lst
#   grp:rctrl_rshift_toggle  Ctrl الأيمن + Shift الأيمن   (الافتراضي)
#   grp:lctrl_lshift_toggle  Ctrl الأيسر + Shift الأيسر
#   grp:ctrl_shift_toggle    أي Ctrl + أي Shift
#   grp:alt_shift_toggle     Alt + Shift
#   grp:win_space_toggle     Super + مسافة
SWITCH_OPT="${SWITCH_OPT:-grp:rctrl_rshift_toggle}"
SWITCH_LABEL="Ctrl الأيمن + Shift الأيمن"

# ---------- عرض ----------
c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_hdr=$'\e[1;36m'; c_off=$'\e[0m'
say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n%s==> %s%s\n' "$c_hdr" "$*" "$c_off"; }
ok()   { printf '%s[ ok ]%s %s\n'   "$c_ok"   "$c_off" "$*"; }
warn() { printf '%s[ ! ]%s %s\n'    "$c_warn" "$c_off" "$*"; }
err()  { printf '%s[fail]%s %s\n'   "$c_err"  "$c_off" "$*"; }

# لوحة الأرقام: keycode في X11/evdev -> الرمزان المطلوبان (NumLock off / on)
KEYPAD_MAP=(
  "79 KP_Home KP_7"
  "80 KP_Up KP_8"
  "81 KP_Prior KP_9"
  "83 KP_Left KP_4"
  "84 KP_Begin KP_5"
  "85 KP_Right KP_6"
  "87 KP_End KP_1"
  "88 KP_Down KP_2"
  "89 KP_Next KP_3"
  "90 KP_Insert KP_0"
  "91 KP_Delete KP_Decimal"
)

# ---------- 1. التشخيص ----------
hdr "التشخيص"

SESSION="${XDG_SESSION_TYPE:-unknown}"
say "نوع الجلسة : $SESSION"
say "سطح المكتب : ${XDG_CURRENT_DESKTOP:-unknown}"

ARA_FILE=/usr/share/X11/xkb/symbols/ara
if [[ -r "$ARA_FILE" ]] && grep -q 'digits_KP' "$ARA_FILE"; then
    ok "وُجدت كتلة digits_KP في $ARA_FILE — هذا هو مصدر الأرقام الهندية."
else
    warn "لم أجد digits_KP في $ARA_FILE (نسخة xkeyboard-config مختلفة). الإصلاح أدناه يبقى صالحًا."
fi

CUR_LAYOUT=""; CUR_VARIANT=""; CUR_OPTIONS=""
if command -v setxkbmap >/dev/null 2>&1 && [[ "$SESSION" == "x11" ]]; then
    CUR_LAYOUT=$(setxkbmap -query 2>/dev/null | awk '/^layout:/  {print $2}')
    CUR_VARIANT=$(setxkbmap -query 2>/dev/null | awk '/^variant:/ {print $2}')
    CUR_OPTIONS=$(setxkbmap -query 2>/dev/null | awk '/^options:/ {print $2}')
    say "التخطيط الحالي : ${CUR_LAYOUT:-<none>}"
    say "المتغيّر الحالي : ${CUR_VARIANT:-<none>}"
    say "الخيارات       : ${CUR_OPTIONS:-<none>}"
    if [[ "$CUR_VARIANT" == *digits* ]]; then
        warn "المتغيّر '$CUR_VARIANT' يتضمّن digits_KP — هذا السبب المباشر."
    fi
fi

if [[ -r /etc/default/keyboard ]]; then
    say ""
    say "محتوى /etc/default/keyboard الحالي:"
    sed 's/^/    /' /etc/default/keyboard
fi

if [[ $APPLY -eq 0 ]]; then
    hdr "وضع الفحص فقط"
    say "لم يُعدَّل أي شيء. لتطبيق الإصلاح شغّل:"
    say "    $0 --apply"
    say ""
    say "تجربة فورية بدون أي تعديل: اضغط AltGr (Alt اليمين) + رقم من اللوحة الجانبية."
    say "إذا طلع رقم إنجليزي، فالتشخيص مؤكد."
    exit 0
fi

# ---------- 2. الإصلاح الدائم على مستوى النظام ----------
hdr "1/3 — ضبط تخطيط النظام في /etc/default/keyboard"

if [[ $EUID -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
    warn "لا صلاحية root ولا sudo — سأتخطى تعديل النظام وأكتفي بإصلاح المستخدم."
else
    SUDO=""; [[ $EUID -ne 0 ]] && SUDO="sudo"

    if [[ -f /etc/default/keyboard ]]; then
        BACKUP="/etc/default/keyboard.bak.$(date +%Y%m%d-%H%M%S)"
        if $SUDO cp -a /etc/default/keyboard "$BACKUP"; then
            ok "نسخة احتياطية: $BACKUP"
        else
            err "فشل أخذ نسخة احتياطية — أوقفت تعديل النظام."
            SUDO="SKIP"
        fi
    fi

    if [[ "$SUDO" != "SKIP" ]]; then
        # us أولًا حتى تكون المجموعة الافتراضية لاتينية، و ara بالمتغيّر الأساسي
        # (basic) الذي لا يتضمّن digits_KP إطلاقًا.
        $SUDO tee /etc/default/keyboard >/dev/null <<EOF
# ضبطه fix_arabic_numpad.sh
XKBMODEL="pc105"
XKBLAYOUT="us,ara"
XKBVARIANT=",basic"
XKBOPTIONS="$SWITCH_OPT"
BACKSPACE="guess"
EOF
        ok "كُتب /etc/default/keyboard (us,ara — المتغيّر basic بلا digits_KP)"

        $SUDO dpkg-reconfigure -f noninteractive keyboard-configuration >/dev/null 2>&1 \
            && ok "أُعيد تكوين keyboard-configuration" \
            || warn "تعذّر dpkg-reconfigure (غير حرج)"
        $SUDO setupcon --save >/dev/null 2>&1 || true
    fi
fi

# ---------- 3. تطبيق فوري على الجلسة الحالية ----------
hdr "2/3 — تطبيق فوري على الجلسة الحالية"

if [[ "$SESSION" == "x11" ]] && command -v setxkbmap >/dev/null 2>&1; then
    if setxkbmap -layout "us,ara" -variant ",basic" -option "" \
                 -option "$SWITCH_OPT" 2>/dev/null; then
        ok "طُبِّق التخطيط على الجلسة الحالية (تبديل اللغة: $SWITCH_LABEL)"
    else
        err "فشل setxkbmap"
    fi
elif [[ "$SESSION" == "wayland" ]] && command -v gsettings >/dev/null 2>&1; then
    if gsettings set org.gnome.desktop.input-sources sources \
        "[('xkb','us'), ('xkb','ara+basic')]" 2>/dev/null; then
        ok "ضُبطت مصادر الإدخال عبر gsettings"
    else
        warn "تعذّر ضبط gsettings — اضبط التخطيط يدويًا من إعدادات النظام."
    fi
else
    warn "جلسة غير معروفة ($SESSION) — سيسري الضبط بعد إعادة تسجيل الدخول."
fi

# ---------- 4. شبكة أمان: فرض الرموز اللاتينية على اللوحة الجانبية ----------
hdr "3/3 — شبكة أمان (xmodmap) للوحة الأرقام الجانبية"

if [[ "$SESSION" == "x11" ]] && command -v xmodmap >/dev/null 2>&1; then
    XMODMAP_FILE="$HOME/.Xmodmap"
    [[ -f "$XMODMAP_FILE" ]] && cp -a "$XMODMAP_FILE" "$XMODMAP_FILE.bak.$(date +%Y%m%d-%H%M%S)"

    {
        echo "! فرض الأرقام اللاتينية على لوحة الأرقام الجانبية"
        echo "! ولّده fix_arabic_numpad.sh"
        for entry in "${KEYPAD_MAP[@]}"; do
            read -r code sym_off sym_on <<<"$entry"
            echo "keycode $code = $sym_off $sym_on"
        done
    } > "$XMODMAP_FILE"
    ok "كُتب $XMODMAP_FILE"

    if xmodmap "$XMODMAP_FILE" 2>/dev/null; then
        ok "طُبِّق xmodmap على الجلسة الحالية"
    else
        err "فشل تطبيق xmodmap"
    fi

    # تشغيل تلقائي عند كل تسجيل دخول
    AUTOSTART_DIR="$HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    cat > "$AUTOSTART_DIR/fix-arabic-numpad.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Latin numpad digits
Comment=Force Latin digits on the numeric keypad
Exec=xmodmap $XMODMAP_FILE
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
    ok "أُضيف تشغيل تلقائي: $AUTOSTART_DIR/fix-arabic-numpad.desktop"

elif [[ "$SESSION" == "wayland" ]]; then
    # xmodmap لا يعمل على Wayland — نستخدم تخطيط XKB مخصص في مجلد المستخدم
    mkdir -p "$HOME/.config/xkb/symbols" "$HOME/.config/xkb/rules"

    {
        echo "partial keypad_keys"
        echo 'xkb_symbols "latinkp" {'
        for entry in "${KEYPAD_MAP[@]}"; do
            read -r code sym_off sym_on <<<"$entry"
            case $code in
                79) k=KP7;; 80) k=KP8;; 81) k=KP9;;
                83) k=KP4;; 84) k=KP5;; 85) k=KP6;;
                87) k=KP1;; 88) k=KP2;; 89) k=KP3;;
                90) k=KP0;; 91) k=KPDL;;
            esac
            printf '    key <%s> {[ %s, %s ]};\n' "$k" "$sym_off" "$sym_on"
        done
        echo '};'
    } > "$HOME/.config/xkb/symbols/latinkp"

    cat > "$HOME/.config/xkb/rules/evdev" <<'EOF'
! option = symbols
  custom:latinkp = +latinkp(latinkp)

! include %S/evdev
EOF
    ok "أُنشئ تخطيط XKB مخصص في ~/.config/xkb"

    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.input-sources xkb-options \
            "['$SWITCH_OPT','custom:latinkp']" 2>/dev/null \
            && ok "فُعِّل خيار custom:latinkp" \
            || warn "تعذّر تفعيل الخيار عبر gsettings"
    fi
else
    warn "تخطيت شبكة الأمان (لا xmodmap ولا جلسة Wayland)."
fi

# ---------- 5. الخلاصة ----------
hdr "تم"
say "جرّب الآن الكتابة من لوحة الأرقام الجانبية (تأكد أن NumLock مضاء)."
say "وتبديل اللغة صار على: $SWITCH_LABEL"
say ""
say "إذا ما زالت الأرقام هندية، سجّل خروجًا ودخولًا — بعض التغييرات"
say "لا تسري إلا على جلسة جديدة."
say ""
say "للتراجع:"
say "  • استرجع /etc/default/keyboard.bak.* ثم: sudo dpkg-reconfigure keyboard-configuration"
say "  • احذف ~/.Xmodmap و ~/.config/autostart/fix-arabic-numpad.desktop"
say "  • احذف ~/.config/xkb (إن أُنشئ)"
