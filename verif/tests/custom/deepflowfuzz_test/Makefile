SHELL := /bin/bash

.DEFAULT_GOAL := help

TEST_DIR ?= $(CURDIR)

CVA6_ROOT ?= $(abspath $(TEST_DIR)/../../../../..)

SIM_DIR    := $(CVA6_ROOT)/verif/sim
COMMON_DIR := $(CVA6_ROOT)/verif/tests/custom/common
ENV_DIR    := $(CVA6_ROOT)/verif/tests/custom/env
RISCV      ?= $(CVA6_ROOT)/tools/riscv

RISCV_CC := $(RISCV)/bin/riscv-none-elf-gcc
OBJCOPY  := $(RISCV)/bin/riscv-none-elf-objcopy
OBJDUMP  := $(RISCV)/bin/riscv-none-elf-objdump

TEST_SOURCES := $(wildcard $(TEST_DIR)/*.c)
SRC ?= $(firstword $(TEST_SOURCES))

TEST_NAME := $(basename $(notdir $(SRC)))

BUILD_DIR := $(TEST_DIR)/build

RUN_ID  ?= $(shell date +%Y%m%d-%H%M%S)
RUN_DIR := $(BUILD_DIR)/runs/$(RUN_ID)

ELF  := $(BUILD_DIR)/$(TEST_NAME).elf
BIN  := $(BUILD_DIR)/$(TEST_NAME).bin
DUMP := $(BUILD_DIR)/$(TEST_NAME).dump

TARGET ?= cv64a6_imafdc_sv39
ISS ?= veri-testharness,spike
SEED ?= 1
ISS_TIMEOUT ?= 500

DFZ_TRACE ?= 0
ISS_COMP_OPTS ?=
ISS_RUN_OPTS ?= +debug_disable=1 +UVM_VERBOSITY=UVM_NONE

TRACE_DIR  := $(RUN_DIR)/TRACE
TRACE_FILE := $(TRACE_DIR)/$(TEST_NAME).l1.tsv
TRACE_LATEST := $(BUILD_DIR)/TRACE/$(TEST_NAME).l1.tsv

ifeq ($(DFZ_TRACE),1)
ISS_COMP_OPTS += +define+DFZ_TRACE
ISS_RUN_OPTS  += +dfz_trace_file=$(TRACE_FILE)
endif

MARCH ?= rv64gc_zba_zbb_zbs_zbc_zbkb_zbkx_zkne_zknd_zknh
MABI  ?= lp64d

LINKER   := $(CVA6_ROOT)/config/gen_from_riscv_config/linker/link.ld
ISS_YAML := $(SIM_DIR)/cva6.yaml

GCC_OPTS := \
	-static \
	-mcmodel=medany \
	-fvisibility=hidden \
	-nostdlib \
	-nostartfiles \
	-g \
	$(COMMON_DIR)/syscalls.c \
	$(COMMON_DIR)/crt.S \
	-I$(SIM_DIR)/dv/user_extension \
	-I$(ENV_DIR) \
	-I$(COMMON_DIR) \
	-lgcc

.PHONY: help list check build run spike rtl trace clean

help:
	@echo "DeepFlowFuzz single-test framework"
	@echo
	@echo "Current test directory: $(TEST_DIR)"
	@echo
	@echo "Targets:"
	@echo "  make list"
	@echo "  make check"
	@echo "  make build"
	@echo "  make run"
	@echo "  make spike"
	@echo "  make rtl"
	@echo "  make trace"
	@echo "  make clean"

list: check
	@echo "Test directory:"
	@echo "  $(TEST_DIR)"
	@echo
	@echo "Test source:"
	@echo "  $(SRC)"
	@echo
	@echo "Build directory:"
	@echo "  $(BUILD_DIR)"
	@echo
	@echo "Current build files:"
	@if [[ -d "$(BUILD_DIR)" ]]; then \
		find "$(BUILD_DIR)" -maxdepth 1 -type f -print | sort; \
	else \
		echo "  build directory does not exist"; \
	fi

check:
	@if [[ ! -d "$(TEST_DIR)" ]]; then \
		echo "ERROR: test directory not found: $(TEST_DIR)" >&2; \
		exit 2; \
	fi

	@if [[ $(words $(TEST_SOURCES)) -ne 1 ]]; then \
		echo "ERROR: exactly one .c source file is required" >&2; \
		echo "Found: $(TEST_SOURCES)" >&2; \
		exit 2; \
	fi

	@test -f "$(LINKER)"
	@test -f "$(COMMON_DIR)/syscalls.c"
	@test -f "$(COMMON_DIR)/crt.S"
	@test -x "$(RISCV_CC)"
	@test -x "$(OBJCOPY)"
	@test -x "$(OBJDUMP)"

	@echo "TEST_DIR = $(TEST_DIR)"
	@echo "SOURCE   = $(SRC)"
	@echo "TARGET   = $(TARGET)"
	@echo "MARCH    = $(MARCH)"
	@echo "MABI     = $(MABI)"

build: check
	@set -euo pipefail; \
	mkdir -p "$(BUILD_DIR)"; \
	echo "[BUILD] $(SRC)"; \
	"$(RISCV_CC)" \
		"$(SRC)" \
		$(GCC_OPTS) \
		-T"$(LINKER)" \
		-march="$(MARCH)" \
		-mabi="$(MABI)" \
		-o "$(ELF)"; \
	"$(OBJCOPY)" \
		-O binary \
		"$(ELF)" \
		"$(BIN)"; \
	"$(OBJDUMP)" \
		-d \
		--disassemble=main \
		-M no-aliases,numeric \
		"$(ELF)" > "$(DUMP)"; \
	echo; \
	echo "ELF:  $(ELF)"; \
	echo "BIN:  $(BIN)"; \
	echo "DUMP: $(DUMP)"

run: build
	@set -euo pipefail; \
	mkdir -p "$(RUN_DIR)"; \
	if [[ "$(DFZ_TRACE)" == "1" ]]; then \
		mkdir -p "$(TRACE_DIR)"; \
	fi; \
	source "$(CVA6_ROOT)/tools/venv/bin/activate"; \
	source "$(SIM_DIR)/setup-env.sh"; \
	cd "$(SIM_DIR)"; \
	python3 cva6.py \
		--elf_tests "$(ELF)" \
		--output "$(RUN_DIR)" \
		--iss_yaml "$(ISS_YAML)" \
		--target "$(TARGET)" \
		--iss "$(ISS)" \
		--linker "$(LINKER)" \
		--sv_seed "$(SEED)" \
		--iss_timeout "$(ISS_TIMEOUT)" \
		--isscomp_opts "$(ISS_COMP_OPTS)" \
		--issrun_opts "$(ISS_RUN_OPTS)"; \
	ln -sfn "runs/$(RUN_ID)" "$(BUILD_DIR)/latest"; \
	if [[ "$(DFZ_TRACE)" == "1" ]]; then \
		ln -sfn "runs/$(RUN_ID)/TRACE" "$(BUILD_DIR)/TRACE"; \
	fi; \
	echo; \
	echo "Simulation completed"; \
	echo "Latest result: $(BUILD_DIR)/latest"

spike:
	@$(MAKE) --no-print-directory \
		ISS=spike \
		SEED="$(SEED)" \
		run

rtl:
	@$(MAKE) --no-print-directory \
		ISS=veri-testharness \
		SEED="$(SEED)" \
		run

trace:
	@$(MAKE) --no-print-directory \
		DFZ_TRACE=1 \
		RUN_ID="$(RUN_ID)" \
		ISS="$(ISS)" \
		SEED="$(SEED)" \
		run
	@echo "DeepFlowFuzz TRACE:"
	@test -f "$(TRACE_FILE)"
	@test -f "$(TRACE_LATEST)"
	@echo "  archive: $(TRACE_FILE)"
	@echo "  stable:  $(TRACE_LATEST)"

clean:
	@if [[ "$(BUILD_DIR)" != "$(TEST_DIR)/build" ]]; then \
		echo "ERROR: unsafe build directory: $(BUILD_DIR)" >&2; \
		exit 2; \
	fi
	@rm -rf -- "$(BUILD_DIR)"
	@echo "Removed: $(BUILD_DIR)"
