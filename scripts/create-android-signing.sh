#!/usr/bin/env bash
set -euo pipefail

repo_root=""
output_directory="${HOME}/.petnote-signing"
keystore_file_name="pet-release.jks"
alias_name="petnote_release"
store_password=""
key_password=""
common_name="PetNote Android Release"
organization_unit="Mobile"
organization="PetNote"
locality="Shanghai"
state="Shanghai"
country="CN"
validity_days=36500
force=0

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

random_secret() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import base64
import secrets

value = base64.b64encode(secrets.token_bytes(24)).decode("ascii")
value = value.replace("+", "A").replace("/", "b").replace("=", "9")
print(value[:24])
PY
    return
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 24 | tr '+/=' 'Ab9' | cut -c1-24
    return
  fi

  fail "Could not generate a random secret. Install python3 or openssl, or pass explicit passwords."
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      repo_root="${2:-}"
      shift 2
      ;;
    --output-directory)
      output_directory="${2:-}"
      shift 2
      ;;
    --keystore-file-name)
      keystore_file_name="${2:-}"
      shift 2
      ;;
    --alias)
      alias_name="${2:-}"
      shift 2
      ;;
    --store-password)
      store_password="${2:-}"
      shift 2
      ;;
    --key-password)
      key_password="${2:-}"
      shift 2
      ;;
    --common-name)
      common_name="${2:-}"
      shift 2
      ;;
    --organization-unit)
      organization_unit="${2:-}"
      shift 2
      ;;
    --organization)
      organization="${2:-}"
      shift 2
      ;;
    --locality)
      locality="${2:-}"
      shift 2
      ;;
    --state)
      state="${2:-}"
      shift 2
      ;;
    --country)
      country="${2:-}"
      shift 2
      ;;
    --validity-days)
      validity_days="${2:-}"
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

mkdir -p "$output_directory"
output_directory="$(cd "$output_directory" && pwd)"
keystore_path="$output_directory/$keystore_file_name"
summary_json_path="$output_directory/pet-release.summary.json"

if [[ -f "$keystore_path" && $force -eq 0 ]]; then
  fail "Keystore already exists at $keystore_path. Use --force only when you have confirmed replacing it is safe."
fi

command -v keytool >/dev/null 2>&1 || fail "keytool was not found."

if [[ -z "$store_password" ]]; then
  store_password="$(random_secret)"
fi

if [[ -z "$key_password" ]]; then
  key_password="$(random_secret)"
fi

dname="CN=$common_name, OU=$organization_unit, O=$organization, L=$locality, ST=$state, C=$country"

rm -f "$keystore_path"
keytool \
  -genkeypair \
  -v \
  -keystore "$keystore_path" \
  -storetype JKS \
  -alias "$alias_name" \
  -keyalg RSA \
  -keysize 2048 \
  -validity "$validity_days" \
  -storepass "$store_password" \
  -keypass "$key_password" \
  -dname "$dname"

prepare_script="$script_dir/prepare-android-signing.sh"
[[ -f "$prepare_script" ]] || fail "Android signing helper script was not found at $prepare_script"

ANDROID_KEYSTORE_FILE="$keystore_path" \
ANDROID_KEYSTORE_PASSWORD="$store_password" \
ANDROID_KEY_ALIAS="$alias_name" \
ANDROID_KEY_PASSWORD="$key_password" \
"$prepare_script" --repo-root "$repo_root" --force

fingerprint_output="$(keytool -list -v -keystore "$keystore_path" -storepass "$store_password" -alias "$alias_name")"

cat >"$summary_json_path" <<EOF
{
  "keystorePath": "$(json_escape "$keystore_path")",
  "alias": "$(json_escape "$alias_name")",
  "storePassword": "$(json_escape "$store_password")",
  "keyPassword": "$(json_escape "$key_password")",
  "distinguishedName": "$(json_escape "$dname")"
}
EOF

printf 'Created Android release signing:\n'
printf '  keystorePath=%s\n' "$keystore_path"
printf '  alias=%s\n' "$alias_name"
printf '  summary=%s\n' "$summary_json_path"
printf '%s\n' "$fingerprint_output"
