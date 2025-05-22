"""
@file src/python/pyphydll.py
@brief PhyDLL's python interface
@authors A. Serhani, C. Lapeyre, G. Staffelbach
@mainpage phydll.readthedocs.io
@email phydll@cerfacs.fr
@date Tue, May 02, 2023
@copyright CeCILL-B FREE SOFTWARE LICENSE AGREEMENT
@copyright COPYRIGHT (C) [2023] [CERFACS]
"""
import numpy as np
from typing import Tuple
from pyphydll.cyphydll import pyphydll_get_distribution_info, pyphydll_init, pyphydll_finalize, pyphydll_define_phy, pyphydll_define_dl, \
    pyphydll_define_phy_with_mesh, pyphydll_recv, pyphydll_irecv, pyphydll_wait_irecv, pyphydll_send, \
    pyphydll_isend, pyphydll_wait_isend, pyphydll_get_field, pyphydll_set_field, pyphydll_get_field_size, \
    pyphydll_get_field_counts, pyphydll_is_phy_signal, pyphydll_is_phy_instance, pyphydll_is_dl_instance, \
    pyphydll_get_local_mpi_comm, pyphydll_opt_set_freq, pyphydll_opt_set_output_freq, pyphydll_opt_enable_cpl_loop
from pyphydll.cyphydll import pyIINIT as IINIT, pyCINIT as CINIT
from mpi4py.MPI import Comm


class PhyDLL:
    """
    PhyDLL's python interface class

    Attributes:
        instance        (str)   Instance name
        size            (int)   Instance field size
        count           (int)   Instance fields count
        phy_count       (int)   Physical fields count
        dl_count        (int)   DL fields count
        is_phy_instance (bool)  Check if current instance is physical one
        is_dl_instance  (bool)  Check if current instance is dl one
    """
    def __init__(self):
        self.instance = CINIT
        self.size = IINIT
        self.count = IINIT
        self.phy_count = IINIT
        self.dl_count = IINIT

        self.is_phy_instance = False
        self.is_dl_instance = False


    def init(self, instance: str) -> None:
        """
        Initialize PhyDLL's coupling instance

        Args:
            instance    (str)   Instance name ('physical', 'phy', 'deeplearning', 'dl', ...)

        Returns:
            None
        """
        self.instance = instance
        pyphydll_init(self.instance)

        self.is_phy_instance = pyphydll_is_phy_instance()
        self.is_dl_instance = pyphydll_is_dl_instance()


    @staticmethod
    def finalize() -> None:
        """
        Finalize PhyDLL's coupling instance
        """
        pyphydll_finalize()


    @staticmethod
    def get_local_mpi_comm() -> Comm:
        """
        Get local mpi communicator

        Returns:
            Comm    (mpi4py.Comm) Local mpi communicator
        """
        return pyphydll_get_local_mpi_comm()


    def define_phy(self, count: int, size: int) -> None:
        """
        Define physical solver instance (non-context aware coupling)

        Args:
            count   (int)   Physical fields count
            size    (int)   Physical field size/length

        Returns:
            None
        """
        self.size = size
        self.count = count
        pyphydll_define_phy(self.count, self.size)
        self.size = pyphydll_get_field_size()
        self.phy_count, self.dl_count = pyphydll_get_field_counts()


    def define_phy_with_mesh(
        self,
        count: int,
        geodim: int,
        ncell: int,
        nnode: int,
        ntcell: int,
        ntnode: int,
        nvert: int,
        connec: np.ndarray,
        coords: np.ndarray,
        local_cell_to_global: np.ndarray,
        local_node_to_global: np.ndarray
        ) -> None:
        """
        Define physical solver instance with mesh support (DirectScheme coupling)

        Args:
            count               (int) Number of Physical fields to send
            geodim              (int) Geometric dimension
            ncell               (int) Number of local mesh cells
            nnode               (int) Number of local mesh nodes
            ntcell              (int) Number of global (full) mesh cells
            ntnode              (int) Number of global (full) mesh nodes (without duplication)
            nvert               (int) Number of nodes per element (eg. quad=4, tetra=4, hexa=8, prism=6, ...)
            connec              (np.ndarray) Local connectivity table (element to node), len=nvert*ncell
            coords              (np.ndarray) Local coordinates table, len=geodim*nnode
            local_cell_to_global(np.ndarray) Table of local to global cell numerotation, len=ncell
            local_node_to_global(np.ndarray) Table of local to global node numerotation, len=nnode

        Returns
            None
        """
        pyphydll_define_phy_with_mesh(
            count, geodim, ncell, nnode, ntcell, ntnode, nvert,
            connec.astype(np.intc),
            coords,
            local_cell_to_global.astype(np.intc),
            local_node_to_global.astype(np.intc)
        )
        self.phy_count, self.dl_count = pyphydll_get_field_counts()


    def define_dl(self, count: int) -> None:
        """
        Define DL instance

        Args:
            count   (int) DL fields count

        Returns:
            None
        """
        self.count = count
        pyphydll_define_dl(self.count)
        self.size = pyphydll_get_field_size()
        self.phy_count, self.dl_count = pyphydll_get_field_counts()


    def _with_arg_fields_dic(self, fields: dict = {}) -> None:
        """
        Set fields (to send) as dictionary

        Args: (opt)
            fields  (dict)  Fields to set (to send).

        Returns:
            None

        Notes:
            fields are like = {"label_0": array_0, "label_1", array_1}
        """
        if bool(fields):
            for label in fields.keys():
                self.set_field(fields[label], label)


    def send(self, fields: dict = {}) -> None:
        """
        Send fields from PhyDLL's buffer

        Args: (opt)
            fields  (dict) Fields to send

        Returns:
            None

        Notes:
            fields argument is optional
            If fields is not given as an argument, fields should be set before by the function set_fields()
        """
        self._with_arg_fields_dic(fields)
        pyphydll_send()


    def isend(self, fields: dict = {}) -> None:
        """
        Non-blocking send fields from PhyDLL's buffer

        Args: (opt)
            fields  (dict) Fields to send

        Returns:
            None

        Notes:
            fields argument is optional
            If fields is not given as an argument, fields should be set before by the function set_fields()
            Call the function wait_isend()
        """
        self._with_arg_fields_dic(fields)
        pyphydll_isend()


    @staticmethod
    def wait_isend() -> None:
        """
        Wait for non-blocking send

        Returns:
            None
        """
        pyphydll_wait_isend()


    def _with_return_fields_dic(self) -> dict:
        """
        Get received fields as dictionary

        Returns:
            fields  (dict) Dictionary of received fields
        """
        fields = {}

        if self.is_phy_instance:
            count = self.dl_count
        elif self.is_dl_instance:
            count = self.phy_count

        for i in range(count):
            field, label = self.get_field()
            fields[label] = field

        return fields


    def recv(self, only: bool = False) -> dict:
        """
        Receive fields and return the fields as dictionary if only=False

        Args: (opt)
            only    (bool) If True, it only receives fields without returning it. Default value is False

        Returns:
            fields  (dict) Received fields as dictonary (if only=False)

        Notes:
            fields are like = {"label_0": array_0, "label_1", array_1}
        """
        pyphydll_recv()
        if not only:
            return self._with_return_fields_dic()


    def irecv(self) -> None:
        """
        Non-blocking receive

        Returns:
            None
        """
        pyphydll_irecv()


    def wait_irecv(self, only: bool = False):
        """
        Waiting barrier for the non-blockking receive fields.
        It returns the fields as dictionary if only=False

        Args: (opt)
            only    (bool) If True, it only receives fields without returning it. Default value is False

        Returns:
            fields  (dict) Received fields as dictonary (if only=False)

        Notes:
            fields are like = {"label_0": array_0, "label_1", array_1}
        """
        pyphydll_wait_irecv()
        if not only:
            return self._with_return_fields_dic()


    @staticmethod
    def set_field(field: np.ndarray, label: str) -> None:
        """
        Set fields to send. Copy the field into PhyDLL's buffer

        Args:
            field   (np.ndarray)    Field array
            label   (str)           Field label

        Returns:
            None
        """
        pyphydll_set_field(field, label)


    @staticmethod
    def get_field() -> Tuple[np.ndarray, str]:
        """
        Get received field. Copy from PhyDLL's buffer

        Returns
            field   (np.ndarray)    Field array
            label   (str)           Field label
        """
        field, label = pyphydll_get_field()
        return field, label


    def get_field_size(self) -> int:
        """
        Get field size (esp. physical fields)

        Returns:
            size    (int) Field size
        """
        return self.size


    def get_field_counts(self) -> Tuple[int, int]:
        """
        Get physical/dl fields counts

        Returns:
            phy_count   (int) Physical fields count
            dl_count    (int) DL fields count
        """
        return self.phy_count, self.dl_count


    @staticmethod
    def get_distribution_info() -> dict:
        """
        Get communication distribution info as dictionary

        Returns:
            distribution info  (dict) Information about communication distribution as dict

        Notes:
            distribution info is like = {"dist_rank": int, "dist_size": int, "ndest": int, "dest": list(int)}
        """
        return pyphydll_get_distribution_info()


    @staticmethod
    def is_phy_signal() -> bool:
        """
        Check if physical solver is communicating

        Returns:
            status  (bool) Status
        """
        return pyphydll_is_phy_signal()


    @staticmethod
    def opt_enable_cpl_loop() -> None:
        """
        Optionally enable coupling in loop mode

        Returns:
            None
        """
        pyphydll_opt_enable_cpl_loop()


    @staticmethod
    def opt_set_freq(freq: int) -> None:
        """
        Optionally set coupling frequency

        Args:
            freq    (int) Coupling frequency

        Returns:
            None
        """
        pyphydll_opt_set_freq(freq)


    @staticmethod
    def opt_set_output_freq(output_freq: int) -> None:
        """
        Optionally set output frequency

        Args:
            output_freq (int) Output frequency

        Returns:
            None
        """
        pyphydll_opt_set_output_freq(output_freq)
