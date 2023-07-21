# DEFAULT COMPILER
FC := mpifort

# FORTRAN FLAGS (INTEL, GNU)
ifeq ("$(FC)", "mpiifort")
FLAGS := -O2 -g -fpp -warn all -traceback
ifdef PHYDLL_DEBUG
FLAGS += -check all
endif
else
FLAGS := -O2 -g -cpp -Wall -Wextra -fbacktrace -ffree-line-length-none
ifdef PHYDLL_DEBUG
FLAGS += -fcheck=all
endif
endif

# ENABLE PYTHON
ENABLE_PYTHON := "OFF"

# DEFAULT SRC
SRC := ./src/fortran
SRCFILES := $(addprefix $(SRC)/, mod_params.f90 mod_env.f90 mod_cpl.f90 mod_mesh.f90 mod_io.f90 mod_phydll.f90 phydll.f90)

# DEFAULT BUILD DIRECTORY
BUILD := ./build
LIB := $(BUILD)/lib
INC := $(BUILD)/include


# CWIPI SUPPORT
ifdef CWIPI_DIR
	FLAGS += -DCWIPI
	FLAGS += -I$(CWIPI_DIR)/include -L$(CWIPI_DIR)/lib -Wl,-rpath=$(CWIPI_DIR)/lib -lcwp -lcwpf
endif

# HDF5 SUPPORT
ifdef HDF5_DIR
	FLAGS += -DHDF5
	FLAGS += -I${HDF5_DIR}/include -L${HDF5_DIR}/lib -lhdf5_fortran -lhdf5 -lhdf5_hl -lhdf5hl_fortran
endif

all: echo0 clean compile install pyinstall echo1

echo0:
	@echo "-------------------------------------------------"
	@echo "Welcome to PhyDLL <Physics Deep Learning coupLer>"
	@echo "phydll@cerfacs.fr                      CERFACS(C)"
	@echo -e "-------------------------------------------------\n"
	@echo -e "(PhyDLL) -----> INSTALL ...\n"
	@echo "          Build directory: $(realpath $(BUILD))"
	@echo -e "          Sources directory: $(realpath $(SRC))\n"
	@if [[ -z "${CWIPI_DIR}" ]]; then\
		echo -e "          CWIPI support: False\n";\
	else\
		echo "          CWIPI support: True";\
		echo -e "          CWIPI directory: ${CWIPI_DIR}\n";\
	fi
	@if [[ -z "${HDF5_DIR}" ]]; then\
		echo -e "          HDF5 support: False\n";\
	else\
		echo "          HDF5 support: True";\
		echo -e "          HDF5 directory: ${HDF5_DIR}\n";\
	fi
	@echo "          Fortran compiler: $(FC) ($(shell which $(FC)))"
	@echo -e "          Fortran flags: $(FLAGS)\n"
	@echo "          Compiling ..."

compile: $(SRCFILES)
	@mkdir -p $(LIB) $(INC)
	$(FC) $(FLAGS) -fpic -shared $(SRCFILES) -o $(LIB)/libphydll.so -I$(INC)
	@mv *.mod $(INC)
	@echo -e "\n          PhyDLL Library path: $(shell realpath $(LIB))"
	@echo -e "          PhyDLL Include path: $(shell realpath $(INC))"

pyinstall:
	@if [[ $(ENABLE_PYTHON) == "ON" ]]; then\
		echo -e "\n          Install Python API of PhyDLL ...";\
		cp ./setup.cfg ./setup.py $(BUILD);\
		rm -rf $(BUILD)/src/python;\
		mkdir -p $(BUILD)/src/python;\
		cp -r ./src/python/phydll $(BUILD)/src/python/;\
		cd $(BUILD);\
		pip install -e .;\
		cd -;\
	fi

echo1:
	@echo -e "\n(PhyDLL) -----> DONE \n"

install: 
	@mkdir -p $(BUILD)/src/python/phydll/
	@cp -r ./src/python/phydll/* $(BUILD)/src/python/phydll/;
	@mkdir -p $(BUILD)/src
	@cp -r ./src/fortran $(BUILD)/src
	@cp -r ./scripts $(BUILD)
	@echo -e "\n          PhyDLL additional scripts: $(BUILD)/scripts"
	@mkdir -p $(BUILD)/test/utsim
	@cp -r ./test/ds_nc $(BUILD)/test
	@echo -e "          PhyDLL test directory: $(BUILD)/test"

clean:
	@rm -rf $(BUILD)
	@rm -f $(SRC)/*.mod
	@rm -f ./*.o
	@mkdir -p $(BUILD)
