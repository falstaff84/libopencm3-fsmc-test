##
## FSMC test for NG-UAVP HW0.30
##
## Copyright (C) 2009 Uwe Hermann <uwe@hermann-uwe.de>
## Copyright (C) 2010 Piotr Esden-Tempski <piotr@esden.net>
## Copyright (C) 2011 Fergus Noble <fergusnoble@gmail.com>
## Copyright (C) 2013 Stefan Agner <stefan@dev.uavp.ch>
##
## This library is free software: you can redistribute it and/or modify
## it under the terms of the GNU Lesser General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## This library is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU Lesser General Public License for more details.
##
## You should have received a copy of the GNU Lesser General Public License
## along with this library.  If not, see <http://www.gnu.org/licenses/>.
##

BINARY = fsmc_test

LDSCRIPT = stm32f4.ld

PREFIX	?= arm-none-eabi
#PREFIX	?= arm-ngos-eabi

CC		= $(PREFIX)-gcc
LD		= $(PREFIX)-gcc
OBJCOPY		= $(PREFIX)-objcopy
OBJDUMP		= $(PREFIX)-objdump
GDB		= $(PREFIX)-gdb
FLASH		= $(shell which st-flash)

# TOOLCHAIN_DIR is libopencm3 directory..
TOOLCHAIN_DIR ?= ../libopencm3
#ifeq ($(wildcard ../../../../../libopencm3/lib/libopencm3_stm32f4.a),)
#ifneq ($(strip $(shell which $(CC))),)
#TOOLCHAIN_DIR := $(shell dirname `which $(CC)`)/../$(PREFIX)
#endif
#else
#ifeq ($(V),1)
#$(info We seem to be building the example in the source directory. Using local library!)
#endif
#endif

CFLAGS		+= -O0 -g \
		   -Wall -Wextra -Wimplicit-function-declaration \
		   -Wredundant-decls -Wmissing-prototypes -Wstrict-prototypes \
		   -Wundef -Wshadow \
		   -I$(TOOLCHAIN_DIR)/include \
		   -fno-common -mcpu=cortex-m4 -mthumb \
		   -mfloat-abi=hard -mfpu=fpv4-sp-d16 -MD -DSTM32F4
LDSCRIPT	?= $(BINARY).ld
LDFLAGS		+= --static -lc -lnosys -L$(TOOLCHAIN_DIR)/lib \
			 -L$(TOOLCHAIN_DIR)/lib/stm32/f4 \
		   -T$(LDSCRIPT) -nostartfiles -Wl,--gc-sections \
		   -mthumb -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16
OBJS		+= $(BINARY).o

OOCD		?= openocd
OOCD_INTERFACE	?= uavp-ng-ftdi-jtag.cfg
OOCD_BOARD_FC	?= openocd-stm32f4-fc.cfg
OOCD_BOARD_UC	?= openocd-stm32f4-uc.cfg
OOCD_SCRIPT	?= uavp-ng-hw-0.30.conf
# Black magic probe specific variables
# Set the BMP_PORT to a serial port and then BMP is used for flashing
BMP_PORT        ?=

# Be silent per default, but 'make V=1' will show all compiler calls.
ifneq ($(V),1)
Q := @
NULL := 2>/dev/null
else
LDFLAGS += -Wl,--print-gc-sections
endif

.SUFFIXES: .elf .bin .hex .srec .list .images
.SECONDEXPANSION:
.SECONDARY:

all: images

images: $(BINARY).images
flash: $(BINARY).flash
flash-fc: $(BINARY).flash-fc
flash-uc: $(BINARY).flash-uc

%.images: %.bin %.hex %.srec %.list
	@#echo "*** $* images generated ***"

%.bin: %.elf
	@#printf "  OBJCOPY $(*).bin\n"
	$(Q)$(OBJCOPY) -Obinary $(*).elf $(*).bin

%.hex: %.elf
	@#printf "  OBJCOPY $(*).hex\n"
	$(Q)$(OBJCOPY) -Oihex $(*).elf $(*).hex

%.srec: %.elf
	@#printf "  OBJCOPY $(*).srec\n"
	$(Q)$(OBJCOPY) -Osrec $(*).elf $(*).srec

%.list: %.elf
	@#printf "  OBJDUMP $(*).list\n"
	$(Q)$(OBJDUMP) -S $(*).elf > $(*).list

%.elf: $(OBJS) $(LDSCRIPT) $(TOOLCHAIN_DIR)/lib/libopencm3_stm32f4.a
	@#printf "  LD      $(subst $(shell pwd)/,,$(@))\n"
	$(Q)$(LD) -o $(*).elf $(OBJS) -lopencm3_stm32f4 $(LDFLAGS)

%.o: %.c Makefile
	@#printf "  CC      $(subst $(shell pwd)/,,$(@))\n"
	$(Q)$(CC) $(CFLAGS) -o $@ -c $<

clean:
	$(Q)rm -f *.o
	$(Q)rm -f *.d
	$(Q)rm -f *.elf
	$(Q)rm -f *.bin
	$(Q)rm -f *.hex
	$(Q)rm -f *.srec
	$(Q)rm -f *.list

%.stlink-flash: %.bin
	@printf "  FLASH  $<\n"
	$(Q)$(FLASH) write $(*).bin 0x8000000

	
ifeq ($(BMP_PORT),)
%.flash-fc: %.hex
	@printf "  FLASH   $<\n"
	@# IMPORTANT: Don't use "resume", only "reset" will work correctly!
	$(Q)$(OOCD) -f $(OOCD_INTERFACE) \
		    -f $(OOCD_BOARD_UC) \
		    -f $(OOCD_SCRIPT) \
		    -c "init" \
		    -c "flash_it $(*).hex 0"
%.flash-uc: %.hex
	@printf "  FLASH   $<\n"
	@# IMPORTANT: Don't use "resume", only "reset" will work correctly!
	$(Q)$(OOCD) -f $(OOCD_INTERFACE) \
		    -f $(OOCD_BOARD_FC) \
		    -f $(OOCD_SCRIPT) \
		    -c "init" \
		    -c "flash_it $(*).hex 0"
else
%.flash: %.elf
	@echo "  GDB   $(*).elf (flash)"
	$(Q)$(GDB) --batch \
		   -ex 'target extended-remote $(BMP_PORT)' \
		   -x $(TOOLCHAIN_DIR)/scripts/black_magic_probe_flash.scr \
		   $(*).elf
endif

.PHONY: images clean

-include $(OBJS:.o=.d)

