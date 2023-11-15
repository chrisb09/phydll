
# Exchange fields
Once PhyDLL is initialized and defined, you can start exchanging the data between the Physical Solver and the Deep Learning engine.
## 1. Set fields to send:
The core subroutine `phydll_set_phy_field` allows to set the Physical fields with labels to send to DL engine. This subroutine should be called `count` times. Its arguments are
- `field` (*double-precision array/pointer of size `nnode`): The field to send. (If non-context coupling is chosen, `nnode` becomes `size`.)
- `label` (*character string*): Label of the field to send.
#### C interface
```c
void phydll_set_field(double** field, char label[]);
```
#### Fortran interface
```c
phydll_set_field_f(
  double precision, dimension(:), pointer :: field, &
  character(len=*) :: label
)
```
#### Python interface
```python
phyl.set_field(field: np.ndarray, label: str)
```

## 2. Send fields
We can send fields in two ways:
- Blocking send
- Non-blocking asynchronous send
#### C interface
```c
// Blocking
void phydll_send();

// Non-blocking
void phydll_isend();
void phydll_wait_isend();
```
#### Fortran interface
```fortran
! Blocking
phydll_send_f()

! Non-blocking
phydll_isend_f()
phydll_wait_isend_f()
```
#### Python interface
```python
# Blocking
phyl.send()

# Non-blocking
phyl.isend()
phyl.wait_isend()
```
In Python interface, the fields could be set directly as a dictionary argument in the send function (without using `phyl.set_field(field: np.ndarray, label: str)`):
```python
# Blocking
phyl.send(fields: dict)

# Non-blocking
phyl.isend(fields: dict)
phyl.wait_isend()
```
The `fields` dictionary is `{label0: field0, label1: field1}`.
## 3. Receive fields:
We can receive fields in two ways:
- Blocking send
- Non-blocking asynchronous send
#### C interface
```c
// Blocking
void phydll_recv();

// Non-blocking
void phydll_irecv();
void phydll_wait_irecv();
```
#### Fortran interface
```fortran
! Blocking
phydll_recv_f()

! Non-blocking
phydll_irecv_f()
phydll_wait_irecv_f()
```
#### Python interface
```python
# Blocking
phyl.recv()

# Non-blocking
phyl.irecv()
phyl.wait_irecv()
```
## 4. Get received fields
Once the fields are received in PhyDLL's buffer, we call the getter function with the following arguments:
- `field` (*double-precision array/pointer of size `nnode`): The received field to send. (If non-context coupling is chosen, `nnode` becomes `size`.)
- `label` (*character string*): Label of the received field.
#### C interface
```c
void phydll_get_field(double** field, char label[]);
```
#### Fortran interface
```fortran
phydll_get_field_f(
  double precision, dimension(:), pointer :: field
  character(len=*) :: label
)
```
#### Python interface
```python
phyl.get_field() -> Tuple[np.ndarray, str]
```
In Python interface, *receive* functions could return directly the received fields with labels as a dictionary (without calling the function above):
```python
# Blocking
phyl.recv(only=False) -> dict

# Non-blocking
phyl.irecv()
phyl.wait_irecv(only=False) -> dict
```
The returned dictionary is `{label0: field0, label1: field1}`.

## Exchange in loop mode
Data exchange can be performed in temporal loop mode. It allows the Physical solver to send a signal to DL engine to indicate when it’s a coupling iteration. In the Physical solver this option: `opt_enable_cpl_loop` should be enabled.

In the DL engine a `while` temporal loop could be created with the variable:
```c
// C interface
bool phydll_is_phy_signal()
```
```fortran
! Fortran interface
logical :: phydll_is_phy_signal_f()
```
```python
# Python interface
is_phy_signal() -> bool
```

## Useful functions
- Get Physical/DL field size
```c
// C interface
void phydll_get_field_size(int* size);
```
```fortran
! Fortran interface
phydll_get_field_size_f(integer :: size)
```
```python
# Python interface
phyl.size : int
```

- Get Physical and DL fields count
```c
// C interface
void phydll_get_field_counts(int* phy_count, int* dl_count);
```
```fortran
! Fortran interface
phydll_get_field_counts_f(integer :: phy_count, integer :: dl_count)
```
```python
# Python interface
self.phy_count : int
self.dl_count : int
```

- Get current Physical Solver iteration
```c
// C interface
int phydll_get_phy_ite();
```
```fortran
! Fortran interface
phydll_get_phy_ite_f(integer :: phy_ite)
```

- Get current coupling iteration
```c
// C interface
int phydll_get_ite();
```
```fortran
! Fortran interface
phydll_get_ite_f(integer :: ite)
```
