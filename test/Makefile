# Makefile for Cocotb testing
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src

# Include the Verilog sources
VERILOG_SOURCES += $(SRC_DIR)/project.v

# TOPLEVEL is the name of the module in your Verilog file
TOPLEVEL = tt_um_nebula_starfield

# MODULE is the name of the Python test file (without .py)
MODULE = test

# Include cocotb's make rules
include $(shell cocotb-config --makefiles)/Makefile.sim
