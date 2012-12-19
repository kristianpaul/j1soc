#
# Author: Xiangfu Liu
#
# This is free and unencumbered software released into the public domain.
# For details see the UNLICENSE file at the root of the source tree.
#

all: soc.bit

# Build for m1
#FPGA_TARGET ?= xc6slx45-fgg484-2

# Build for mini-slx9 board tqg144/ftg256/csg324
#FPGA_TARGET ?= xc6slx9-2-csg324
#FPGA_TARGET ?= xc6slx9-2-ftg256
FPGA_TARGET ?= xc6slx9-2-tqg144

%.bit: %-routed.ncd
# -d disables DRC
# -b creates rawbits file .rbt
# -l creates logic allocation file .ll
# -w overwrite existing output file
# "-g compress" enables compression
	if test -f $<; then bitgen -b -l -w $< $@; fi
	mkdir -p bits
	cp $@ bits/$(FPGA_TARGET).$@

%.ncd: %.xdl
	-xdl -xdl2ncd $<

%-routed.ncd: %.ncd
	par -w $< $@

%.ncd: %.ngd
	map -w $<

%.ngd: %.$(FPGA_TARGET).ucf %.ngc
	ngdbuild -uc $< $(@:.ngd=.ngc)

%.ngc: %.xst
	xst -ifn $<

%.xst: %.prj
	echo run > $@
	echo -ifn $< >> $@
	echo -top $(basename $<) >> $@
	echo -ifmt MIXED >> $@
	echo -opt_mode SPEED >> $@
	echo -opt_level 1 >> $@
	echo -ofn $(<:.prj=.ngc) >> $@
	echo -p $(FPGA_TARGET) >> $@

%.prj: %.v
	for i in `echo $^`; do \
	    echo "verilog $(basename $<) $$i" >> $@; \
	done

load: soc.bit
	echo "cable milkymist" > load.jtag
	echo "detect" >> load.jtag
	echo "instruction CFG_OUT 000100 BYPASS" >> load.jtag
	echo "instruction CFG_IN 000101 BYPASS" >> load.jtag
	echo "pld load $<" >> load.jtag
	jtag load.jtag

reset:
	echo "cable milkymist" > load.jtag
	echo "detect" >> load.jtag
	echo "instruction CFG_OUT 000100 BYPASS" >> load.jtag
	echo "instruction CFG_IN 000101 BYPASS" >> load.jtag
	echo "pld reconfigure" >> load.jtag
	jtag load.jtag
