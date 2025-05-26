FROM mcr.microsoft.com/devcontainers/base:1.2.6-ubuntu-24.04

RUN apt update && apt install -y \
	nextpnr-ice40 yosys \
	fpga-icestorm iverilog \
	python3-pip netcat-traditional \
	git make binutils screen vim-nox \
	telnet && \
	apt remove -y vim-tiny && \
	apt clean
RUN python3 -m pip install --break-system-packages upydev
