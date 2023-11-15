CC := $(CC)
CFLAGS := -g -O2 -Wall -Wextra -std=c99

FC := $(FC)
FFLAGS := -g -O2 -cpp -Wall -Wextra -ffree-line-length-none
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

PYDIR := $(PHYDLL_REPO)/src/python/pyphydll

BUILD := $(PHYDLL_REPO)/build
BUILD_DIR = $(shell realpath $(BUILD))
LIB = $(BUILD_DIR)/lib
INC = $(BUILD_DIR)/include

TESTDIR = $(PHYDLL_REPO)/test/t0_nc

ENABLE_FORTRAN = "OFF"
ENABLE_PYTHON = "OFF"

TEST_VERBOSE := "OFF"

all: info compile fcompile pysetup
install: crun frun pyrun
phydll: all install

ctest: info clean compile crun
ftest: info clean compile fcompile crun frun
pytest: info clean compile fcompile pysetup pyrun


info:
	@echo "-------------------------------------------------"
	@echo "Welcome to PhyDLL <Physics Deep Learning coupLer>"
	@echo "phydll@cerfacs.fr                      CERFACS(C)"
	@echo -e "-------------------------------------------------\n"

	@echo -e "(PhyDLL)... -----> INSTALLATION INFORMATION --------------------------\n"
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
		echo -e "          PhyDLL's Python package: $(BUILD_DIR)/src/python/pyphydll"; \
	fi
	@echo -e "\n------------------------------------------------------------ ...done\n\n"

compile: $(SRCFILES)
	@echo -e "(PhyDLL)... -----> C COMPILING ---------------------------------------\n"
	mkdir -p $(LIB) $(INC)
	$(CC) $(CFLAGS) -fPIC -shared -I$(SRCDIR) $(SRCFILES) -o $(LIB)/libphydll.so
	cp $(SRCDIR)/phydll.h $(INC)
	@echo -e "\n------------------------------------------------------------ ...done\n\n"


fcompile: $(FSRCFILES) $(LIB)/libphydll.so
	@if [[ $(ENABLE_FORTRAN) == "ON" ]]; then \
		echo -e "(PhyDLL)... -----> Fortran COMPILING ---------------------------------\n"; \
		set -x; \
		$(FC) $(FFLAGS) -fPIC -shared $(FSRCFILES) -o $(LIB)/libphydll_f.so -L$(LIB) -lphydll -Wl,-rpath=$(LIB); \
		mv *.mod $(INC); \
		set +x; \
		echo -e "\n------------------------------------------------------------ ...done\n\n"; \
	fi \

pysetup: $(LIB)/libphydll.so $(PYDIR)/cyphydll.pyx
	@if [[ $(ENABLE_PYTHON) == "ON" ]]; then \
		echo -e "(PhyDLL)... -----> Python SETUP --------------------------------------\n"; \
		set -x; \
		cd $(PYDIR) && PHYDLL_CYTHON_SOURCES=$(PYDIR)/cyphydll.pyx PHYDLL_INCLUDE_DIR=$(SRCDIR) PHYDLL_LIBRARIES_DIR=$(LIB) python $(PYDIR)/setup.py build_ext --build-temp=$(PYDIR) --build-lib=$(PYDIR); \
		cp $(realpath ./setup.cfg) $(realpath ./setup.py) $(BUILD_DIR); \
		rm -rf $(BUILD_DIR)/src/python; \
		mkdir -p $(BUILD_DIR)/src/python; \
		cp -r $(realpath ./src/python/pyphydll) $(BUILD_DIR)/src/python/; \
		cd $(BUILD_DIR) && pip install .; \
		set +x; \
		echo -e "\n------------------------------------------------------------ ...done\n\n"; \
	fi \

clean:
	@echo -e "(PhyDLL)... -----> CLEANING ------------------------------------------\n"
	rm -f log.*
	rm -f phydll-*.log
	rm -rf $(BUILD_DIR)/* $(TESTDIR)/*.exe $(PYDIR)/build/
	rm -rf $(PYDIR)/__pycache__ $(PYDIR)/cyphydll.c $(PYDIR)/cyphydll.cpython*.so
	rm -rf $(PYDIR)/../pyphydll.egg-info/
	@echo -e "\n------------------------------------------------------------ ...done\n\n"

crun: $(TESTDIR)/phy_main.c $(TESTDIR)/dl_main.c $(LIB)/libphydll.so
	@cp -vr $(TESTDIR) $(BUILD_DIR)
	@echo -e "\n(PhyDLL)... -----> C/C TESTS -----------------------------------------\n"
	@if [[ $(TEST_VERBOSE) == "ON" ]]; then \
		set -x; \
		$(CC) $(CFLAGS) $(TESTDIR)/phy_main.c -o $(TESTDIR)/phy.exe -I$(INC) -L$(LIB) -lphydll -Wl,-rpath=$(LIB); \
		$(CC) $(CFLAGS) $(TESTDIR)/dl_main.c -o $(TESTDIR)/dl.exe -I$(INC) -L$(LIB) -lphydll -Wl,-rpath=$(LIB); \
		cd $(TESTDIR); \
		mpirun -n 7 $(TESTDIR)/phy.exe : -n 2 $(TESTDIR)/dl.exe; \
		set +x; \
	elif [[ $(TEST_VERBOSE) == "OFF" ]]; then \
		cd $(TESTDIR); \
		echo -e "\tCompiling/linking C test physical solver..."; \
		$(CC) $(CFLAGS) $(TESTDIR)/phy_main.c -o $(TESTDIR)/phy.exe -I$(INC) -L$(LIB) -lphydll -Wl,-rpath=$(LIB); \
		if [[ $$? -eq 0 ]]; then \
        	echo -e "\t\tSucceeded\n\t...done\n"; \
    	else \
        	echo -e "\t\tFailed"; \
			exit 1; \
    	fi; \
		echo -e "\tCompiling/linking C test DL engine..."; \
		$(CC) $(CFLAGS) $(TESTDIR)/dl_main.c -o $(TESTDIR)/dl.exe -I$(INC) -L$(LIB) -lphydll -Wl,-rpath=$(LIB); \
		if [[ $$? -eq 0 ]]; then \
        	echo -e "\t\tSucceeded\n \t...done\n"; \
    	else \
        	echo -e "\t\tFailed"; \
			exit 1; \
    	fi; \
		echo -e "\tRunning..."; \
		mpirun -n 7 $(TESTDIR)/phy.exe : -n 2 $(TESTDIR)/dl.exe &> /dev/null; \
		if [[ $$? -eq 0 ]]; then \
        	echo -e "\t\tSucceeded\n \t...done"; \
    	else \
        	echo -e "\t\tFailed"; \
			exit 1; \
    	fi; \
	fi \

	@echo -e "\n------------------------------------------------------------ ...done\n\n"

frun:
	@if [[ $(ENABLE_FORTRAN) == "ON" ]]; then \
		echo -e "(PhyDLL)... -----> Fortran/C TESTS -----------------------------------\n"; \
		if [[ $(TEST_VERBOSE) == "ON" ]]; then \
			set -x; \
			$(FC) $(FFLAGS) $(TESTDIR)/phy_main.f90 -o $(TESTDIR)/phy_f.exe -I$(INC) -L$(LIB) -lphydll -lphydll_f -Wl,-rpath=$(LIB); \
			mpirun -n 7 $(TESTDIR)/phy_f.exe : -n 2 $(TESTDIR)/dl.exe; \
			set +x; \
		elif [[ $(TEST_VERBOSE) == "OFF" ]]; then \
			cd $(TESTDIR); \
			echo -e "\tCompiling/linking Fortran test physical solver..."; \
			$(FC) $(FFLAGS) $(TESTDIR)/phy_main.f90 -o $(TESTDIR)/phy_f.exe -I$(INC) -L$(LIB) -lphydll -lphydll_f -Wl,-rpath=$(LIB); \
			if [[ $$? -eq 0 ]]; then \
				echo -e "\t\tSucceeded\n\t...done\n"; \
			else \
				echo -e "\t\tFailed"; \
				exit 1; \
			fi; \
			echo -e "\tRunning..."; \
			mpirun -n 7 $(TESTDIR)/phy_f.exe : -n 2 $(TESTDIR)/dl.exe &> /dev/null; \
			if [[ $$? -eq 0 ]]; then \
				echo -e "\t\tSucceeded\n \t...done"; \
			else \
				echo -e "\t\tFailed"; \
				exit 1; \
			fi; \
		fi; \
		echo -e "\n------------------------------------------------------------ ...done\n\n"; \
	fi \

pyrun:
	@if [[ $(ENABLE_PYTHON) == "ON" ]]; then \
		echo -e "(PhyDLL)... -----> Python/Python TESTS --------------\n"; \
		if [[ $(TEST_VERBOSE) == "ON" ]]; then \
			set -x; \
			cd $(TESTDIR); \
			mpirun -n 7 python $(TESTDIR)/phy_main.py : -n 2 python $(TESTDIR)/dl_main.py; \
			set +x; \
		elif [[ $(TEST_VERBOSE) == "OFF" ]]; then \
			cd $(TESTDIR); \
			echo -e "\tRunning Python/Python coupling..."; \
			mpirun -n 7 python $(TESTDIR)/phy_main.py : -n 2 python $(TESTDIR)/dl_main.py &> /dev/null; \
			if [[ $$? -eq 0 ]]; then \
				echo -e "\t\tSucceeded\n \t...done"; \
			else \
				echo -e "\t\tFailed"; \
				exit 1; \
			fi; \
		fi; \
		echo -e "\n------------------------------------------------------------ ...done\n\n"; \
	fi \
