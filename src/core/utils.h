/******************************************************************************
 * \headerfile src/core/utils.h
 * \brief Headerfile of utility functions for integer array operations
 * \authors A. Serhani, C. Lapeyre, G. Staffelbach
 * \mainpage phydll.readthedocs.io
 * \remark phydll@cerfacs.fr
 * \date Sun, May 09, 2023
 * \copyright CeCILL-B FREE SOFTWARE LICENSE AGREEMENT
 * \copyright COPYRIGHT (C) [2023] [CERFACS]
******************************************************************************/

// Unique/reveres indexes
void utils_unique(int* array, int N, int* unique_indexes, int* unique_inverse);

// Sort array
void utils_sort(int* array, int size);

// Argsort indexes
void utils_argsort(int* array, int size, int* index_array);
