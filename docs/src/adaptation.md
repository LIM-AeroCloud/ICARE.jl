# Adapting the package

## Intended use

The package is written to synchronise CALIOP data from the AERIS/ICARE server with a local system.
Data is in the format:

    <root>/<product>.v<Major>.<Minor>/yyyy/yyyy_mm_dd

The product version consists of a single-digit major and double-digit minor version.
HDF4 data files (`.hdf`) are located in the date folders at the lowest level. They are
converted to HDF5 format (`.h5`) by default. All this functionality can be achieved with the
[`sftp_download`](@ref) function.

!!! warning "Important notice"
    All adaptations described here should work in theory, but have only been tested to a minimal extent.
    If you encounter problems and find a workaround for it, consider a PR with a documentation
    update. If you have troubles, finding a solution or workaround, feel free to open a new issue.

## Use different products with the same format

The AERIS/ICARE data server holds other products with the same structure; [`sftp_download`](@ref)
can be directly used to download this data by changing the `remoteroot` keyword argument to the
new root path and supplying the correct `product` argument. If the data files are not in HDF4
format (or the `convert` option is set to `false`), no conversion to HDF5 is performed.

Some products have different version formats, but the same folder structure. For these products,
you need to set the `version` keyword argument to `nothing` and give the complete folder name
(product name and version number) to the third positional `product` argument. Any products without
the above folder structure cannot be synchronised with this package.

## Converting to other file formats

If you prefer to convert the downloaded files to another file format, you can write your own
conversion routine and overload the routines of the _ICARE.jl_ package. You need the following
routines with the given signature (function names, argument types and return types must match):

* `newext(ext::AbstractString)::String` returns the file extension including the leading dot
  for the given `ext`ension, e.g. `".h5"` for the `".hdf"` extension in the default conversion
* `convert_file(input::String, output::String)::Nothing` converts the `input` file to the `output`
  format; both `input` and `output` may be absolute or relative paths to the respective files

In your script import (or use) the _ICARE_ package, overload the above functions (don't forget
to prepend each function name with `ICARE.` as both functions are unexported) and call the
[`sftp_download`](@ref) function. An example script for NetCDF to HDF5 conversion may look
like this:

```julia
using ICARE

# Only NetCDF data is converted, other newext stays empty
ICARE.newext(ext::AbstractString) = ext == ".nc" ? ".h5" : ""

function ICARE.convert_file(input::String, output::String)
    # Convert path/to/input.nc > path/to/output.h5 here
    return
end

inventory = sftp_download("user", "password", "product", 20200220)
```

The function signatures of the default functions are these:

```@docs
ICARE.convert_file
ICARE.newext
```
