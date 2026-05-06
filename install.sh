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

if [ -d "$install_dir/.git" ]; then
  chown -R "$control_user:$control_user" "$install_dir"
  runuser -u "$control_user" -- git -C "$install_dir" pull --ff-only
else
  rm -rf "$install_dir"
  git clone "$repo_url" "$install_dir"
fi

chown -R "$control_user:$control_user" "$install_dir"

AGENTYARD_SUPPRESS_NEXT_STEPS=1 "$install_dir/agentyard" install-control-plane
chown -R "$control_user:$control_user" "$install_dir"

printf '\nAgentyard control plane bootstrap complete.\n'
printf 'Next steps:\n'
printf '  sudo -iu %s\n' "$control_user"
printf '  cd ~/agentyard\n'
printf '  ./agentyard install\n'
