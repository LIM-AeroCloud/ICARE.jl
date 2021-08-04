ICARE.jl
========

A Julia package for retrieving data from the 
[AERIS/ICARE server](http://www.icare.univ-lille1.fr/).

Use function `ftp_download` to retrieve missing CALIOP data 
files in a specified time frame. 

The function may work for other data as well, but was only designed to downlaod 
CALIOP aerosol and cloud data. Try to change `caliopdir` in `ftp_download` and
make it an arg or kwarg `maindir`.

Installation
------------

ICARE.jl is an unregistered Julia package, but can be 
installed with the package manager:

```julia
julia> ]
pkg> add https://github.com/pb866/ICARE.jl.git
pkg> ← (backspace)
julia> import ICARE
```

Exported functions
------------------

```julia
function ftp_download(
  user::String,
  password::String,
  product::String,
  startdate::Int,
  enddate::Int=-1;
  version::Float64 = 4.20,
  dir::String = ".",
  savelog::String = "ICAREdownloads.log",
  warnlog::String = "ICAREwarnings.log",
  cleandata::Union{Nothing,Bool} = nothing,
  download::Bool = true,
  appendlog::Bool = false,
  restart::String = "ask"
)
```

Download missing CALIOP hdf files of `product` type (e.g., `"05kmAPro"` or `"01kmCLay"`)
and `version` (e.g., `3.01` or `4.2`, default is `4.20`) from the ICARE server
using your `user` login name and `password`.

---
> :information_source: **NOTE**
>
> Passwords containing special characters must be encoded with URI encoding,  
> e.g., `%21` for exclamation mark (`!`) or `%23` for hash or number sign (`#`).
---

Data is downloaded for the specified time frame in the range `startdate` to `enddate`;
`startdate` and `enddate` are positiv integers in the date format `"yyyymmdd"`.
Months (`"mm"`) or month and days (`"mmdd"`) can be missing and are substituted with the first
possible date for the `startdate` and last possible date for the `enddate`.
If `enddate` is not specified, it is assigned the same value as `startdate`, but can
actually be a different date, when the day and/or month is not specified as the value
is assigned prior to the conversion to dates.

#### Examples

- `startdate = 2010`: download all data available in 2006 (from 2010-01-01 to 2010-12-31)
- `startdate = 201001`: download all data from January 2010 (from 2010-01-01 to 2010-01-31)
- `startdate = 20100101`: download data only for 2010-01-01
- `startdate = 2010`, `enddate = 201006`: download first half of 2010 (from 2010-01-01 to 2010-06-30)
- `startdate = 20100103`, `enddate = 20100105`: download data from 2010-01-03 to 2010-01-05


### Data structure

Data are downloaded to the local directory `dir`, where `dir` is the main folder containing the data folder
for `product` files. Folder structure within `dir` is synced with ICARE.
Data is placed in the same folders as on the ICARE server; missing folders are created.
If already existing folders contain any other files than hidden files or files
also available on the ICARE server a warning is given with the option to delete those
files. You are asked in the terminal for the following options:

- `y`: current file is deleted
- `n`: current file deletion is skipped
- `all`: press at any time; __all files__ are deleted __even previously skipped files__
- `remaining`: the current and __all remaining files__ in the list are deleted;
  _previously skipped files are kept_
- `none`: __all remaining files__ are kept (previously deleted files are __not__ restored)

Alternatively, you can set the `cleandata` kwarg to `true`/`false` to delete all/no
data file without programme interruption.

**Files are not synced with ICARE, missing files are downloaded, but existing files
are not checked for file changes.**


### Logging and recovery

Download is monitored in `ICAREdownloads.log`; warnings of missing ICARE data
or additional local data files are given in `ICAREwarnings.log` (or the specified
alternative paths/names for the `savelog` and `warnlog` files). By default, new
log files are created for every run of `ftp_download`, but existing log files can
be appended, if `appendlog` is set to `true`.

Furthermore, a temporary `dsl` (download session log) file is created, which is 
deleted after a successful run. In case of a premature interuption of `ftp_download`,
the `dsl` file is used to recover the last session and continue the downloads.  
In this case the user is prompted to the following options for a restart:

- `y`: Restart the previous download session. This always appends the previous
  `savelog` file of the same name as the `dsl` file
- `n`: This continues the current download session and deletes the `dsl` file
  with the download history of a previously interrupted session
- `l` (option is only available, if the `dsl` file name is not the same as the 
  `savelog` file name of the current session): If a session was previously interrupted,
  but you started a different download session (based on the `savelog` file name),
  you can continue the current download session, but keep the `dsl` file for a later
  recovery of the session

By default, user input occurs via the REPL/terminal. For uninterrupted sessions,
e.g. for ICARE runs in the background, the above choices can be passed to
`ftp_download` with the keyword argument `restart`.

If `download` is set to `false`, `ftp_download` only checks for available
additional data files on the ICARE server in the specified time frame and reports
them in the `savelog` file. Furthermore, missing dates on ICARE or misplaced
files in the local directories are given in the `warnlog` file. Directories are
not synced with ICARE, and files are not downloaded. However, additional files in
the local directories can be removed. This option is available to check your data 
coverage compared to the ICARE server.


Example script
--------------

```julia
import Pkg
Pkg.activate("/Users/home/ICARE")

import Dates.Date
import ICARE

# Download all data from the year 2010
dir = "/Users/home/data/CALIOP/"
ICARE.ftp_download(
  "pb866",
  "PassWord%231%21", #"PassWord#1!"
  "05kmCPro",
  2010,
  dir = dir,
  savelog = joinpath(dir, "ICAREdownloads.log"),
  warnlog = joinpath(dir, "ICAREwarnings.log"),
  cleandata = true
)
```
