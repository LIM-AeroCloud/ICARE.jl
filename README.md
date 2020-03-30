ICARE.jl
========

A Julia package related for retrieving data from the 
[AERIS/ICARE server](http://www.icare.univ-lille1.fr/).

Currently only function `ftp_download` exists to retrieve missing CALIOP data 
files in a specified timeframe. 

The function may work for other data as well, but was only designed to downlaod 
CALIOP aerosol and cloud data. Try to change `caliopdir` in `ftp_download` and
make it an arg or kwarg `maindir`.

Install
-------

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
  dir::String = "."
) -> remotefiles
```

Download missing CALIOP hdf files of `product` type (e.g., `"05kmAPro"` or `"01kmCLay"`)
and `version` (e.g., `3.01` or `4.2`, default is `4.20`) from the ICARE server
using your `user` login name and `password`.

Data is downloaded for the specified time frame in the range `startdate` to `enddate`
to the local directory `dir`, where `dir` is the main folder containing the data folder
for `product` files. Folder structure in `dir` must be the same as on the ICARE server
otherwise already existing files will not be found. However, missing folders will be 
created automatically.

**Files are not synced, missing files are downloaded, but existing files are not 
checked for file changes.**

Returns a `Vector{String}` with all the file names of the downloaded files.
