#!/bin/bash
set -euo pipefail
set -x

git rev-parse HEAD > server/api/gitrev.txt
cp LICENSE server/LICENSE
