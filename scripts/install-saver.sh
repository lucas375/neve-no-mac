#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
zsh scripts/build-saver.sh "$@"
source_dir="$project_dir/dist/Neve no Mac.saver"
target_dir="$HOME/Library/Screen Savers/Neve no Mac.saver"
if [[ -L "$target_dir" ]]; then
    print -u2 'O destino é um link simbólico. Nenhum arquivo foi substituído.'
    exit 1
fi
if [[ -d "$target_dir" ]]; then
    existing_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$target_dir/Contents/Info.plist")
    if [[ "$existing_id" != local.lucas.nevemac.screensaver ]]; then
        print -u2 'Já existe outro protetor com esse nome. Nenhum arquivo foi substituído.'
        exit 1
    fi
    backup_dir="$HOME/Library/Application Support/NeveMac/Backups/ScreenSaver-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${backup_dir:h}"
    ditto "$target_dir" "$backup_dir"
    # Avoid keeping stale private resources when the new build does not contain them.
    rm -f "$target_dir/Contents/Resources/Background.image" "$target_dir/Contents/Resources/SnowSettings.json"
fi
mkdir -p "${target_dir:h}"
ditto "$source_dir" "$target_dir"
codesign --verify --strict "$target_dir"
print -r -- "$target_dir"
