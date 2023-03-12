
all: compile link

full: compile link run

# compile:
# 	mpicc main.c -I${PARMETIS_DIR}/include -L${PARMETIS_DIR}/lib -lparmetis -lmetis -I${HDF5_DIR}/include -L${HDF5_DIR}/lib -lhdf5 -lhdf5_hl -lm

# run: ./a.out
# 	mpirun -n 4 ./a.out

# compile:
# 	mpifort main.f90 -Wall -I${PARMETIS_DIR}/include -L${PARMETIS_DIR}/lib -lparmetis -lmetis -I${HDF5_DIR}/include -L${HDF5_DIR}/lib -lhdf5_fortran -lhdf5_hl_fortran -lm

# run: ./a.out
# 	mpirun --tag-output -n 4 ./a.out
# #
FLAGS := -O2 -g3 -cpp -Wall -Wextra -fbacktrace -ffree-line-length-none

BUILD := $(shell realpath ./build)

clean:
	rm $(BUILD)/*

compile: mod_solver.f90
	mpifort $(FLAGS) -fpic -shared mod_solver.f90 -o $(BUILD)/libtest.so -I$(BUILD) -lm -I${HDF5_DIR}/include -L${HDF5_DIR}/lib -lhdf5_fortran -lhdf5_hl_fortran -lm
	mv mod_solver.mod $(BUILD)

link: $(BUILD)/libtest.so
	mpifort $(FLAGS) -o ./solver.exe main_solver.f90 -I$(BUILD) -L$(BUILD) -ltest -Wl,-rpath=$(BUILD) -DPHYDLL -I$(PHYDLL_DIR)/include -L$(PHYDLL_DIR)/lib -Wl,-rpath=$(PHYDLL_DIR)/lib -lphydll

run: ./solver.exe
	mpirun -np 4 ./solver.exe
