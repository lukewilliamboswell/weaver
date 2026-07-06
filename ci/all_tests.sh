#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

roc_bin="${ROC:-roc}"

if [ -n "${WEAVER_TMPDIR:-}" ]; then
    tmp_base="$WEAVER_TMPDIR"
else
    tmp_base="$root_dir/.weaver-tmp"
fi
export WEAVER_TMPDIR="$tmp_base"
export ROC="$roc_bin"

tmp_dir="$tmp_base/weaver-ci"
docs_dir="$tmp_dir/docs"
bundle_dir="$tmp_dir/bundle"

rm -rf "$tmp_dir"
mkdir -p "$docs_dir" "$bundle_dir"

echo "$("$roc_bin" version)"

echo ""
echo "Checking format..."
"$roc_bin" fmt --check package examples

echo ""
echo "Checking package..."
"$roc_bin" check package/main.roc

echo ""
echo "Running package tests..."
"$roc_bin" test package/main.roc

echo ""
echo "Generating package docs..."
"$roc_bin" docs package/main.roc --output="$docs_dir"

case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
        echo ""
        echo "Skipping package bundling on Windows."
        exit 0
        ;;
esac

echo ""
echo "Bundling package..."
scripts/bundle.sh --output-dir "$bundle_dir"

echo ""
echo "Testing examples against localhost bundle..."
python3 ci/test_bundle_examples.py --skip-build-run
