FLAGS := -O2 -g3 -cpp -Wall -Wextra -fbacktrace -ffree-line-length-none

all: clean cplk

clean:
	rm -f ./main.exe

cplk: main.f90
	mpifort $(FLAGS) -o ./main.exe main.f90 -I$(PHYDLL_DIR)/include -L$(PHYDLL_DIR)/lib -Wl,-rpath=$(PHYDLL_DIR)/lib -lphydll
