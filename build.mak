
arch = x64
INCLUDES = -I. -I$(src)/arch/$(arch) -I$(src)
CXXFLAGS = -std=gnu++11 -lstdc++ $(CFLAGS) $(do-sys-includes) $(INCLUDES)
CFLAGS = $(autodepend) -g -Wall -Wno-pointer-arith $(INCLUDES) -Werror $(cflags-$(mode)) \
	$(arch-cflags)
ASFLAGS = -g $(autodepend)

cflags-debug =
cflags-release = -O2

arch-cflags = -msse4.1

define newline =


endef

quiet = $(if $V, $1, @echo ' ' $2 $(newline) @$1)
very-quiet = $(if $V, $1, @$1)

makedir = $(call very-quiet, mkdir -p $(dir $@))
build-cxx = $(CXX) $(CXXFLAGS) -c -o $@ $<
q-build-cxx = $(call quiet, $(build-cxx), CXX $@)
build-c = $(CC) $(CFLAGS) -c -o $@ $<
q-build-c = $(call quiet, $(build-c), CC $@)
build-s = $(CXX) $(CXXFLAGS) $(ASFLAGS) -c -o $@ $<
q-build-s = $(call quiet, $(build-s), AS $@)

%.o: %.cc
	$(makedir)
	$(q-build-cxx)

%.o: %.c
	$(makedir)
	$(q-build-c)

%.o: %.S
	$(makedir)
	$(q-build-s)

sys-includes = $(jdkbase)/include $(jdkbase)/include/linux
autodepend = -MD -MT $@ -MP

do-sys-includes = $(foreach inc, $(sys-includes), -isystem $(inc))

all: loader.bin

loader.bin: arch/x64/boot32.o arch/x64/loader32.ld
	$(call quiet, $(LD) -nostartfiles -static -nodefaultlibs -o $@ \
	                $(filter-out %.bin, $(^:%.ld=-T %.ld)), LD $@)

arch/x64/boot32.o: loader.elf

fs = fs/fs.o fs/bootfs.o bootfs.o

drivers = drivers/vga.o drivers/console.o drivers/isa-serial.o
drivers += $(fs)
drivers += mmu.o
drivers += elf.o
drivers += drivers/device.o drivers/device-factory.o
drivers += drivers/driver.o drivers/driver-factory.o
drivers += drivers/virtio.o

objects = arch/x64/exceptions.o
objects += arch/x64/entry.o
objects += arch/x64/math.o
objects += mutex.o
objects += debug.o
objects += drivers/pci.o
objects += mempool.o
objects += arch/x64/elf-dl.o
objects += linux.o

libc = libc/string/strcmp.o
libc += libc/printf.o
libc += libc/pthread.o
libc += libc/file.o
libc += libc/fd.o
libc += libc/libc.o

libstdc++.a = $(shell $(CXX) -static -print-file-name=libstdc++.a)
libsupc++.a = $(shell $(CXX) -static -print-file-name=libsupc++.a)
libgcc_s.a = $(shell $(CXX) -static -print-libgcc-file-name)

loader.elf: arch/x64/boot.o arch/x64/loader.ld loader.o runtime.o $(drivers) \
        $(objects) dummy-shlib.so \
		$(libc) bootfs.bin
	$(call quiet, $(LD) -o $@ \
		-Bdynamic --export-dynamic \
	    $(filter-out %.bin, $(^:%.ld=-T %.ld)) \
	    $(libstdc++.a) $(libsupc++.a) $(libgcc_s.a) $(src)/libunwind.a, \
		LD $@)

dummy-shlib.so: dummy-shlib.o
	$(call quiet, $(CXX) -nodefaultlibs -shared -o $@ $^, LD $@)

jdk-jni.h := $(shell rpm -ql java-1.7.0-openjdk-devel | grep include/jni.h$$)
jdkbase := $(jdk-jni.h:%/include/jni.h=%)

bootfs.bin: scripts/mkbootfs.py bootfs.manifest
	$(src)/scripts/mkbootfs.py -o $@ -d $@.d -m $(src)/bootfs.manifest \
		-D jdkbase=$(jdkbase)

bootfs.o: bootfs.bin

runtime.o: ctype-data.h

ctype-data.h: gen-ctype-data
	$(call quiet, ./gen-ctype-data > $@, GEN $@)

gen-ctype-data: gen-ctype-data.o
	$(call quiet, $(CXX) -o $@ $^, LD $@)

clean:
	find -name '*.[od]' | xargs rm
	rm -f loader.elf loader.bin

-include $(shell find -name '*.d')
