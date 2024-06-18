ICARE.jl
========

A Julia package for retrieving data from the
[AERIS/ICARE server](http://www.icare.univ-lille1.fr/).

Use function `sftp_download` to retrieve missing data files in a specified time frame.
Routines are developed to retrieve CALIOP aerosol and cloud data, but will work for any
data that has a root folder in the format `<product>.v<major>.<minor>` and a subfolder
structure of years and dates like this: `yyyy/yyyy_mm_dd`.

Installation
------------

ICARE.jl is an unregistered Julia package, but can be installed with the package manager:

```julia
julia> ]
pkg> add https://github.com/pb866/ICARE.jl.git
pkg> ← (backspace)
julia> using ICARE
```

SFTP download
-------------

```julia
function sftp_download(
  user::String,
  password::String,
  product::String,
  startdate::Int,
  enddate::Int=-1;
  version::Float64 = 4.20,
  remoteroot::String = "/SPACEBORNE/CALIOP/",
  localroot::String = ".",
  format::UInt8 = 0x02,
  update::Bool = false,
  remoteext::String = ".hdf",
  logfile::String = "downloads.log",
  loglevel::Symbol = :Debug
)::Nothing
```

Download missing CALIOP hdf files of `product` type (e.g., `"05kmAPro"` or `"01kmCLay"`)
and `version` (e.g., `3.01` or `4.2`, default is `4.20`) from the ICARE server
using your `user` login name and `password`.

Data is downloaded for the specified time frame in the range `startdate` to `enddate`;
`startdate` and `enddate` are positive integers in the date format `"yyyymmdd"`.
Months (`"mm"`) or month and days (`"mmdd"`) can be missing and are substituted with the first
possible date for the `startdate` and last possible date for the `enddate`.
If `enddate` is not specified, data is downloaded for the given range of the `startdate`,
i.e. one year, month or day of data.

**Examples:**

- startdate = `2010`: download all data available in 2010 (from 2010-01-01 to 2010-12-31)
- startdate = `201001`: download all data from January 2010 (from 2010-01-01 to 2010-01-31)
- startdate = `20100101`: download data only for 2010-01-01
- startdate, enddate = `2010, 201006`: download first half of 2010 (from 2010-01-01 to 2010-06-30)
- startdate, enddate = `20100103, 20100105`: download data from 2010-01-03 to 2010-01-05

### Data structure

Data are downloaded to a `localroot` directory. If the local root directory does not
exist, you are prompted to confirm it's creation or abort the download.
In the root folder the following folder structure will be used, missing folders are
automatically created:

- product folder as `<product>.v<major>.<minor>`
  - year folder as `yyyy`
    - date folder as `yyyy_mm_dd`

Hence, the folder structure of the Aeris/ICARE server will be synced and data files
are downloaded to the appropriate folders.

In contrast to previous versions, folders will only be created upon the initial download
of the first data file. If the folder already contains data files from previous downloads,
these downloads will be skipped, if the previous download was complete.

You may enforce an update of newer versions of a file on the server by setting
`update` to `true`.

Furthermore, the option is given to convert to the newer HDF5 format. You may keep the old
HDF4, or only use `.h5` files to save disk space. The following options are available by
setting the `format` flag. The `UInt8` input can be given in hex or binary format:

- HDF4: `0x01` or `0b01`
- HDF5: `0x02` or `0b10`
- both: `0x03` or `0b11`

### Logging

Download sessions are logged to a log file in addition to the progress bar for downloads
of each date. You can specify the directory and file name with the `logfile` keyword 
argument. By default, all log files are written to the main folder of each `product`.
By passing a valid path (relative or absolute) within the `logfile` keyword, this position 
can be changed as well as the file name, e.g. to save the log file in the parent folder of 
your current directory, rename it to "CALIOPdownloads" and chang the extension to ".txt", use
`../CALIOPdownloads.txt`. 

To all log files a timestamp will be added automatically in the format `yyyy_mm_dd_HH_MM_SS`. 
All log files have the format `path/to/logfile_<timestamp>.ext`.
This has the advantage that names can be reused for several download sessions and the 
standard file name does not have to be changed. One can also see, when files where last 
downloaded from a glance.

### Example script

```julia
import Pkg
Pkg.activate("/Users/home/ICARE")

using ICARE

# Download all data from the year 2010
localroot = "/Users/home/data/CALIOP/"
sftp_download(
  "pb866",
  "PassWord#1!",
  "05kmCPro",
  2010;
  localroot
)
```

HDF4 to HDF5 conversion
-----------------------

```julia
function hdfupgrade(
  rootdir::String=".",
  ext::Union{String,Vector{String}}=[".hdf", ".h4", ".hdf4"];
  recursive::Bool=true,
  h5exists::Symbol=:skip,
  h5ext::String=".h5",
  clean::Bool=false,
  logfile::String=joinpath(rootdir, "hdfupgrades.log"),
  loglevel::Symbol=:Debug
)::Nothing
```

Function `hdfupgrade` converts HDF4 to HDF5 files in the given `rootdir`.
Files ending with `.hdf`, `.h4` or `.hdf4` will be converted to `.h5` files,
but file extensions can be altered with the `ext` argument or `h5ext` keyword argument.
Unless `recursive` is set to `false`, `hdfupgrade` will convert all files with the 
specified extensions in the `rootdir` and all containing subfolders.
After conversion, HDF4 files may be deleted setting the `clean` flag to `true` and
confirming with `"yes"` after being prompted to a confirmation at the beginning of the
function call.

If an h5 file already exists, the following options exist for the conversion
(given as `Symbol` to the `h5exists` flag):

- `skip` (default): skips conversion and leaves existing HDF5 file
- `overwrite`: overwrites the existing HDF5 file
- `cancel`: stops on the first existing HDF5 file
- `abort`: same as `cancel`, but does not convert HDF4 files up to this point

Log files for the conversion will be created. The path and file name can be specified
with the `logfile` keyword. A timestamp will be appended to the logfile name, so you
can reuse `logfile` names. By default, `hdfupgrades_<timestamp>.log` will be saved to
the `rootdir`.
The level of information can be reduced. By default, all information is given. The 
following levels exist, and can be specified with the `loglevel` keyword as `Symbol`:

- `:Error`: Only errors (and severe warnings) are shown.
- `:Warn`: Warnings and errors are shown.
- `:Info`: Info messages are shown additionally.
- `:Debug`: All log messages are shown.
