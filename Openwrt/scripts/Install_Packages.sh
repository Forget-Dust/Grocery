#!/bin/sh
# for f in */*.sh;do f="${f}";rm -rf "${f}";done
# for d in */;do d="${d%/}";cp -rf Install.sh ${d};done
# for f in *.run;do f="${f}";./${f} --target ${f%.run};done
# for d in */;do d="${d%/}";makeself --xz "${d}" "${d}.run" "${d}" ./Install.sh;done

if ls *.run >/dev/null 2>&1; then
    for f in *.run; do sh "$f" && rm -rf "$f" "${f%.run}"; done
else
    case "$(command -v apk || command -v opkg)" in
        *apk) echo "==> Updating apk list..." && apk update || echo "update failed"; pm="apk add --allow-untrusted --force-overwrite"; ext="apk" ;;
        *opkg) echo "==> Updating opkg list..." && opkg update || echo "update failed"; pm="opkg install --force-overwrite"; ext="ipk" ;;
        *) echo "==> System Not Supported"; pm="" ;;
    esac
    if [ -n "$pm" ]; then
        echo "==> Installing packages..."
        find . -type f \( -name "*$(uname -m)*.$ext" -o -name "luci-*.$ext" -o -name "*.$ext" \) | while read -r pkg; do
            $pm "$pkg" 2>/dev/null && rm -f "$pkg"
        done; echo "==> Done"
    fi
fi
