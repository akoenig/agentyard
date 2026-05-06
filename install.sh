#!/usr/bin/env sh
set -eu

[ "$(id -u)" -eq 0 ] || { printf 'Run this installer as root, for example: curl -fsSL <url> | sudo sh\n' >&2; exit 1; }

repo_url=${AGENTYARD_REPO_URL:-https://github.com/akoenig/agentyard.git}
control_user=${AGENTYARD_CONTROL_USER:-minder}
install_dir=${AGENTYARD_INSTALL_DIR:-/home/$control_user/agentyard}

install_base_packages() {
  if ! command -v apt-get >/dev/null 2>&1; then
    printf 'Agentyard currently supports Ubuntu/Debian hosts with apt-get.\n' >&2
    exit 1
  fi

  apt-get update
  apt-get install -y ca-certificates curl git sudo
}

install_base_packages

if ! id "$control_user" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$control_user"
  passwd -l "$control_user" >/dev/null 2>&1 || true
fi

tmp_dir=$(mktemp -d)
git clone "$repo_url" "$tmp_dir/agentyard"

if [ -f "$install_dir/.env" ]; then
  cp "$install_dir/.env" "$tmp_dir/agentyard/.env"
fi

rm -rf "$install_dir"
mkdir -p "$(dirname "$install_dir")"
mv "$tmp_dir/agentyard" "$install_dir"
rm -rf "$tmp_dir"

chown -R "$control_user:$control_user" "$install_dir"

AGENTYARD_SUPPRESS_NEXT_STEPS=1 "$install_dir/agentyard" install-control-plane
chown -R "$control_user:$control_user" "$install_dir"

printf '\nAgentyard control plane bootstrap complete.\n'
printf 'Next step:\n'
printf '  agentyard init\n'
