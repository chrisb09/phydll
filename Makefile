SHELL := /bin/bash
CC := $(CC)
CFLAGS := -g -O2 -Wall -Wextra -std=c99

FC := $(FC)
FFLAGS := -g -O2 -cpp -Wall -Wextra -ffree-line-length-none -fcheck=all
ifeq ("$(FC)", "mpiifort")
FFLAGS := -g -O2 -fpp -warn all -traceback
endif

ifdef HDF5_DIR
	CFLAGS += -DHDF5
	CFLAGS += -I${HDF5_DIR}/include -L${HDF5_DIR}/lib -lhdf5 -lhdf5_hl
	FFLAGS += -I${HDF5_DIR}/include -L${HDF5_DIR}/lib -lhdf5 -lhdf5_hl -lhdf5_fortran -lhdf5hl_fortran
endif

PHYDLL_REPO := $(realpath .)

SRCDIR := $(PHYDLL_REPO)/src/core
SRCFILES := $(addprefix $(SRCDIR)/, phydll.c kernel.c kernel_structs.c io.c utils.c)

FSRCDIR := $(PHYDLL_REPO)/src/fortran
FSRCFILES := $(addprefix $(FSRCDIR)/, phydll_cf.f90 phydll_f.f90)

BUILD := $(PHYDLL_REPO)/build
BUILD_DIR = $(shell realpath $(BUILD))
LIB = $(BUILD_DIR)/lib
INC = $(BUILD_DIR)/include

PYDIR := $(PHYDLL_REPO)/src/python/pyphydll
PYPACK := $(BUILD_DIR)/src/python/pyphydll

TESTDIR = $(PHYDLL_REPO)/test/t0_nc

ENABLE_FORTRAN = "OFF"
ENABLE_PYTHON = "OFF"

all: info compile fcompile pysetup
install: crun frun pyrun
phydll: all install

ctest: info clean compile crun
ftest: info clean compile fcompile frun
pytest: info clean compile fcompile pysetup pyrun

info:
	@echo "-------------------------------------------------"
	@echo "Welcome to PhyDLL <Physics Deep Learning coupLer>"
	@echo "phydll@cerfacs.fr                      CERFACS(C)"
	@echo -e "-------------------------------------------------\n"

	@echo -e "\n(PhyDLL)... -----> INSTALLATION INFORMATION --------------------------\n"
	@echo "          Build directory: $(BUILD_DIR)"
	@echo -e "          Sources directory: $(SRCDIR))\n"
	@echo -e "          Enable Fortran API: $(ENABLE_FORTRAN)"
	@echo -e "          Enable Python API: $(ENABLE_PYTHON)\n"
	@if [[ -z "${HDF5_DIR}" ]]; then \
		echo -e "          HDF5 support: False\n"; \
	else \
		echo "          HDF5 support: True"; \
		echo -e "          HDF5 directory: ${HDF5_DIR}\n"; \
	fi
	@echo "          C compiler: $(CC) ($(shell which $(CC)))"
	@if [[ $(ENABLE_FORTRAN) == "ON" ]]; then \
		echo -e "          Fortran compiler: $(FC) ($(shell which $(FC)))\n"; \
	fi
	@if [[ $(ENABLE_PYTHON) == "ON" ]]; then \
		echo -e "          Python interpreter: $(shell python --version) ($(shell which python))\n"; \
	fi
	@echo -e "          PhyDLL's Library path: $(LIB)"
	@echo -e "          PhyDLL's Include path: $(INC)"
	@if [[ $(ENABLE_PYTHON) == "ON" ]]; then \
		echo -e "          PhyDLL's Python package: $(PYPACK)"; \
	fi
	@echo -e "\n-------------------------------------------------------------- ...done\n"

compile: $(SRCFILES)
	@echo -e "\n(PhyDLL)... -----> C COMPILING ---------------------------------------\n"
	mkdir -p $(LIB) $(INC)
	$(CC) $(CFLAGS) -fPIC -shared -I$(SRCDIR) $(SRCFILES) -o $(LIB)/libphydll.so || exit 1
	cp $(SRCDIR)/phydll.h $(INC)
	@echo -e "\n-------------------------------------------------------------- ...done\n"

fcompile: $(FSRCFILES) $(LIB)/libphydll.so
	@if [[ $(ENABLE_FORTRAN) == "ON" ]]; then \
		echo -e "\n(PhyDLL)... -----> Fortran COMPILING ---------------------------------\n"; \
		set -x; \
		$(FC) $(FFLAGS) -fPIC -shared $(FSRCFILES) -o $(LIB)/libphydll_f.so -L$(LIB) -lphydll -Wl,-rpath=$(LIB) || exit 1; \
		mv *.mod $(INC); \
		set +x; \
		echo -e "\n-------------------------------------------------------------- ...done\n"; \
	fi \

pysetup: $(LIB)/libphydll.so $(PYDIR)/cyphydll.pyx
	@if [[ $(ENABLE_PYTHON) == "ON" ]]; then \
		echo -e "\n(PhyDLL)... -----> Python SETUP --------------------------------------\n"; \
		set -x; \
		cd $(PYDIR) && PHYDLL_CYTHON_SOURCES=$(PYDIR)/cyphydll.pyx PHYDLL_INCLUDE_DIR=$(SRCDIR) PHYDLL_LIBRARIES_DIR=$(LIB) python $(PYDIR)/setup.py build_ext --build-temp=$(PYDIR) --build-lib=$(PYDIR) || exit 1; \
		cp $(realpath ./setup.cfg) $(realpath ./setup.py) $(BUILD_DIR); \
		mkdir -p $(PYPACK); \
		rm -rf $(PYPACK)/*; \
		cp -r $(PYDIR)/* $(PYPACK); \
		cd $(BUILD_DIR) && pip install -e .; \
		set +x; \
		echo -e "\n-------------------------------------------------------------- ...done\n"; \
	fi \

clean:
	@echo -e "\n(PhyDLL)... -----> CLEANING ------------------------------------------\n"
	rm -f log.*
	rm -f phydll-*.log
	rm -rf $(BUILD_DIR)/* $(TESTDIR)/*.exe $(PYDIR)/build/
	rm -rf $(PYDIR)/__pycache__ $(PYDIR)/cyphydll.c $(PYDIR)/cyphydll.cpython*.so
	rm -rf $(PYDIR)/../pyphydll.egg-info/
	@echo -e "\n-------------------------------------------------------------- ...done\n"

crun: $(TESTDIR)/phy_main.c $(TESTDIR)/dl_main.c $(INC)/phydll.h $(LIB)/libphydll.so
	@cp -r $(TESTDIR) $(BUILD_DIR)
	@echo -e "\n(PhyDLL)... -----> C/C TESTS -----------------------------------------\n"
	@$(TESTDIR)/create_c_exec.sh $(CC) "$(CFLAGS)" $(INC) $(LIB) || exit 1
	@$(TESTDIR)/run_c-c.sh || exit 1
	@echo -e "-------------------------------------------------------------- ...done\n"

frun: $(TESTDIR)/phy_main.f90 $(TESTDIR)/dl_main.c $(INC)/phydll.h $(INC)/phydll_cf.mod $(INC)/phydll_f.mod $(LIB)/libphydll.so $(LIB)/libphydll_f.so
	@if [[ $(ENABLE_FORTRAN) == "ON" ]]; then \
		echo -e "\n(PhyDLL)... -----> Fortran/C TESTS -----------------------------------\n"; \
		$(TESTDIR)/create_c_exec.sh $(CC) "$(CFLAGS)" $(INC) $(LIB) "NOPHY" || exit 1; \
		$(TESTDIR)/create_f_exec.sh $(FC) "$(FFLAGS)" $(INC) $(LIB) || exit 1; \
		$(TESTDIR)/run_f-c.sh; \
		echo -e "-------------------------------------------------------------- ...done\n"; \
	fi \

pyrun: $(PYPACK)/pyphydll.py $(PYPACK)/cyphydll.c
	@if [[ $(ENABLE_PYTHON) == "ON" ]]; then \
		echo -e "\n(PhyDLL)... -----> Python/Python TESTS -------------------------------\n"; \
		$(TESTDIR)/run_py-py.sh || exit 1; \
		echo -e "-------------------------------------------------------------- ...done\n"; \
	fi \
