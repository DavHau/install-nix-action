#!/usr/bin/env bash
set -euo pipefail

if type -p nix &>/dev/null ; then
  echo "Aborting: Nix is already installed at $(type -p nix)"
  exit
fi

# Configure Nix
add_config() {
  echo "$1" | tee -a /tmp/nix.conf >/dev/null
}
# Set jobs to number of cores
add_config "max-jobs = auto"
# Allow binary caches for user
add_config "trusted-users = root $USER"
# Append extra nix configuration if provided
if [[ $INPUT_EXTRA_NIX_CONFIG != "" ]]; then
  add_config "$INPUT_EXTRA_NIX_CONFIG"
fi
if [[ ! $INPUT_EXTRA_NIX_CONFIG =~ "experimental-features" ]]; then  
  add_config "experimental-features = nix-command flakes"
fi

# Nix installer flags
installer_options=(
  --no-channel-add
  --darwin-use-unencrypted-nix-store-volume
  --nix-extra-conf-file /tmp/nix.conf
)

# only use the nix-daemon settings if on darwin (which get ignored) or systemd is supported
if [[ $OSTYPE =~ darwin || -e /run/systemd/system ]]; then
  installer_options+=(
    --daemon
    --daemon-user-count `python -c 'import multiprocessing as mp; print(mp.cpu_count() * 2)'`
  )
else
  # "fix" the following error when running nix*
  # error: the group 'nixbld' specified in 'build-users-group' does not exist
  add_config "build-users-group ="
fi

if [[ $INPUT_INSTALL_OPTIONS != "" ]]; then
  IFS=' ' read -r -a extra_installer_options <<< $INPUT_INSTALL_OPTIONS
  installer_options=("${extra_installer_options[@]}" "${installer_options[@]}")
fi

echo "installer options: ${installer_options[@]}"

# There is --retry-on-errors, but only newer curl versions support that
until curl -o /tmp/install -v --fail --retry 5 --retry-connrefused -L "${INPUT_INSTALL_URL:-https://nixos.org/nix/install}" 
do
  sleep 1
done

chmod +x /tmp/install
sh /tmp/install "${installer_options[@]}"

if [[ $OSTYPE =~ darwin ]]; then
  # macOS needs certificates hints
  cert_file=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt
  echo "NIX_SSL_CERT_FILE=$cert_file" >> "$GITHUB_ENV"
  export NIX_SSL_CERT_FILE=$cert_file
  sudo launchctl setenv NIX_SSL_CERT_FILE "$cert_file"
fi

# Set paths
echo "/nix/var/nix/profiles/per-user/$USER/profile/bin" >> "$GITHUB_PATH"
echo "/nix/var/nix/profiles/default/bin" >> "$GITHUB_PATH"

if [[ $INPUT_NIX_PATH != "" ]]; then
  echo "NIX_PATH=${INPUT_NIX_PATH}" >> "$GITHUB_ENV"
fi
