# Routines related to downloading ICARE data and folder syncing with ICARE

## Overload Base functions for SFTP file system
Base.pwd(server::SFTP) = server.uri.path


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
  logfile::String = "ICAREdownloads.log",
  format::UInt8 = 0x02,
  update::Bool = false,
  remoteext::String = ".hdf"
)::Nothing
  # Get connection to server
  icare = __connect(user, password, product, version, remoteroot, remoteext)
  # Create product folder, if not existent
  productfolder = abspath(joinpath(localroot, icare.productfolder))
  if !isdir(productfolder)
    @warn "$productfolder does not exist"
    print("Create? (y/n) ")
    create = readline()
    if startswith(lowercase(create), "y")
      mkpath(productfolder)
    else
      throw(Base.IOError("path for local root and/or product folder does not exist; create path and restart ftp_download", 1))
    end
  end
  # Get folder structure from server
  folders = folderstructure(icare, startdate, enddate)
  # Set up log file in product dir unless a different folder is specified
  contains("/", logfile) || (logfile = joinpath(productfolder, logfile))
  # Save current path to return to at the end
  cwd = pwd()
  # Loop over folders, download missing data from server
  for folder in folders, date in folder.dates
    # Start from product folder
    cd(productfolder)
    # Match folder structure with server
    setpath(icare, folder.year, date)
    files = filenames(icare.server)
    # Download files from ICARE server to local directory
    __download(files, icare, format, update)
  end
  # Return to original directory
  cd(cwd)
end #function ftp_download


## Functions for syncing with server and setting up local structure

"""
    __connect(
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
function __connect(
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
    folderstructure(icare::Connection, startdate::Int, enddate::Int)::Vector{DataStorage}

Analyse the folder structure on the `icare` server and return a vector of
`DataStorage` structs holding the relevant folders for each year.
"""
function folderstructure(icare::Connection, startdate::Int, enddate::Int)::Vector{DataStorage}
  # Convert integer dates to dates
  enddate > 0 || (enddate = startdate)
  startdate, enddate = convertdates(startdate, enddate)

  # Define years and dates in range
  folders = datafolders(startdate, enddate)

  # Remove missing remote folders in local folders
  for folder in folders
    cd(icare.server, joinpath(icare.productpath, folder.year))
    remotefolders = readdir(icare.server)
    intersect!(folder.dates, remotefolders)
  end #loop over dates

  return folders
end #function setup_download


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
    setpath(connection::Connection, year::String, date::String)::Nothing

Change to the current date folder on the server as well as locally.
Create missing local folders.
"""
function setpath(connection::Connection, year::String, date::String)::Nothing
  # Set local path (starting from product path), create if missing
  datadir = mkpath(joinpath(year, date))
  cd(datadir)
  # Set path on server
  cd(connection.server, joinpath(connection.productpath, datadir))
end


"""
    filenames(dir::Union{String,SFTP}=".")::Vector{String}

Return a vector of base names without the extension for the given `dir`ectory.
"""
filenames(dir::Union{String,SFTP}=".")::Vector{String} = getindex.(readdir(dir) .|> splitext,1)


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
    __download(
      files::Vector{String},
      icare::Connection,
      format::UInt8,
      update::Bool
    )::Nothing

Download the `files` from the `icare` server and save in the specified `format`.
If set, `update` files to the latest version available on the server.
"""
function __download(
  files::Vector{String},
  icare::Connection,
  format::UInt8,
  update::Bool
)::Nothing
  for file in files
    for i = 1:5
      # Set flag for presence of hdf file
      h4 = isfile(file)
      # Check download status (no directory needed, already in product directory)
      downloaded(file, icare, format, update) && break
      # Download data, if not in local path
      sftp.download(icare.server, file*icare.extension, downloadDir=".")
      # download_data(icare)
      # Convert to h5, if option is set
      ext = bits(format)
      if ext[2]
        # Make previous h5 versions are overwritten
        rm("$file.h5", force=true)
        # Convert hdf4 to hdf5
        run(`h4toh5 $file.hdf`)
      end
      # Delete hdf, if option is set and file was not already present
      (ext[1] && h4) || rm(file*".hdf")
      # Abort download attempts after fifth try
      if !downloaded(file, icare, format, update)
        throw(Base.IOError("Could not download $(file*icare.extension); aborting further download attempts", 3))
      end
    end
  end
  return
end


"""
    downloaded(
      targetfile::String,
      icare::Connection,
      format::UInt8,
      update::Bool;
      dir::String="."
    )::Bool

Check, whether the `targetfile` has already been downloaded from the `icare` server
to the local `dir`ectory in the specified `format`. If desired, `update` if newer
file versions are available.
"""
function downloaded(
  targetfile::String,
  icare::Connection,
  format::UInt8,
  update::Bool;
  dir::String="."
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
    isfile(targetfile*hdf) || return false
    localstats = stat(targetfile*hdf)
    localstats.size == remotestats.size || return false
    (update && localstats.mtime > remotestats.mtime) && return false
  end
  # Check hdf5 files for size and modified date
  if hdf_version[2]
    hdf = ".h5"
    isfile(targetfile*hdf) || return false
    localstats = stat(targetfile*hdf)
    (update && localstats.mtime > remotestats.mtime) && return false
  end
  # Return true if all checks have been passed
  return true
end

#=
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
  user::String,
  password::String,
  remotefiles::Vector{String},
  localfiles::Vector{String},
  savelog::String = "ICAREdownloads.log",
  rwa::String = "w+"
)
  # Start file logger
  logio = open(savelog, rwa)
  logger = logg.SimpleLogger(logio, logg.Debug)
  sepline(logio, logger)
  # Connect to ICARE server
  icare = sftp.SFTP("sftp://sftp.icare.univ-lille.fr", user, password)
  # Error on different remote and local file definitions
  length(remotefiles) ≠ length(localfiles) &&
    @error "Different number of local and remote files defined"
  # Loop over remotefiles and download to local machine as localfiles
  tstart = Dates.now()
  @pm.showprogress 5 "download..." for (rem, loc) in zip(remotefiles, localfiles)
    sftp.download(icare, rem, downloadDir=loc)
    # Log download process
    logg.with_logger(logger) do
      println(logio, basename(rem))
      println(logio, "-> download completed at $(Dates.now())")
    end
    flush(logio)
  end
  # Log download time
  tend = Dates.now()
  logg.with_logger(logger) do
    tdiff = Dates.canonicalize(Dates.CompoundPeriod(tend - tstart))
    isempty(remotefiles) ? println(logio, "no download performed") : println(logio,
      "\ndownload took $(join(tdiff.periods[1:min(2,length(tdiff.periods))], ", "))")
  end
  # Clean-up
  close(icare)
  ftp.ftp_cleanup()
  sepline(logio, logger)
  close(logio)
end #function download_data


## Functions for logging

"""
    sepline(logio::IOStream, logger::logg.SimpleLogger)

Print a separator line to the stream `logio` using the `logger`.
"""
sepline(logio::IOStream, logger::logg.SimpleLogger) = logg.with_logger(logger) do
  println(logio, "––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––")
end
=#
