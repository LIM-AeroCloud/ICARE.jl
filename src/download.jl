## Routines related to downloading ICARE data and folder syncing with ICARE

## Types

"""



"""
mutable struct Counter
  downloads::Int
  skipped::Int
  function Counter(downloads::Int=0, skipped::Int=0)
    new(downloads,skipped)
  end
end

## API functions
#* Overload Base functions for SFTP file system

"""
    pwd(server::SFTP)::String

Return the absolute path of the present working directory on the `server` as string.
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


#* Main function for download from server
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
      format::UInt8 = 0x02,
      update::Bool = false,
      remoteext::String = ".hdf",
      logfile::String = "downloads.log",
      loglevel::Symbol = :Debug
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

A log file `downloads_<timestamp>.log` will be created in the `product` main folder,
where the timestamp in the format `yyyy_mm_dd_HH_MM_SS` is added automatically to the
file. You can change the file name (the timestamp will also be added to the new file name).
If the log file includes a path, it will be saved to that directory instead.
The number of log messages can be influenced with the `loglevel` keyword given as
a `Symbol`. The following options exist:

- `:Error`: Only errors (and severe warnings) are shown.
- `:Warn`: Warnings and errors are shown.
- `:Info`: Info messages are shown additionally.
- `:Debug`: All log messages are shown.
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
  remoteext::String = ".hdf",
  logfile::String = "downloads.log",
  loglevel::Symbol = :Debug
)::Nothing
  # Get connection to server, go to product folder on remote
  icare = connect(user, password, product, version, remoteroot, remoteext)
  # Create product folder, if not existent
  productfolder = set_localroot(localroot, icare.productfolder)
  # Start logging
  logfile, level = init_logging(logfile, productfolder, loglevel)
  open(logfile, "w") do logio
    logger = Logging.ConsoleLogger(logio, level, show_limited=false)
    Logging.with_logger(logger) do
      @info "downloading \"$product\" data, version $version to \"$productfolder\"" icare.productpath
    end
    # Read server data, if available
    inventory = product_database(icare, productfolder)
    # Get folder structure from server
    folders = folderstructure(icare, startdate, enddate, productfolder, logger)
    # Log download session
    t0 = Dates.now()
    Logging.with_logger(logger) do
      formats = [".hdf", ".h5"]
      not = update ? "" : " not"
      @info "data files downloaded in $(formats[bits(format)[1:2]]) format"
      @info "files will$not be updated, if newer files are available on the server"
      @info "starting downloads @$(t0)"
    end
    # Loop over folders, download missing data from server
    counter = Counter()
    try
      for folder in folders, date in folder.dates
        # Match folder structure with server
        datadir = (; :abs=>joinpath(productfolder, folder.year, date), :rel=>joinpath(folder.year, date))
        mkpath(datadir.abs)
        date = remotefiles!(icare, inventory, datadir.rel, productfolder)
        # Download files from ICARE server to local directory
        counter = download(icare, inventory, datadir, date, format, update, logger, logio, counter)
      end #loop over dates/data files
    catch error
      rethrow(error)
    finally
      # Log end of download session
      t1 = Dates.now()
      Logging.with_logger(logger) do
        @info "$(counter.downloads) files downloaded in $(Dates.canonicalize(t1-t0)) @$(t1)"
        @info "$(counter.skipped) files were already previously downloaded"
      end
    end
  end #logging
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

Securely connect to the server with SFTP using the credentials `user` and `password`
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
  # Instantiate and return Connection
  Connection(icare, root, productfolder, extension)
end


"""
    folderstructure(
      icare::Connection,
      startdate::Int,
      enddate::Int,
      inventory::SortedDict,
      productfolder::String,
      logger::Logging.ConsoleLogger
    )::Vector{DataStorage}

Analyse the folder structure on the `icare` server and return a vector of
`DataStorage` structs holding the relevant folders for each year between the
`startdate` and the `enddate`.

Update the `inventory` according to the folder structure and save to the
`inventory.yaml` in the `productfolder`. Use `logger` to log to the given log file.

"""
 function folderstructure(
  icare::Connection,
  startdate::Int,
  enddate::Int,
  inventory::SortedDict,
  productfolder::String,
  logger::Logging.ConsoleLogger
)::Vector{DataStorage}
  # Convert integer dates to dates
  enddate > 0 || (enddate = startdate)
  startdate, enddate = convertdates(startdate, enddate)
  Logging.with_logger(logger) do
    @info "Downloading for dates $startdate – $enddate"
  end
  # Define years and dates in range
  folders = datafolders(startdate, enddate)
  # Loop over all dates
  years_without_data = Int[]
  for (i, folder) in enumerate(folders)
    # Sync local with remote folders, remove missing years
    remotefolders = try readdir(icare.server, joinpath(icare.productpath, folder.year), change=true)
    catch error
      error isa sftp.RequestError && error.code == 78 ? String[] : rethrow(error)
    end
    # Remove missing remote date folders in local folders
    rm_missingdates!(folder.dates, remotefolders, inventory, productfolder)
    # Set year without dates empty
    isempty(folder.dates) && push!(years_without_data, i)
  end #loop over dates
  # Clean-up and logging
  cd(icare.server, icare.productpath)
  missing_years = [tryparse(Int, folder.year) for folder in folders[years_without_data]]
  deleteat!(folders, years_without_data)
  dates = try sum(length(d.dates) for d in folders)
  catch
    0
  end
  s = dates > 1 ? "s" : ""
  Logging.with_logger(logger) do
    @info "'$(icare.extension)' data files for $dates date$s available for download"
    for data in folders
      @info "$(data.year)" dates = replace.(data.dates, "_"=>"-")
    end
    if !isempty(missing_years)
      @warn "no data available for the following years" missing_years _module=nothing _file=nothing _line=nothing
    end
  end

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
  return productfolder
end


"""
    product_database(icare::Connection, productfolder::String)::SortedDict

Return the inventory of `icare` server-side data files.
Either read the database from the yaml file in the `productfolder` or initialise
a new and empty database.
"""
function product_database(icare::Connection, productfolder::String)::SortedDict
  database = joinpath(productfolder, "inventory.yaml")
  return isfile(database) ?
    YAML.load_file(database, dicttype=SortedDict{Any,Any}) :
    SortedDict{Int,Any}(0 => SortedDict(
      "file" => SortedDict(
        "extension" => icare.extension,
        "count" => 0
      ),
      "server" => SortedDict(
        "updated" => nothing,
        "product" => icare.productfolder,
        "root" => icare.root
      )
    ))
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
    rm_missingdates!(
      localfolders::Vector{String},
      remotefolders::Vector{String},
      inventory::SortedDict,
      productfolder::String
    )::Nothing

Remove dates in `localfolders` where missing in `remotefolders`.
Update the `inventory` with missing dates and save to the `inventory.yaml` in the
`productfolder`.
"""
function rm_missingdates!(
  localfolders::Vector{String},
  remotefolders::Vector{String},
  inventory::SortedDict,
  productfolder::String
)::Nothing
  # Restrict remote folder to bounds of local folders
  filter!(d -> localfolders[1] ≤ d ≤ localfolders[end], remotefolders)
  # Add missing dates to inventory
  missed = false
  missing_dates = setdiff(localfolders, remotefolders)
  for date in missing_dates
    y, m, d = parse.(Int, split(date, "_"))
    hasentry!(inventory, y, m, d) || (missed = true)
  end
  # Update inventory.yaml
  if missed
    println("missed")
    YAML.write_file(joinpath(productfolder, "inventory.yaml"), inventory)
  end
  # Remove missing dates from local folder list
  intersect!(localfolders, remotefolders)
  return
end


"""
    filenames(dir::String=".")

Return a vector of base names without the extension for the given `dir`ectory.
"""
function filenames(dir::String=".")
  getindex.(readdir(dir) .|> splitext,1)
end


"""
    remotefiles!(
      icare::Connection,
      inventory::SortedDict,
      datadir::String,
      productdir::String
    )::@NamedTuple{year::Int,month::Int,day::Int}

Check, if the files on the `icare` server in the `datadir` path are already in the inventory,
otherwise update the inventory (including the metadata). Save the updated inventory as
yaml file to the `productfolder` and return the year `y`, month `m`, and day `d` as
`NamedTuple` to easily address the current data in the inventory.
"""
function remotefiles!(
  icare::Connection,
  inventory::SortedDict,
  datadir::String,
  productdir::String
)::@NamedTuple{year::Int,month::Int,day::Int}
  y, m, d = parse.(Int, split(basename(datadir), "_"))
  if hasentry!(inventory, y, m, d)
    inventory[y][m][d]
  else
    # Get stats of remote files
    files = sftp.sftpstat(icare.server, joinpath(icare.productpath, datadir))
    # Remove current and perant directory from stats
    deleteat!(files, 1:2)
    # Save file stats to new inventory entry
    for file in files
      inventory[y][m][d][splitext(file.desc)[1]] = SortedDict(
        "mtime" => Dates.unix2datetime(file.mtime),
        "size" => file.size
      )
    end
    # Update inventory metadata
    inventory[0]["file"]["count"] += length(files)
    inventory[0]["server"]["updated"] = Dates.now()
    YAML.write_file(joinpath(productdir, "inventory.yaml"), inventory)
  end
  return (; :year=>y, :month=>m, :day=>d)
end


"""
    hasentry!(inventory::SortedDict, y::Int, m::Int, d::Int)::Bool

Check whether the date (year `y`, month `m`, and day `d`) is in the current `inventory`
and return as `Bool`.
"""
function hasentry!(inventory::SortedDict, y::Int, m::Int, d::Int)::Bool
  haskey(inventory, y) || (inventory[y] = SortedDict())
  haskey(inventory[y], m) || (inventory[y][m] = SortedDict())
  if haskey(inventory[y][m], d)
    true
  else
    inventory[y][m][d] = SortedDict()
    false
  end
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
      update::Bool,
      logger::Logging.ConsoleLogger,
      logio::IOStream,
      counter::Counter
    )::Coutner

Download the `files` from the `icare` server and save in the specified `format`
to the given `datadir`. If set, `update` files to the latest version available
on the server. Log `logger` events to a log file in the `logio` I/O stream.
Return an updated `counter` of how many files were downloaded or skipped.
"""
function download(
  icare::Connection,
  inventory::SortedDict,
  datadir::@NamedTuple{abs::String,rel::String},
  date::@NamedTuple{year::Int,month::Int,day::Int},
  format::UInt8,
  update::Bool,
  logger::Logging.ConsoleLogger,
  logio::IOStream,
  counter::Counter
)::Counter
  # TODO use several threds for parallel downloads
  files = inventory[date.year][date.month][date.day]
  try
    pm.@showprogress 1 "$(replace(basename(datadir.rel), "_"=>"-")):" for (file, data) in files
      download_data(icare, file, datadir, data, format, update, logger, logio, counter)
    end
  finally
    return counter
  end
end


"""
    download_data(
      icare::Connection,
      file::String,
      datadir::@NamedTuple{abs::String,rel::String},
      filestats::SortedDict,
      format::UInt8,
      update::Bool,
      logger::Logging.ConsoleLogger,
      logio::IOStream,
      counter::Counter
    )::Counter

Check whether the current `file` has already been downloaded by comparing it to the
`icare` `filestats`, otherwise download it from the `datadir` on the `icare` server
to the local `datadir` in the specified format:
- HDF4: `0x01` or `0b01`
- HDF5: `0x02` or `0b10`
- both: `0x03` or `0b11`
Newer versions of existing local files are only downloaded from the `icare` server,
if `update` is set to `true`. Log `logger` events to a log file in the `logio` I/O stream.
Return an updated `counter` of how many files were downloaded or skipped.
"""
function download_data(
  icare::Connection,
  file::String,
  datadir::@NamedTuple{abs::String,rel::String},
  filestats::SortedDict,
  format::UInt8,
  update::Bool,
  logger::Logging.ConsoleLogger,
  logio::IOStream,
  counter::Counter
)::Counter
  t0 = Dates.now()
  for i = 1:5
    # Set flag for presence of hdf file
    h4 = isfile(file)
    # Check download status (no directory needed, already in product directory)
    if downloaded(file, datadir.abs, filestats, format, update)
      Logging.with_logger(logger) do
        @debug "$file already downloaded, skipping download" _module=nothing _file=nothing _line=nothing
      end
      flush(logio)
      counter.skipped += 1
      return counter
    end
    # Download data
    cd(icare.server, joinpath(icare.productpath, datadir.rel))
    sftp.download(icare.server, file*icare.extension, downloadDir=datadir.abs)
    # Convert to h5, if option is set
    ext = bits(format)
    if ext[2]
      # Make sure, previous h5 versions are overwritten
      rm("$(joinpath(datadir.abs, file)).h5", force=true)
      # Convert hdf4 to hdf5
      run(`h4toh5 $(joinpath(datadir.abs, file)).hdf`)
    end
    # Delete hdf, if option is set and file was not already present
    if !ext[1] && !h4
      rm(joinpath(datadir.abs, file)*".hdf")
    end
    # Abort download attempts after fifth try
    if downloaded(file, datadir.abs, filestats, format, update)
      t1 = Dates.now()
      s = i > 1 ? "s" : ""
      Logging.with_logger(logger) do
        @debug "$file downloaded in $i attempt$s in $(Dates.canonicalize(t1-t0)) @$t1" _module=nothing _file=nothing _line=nothing
      end
      flush(logio)
      counter.downloads +=1
      break
    elseif i == 5
      throw(Base.IOError("Could not download $(file*icare.extension); aborting further download attempts", 3))
    end
  end
  return counter
end #function download_data


"""
    downloaded(
      targetfile::String,
      dir::String,
      filestats::SortedDict,
      format::UInt8,
      update::Bool
    )::Bool

Check, whether the `targetfile` has already been downloaded from the server
to the local `dir`ectory in the specified `format` by compoaring it to the `filestats`
of the remote server. If desired, `update` if newer file versions are available.
"""
function downloaded(
  targetfile::String,
  dir::String,
  filestats::SortedDict,
  format::UInt8,
  update::Bool
)::Bool
  # Get files in local director and verify HDF version
  localfiles = filenames(dir)
  hdf_version = bits(format)
  # Return false, if file doesn't exist
  targetfile ∈ localfiles || return false
  # Check hdf4 files for size and modified date
  if hdf_version[1]
    hdf = ".hdf" #¿use variable for extension?
    isfile(joinpath(dir, targetfile*hdf)) || return false
    localstats = stat(joinpath(dir, targetfile*hdf))
    localstats.size == filestats["size"] || return false
    (update && localstats.mtime > filestats["mtime"]) && return false
  end
  # Check hdf5 files for size and modified date
  if hdf_version[2]
    hdf = ".h5" #¿use variable for extension?
    isfile(joinpath(dir, targetfile*hdf)) || return false
    localstats = stat(joinpath(dir, targetfile*hdf))
    (update && localstats["mtime"] > filestats["mtime"]) && return false
  end
  # Return true if all checks passed
  return true
end
