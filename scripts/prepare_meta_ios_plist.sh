#!/bin/bash
# Xcode build phase: copy the source plist and inject only the two Meta
# Flutter defines. Never evaluate define contents or print decoded values.
set +x
set -euo pipefail
umask 077

source_plist="${SCRIPT_INPUT_FILE_0:-${SRCROOT:?}/Runner/Info.plist}"
output_plist="${SCRIPT_OUTPUT_FILE_0:-${DERIVED_FILE_DIR:?}/BaraInfo.plist}"
meta_app_id=""
meta_client_token=""
app_id_count=0
client_token_count=0
invalid=0
remaining="${DART_DEFINES:-}"

while [[ -n "$remaining" ]]; do
  if [[ "$remaining" == *,* ]]; then
    entry="${remaining%%,*}"
    remaining="${remaining#*,}"
    [[ -n "$remaining" ]] || invalid=1
  else
    entry="$remaining"
    remaining=""
  fi
  if [[ ! "$entry" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]; then
    invalid=1
    break
  fi
  # The sentinel preserves trailing newlines; canonical re-encoding rejects
  # malformed padding and NULs that shell variables cannot represent.
  if ! decoded_with_sentinel="$(printf '%s' "$entry" | /usr/bin/base64 -D 2>/dev/null && printf '.')"; then
    invalid=1
    break
  fi
  decoded="${decoded_with_sentinel%.}"
  canonical="$(printf '%s' "$decoded" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')"
  if [[ "$canonical" != "$entry" ]]; then
    invalid=1
    break
  fi
  case "$decoded" in
    META_APP_ID=*)
      app_id_count=$((app_id_count + 1))
      meta_app_id="${decoded#META_APP_ID=}"
      ;;
    META_CLIENT_TOKEN=*)
      client_token_count=$((client_token_count + 1))
      meta_client_token="${decoded#META_CLIENT_TOKEN=}"
      ;;
  esac
done

if [[ "$invalid" != 0 || "$app_id_count" != 1 || "$client_token_count" != 1 ||
      "$meta_app_id" != 1600882908142439 || ! "$meta_client_token" =~ ^[0-9a-fA-F]{32}$ ]]; then
  if [[ "${CONFIGURATION:-}" != Debug ]]; then
    printf '%s\n' 'error: META_APP_ID and META_CLIENT_TOKEN must be supplied once as valid Flutter dart-defines.' >&2
    exit 1
  fi
  # Debug can build without measurement. Always clear both values so a prior
  # configured build cannot leave stale credentials in the generated plist.
  meta_app_id=""
  meta_client_token=""
fi

if [[ "$source_plist" == "$output_plist" ]]; then
  printf '%s\n' 'error: Meta derived plist must differ from the source plist.' >&2
  exit 1
fi
/bin/mkdir -p "$(/usr/bin/dirname "$output_plist")"
temporary="$(/usr/bin/mktemp "${output_plist}.XXXXXX")"
trap '/bin/rm -f "$temporary"' EXIT
/bin/cp "$source_plist" "$temporary"
/bin/chmod 600 "$temporary"
/usr/bin/plutil -replace FacebookAppID -string "$meta_app_id" "$temporary"
/usr/bin/plutil -replace FacebookClientToken -string "$meta_client_token" "$temporary"
/bin/mv -f "$temporary" "$output_plist"
