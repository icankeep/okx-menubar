#!/usr/bin/env bash
set -euo pipefail
make app
open .build/OKXMenuBar.app
