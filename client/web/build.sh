#!/usr/bin/env bash
# Build the browser client into web/www/.
#
# Needs the wasm target and a matching wasm-bindgen CLI:
#   rustup target add wasm32-unknown-unknown
#   cargo install wasm-bindgen-cli --version 0.2.128
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
client="$(dirname "$here")"
profile="${1:-release}"

echo "building dso-web ($profile)"
cargo build --manifest-path "$here/Cargo.toml" --target wasm32-unknown-unknown \
  $([ "$profile" = release ] && echo --release)

wasm="$client/target/wasm32-unknown-unknown/$profile/dso_web.wasm"

# cargo install puts it in ~/.cargo/bin, which is not always on PATH.
bindgen="$(command -v wasm-bindgen || echo "$HOME/.cargo/bin/wasm-bindgen")"
if [ ! -x "$bindgen" ]; then
  echo "wasm-bindgen not found; install it with:" >&2
  echo "  cargo install wasm-bindgen-cli --version 0.2.128" >&2
  exit 1
fi
"$bindgen" --target web --out-dir "$here/www/pkg" --no-typescript "$wasm"

# The shipped player directory, which the client loads into its filesystem at
# startup. A manifest saves the page from having to guess what exists.
#
# Every file, not just *.ds: the READMEs are what bring /downloads and
# /home/music into being, and a console starts in /home, so filtering them out
# left it pointing at a directory that did not exist. The remote filesystem's
# .run and .password files are game content too.
scripts_src="$client/../client-legacy/user"
scripts_out="$here/www/scripts"
rm -rf "$scripts_out"
if [ -d "$scripts_src" ]; then
  manifest="["
  first=1
  while IFS= read -r file; do
    rel="${file#"$scripts_src"}"
    mkdir -p "$scripts_out$(dirname "$rel")"
    cp "$file" "$scripts_out$rel"
    [ $first -eq 1 ] && first=0 || manifest+=","
    manifest+="\"$rel\""
  done < <(find "$scripts_src" -type f | sort)
  manifest+="]"
  mkdir -p "$scripts_out"
  printf '%s' "$manifest" > "$scripts_out/manifest.json"
  echo "bundled $(find "$scripts_out" -type f -not -name manifest.json | wc -l) files"
fi

echo "built into $here/www"
