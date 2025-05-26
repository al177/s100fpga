FROM ubuntu:24.04

RUN apt update && apt install -y \
	nextpnr-ice40 yosys \
	fpga-icestorm iverilog \
	git make binutils screen vim-nox && \
	apt remove vim-tiny && \
	apt clean
