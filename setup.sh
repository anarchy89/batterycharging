#!/bin/sh
# Installs batterycharging into /usr/local/bin.
#
#   curl -fsSL https://raw.githubusercontent.com/anarchy89/batterycharging/main/setup.sh | sh
#
# It downloads the latest released script, checks that it runs and copies it into
# place. Run it again at any time to reinstall.
#
# Everything is inside a function that is called on the last line, so a
# download of this script that is cut short does nothing at all.
set -e

main() {
    url="https://github.com/anarchy89/batterycharging/releases/latest/download/batterycharging"
    folder="/usr/local/bin"
    download=$(mktemp -t batterycharging)
    trap 'rm -f "$download"' EXIT

    echo "Downloading batterycharging..."
    if ! curl -fsSL -o "$download" "$url"; then
        echo "Could not download $url" >&2
        exit 1
    fi
    chmod 755 "$download"
    if ! "$download" --version > /dev/null 2>&1; then
        echo "The downloaded file is not a working batterycharging." >&2
        exit 1
    fi

    if [ -d "$folder" ] && [ -w "$folder" ]; then
        install -m 755 "$download" "$folder/batterycharging"
    else
        echo "Installing into $folder needs your password."
        sudo mkdir -p "$folder"
        sudo install -m 755 "$download" "$folder/batterycharging"
    fi

    echo "Installed $("$folder/batterycharging" --version) in $folder."
    echo "Run: batterycharging off"
}

main
