#!/usr/bin/env bash

# thư mục mặc định
lib32="x32"
lib64="x64"

# đường dẫn tuyệt đối của thư mục chứa tệp thực thi
basedir=$(dirname "$(readlink -f "$0")")

action="$1"
if ! ([ "$action" = "install" ] || [ "$action" = "uninstall" ]); then
  echo "Hành động không hợp lệ: $action"
  echo "Cách dùng: $0 [install | uninstall] [--symlink]"
  exit 1
fi

# tham số tiếp theo
shift

file_cmd="cp -v"
if [ $# -gt 0 ]; then
  [[ $1 = "--symlink" ]] && file_cmd="ln -s -v"
fi

# kiểm tra Wine
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"
if [ -n "$WINEPREFIX" ] && ! [ -f "$WINEPREFIX/system.reg" ]; then
  echo "$WINEPREFIX: Không phải là môi trường Wine hợp lệ" >&2
  exit 1
fi

# tìm Wine có thể thực thi
export WINEDEBUG="${WINEDEBUG:--all}"

# tắt mscoree và mshtml để tránh tải về Wine Gecko và Mono:
# $WINEDLLOVERRIDES="a" -> $WINEDLLOVERRIDES="a,mscoree,mshtml="
# $WINEDLLOVERRIDES= -> $WINEDLLOVERRIDES="mscoree,mshtml="
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-}${WINEDLLOVERRIDES:+,}mscoree,mshtml="

wine_path="$(which wine 2>/dev/null)"
wine64_path="$(which wine64 2>/dev/null)"
if [ -n "$wine_path" ] && [ -n "$wine64_path" ] && [ "$(dirname "$wine_path")" != "$(dirname "$wine64_path")" ]; then
  echo "Tìm thấy nhiều bản cài Wine:"
  echo "1) $wine_path"
  echo "2) $wine64_path"

  while true; do
    read -p "Chọn bản cài Wine để sử dụng (1 hoặc 2): " choice
    case "$choice" in
      1)
        wine="wine"
        break
        ;;
      2)
        wine="wine64"
        break
        ;;
      *)
        echo "Lựa chọn không hợp lệ. Hãy nhập 1 hoặc 2"
        ;;
    esac
  done
else
  if [ -n "$wine_path" ]; then
    wine="wine"
  fi

  if [ -n "$wine64_path" ]; then
    wine="wine64"
  fi
fi

winever=$($wine --version | grep wine)
if [ -z "$winever" ]; then
    echo "$wine: Không thể thực thi Wine. Hãy kiểm tra lại $wine" >&2
    exit 1
fi

echo "Sử dụng: $winever"

wineboot="$wine wineboot"
win64=true
win32=true

# tạo lại các thư viện .dll nếu thiếu
$wineboot -u

win64_sys_path="$WINEPREFIX/drive_c/windows/system32"
if grep -q -e '#arch=win32' "$WINEPREFIX/system.reg"; then
  win32_sys_path=$win64_sys_path
  win64=false
else
  win32_sys_path="$WINEPREFIX/drive_c/windows/syswow64"
fi

overrideDll() {
  if ! $wine reg add 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v "$1" /d native,builtin /f >/dev/null 2>&1
  then
    echo -e "Lỗi ghi đè khóa $1"
    exit 1
  fi
}

restoreDll() {
  if ! $wine reg delete 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v "$1" /f > /dev/null 2>&1
  then
    echo "Lỗi xóa ghi đè khóa $1"
  fi
}

# TODO
installFile() {
  dstfile="${1}/${3}.dll"
  srcfile="${basedir}/${2}/${3}.dll"
  if ! [ -f "${srcfile}" ]; then
    echo "${srcfile}: Không tìm thấy tệp. Bỏ qua" >&2
    return 1
  fi

  if [ -n "$1" ]; then
    if [ -f "${dstfile}" ] || [ -L "${dstfile}" ]; then
      if ! [ -f "${dstfile}.old" ]; then
        mv -v "${dstfile}" "${dstfile}.old"
      else
        rm -v "${dstfile}"
      fi
    else
      touch "${dstfile}.old_none"
    fi

    $file_cmd "${srcfile}" "${dstfile}"
  fi

  return 0
}

# TODO
uninstallFile() {
  dstfile="${1}/${3}.dll"
  srcfile="${basedir}/${2}/${3}.dll"
  if ! [ -f "${srcfile}" ]; then
    echo "${srcfile}: Không tìm thấy tệp. Bỏ qua" >&2
    return 1
  fi

  if ! [ -f "${dstfile}" ] && ! [ -h "${dstfile}" ]; then
    echo "${dstfile}: Không tìm thấy tệp. Bỏ qua" >&2
    return 1
  fi

  if [ -f "${dstfile}.old" ]; then
    rm -v "${dstfile}"
    mv -v "${dstfile}.old" "${dstfile}"
    return 0
  elif [ -f "${dstfile}.old_none" ]; then
    rm -v "${dstfile}.old_none"
    rm -v "${dstfile}"
    return 0
  else
    return 1
  fi
}

install() {
  inst64_ret=-1
  if [ $win64 = "true" ]; then
    installFile "$win64_sys_path" "$lib64" "$1"
    inst64_ret="$?"
  fi

  inst32_ret=-1
  if [ $win32 = "true" ]; then
    installFile "$win32_sys_path" "$lib32" "$1"
    inst32_ret="$?"
  fi

  if (( ($inst32_ret == 0) || ($inst64_ret == 0) )); then
    overrideDll "$1"
  fi
}

uninstall() {
  uninst64_ret=-1
  if [ $win64 = "true" ]; then
    uninstallFile "$win64_sys_path" "$lib64" "$1"
    uninst64_ret="$?"
  fi

  uninst32_ret=-1
  if [ $win32 = "true" ]; then
    uninstallFile "$win32_sys_path" "$lib32" "$1"
    uninst32_ret="$?"
  fi

  if (( ($uninst32_ret == 0) || ($uninst64_ret == 0) )); then
    restoreDll "$1"
  fi
}

$action d3d9
$action d3d11
$action dxgi
