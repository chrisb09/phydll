+ [x] Create function to set options.
+ [x] Coupling frequency.
+ [ ] Static communication.
+ [x] Save fields for (one-way communication lbm) (because save is made with recv in phySol and send in dl)
+ [x] Separate counters `cpl->phy_ic` and `cpl->dl_ic`
+ [ ] Set `count=-1`, if only one way comm (lbm-dl).
+ [ ] `MPI_APP_NUM` pour le split
+ [x] Debug le problème de la deriène fois "seg fault" pour cloture xdmf collection
+ [x] Fix wait_isend in one-side comms
+ [x] `while phy_signal` set as option.
+ [ ] Automate hard-coded `"(PhyDLL:PHY) ---->"`
+ [ ] Array element access with indexes instead of pointer addresses.
+ [ ] Stop cython from creating redundant subdirectories (${PYDIR}/${PYDIR})
+ [ ] Complete coupling frequency feature (Adapt send/recv conditions)

