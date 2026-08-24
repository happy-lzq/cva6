#!/usr/bin/env bash

export CVA6_ROOT=/workspace/cva6
export RISCV="${CVA6_ROOT}/tools/riscv"
export VERILATOR_INSTALL_DIR="${CVA6_ROOT}/tools/verilator-v5.008"
export SPIKE_INSTALL_DIR="${CVA6_ROOT}/tools/spike"

export PATH="${CVA6_ROOT}/tools/bin:${VERILATOR_INSTALL_DIR}/bin:${SPIKE_INSTALL_DIR}/bin:${PATH}"

if [ -f "${CVA6_ROOT}/tools/venv/bin/activate" ]; then
    source "${CVA6_ROOT}/tools/venv/bin/activate"
fi

if [ -f "${CVA6_ROOT}/verif/sim/setup-env.sh" ]; then
    source "${CVA6_ROOT}/verif/sim/setup-env.sh"
fi

alias ..='cd ..'

if [[ $- == *i* ]] && command -v tput >/dev/null 2>&1 &&
   tput setaf 1 >/dev/null 2>&1; then
    export TERM="${TERM:-xterm-256color}"
    PS1='\[\033[1;32m\]\u@cva6\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ '
fi