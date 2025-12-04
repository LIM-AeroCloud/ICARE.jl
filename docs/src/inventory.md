# Analysing and manipulating the inventory

## Analysing the inventory

The structure and files including file stats are saved in an inventory that is return by all
API functions [`sftp_download`](@ref), [`clean`](@ref), [`convert!`](@ref), and [`convert`](@ref).
The inventory is a `SortedDict` that saves relevant data such as the available data range,
the file count and the overall size in the metadata. Stats about the data file are kept in the
`"dates"` section and missing dates are listed in `"gaps"`.

## Manipulating the inventory

Several functions exist to help shaping the database to the users need. 

### Batch conversions

Methods [`convert`](@ref)/[`convert!`](@ref) can be used to convert data files to a new file format.
By default, HDF4 files are upgraded to HDF5. The same could be achieved by re-running
[`sftp_download`](@ref) with `covert` option set to `true`. If the original files are already
downloaded, then [`sftp_download`](@ref) will not re-download these files and just convert them.
If you have already loaded the inventory, then [`convert!`](@ref) is the more performant option;
[`convert`](@ref) is a convenience method that will load the inventory first and then call
[`convert!`](@ref).

```@docs
convert(::String)
convert!
```

### Cleaning up the inventory

Function [`clean`](@ref) can be used to remove all files in a product folder that do not belong
to the database, i.e. that don't exist on the ICARE server. Files will be permanently deleted,
but the user will always be shown, which files will be deleted, and ask for confirmation.

By passing a file extension or a vector of file extensions to the keyword argument `keepext`,
those files will be ignored for the clean-up. This can be useful, for example, to keep log files
defaulting to the `.log` extension. Otherwise, they will be removed not counting as part of the
database and only the log file from the current cleaning run is saved.

The database itself can be cleaned up as well. By default, both the original and converted files
are considered part of the database. But one or the other file type can be removed during cleaning.
This is done by specifying which datatype shall be removed to the `erase` keyword argument with
the [`Extension`](@ref) enum. The two choices available are `original` and `converted`.
The enums are passed directly to the `erase` kwarg (without quotes or any other specifier).
They are constants in ICARE that are exported from the package. Therefore, they should not be
overwritten.

!!! warning
    The [`Extension`](@ref) enum together with the values `original` and `converted` is exported
    by _ICARE.jl_. Do not unintentionally overwrite them or you will get error messages, when
    tyring to set the `erase` option in [`clean`](@ref).

!!! danger
    If the original files are removed during [`clean`](@ref), they are permanently lost and
    will have to be re-downloaded, if needed. If converted files are deleted, they can be converted
    again from the original, which is much faster than downloading.

```@docs
clean
Extension
```
