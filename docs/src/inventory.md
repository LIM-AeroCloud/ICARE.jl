# Analysing and manipulating the inventory

## Analysing the inventory

The structure and files including file stats are saved in an inventory that is returned by most
API functions like [`sftp_download`](@ref), [`clean!`](@ref), [`convert!`](@ref), and [`convert`](@ref).
The inventory is a `SortedDict` that saves relevant data such as the available data range,
the file count and the overall size in the metadata. Stats about the data files are kept in the
`"dates"` section and missing dates are listed in `"gaps"`. Function [`list_inventory`](@ref)
gives a simplified view of the folder and file tree together with important statistics about the
inventory and the downloaded portion.

Any function relying on the inventory will load it when needed. However, the inventory can also
be loaded on its own with [`load_inventory`](@ref). For many functions, convenience methods exist
that load the inventory from the hidden `.inventory.yaml` in the product folder and more
performant methods exist using the preloaded inventory, skipping the load step.

!!! warning "Important notice"
    There is no public function to save the inventory. This is done automatically every time
    the inventory is updated by any _ICARE_ function. Users should not have to save the inventory
    manually and should not attempt to do so as a wrong format might lead to unintended errors.

```@docs
load_inventory
list_inventory
```

## Manipulating the inventory

Several functions exist to help shaping the database to the users need.

### Batch conversions

Methods [`convert`](@ref)/[`convert!`](@ref) can be used to convert data files to a new file format.
By default, HDF4 files are upgraded to HDF5. The same could be achieved by re-running
[`sftp_download`](@ref) with `convert` option set to `true`. If the original files are already
downloaded, then [`sftp_download`](@ref) will not re-download these files and just convert them.
If you have already loaded the inventory, then [`convert!`](@ref) is the more performant option;
[`convert`](@ref) is a convenience method that will load the inventory first and then call
[`convert!`](@ref).

```@docs
convert(::String)
convert!
```

### Cleaning up the inventory

Function [`clean!`](@ref) can be used to remove all files in a product folder that do not belong
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
    trying to set the `erase` option in [`clean!`](@ref), unless you prepend the constants with
    the module name `ICARE.original` and `ICARE.converted`.

!!! danger
    If the original files are removed during [`clean!`](@ref), they are permanently lost and
    will have to be re-downloaded, if needed. If converted files are deleted, they can be converted
    again, if the originals are still present, which is much faster than downloading.

```@docs
clean!
Extension
```

### Ignoring granules in the inventory

Users can choose to ignore specific granules in the inventory. This functionality is meant for
corrupted files in the remote database and will allow to remove them from the inventory and
suppress re-downloads. Ignored files are not considered part of the inventory and are moved
from the inventory's `dates` section to an `ignore` section, when function [`ignore!`](@ref) is
invoked. The can be re-joined with the inventory, e.g. when files in the remote database are
fixed, with function [`unignore!`](@ref). Already downloaded, but ignored files will be deleted
during [`clean!`](@ref) operations.

```@docs
ignore!
unignore!
```

### Allowing extra data in the product folder

Normally, the product folder should be a direct copy of the remote database with the exception
of the `.inventory.yaml` and any log files. However, some users might also want to store additional
metadata, analyses of the database files or results from any investigations. For these reasons,
additional files and folders can be flagged as `extras` and are added to an `extras` section
in the inventory. Files in the `extras` section of the inventory are considered attached to the
inventory, but not part of the database. They will be kept during [`clean!`](@ref) operations,
but don't have influence on downloads or anything else.

Function [`attach!`](@ref) can be used to flag files and folders as `extras` and function
[`detach!`](@ref) will remove them again and allow for them to be cleaned.

```@docs
attach!
detach!
```
