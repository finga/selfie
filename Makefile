# Compiler flags
CFLAGS := -Wall -Wextra -O3 -m64 -D'uint64_t=unsigned long long'

# Bootstrap selfie.c into selfie executable
selfie: selfie.c
	$(CC) $(CFLAGS) $< -o $@

# Compile *.c including selfie.c into RISC-U *.m executable
%.m: %.c selfie
	./selfie -c $< -o $@

# Compile *.c including selfie.c into RISC-U *.s assembly
%.s: %.c selfie
	./selfie -c $< -s $@

# Generate selfie library as selfie.h
selfie.h: selfie.c
	sed 's/main(/selfie_main(/' selfie.c > selfie.h

# Consider these targets as targets, not files
.PHONY: compile quine escape debug replay os vm min mob sat mon smt mod btor2 x86 all assemble spike qemu boolector btormc validator grader grade extras everything clean

# Self-contained fixed-point of self-compilation
compile: selfie
	./selfie -c selfie.c -o selfie1.m -s selfie1.s -m 2 -c selfie.c -o selfie2.m -s selfie2.s
	diff -q selfie1.m selfie2.m
	diff -q selfie1.s selfie2.s

# Compile and run quine and compare its output to itself
quine: selfie selfie.h
	./selfie -c selfie.h examples/quine.c -m 1 | sed '/selfie/d' | diff --strip-trailing-cr examples/quine.c -

# Demonstrate available escape sequences
escape: selfie
	./selfie -c examples/escape.c -m 1

# Run debugger
debug: selfie
	./selfie -c examples/pointer.c -d 1

# Run replay engine
replay: selfie
	./selfie -c examples/division-by-zero.c -r 1

# Run emulator on emulator
os: selfie.m
	./selfie -l selfie.m -m 2 -l selfie.m -m 1

# Self-compile on two virtual machines
vm: selfie.m selfie.s
	./selfie -l selfie.m -m 3 -l selfie.m -y 3 -l selfie.m -y 2 -c selfie.c -o selfie3.m -s selfie3.s
	diff -q selfie.m selfie3.m
	diff -q selfie.s selfie3.s

# Self-compile on two virtual machines on fully mapped virtual memory
min: selfie.m selfie.s
	./selfie -l selfie.m -min 15 -l selfie.m -y 3 -l selfie.m -y 2 -c selfie.c -o selfie4.m -s selfie4.s
	diff -q selfie.m selfie4.m
	diff -q selfie.s selfie4.s

# Run mobster, the emulator without pager
mob: selfie
	./selfie -c -mob 1

# Compile babysat.c with selfie.h as library into babysat executable
babysat: tools/babysat.c selfie.h
	$(CC) $(CFLAGS) --include selfie.h $< -o $@

# Run babysat, the naive SAT solver, natively and as RISC-U executable
sat: babysat selfie selfie.h
	./babysat examples/rivest.cnf
	./selfie -c selfie.h tools/babysat.c -m 1 examples/rivest.cnf

# Compile monster.c with selfie.h as library into monster executable
monster: tools/monster.c selfie.h
	$(CC) $(CFLAGS) --include selfie.h $< -o $@

# Run monster, the symbolic execution engine, natively and as RISC-U executable
mon: monster selfie.h selfie
	./monster
	./selfie -c selfie.h tools/monster.c -m 1

# Prevent make from deleting intermediate target monster
.SECONDARY: monster

# Translate *.c including selfie.c into SMT-LIB model
%-35.smt: %-35.c monster
	./monster -c $< - 0 35 --merge-enabled
%-10.smt: %-10.c monster
	./monster -c $< - 0 10 --merge-enabled

# Gather symbolic execution example files as .smt files
smts-1 := $(patsubst %.c,%.smt,$(wildcard symbolic/*-1-*.c))
smts-2 := $(patsubst %.c,%.smt,$(wildcard symbolic/*-2-*.c))
smts-3 := $(patsubst %.c,%.smt,$(wildcard symbolic/*-3-*.c))

# Run monster on *.c files in symbolic
smt: $(smts-1) $(smts-2) $(smts-3)

# Compile modeler.c with selfie.h as library into modeler executable
modeler: tools/modeler.c selfie.h
	$(CC) $(CFLAGS) --include selfie.h $< -o $@

# Run modeler, the symbolic model generator, natively and as RISC-U executable
mod: modeler selfie.h selfie
	./modeler
	./selfie -c selfie.h tools/modeler.c -m 1

# Prevent make from deleting intermediate target modeler
.SECONDARY: modeler

# Translate *.c including selfie.c into BTOR2 model
%.btor2: %.c modeler
	./modeler -c $< - 0 --check-block-access

# Gather symbolic execution example files as .btor2 files
btor2s := $(patsubst %.c,%.btor2,$(wildcard symbolic/*.c))

# Run modeler on *.c files in symbolic and even on selfie
btor2: $(btor2s) selfie.btor2

# Compile riscv-2-x86.c with selfie.h as library into riscv-2-x86 executable
riscv-2-x86: tools/riscv-2-x86.c selfie.h
	$(CC) $(CFLAGS) --include selfie.h $< -o $@

# Run RISC-V-to-x86 translator natively and as RISC-U executable
# TODO: check self-compilation
x86: riscv-2-x86 selfie.m selfie
	./riscv-2-x86 -c selfie.c
	# ./selfie -c selfie.h tools/riscv-2-x86.c -m 1 -l selfie.m

# Run everything that only requires standard tools
all: compile quine debug replay os vm min mob sat mon smt mod btor2 x86

# Test autograder
grader: selfie
	cd grader && python3 -m unittest discover -v

# Run autograder
grade:
	grader/self.py self-compile

# Assemble RISC-U with GNU toolchain for RISC-V
assemble: selfie.s
	riscv64-linux-gnu-as selfie.s -o a.out
	rm -f a.out

# Run selfie on spike
spike: selfie.m selfie.s
	spike pk selfie.m -c selfie.c -o selfie5.m -s selfie5.s -m 1
	diff -q selfie.m selfie5.m
	diff -q selfie.s selfie5.s

# Run selfie on qemu usermode emulation
qemu: selfie.m selfie.s
	chmod +x selfie.m
	qemu-riscv64-static selfie.m -c selfie.c -o selfie6.m -s selfie6.s -m 1
	diff -q selfie.m selfie6.m
	diff -q selfie.s selfie6.s

# Run boolector SMT solver on SMT-LIB files generated by monster
boolector: smt
	$(foreach file, $(smts-1), [ $$(boolector $(file) -e 0 | grep -c ^sat$$) -eq 1 ];)
	$(foreach file, $(smts-2), [ $$(boolector $(file) -e 0 | grep -c ^sat$$) -eq 2 ];)
	$(foreach file, $(smts-3), [ $$(boolector $(file) -e 0 | grep -c ^sat$$) -eq 3 ];)

# Run btormc bounded model checker on BTOR2 files generated by modeler
btormc: btor2
	$(foreach file, $(btor2s), btormc $(file);)

# Run validator on *.c files in symbolic
validator: selfie modeler
	$(foreach file, $(wildcard symbolic/*.c), tools/validator.py $(file);)

# Run everything that requires non-standard tools
extras: assemble spike qemu boolector btormc validator grader grade

# Run everything
everything: all extras

# Clean up
clean:
	rm -f *.m
	rm -f *.s
	rm -f *.smt
	rm -f *.btor2
	rm -f *.x86
	rm -f selfie selfie.h selfie.exe
	rm -f babysat monster modeler riscv-2-x86
	rm -f examples/*.m
	rm -f examples/*.s
	rm -f symbolic/*.smt
	rm -f symbolic/*.btor2