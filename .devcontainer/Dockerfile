FROM mcr.microsoft.com/devcontainers/base:1.2.6-ubuntu-24.04

RUN apt update && apt install -y \
	nextpnr-ice40 yosys \
	fpga-icestorm iverilog \
	git make binutils screen vim-nox && \
	apt remove -y vim-tiny && \
	apt clean
