## Routines related to downloading ICARE data and folder syncing with ICARE

## Overload Base functions for SFTP file system

"""
    pwd(server::SFTP)::String

Return the absolute path of the present working directory as string.
"""
Base.pwd(server::SFTP)::String = string(server.uri.path)


"""
    readdir(server::SFTP, dir::String; join::Bool=false, change::Bool=false)::Vector{String}

Read the files on the `server` in the given `dir`ectory.
If `join` is set to `true`, the absolute paths are returned.
If `change` is set to `true`, the working directory is change to the given `dir`.
"""
function Base.readdir(server::SFTP, dir::String; join::Bool=false, change::Bool=false)::Vector{String}
  # Save current directory and change to dir
  change || (cwd = pwd(server))
  cd(server, dir)
  # Read contents of dir
  files = readdir(server, join)
  # Change back to previous directory and return contents
  change || cd(server, cwd)
  return files
end


## Exported functions
"""
    sftp_download(
      user::String,
      password::String,
      product::String,
      startdate::Int,
      enddate::Int=-1;
      version::Float64 = 4.20,
      remoteroot::String = "/SPACEBORNE/CALIOP/",
      localroot::String = ".",
      logfile::String = "ICAREdownloads.log",
      format::UInt8 = 0x02,
      update::Bool = false,
      remoteext::String = ".hdf"
    )::Nothing

Download satellite data from the Aeris/ICARE server.

# General usage

To use `sftp_download`, an Aeris/ICARE account is needed that is available for free at
https://www.icare.univ-lille.fr. Download satellite data by giving the `user`name and `password`
of that account as the first two arguments.

By default, CALIOP data is downloaded. This can be changed by setting the `remoteroot`
keyword argument as long as the contained folder structure is in the format
`<product>.v<version>/yyyy/yyyy_mm_dd`. The root path can be found in the Aeris/ICARE database.
Files are assumed to be hdf4 files with extension `.hdf`. This can be changed to hdf5 (`.h5` files)
by passing the extension including the dot to the `remoteext` keyword argument.

In addition to the root, the desired `product` is needed as third positional argument,
e.g. `05kmCPro` or `01kmALay`. The name must match the name in the folder excluding
the version number, which is passed as float in the keyword argument `version` (default = `4.20`).

Finally, the desired date range can be specified with the fourth and optional fifth
positional argument. Dates are passed as integer values in the format `yyyymmdd`.
Days and months are optional. If only one Date is passed, all files for that date are
downloaded, e.g. `20200101` will download all granules for the day January 1st, 2020.
If the date is omitted (`202001`) the whole January 2020 is downloaded and if just the year
is given, the whole year is downloaded. Date ranges can be specified by giving a start date
as fourth and end date as fifth argument. If days or days and months are omitted in the
start date, the are assumed to be the first of that period, if days and months are omitted
in the end date, the are the last of that period. E.g., `202007, 2020` will download the
second half of 2020 from 01.07.2020 to 31.12.2020, `20220415, 20230103` will download
for the range 14.04.2022 to 03.01.2023 including the start and end date.

Finally, it is necesary to specify where and how the data should be stored locally.
By default, data will be downloaded to the current folder (where julia was started from
or in which the julia script/REPL command changed). This can be overwritten with the
`localroot` keyword argument. Data is downloaded to the date folders within the product
folder contained directly in `localroot`. Missing folders will be created automatically
upon confirmation.

By default all data will be saved as `.h5` files in the HDF5 format regardless of the
file format on the server. This behaviour can be influended with the `format` kwarg.
Format options are given as `UInt8`. The following options are available:
- HDF4: `0x01` or `0b01`
- HDF5: `0x02` or `0b10`
- both: `0x03` or `0b11`

Only missing files will be downloaded. Already downloaded files will be skipped.
If `update` is set to `true`, the modified dates of the local and remote files are
compared and newer files will be downloaded from the server.
"""
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
  remoteext::String = ".hdf"
)::Nothing
  # Save current path to return to at the end
  cwd = pwd()
  try
    # Get connection to server
    icare = connect(user, password, product, version, remoteroot, remoteext)
    # Create product folder, if not existent
    productfolder = set_localroot(localroot, icare.productfolder)
    # Get folder structure from server
    folders = folderstructure(icare, startdate, enddate)
    # Loop over folders, download missing data from server
    for folder in folders, date in folder.dates
      # Match folder structure with server
      datadir = mkpath(joinpath(folder.year, date))
      files = filenames!(icare, datadir)
      # Download files from ICARE server to local directory
      download(icare, files, datadir, format, update)
    end
  catch error
    rethrow(error)
  finally
    # Return to original directory
    cd(cwd)
  end
end #function ftp_download


## Functions for syncing with server and setting up local structure

"""
    connect(
      user::String,
      password::String,
      product::String,
      version::Float64,
      root::String,
      extension::String
    )::Connection

Securely connects to the server with SFTP using the credentials `user` and `password`
and changing to the `product` folder of the specified `version` in the `root` directory
assuming files with the given `extension`.

Several checks are performed about the connection and folder structure and a
`Connection` struct is returned with all relevant information about the server.
"""
function connect(
  user::String,
  password::String,
  product::String,
  version::Float64,
  root::String,
  extension::String
)::Connection
  # Connect to server and go to root of selected data
  icare = SFTP("sftp://sftp.icare.univ-lille.fr", user, password)
  try cd(icare, root)
  catch err
    rethrow(err)
  end

  # Go to product main folder
  productfolder = @sprintf "%s.v%.2f" product version
  try cd(icare, productfolder)
  catch
    throw(Base.IOError("incorrect product name or version number", 2))
  end

  Connection(icare, root, productfolder, extension)
end


"""
    folderstructure(icare::Connection, startdate::Int, enddate::Int)::Vector{String}

Analyse the folder structure on the `icare` server and return a vector of
`DataStorage` structs holding the relevant folders for each year.
"""
 function folderstructure(icare::Connection, startdate::Int, enddate::Int)::Vector{DataStorage}
  # Convert integer dates to dates
  enddate > 0 || (enddate = startdate)
  startdate, enddate = convertdates(startdate, enddate)

  # Define years and dates in range
  folders = datafolders(startdate, enddate)
  # Loop over all dates
  missing_years = Int[]
  for (i, folder) in enumerate(folders)
    # Sync local with remote folders, remove missing years
    remotefolders = try readdir(icare.server, joinpath(icare.productpath, folder.year), change=true)
    catch error
      error isa sftp.RequestError && error.code == 78 ? [] : rethrow(error)
    end
    # Remove missing remote date folders in local folders
    intersect!(folder.dates, remotefolders)
    # Set year without dates empty
    isempty(folder.dates) && push!(missing_years, i)
  end #loop over dates
  deleteat!(folders, missing_years)

  return folders
end #function setup_download


"""
    set_localroot(localroot::String, mainfolder::String)::String

Define the product folder on the local system from the `localroot` and the `mainfolder`
containing all the year folders for the ICARE data.
"""
function set_localroot(localroot::String, mainfolder::String)::String
  productfolder = abspath(joinpath(localroot, mainfolder))
  if !isdir(productfolder)
    @warn "$(abspath(productfolder)) does not exist"
    print("Create? (y/n) ")
    create = readline()
    if startswith(lowercase(create), "y")
      mkpath(productfolder)
    else
      throw(Base.IOError("path for local root and/or product folder does not exist; create path and restart ftp_download", 1))
    end
  end
  # Change to productfolder and return absolute path as String
  cd(productfolder)
  return productfolder
end


"""
    datafolders(start::Date, stop::Date)::Vector{DataStorage}

Return a `Vector{DateStorage}` holding the years with the respective dates in the
format `yyyy_mm_dd` between the `start` and `stop` date. Boths, years and dates are
stored as `String`.
"""
function datafolders(start::Date, stop::Date)::Vector{DataStorage}
  # Define years in range
  years = Dates.year(start):Dates.year(stop)
  folders = DataStorage[]
  # Loop over years and get dates for each year
  for yr in years
    push!(folders, DataStorage(max(start, Date(yr)), min(stop, Date(yr, 12, 31))))
  end
  # Return Vector of DataStorage structs
  return folders
end


"""
    filenames!(icare::Connection, dir::String)::Vector{String}

Return a vector of base names without the extension for the given `dir`ectory
starting from the product folder on the `icare` connection and change to the given `dir`.
"""
function filenames!(icare::Connection, dir::String)::Vector{String}
  getindex.(readdir(icare.server, joinpath(icare.productpath, dir), change=true) .|> splitext,1)
end


"""
    filenames(dir::String=".")

Return a vector of base names without the extension for the given `dir`ectory.
"""
function filenames(dir::String=".")
  getindex.(readdir(dir) .|> splitext,1)
end


"""
    convertdates(startdate::Int, enddate::Int) -> startdate::Date, enddate::Date

Convert `startdate` and `enddate` from `Int` to `Date`.
If the day and/or month in `startdate` are missing, `startdate` is completed with
the earliest possible date (day = `01` and month = `01`).
If the day and/or month in `enddate` are missing, `enddate` is completed with
the latest possible date (month = `12` and day = last day of that month).
"""
function convertdates(startdate::Int, enddate::Int)::Tuple{Date,Date}
  startdate = Date(string(startdate), "yyyymmdd")
  enddate = string(enddate)
  l = length(enddate)
  enddate = if l == 8
    Date(enddate, "yyyymmdd")
  else
    Dates.lastdayofmonth(Date(enddate*"12", "yyyymmdd"))
  end

  return startdate, enddate
end #function convertdates!


## Function for sftp download

"""
    download(
      icare::Connection,
      files::Vector{String},
      datadir::String,
      format::UInt8,
      update::Bool
    )::Nothing

Download the `files` from the `icare` server and save in the specified `format`
to the given `datadir`. If set, `update` files to the latest version available
on the server.
"""
function download(
  icare::Connection,
  files::Vector{String},
  datadir::String,
  format::UInt8,
  update::Bool
)::Nothing
  prog = pm.Progress(length(files), dt=1, desc="downloading...")
  for file in files
      download_data(icare, file, datadir, format, update)
      pm.next!(prog, showvalues = [(:date,Dates.Date(basename(datadir), "y_m_d"))])
  end
  pm.finish!(prog)
  return
end


"""
    downloaded(
      icare::Connection,
      targetfile::String,
      dir::String,
      format::UInt8,
      update::Bool
    )::Bool

Check, whether the `targetfile` has already been downloaded from the `icare` server
to the local `dir`ectory in the specified `format`. If desired, `update` if newer
file versions are available.
"""
function downloaded(
  icare::Connection,
  targetfile::String,
  dir::String,
  format::UInt8,
  update::Bool
)::Bool
  # Get files in local director and verify HDF version
  localfiles = filenames(dir)
  hdf_version = bits(format)
  # Return false, if file doesn't exist
  targetfile ∈ localfiles || return false
  # Get stats on remote files
  remotestats = sftp.sftpstat(icare.server)
  i = findfirst(isequal(targetfile*icare.extension), [f.desc for f in remotestats])
  remotestats = remotestats[i]
  # Check hdf4 files for size and modified date
  if hdf_version[1]
    hdf = ".hdf"
    isfile(joinpath(dir, targetfile*hdf)) || return false
    localstats = stat(joinpath(dir, targetfile*hdf))
    localstats.size == remotestats.size || return false
    (update && localstats.mtime > remotestats.mtime) && return false
  end
  # Check hdf5 files for size and modified date
  if hdf_version[2]
    hdf = ".h5"
    isfile(joinpath(dir, targetfile*hdf)) || return false
    localstats = stat(targetfile*hdf)
    (update && localstats.mtime > remotestats.mtime) && return false
  end
  # Return true if all checks have been passed
  return true
end


"""
    download_data(
      user::String,
      password::String,
      remotefiles::Vector{String},
      localfiles::Vector{String},
      savelog::String = "ICAREdownloads.log",
      rwa::String = "w+"
    )

Connect to ICARE server with `user` login name and `password` and download
`remotefiles` to local directory as `localfiles`. Monitor progress in `savelog`.
Old log files are overwritten unless read/write access to files (`rwa`) is set to
`"a+"`.
"""
function download_data(
  icare::Connection,
  file::String,
  datadir::String,
  format::UInt8,
  update::Bool
)::Nothing
  for i = 1:5
    # Set flag for presence of hdf file
    h4 = isfile(file)
    # Check download status (no directory needed, already in product directory)
    downloaded(icare, file, datadir, format, update) && break
    # Download data
    sftp.download(icare.server, file*icare.extension, downloadDir=datadir)
    # Convert to h5, if option is set
    ext = bits(format)
    if ext[2]
      # Make sure, previous h5 versions are overwritten
      rm("$(joinpath(datadir, file)).h5", force=true)
      # Convert hdf4 to hdf5
      run(`h4toh5 $(joinpath(datadir, file)).hdf`)
    end
    # Delete hdf, if option is set and file was not already present
    if !ext[1] && !h4
      rm(joinpath(datadir, file)*".hdf")
    end
    # Abort download attempts after fifth try
    if !downloaded(icare, file, datadir, format, update)
      throw(Base.IOError("Could not download $(file*icare.extension); aborting further download attempts", 3))
    end
  end
end #function download_data
