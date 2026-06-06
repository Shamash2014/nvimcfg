#!/usr/bin/env bash
# Run the headless nvim test suite. Optional arg = single test name to scope the run.
#   tests/run.sh                          # whole suite
#   tests/run.sh test_tab_cycle_keymaps_exist   # one test (fast — good for TCR)
# Exits 0 if all selected tests pass, 1 otherwise.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

FILTER="${1:-}"
ARG="nil"
[ -n "$FILTER" ] && ARG="'$FILTER'"

NVIM3_TESTING=1 nvim --headless -u init.lua \
  -c "lua local ok,err=pcall(function() dofile('tests/runner.lua').run($ARG) end); if ok then vim.cmd('qa!') else io.stderr:write('TEST FAIL: '..tostring(err)..'\n'); vim.cmd('cq 1') end"
