# ICARE.jl

![ICARE logo](assets/logo.svg)

## Overview

__ICARE.jl__ provides a secure ftp connection to the ICARE Data and Services Centre to download
available satellite data. The package is intended for CALIOP data, but was written in a generic
way that should allow downloads of any data with a folder structure:

    <root path>/<main product folder>/yyyy/yyyy_mm_dd

Furthermore, __ICARE.jl__ allows the upgrade of HDF4 file format used in the ICARE database to
HDF5 or any user defined conversions. Parallel downloads are possible by starting julia with
multiple threads:

    julia --threads auto

Or with the short form:

    julia -t auto

`auto` will give all available threads on the current system, but depending on the internet
connection, fewer threads may be desired. In this case, give the number of threads instead of
`auto`.

!!! note
    To use the package, a user account at the
    [AERIS/ICARE Data Centre](https://www.icare.univ-lille1.fr/) is needed, which is available
    free of charge.

## License

__ICARE.jl__ is free to use for non-commercial applications under the Gnu General Public License. 
Binaries included for the HDF4 to HDF5 file conversion are available under szip license for 
non-commercial, scientific use.

## Installation

_ICARE.jl_ is an unregistered Julia package, but can be installed with the package manager.
Start the package manager by typing `]` in the REPL and add _ICARE.jl__ with:

    add https://github.com/LIM-AeroCloud/ICARE.jl.git

By default, the development version will be installed. To use released stable versions switch
to the `main` channel by installing _ICARE.jl_ with:

    add https://github.com/LIM-AeroCloud/ICARE.jl.git#main

## Contents

```@contents
Pages = [
    "index.md",
    "release-notes.md"
]
```
