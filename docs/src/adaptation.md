# Adapting the package

## Intended use

The package is written to synchronise CALIOP data from the AERIS/ICARE server a local system.
Data is in the format:

    <root>/<product>.v<Major>.<Minor>/yyyy/yyyy_mm_dd

The product version consists of a single-digit major and double-digit minor version.
HDF4 data files (`.hdf`) are located in the date folders at the lowest level. The can be
converted to HDF5 format (`.h5`). All this functionality can be achieved with the
`sftp_download` function.

!!! warning "Important notice"
    All adaptations described here should work in theory, but have never been tested in reality.
    If you encounter problems and find a workaround for it, consider a PR with a documentation
    update. If you have troubles, finding a solution or workaround, feel free to open a new issue.

## Use different products with the same format

The AERIS/ICARE data server holds other products with the same structure; `sftp_download` can
be directly used to download this data, by changing the `remoteroot` keyword argument to the
new root path and supplying the correct `product` argument. If the data files are not in HDF4
format or and upgrade to HDF5 is not desired, switch the `convert` keyword argument to `false`.

Some products have different version formats, but the same folder structure. For these products,
you need to set the `version` keyword argument to `nothing` and give the complete folder name
(product name and version number) to the third positional `product` argument. Any products without
the above folder structure cannot be synchronised with this package.

## Converting to other file formats

If you prefer to convert the downloaded files to another file format, you can write your own
conversion routine and overload the routines of the _ICARE.jl_ package. You need the following
routines with the given signature (function names, argument types and return types must match):

* `newext()::String` returns the file extension including the leading dot for the converted format,
  e.g. `".h5"` for the default conversion
* `convert_file(input::String, output::String)::Nothing` converts the `input` file to the `output`
  format; both `input` and `output` may be absolute or relative paths to the respective files

In your script import (or use) the _ICARE_ package, overload the above functions (don't forget
to prepend each function name with `ICARE.` as both functions are unexported) and call the
`sftp_download` function. An example script can look like this:

```julia
using ICARE

ICARE.newext() = ".newext"

function ICARE.convert_file(input::String, output::String)
    # Convert path/to/input.ext > path/to/output.newext here
    return
end

sftp_download("user", "password", "product", 20200220)
```

The function signatures of the default functions are these:

```@docs
ICARE.convert_file
ICARE.newext
```
