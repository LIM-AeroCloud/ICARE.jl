# Downloading from the ICARE server

## Synchronising folder structure

_ICARE.jl_ is meant for data that is arranged by years and dates with the following structure:

    <root>/<product folder>/yyyy/yyyy_mm_dd

This folder structure is synchronised with the local system and data files are downloaded to
the date folders at the lowest level. To minimize server communication and speed up download
processes, a local `.inventory.yaml` file (hidden on Linux and MacOs) is created in the product
folder. The `.inventory.yaml` contains information about the folder structure and file stats
and should not be edited or deleted. The inventory is created before the first download of a
given product. This process takes several minutes up to hours in extreme cases. After the initial
setup, only dates outside the known date range are updated, which is much faster, unless a
complete resynchronisation is forced.

!!! warning "Important Notice"
    Don't edit or delete the `.inventory.yaml` file in each main product folder unless you know
    what you are doing! The creation or resynchronisation of the inventory takes several minutes
    or up to hours in extreme cases.

!!! note
    Inventories may not be nested, i.e. a product folder may not be inside another product folder.

## Downloading data files

Use the [`sftp_download`](@ref) function to synchronise the AERIS/ICARE server with the local
system. Mandatory arguments are the ICARE user credentials, the product, and the date span.
Further fine-tuning of the downloads is possible with keyword arguments as described in the
[`sftp_download`](@ref) help.

```@docs
sftp_download
```

### Specifying the download product

By default, CALIOP data (`/SPACEBORNE/CALIOP`) will be downloaded, but can be changed with the
`remoteroot` keyword argument. Data will be downloaded to the current folder or the folder
specified by `localroot`. Use the third positional argument to specify the product, you want to
download. Products are assumed in the format `<name>.v.<X.XX>`, where `X.XX` is the version number
with a two-digit minor version. By default, version `4.51` is assumed, but can be changed with
the `version` keyword argument (e.g., upgrade to version 5 with `version=5`).

!!! note
    Currently, the newest version 5 shows a significant performance decrease on the server side.
    Therefore, version `4.51` was chosen as the current default.

For custom formats, `version` can be set to `nothing` and the entire name and version string
passed to the `product` argument.

### Specifying a date range

For convenience, dates are given as integers, so users don't have to import the `Dates` package.
You can either give one date range as fourth positional argument or a start and end date as fourth
and fifth positional argument.

The date format is `yyyy[mm[dd]]`, where the day and/or month part can be omitted.
Defining a span is possible for:

* a whole year (`yyyy`)
* a whole month (`yyyymm`)
* a day (`yyyymmdd`)

If the the day and/or month are omitted in the start or end date, they will be filled with the 
earliest possible day for the `startdate` and the latest possible date for the `enddate`. 

Some examples are:

* `20220212`: Download the whole day of `2022-02-12`
* `202004`: Download the whole April of 2020
* `2020`: Download the whole year 2020
* `2002, 200206`: Download the first half of 2002
* `200207, 2002`: Download the second half of 2002
* `200003, 20000315`: Download the first half of March 2000
* `20000316, 200003`: Download the second half of March 2000

Only complete days can be downloaded.

### Updating the inventory

As mentioned before, updating the entire inventory including the parts already synced may take
a long time and should not be necessary under normal circumstances. It can be achieved by setting
`resync` to `true`.

If you want to check for updated data files on the server, you can set the `update` flag to
`true`. This will also resync the complete inventory and, hence, take a long time to finish.
If `update` is set, any newer file on the server compared to the modified time on the local
system will be downloaded.

### Logging

Some basic information about the current download session is printed to the screen with further
comprehensive information in a log file. By default, log files are saved to the product folder
as `download_<timestamp>.log`. You can change the file name with the `logfile` keyword argument.
The file name will automatically be appended with the time stamp, when the download session
started. If the file name includes a path, the logfile will be saved to this path. The path can
be absolute or relative to your current location (where you started your julia session or where
you change to during your julia session), i.e. `logfile = "~/icare.log"` will create a logfile
`icare_<timeestamp>.log` in your root directory. Note that the extension can be change as well
to, e.g., `.txt` or `.dat`.

For the log file the verbosity can be set to 4 levels given as `Symbol` (with verbosity listed
from least to most):

* `Error`
* `Warn`
* `Info`
* `Debug`

By default, all messages are printed allowing you to track the download status on screen and
in the log file. The `Debug` level is used to inform about completed downloads.

## Converting data files

### During download

During an `sftp_download`, you can set the `convert` keyword argument to `true`. By default,
this will save downloads in the HDF5 (`.h5`) format instead of the expected HDF4 (`.hdf`) format.
You can overload the [`ICARE.convert_file`](@ref) function, see section about
[Converting to other file formats](@ref). However, only one or the other format will be saved.

!!! tip
    If, you want both formats saved on your local machine, download the original format with
    `sftp_download` by setting `convert` to `false` and re-run `sftp_download` with `convert=true`.
    The second run will only convert the files without re-downloading them and also keep the
    original downloads. If your run `sftp_download` with `convert=true` the first time, original
    downloads are not kept.

### Separate file conversions

Routines related to file conversion without download from the AERIS/ICARE server are
being refactored. **They may or may not work at current.**

```@docs
hdfupgrade
```
