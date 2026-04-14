#!/usr/bin/env bash
set -euo pipefail

repo_root=""
keystore_base64="${ANDROID_KEYSTORE_BASE64:-}"
keystore_file="${ANDROID_KEYSTORE_FILE:-}"
store_password="${ANDROID_KEYSTORE_PASSWORD:-}"
key_alias="${ANDROID_KEY_ALIAS:-}"
key_password="${ANDROID_KEY_PASSWORD:-}"
force=0

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      repo_root="${2:-}"
      shift 2
      ;;
    --keystore-base64)
      keystore_base64="${2:-}"
      shift 2
      ;;
    --keystore-file)
      keystore_file="${2:-}"
      shift 2
      ;;
    --store-password)
      store_password="${2:-}"
      shift 2
      ;;
    --key-alias)
      key_alias="${2:-}"
      shift 2
      ;;
    --key-password)
      key_password="${2:-}"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$repo_root" ]]; then
  repo_root="$(cd "$script_dir/.." && pwd)"
else
  repo_root="$(cd "$repo_root" && pwd)"
fi

android_dir="$repo_root/android"
key_properties_path="$android_dir/key.properties"
signing_dir="$android_dir/signing"
keystore_target_path="$signing_dir/pet-release.jks"

if [[ $force -eq 0 && -z "$keystore_base64" && -z "$keystore_file" && -f "$key_properties_path" && -f "$keystore_target_path" ]]; then
  printf 'Android release signing is already prepared at %s\n' "$key_properties_path"
  exit 0
fi

if [[ -z "$keystore_base64" && -z "$keystore_file" ]]; then
  fail "Android release signing is not configured. Provide ANDROID_KEYSTORE_FILE or ANDROID_KEYSTORE_BASE64 before running this script."
fi

if [[ -n "$keystore_base64" && -n "$keystore_file" ]]; then
  fail "Provide only one keystore source: ANDROID_KEYSTORE_FILE or ANDROID_KEYSTORE_BASE64."
fi

[[ -n "$store_password" ]] || fail "Missing required signing value: ANDROID_KEYSTORE_PASSWORD"
[[ -n "$key_alias" ]] || fail "Missing required signing value: ANDROID_KEY_ALIAS"
[[ -n "$key_password" ]] || fail "Missing required signing value: ANDROID_KEY_PASSWORD"

mkdir -p "$signing_dir"

decode_base64_to_file() {
  local input="$1"
  local out_file="$2"

  if command -v python3 >/dev/null 2>&1; then
    BASE64_INPUT="$input" OUTPUT_PATH="$out_file" python3 - <<'PY'
import base64
import os
from pathlib import Path

data = os.environ["BASE64_INPUT"]
decoded = base64.b64decode(data)
Path(os.environ["OUTPUT_PATH"]).write_bytes(decoded)
PY
    return
  fi

  if printf '%s' "$input" | base64 --decode >"$out_file" 2>/dev/null; then
    return
  fi

  if printf '%s' "$input" | base64 -d >"$out_file" 2>/dev/null; then
    return
  fi

  if printf '%s' "$input" | base64 -D >"$out_file" 2>/dev/null; then
    return
  fi

  fail "Could not decode ANDROID_KEYSTORE_BASE64. Install python3 or a compatible base64 command."
}

if [[ -n "$keystore_base64" ]]; then
  decode_base64_to_file "$keystore_base64" "$keystore_target_path"
  [[ -s "$keystore_target_path" ]] || fail "ANDROID_KEYSTORE_BASE64 decoded to an empty keystore file."
else
  [[ -f "$keystore_file" ]] || fail "ANDROID_KEYSTORE_FILE was not found: $keystore_file"
  source_keystore_path="$(cd "$(dirname "$keystore_file")" && pwd)/$(basename "$keystore_file")"
  if [[ "$source_keystore_path" != "$keystore_target_path" ]]; then
    cp "$source_keystore_path" "$keystore_target_path"
  fi
fi

cat >"$key_properties_path" <<EOF
storePassword=$store_password
keyPassword=$key_password
keyAlias=$key_alias
storeFile=signing/pet-release.jks
EOF

printf 'Prepared Android release signing at %s\n' "$key_properties_path"
