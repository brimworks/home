#!/bin/bash
#
# NOTE: Only tested on raspian buster
HOME_VERSION="${VERSION:-4}"
INSTALL_DIR=/opt/home

if [ "$EUID" -ne 0 ]; then
    echo "This script must be ran as root... try sudo!" 1>&2
    exit 1
fi

expand() {
    echo "Expanding $1" 1>&2
    eval "cat <<EOF
$(<$1)
EOF
" || {
        printf "\t...during expansion of %s\n" "$1" 1>&2
        exit 1
    }
}

expand-r() {
    local IFS=$'\n'
    for src_path in $(find "$1" -type f -name '*.expand'); do
        dst_path="${src_path%.expand}"
        # Use `cp` to preserve permissions:
        cp -p "$src_path" "$dst_path"
        # Now expand it:
        expand "$src_path" > "$dst_path"
    done
}

# Download home executable:
mkdir -p "$INSTALL_DIR"
curl -sSL -o home.tgz "https://github.com/brimworks/home/releases/download/snapshot-${HOME_VERSION}/home"
tar -C "$INSTALL_DIR" -xvf home.tgz

expand-r "$INSTALL_DIR"

################ TLS Key ################
if ! [ -e "$INSTALL_DIR/server.key" ]; then
    openssl req -new -newkey rsa:2048 -nodes -keyout "$INSTALL_DIR/server.key" -out "$INSTALL_DIR/server.csr"
    # Now get server.csr signed (manual step)
fi

################ NATS ################
# "nats" group/user:
if ! getent group nats > /dev/null; then
    addgroup --system nats
fi
if ! id -u nats > /dev/null; then
    adduser --system --no-create-home --disabled-password --disabled-login nats
fi
# Add symlink for systemd:
ln -sf "$INSTALL_DIR/etc/nats-server.service" "$(pkg-config systemd --variable=systemdsystemunitdir)"
systemctl --now enable nats-server


################ home server ################
# "home" group/user:
if ! getent group home > /dev/null; then
    addgroup --system home
fi
if ! id -u home > /dev/null; then
    adduser --system --no-create-home --disabled-password --disabled-login --ingroup home home
fi
# Add symlinks for sytemd
ln -sf "$INSTALL_DIR/etc/home.service" "$(pkg-config systemd --variable=systemdsystemunitdir)"
systemctl --now enable home

