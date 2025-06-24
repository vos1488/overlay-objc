#!/bin/bash
# Быстрый запуск overlay в компактном режиме

cd "$(dirname "$0")"
./build/release/overlay --compact
