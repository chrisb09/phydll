# Changelog

All notable changes to this project will be documented in this file.
The format is based on Keep a Changelog,
and this project adheres to Semantic Versioning.


## [0.1.2] - 2023-04-12

### Added
- Communication of static fields
- Main python script for generic testing.
- Intel compilation support for `utsim`.
- Support of Physical non-connected geometry.
  
### Changed
- Install python API in build directory
- Remove hardcoded variables in `cnntf` DLengine.
- Move `neuralnet` directory to `./scripts`.

### Fixed
- Typos in the doc
- Reshape fields in voxgrid class.
- Invalid characeter typo.


## [0.1.1] - 2023-03-12

### Added
- 3D coupling support for *Prisms* meshes.
- 2D coupling support: *Non-context aware; Quadrilaterals, Tringales*.
- Save exchanged fields in Physical solver with HDF5 support.
- Create generic unit test.
- Check MPMD and PhyDLL enabling in *initialization* subroutine.

### Changed
- Rename PhyDLL directory to save aggregated phymesh: `./dmpi_saves -> ./PhyDLL_MESH`.
- Reorder mesh definition for CWIPI coupling.

### Fixed
- Fix 3D coupling for hexahedron meshes.
- Fix XDMF writer for hexahedron meshes.
- Fix first coupling iteration output.
- Remove hard-coded mask of located cwipi points.
- Remove duplicated nodes for single field exchanges (*send DS*).


## [0.1.0] - 2023-02-01 
First version of PhyDLL.
	
