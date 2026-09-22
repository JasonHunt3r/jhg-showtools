#!/bin/sh
# Builds build/library-probe from probe.swift plus ShowToolsCore's sources.
set -e
cd "$(dirname "$0")/../.."
mkdir -p build
swiftc -O -parse-as-library -module-name ShowToolsCore tools/library-probe/probe.swift \
  Sources/ShowToolsCore/*.swift -lsqlite3 -o build/library-probe
echo "built build/library-probe"
