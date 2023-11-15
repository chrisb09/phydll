/******************************************************************************
 * \file src/core/utils.c
 * \brief Utility functions for integer array operations
 * \authors A. Serhani, C. Lapeyre, G. Staffelbach
 * \mainpage phydll.readthedocs.io
 * \remark phydll@cerfacs.fr
 * \date Sun, May 09, 2023
 * \copyright CeCILL-B FREE SOFTWARE LICENSE AGREEMENT
 * \copyright COPYRIGHT (C) [2023] [CERFACS]
******************************************************************************/
#include <stdbool.h>
#include <stdlib.h>

#include "params.h"


/******************************************************************************
 * \brief Find unique element of an array of integers
 * \param int* Integer array
 * \param int Size of array
 * \param int* Sorted unique indexes
 * \param int* Indexes to reconstruct the original array
******************************************************************************/
void utils_unique(int* array, int size, int* unique_indexes, int* unique_inverse) {
    int cnt = 0;
    bool is_unique;
    int* unique = malloc(size * sizeof(int));

    // Find unique elements and their indexes
    for (int i = 0; i < size; i++) {
        is_unique = true;

        for (int j = 0; j < cnt; j++) {
            if (array[i] == unique[j]) {
                is_unique = false;
                unique_inverse[i] = j;
                break;
            }
        }

        if (is_unique) {
            unique[cnt] = array[i];
            unique_indexes[cnt] = i;
            unique_inverse[i] = cnt;
            cnt++;
        }
    }

    // Sort the unique array
    for (int i = 0; i < cnt - 1; i++) {
        for (int j = 0; j < cnt - i - 1; j++) {
            if (unique[j] > unique[j + 1]) {
                int temp = unique[j];
                unique[j] = unique[j + 1];
                unique[j + 1] = temp;

                temp = unique_indexes[j];
                unique_indexes[j] = unique_indexes[j + 1];
                unique_indexes[j + 1] = temp;
            }
        }
    }

    // Find unique inverse indexes
    for (int i = 0; i < size; i++) {
        unique_inverse[i] = IINIT;
    }
    for (int i = 0; i < cnt; i++) {
        for (int j = 0; j < size; j++) {
            if (unique[i] == array[j]) {
                unique_inverse[j] = i;
            }
        }
    }

    free(unique);
}


/******************************************************************************
 * \brief Return indexes to sort an array of integers
 * \param int* Integer array
 * \param int Size of array
 * \param int* Indexes to sort the array
******************************************************************************/
void utils_argsort(int* array, int size, int* index_array) {
    // Initialize indexes
    for (int i = 0; i < size; i++) {
        index_array[i] = i;
    }

    // Perform bubble sort on indexes array based on values in array
    for (int i = 0; i < size - 1; i++) {
        for (int j = 0; j < size - i - 1; j++) {
            if (array[index_array[j]] > array[index_array[j + 1]]) {
                int tmp = index_array[j];
                index_array[j] = index_array[j + 1];
                index_array[j + 1] = tmp;
            }
        }
    }
}


/******************************************************************************
 * @docstring
******************************************************************************/
int _sortfunc(const void* val_0, const void* val_1) {
    return (*(int*) val_0 - *(int*) val_1);
}


/******************************************************************************
 * @docstring
******************************************************************************/
void utils_sort(int* array, int size) {
    qsort(array, size, sizeof(int), _sortfunc);
}
