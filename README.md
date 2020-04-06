ICARE.jl
========

A Julia package for retrieving data from the 
[AERIS/ICARE server](http://www.icare.univ-lille1.fr/).

Use function `ftp_download` to retrieve missing CALIOP data 
files in a specified timeframe. 

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
pkg> instantiate
pkg> ← (backspace)
julia> import ICARE
julia> Dates.Date
```

Exported functions
------------------

```julia
function ftp_download(
  user::String,
  password::String,
  product::String,
  startdate::Date,
  enddate::Date,
  version::Float64 = 4.20;
  dir::String = ".",
  savelog::String = "ICAREdownloads.log",
  warnlog::String = "ICAREwarnings.log",
  cleandata::Union{Nothing,Bool} = nothing
)
```

Download missing CALIOP hdf files of `product` type (e.g., `"05kmAPro"` or `"01kmCLay"`)
and `version` (e.g., `3.01` or `4.2`, default is `4.20`) from the ICARE server
using your `user` login name and `password`.

Data is downloaded for the specified time frame in the range `startdate` to `enddate`
to the local directory `dir`, where `dir` is the main folder containing the data folder
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
data file without programme interuption.

**Files are not synced with ICARE, missing files are downloaded, but existing files
are not checked for file changes.**

Downloaded files are logged in `ICAREdownloads.log`; warnings of missing ICARE data
or additional local data files is given in `ICAREwarnings.log`.


---
> **NOTE**
>
> Passwords containing special characters must be encoded with URI encoding,  
> e.g., `%20` for space or `%21` for exclamation mark (`!`).
---


Example script
--------------

```julia
import Pkg
Pkg.activate("/Users/home/ICARE")

import Dates.Date
import ICARE

# Download the first half of 2019 cloud profiles
dir = "/Users/home/data/CALIOP/"
ICARE.ftp_download(
  "pb866",
  "PassWord%21",
  "05kmCPro",
  Date(2019),
  Date(2019, 6, 30),
  dir = dir,
  savelog = joinpath(dir, "ICAREdownloads.log"),
  warnlog = joinpath(dir, "ICAREwarnings.log"),
  cleandata = true
)
```
