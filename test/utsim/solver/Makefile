FC := mpiifort 
FLAGS := -g -fpp -warn all -traceback -check all

ifeq ("$(FC)", "mpifort")
FLAGS = -cpp -Wall -Wextra -fbacktrace -ffree-line-length-none -fcheck=all
endif

SRCFILE := ./mod_solver.f90
EXECBIN := ./solver.exe

BUILD := $(PWD)/build

all: clean compile link

clean:
	@echo -e "\t CLEAN ..."
	rm -f $(BUILD)/* *.mod $(EXECBIN)
	mkdir -p $(BUILD)
	mkdir -p ../run/HASH_TABLES
	mkdir -p ../run/OUTPUTED_MESH_PARTITIONS
	@echo -e "\t ... DONE\n"

compile: $(SRCFILE)
	@echo -e "\t COMPILE SOURCES ..."
	$(FC) $(FLAGS) -fpic -shared $(SRCFILE) -o $(BUILD)/libsolver.so -I$(BUILD) -lm -I${HDF5_DIR}/include -L${HDF5_DIR}/lib -lhdf5_fortran -lhdf5 -lhdf5_hl -lhdf5hl_fortran -lm
	mv mod_solver.mod $(BUILD)
	@echo -e "\t ... DONE\n"

link: $(BUILD)/libsolver.so
	@echo -e "\t CREATE EXECUTABLE ..."
	$(FC) $(FLAGS) -o $(EXECBIN) main_solver.f90 -I$(BUILD) -I${HDF5_DIR}/include -L$(BUILD) -lsolver -Wl,-rpath=$(BUILD) -DPHYDLL -I$(PHYDLL_DIR)/include -L$(PHYDLL_DIR)/lib -Wl,-rpath=$(PHYDLL_DIR)/lib -lphydll
	@echo -e "\t ... DONE\n"
