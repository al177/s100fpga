# Architecture
* blinkencard/ submodule for PCB, enclosure, Python code for ESP32
* PCB LEDs show the bus and other state on a front panel like an Altair 8800
* ESP32 SPI controller connected to ICE40UP5K FPGA SPI target
  * ESP32 loads bitstream to FPGA by first toggling /CRESET and sending over SPI. See iceboot.py
  * After configuration ESP32 to FPGA SPI can be used for sideband control of logic on FPGA
  * SPI signals on the FPGA use IOs:
    * SPI clock: 34
    * SPI MOSI: 33
    * SPI MISO: 32
    * SPI SS: 35
  * FPGA_INT is an output on FPGA IO 22 from the FPGA to the ESP32 for code running on the FPGA to get the ESP32's attention
  * The ESP32 currently drives the SPI target on the FPGA at 4MHz. Any SPI target in the RTL should be usable at up to 4MHz.
The ICE40UP5K contains a hard IP SPI interface. Evaluate whether or not using the SPI hard IP is more space efficient than an RTL implementation before finalizing a design.
* Serial port between FPGA and ESP32 mapped to serial console of emulation
  * ESP32 has a telnet terminal emulator for connecting remotely to the emulation console port, see term_server.py
* Toolchain is the open source IceStorm for ICE40 FPGAs
* Target FPGA is Lattice ICE40UP5K

# Coding
* Test benches should be created for any new or modified features in the FPGA
* Test benches should be in SystemVerilog

