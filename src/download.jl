# Routines related to downloading ICARE data and folder syncing with ICARE

"""
    ftp_download(
      user::String,
      password::String,
      product::String,
      startdate::Date,
      enddate::Date,
      version::Float64 = 4.20;
      dir::String = ".",
      savelog::String = "ICAREdownloads.log",
      warnlog::String = "ICAREwarnings.log",
      cleandata::Union{Nothing,Bool} = nothing,
      download::Bool = true,
      appendlog::Bool = false
    )

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

Download is monitored in `ICAREdownloads.log`; warnings of missing ICARE data
or additional local data files is given in `ICAREwarnings.log` (or the specified
alternative paths/names for the `savelog` and `warnlog` files). By default, new
log files are created for every run of `ftp_download`, but existing log files can
be appended, if `appendlog` is set to `true`.

If `download` is set to `false`, `ftp_download` only checks for available
additional data files on the ICARE server in the specified timeframe and reports
them in the `savelog` file. Furthermore, missing dates on ICARE or misplaced
files in the local directories are given in the `warnlog` file. Directories are
not synced with ICARE, and files are not downloaded. This option is available to
check your data coverage compared to the ICARE server.

If `ftp_download` is prematurely interrupted, you will be prompted to restart your
old session at the next call of `ftp_download`.
"""
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
  cleandata::Union{Nothing,Bool} = nothing,
  download::Bool = true,
  appendlog::Bool = false
)
  # Check for possible continuation of previous downloads from donwload session log
  prevsession = init_restart(savelog)
  # Define read/write access to log files based on appendlog
  rwa = appendlog || !isempty(prevsession) ? "a+" : "w+"

  if isempty(prevsession) # new download session
    # Scan for available files on ICARE server,
    # sync folder structure and find missing files to download
    remotefiles, localfiles, misplacedfiles = setup_download(user, password,
      product, startdate, enddate, version, rwa, dir=dir, warnlog=warnlog,
      download=download)
    # Create restart file
    CSV.write(splitext(savelog)[1]*".dsl",
      DataFrame(remote = remotefiles, home = localfiles))
    # Optionally delete misplaced files in local directories
    rm_misplacedfiles(misplacedfiles, cleandata)
  else # continue previous download session
    remotefiles, localfiles = eachcol(prevsession)
  end
  if download
    download_data(user, password, remotefiles, localfiles, savelog, rwa)
  else
    if isempty(remotefiles)
      open(savelog, rwa) do f
        println(f, "̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅")
        println(f, "No data available for download on ICARE\nin the specified timeframe.")

        println(f, "____________________________________________________________")
      end
    else
      open(savelog, rwa) do f
        println(f, "̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅")
        println(f, "Additional files available for download on ICARE:\n")
        foreach(file -> println(f, file), remotefiles)
        println(f, "____________________________________________________________")
      end
    end
  end
  rm(splitext(savelog)[1]*".dsl")
end #function ftp_download


"""
    setup_download(
      user::String,
      password::String,
      product::String,
      startdate::Date,
      enddate::Date,
      version::Float64 = 4.20,
      rwa::String = "w+";
      dir::String = ".",
      warnlog::String = "ICAREwarnings.log"
    ) -> remotefiles, localfiles, misplacedfiles

Connect to ICARE server with `user` login name and `password` and scan for available
files in the timeframe `startdate` to `enddate` for the `version` of the given `product`.
Sync the folder structure to the local `dir`ectory and warn of missing data folders
on the ICARE server or misplaced files in already existing local folders in the
`warnlog` file. Existing log files are overwritten unless read/write access of files
(`rwa`) is set to `"a+"`.

Returns a `Vector{String}` with absolute folder path and file names for remote
and local directory as well as for misplaced files in the local directories.
"""
function setup_download(
  user::String,
  password::String,
  product::String,
  startdate::Date,
  enddate::Date,
  version::Float64 = 4.20,
  rwa::String = "w+";
  dir::String = ".",
  warnlog::String = "ICAREwarnings.log",
  download::Bool=true
)
  # Start file logger
  logio = open(warnlog, rwa)
  logger = logg.SimpleLogger(logio, logg.Debug)
  # Connect to ICARE server
  ftp.ftp_init()
  icare = ftp.FTP(hostname = "ftp.icare.univ-lille1.fr",
    username = user, password = password)
  # Define main folder for selected data type
  caliopdir = "/SPACEBORNE/CALIOP/"
  datadir = @sprintf "%s.v%.2f" product version
  # Test connection and product name
  try cd(icare, caliopdir)
  catch
    @error "bad connection to ICARE server"
  end
  try cd(icare, joinpath(caliopdir, datadir))
  catch
    @error "incorrect product name or version number"
  end
  # Define dates in range
  years = [string(y) for y = Dates.year(startdate):Dates.year(enddate)]
  dates = [Dates.format(d, "yyyy_mm_dd") for d = startdate:Dates.Day(1):enddate]
  missingdates = String[]
  ## Sync data files
  remotefiles = String[]; localfiles = String[]; misplacedfiles = String[]
  prog = pm.Progress(length(dates), "setup...")
  for year in years, date in dates
    # Only look for dates with matching years
    startswith(date, year) || continue
    # Define current remote directory from date
    remotedir = joinpath(caliopdir, datadir, year, date)
    localdir = joinpath(dir, datadir, year, date)
    try
      # Get all data files in date range
      cd(icare, remotedir)
      remfiles = readdir(icare)
      # Sync local folder structure with ftp server
      if isdir(localdir)
        # Find additional (misplaced) files in local directory
        push!(misplacedfiles, joinpath.(localdir,
          setdiff(readdir(localdir)[.!startswith.(readdir(localdir), ".")],
          remfiles))...)
        # Remember missing files in local directory for download
        for file in remfiles
          if !isfile(joinpath(localdir, file))
            push!(remotefiles, joinpath(remotedir, file))
            push!(localfiles, joinpath(localdir, file))
          end
        end
      else
        # Create missing folders from remote directory in local directory
        download && mkpath(localdir)
        push!(remotefiles, joinpath.(remotedir, remfiles)...)
        push!(localfiles, joinpath.(localdir, remfiles)...)
      end
    catch err
      if isdir(remotedir)
        rethrow(err)
      else
        push!(missingdates, date)
        isdir(localdir) && push!(misplacedfiles, localdir)
      end
    end
    # Monitor progress for progress bar
    pm.next!(prog)
  end #loop over dates
  # Clean-up
  pm.finish!(prog)
  # Close FTP connection to ICARE server
  close(icare)
  ftp.ftp_cleanup()
  # Warn of misplaced files in log file
  isempty(missingdates) && isempty(misplacedfiles) || topline(logio, logger)
  logg.with_logger(logger) do
    if !isempty(missingdates)
      println(logio, "No available data for the following dates:")
      foreach(x -> println(logio, x), missingdates)
    end
    if !isempty(misplacedfiles)
      println(logio,
        "\nThe following misplaced files have been detected in local data folders:")
      foreach(x -> println(logio, x), misplacedfiles)
    end
  end
  isempty(missingdates) && isempty(misplacedfiles) || bottomline(logio, logger)
  close(logio)

  return remotefiles, localfiles, misplacedfiles
end #function setup_download


"""
    rm_misplacedfiles(misplacedfiles::Vector{String})

Delete `misplacedfiles`. The routine loops over `misplacedfiles` and deletes them
with the following confirmation options:

- `y`: current file is deleted
- `n`: current file deletion is skipped
- `all`: press at any time; __all files__ are deleted __even previously skipped files__
- `remaining`: the current and __all remaining files__ in the list are deleted;
  _previously skipped files are kept_
- `none`: __all remaining files__ are kept (previously deleted files are __not__ restored)
"""
function rm_misplacedfiles(misplacedfiles::Vector{String}, cleandata::Union{Nothing,Bool})
  # Skip if no misplaced files exist
  length(misplacedfiles) > 0 || return
  if cleandata == nothing
    # Warn of missing files and manually delete files depending on user input choice
    @warn "misplaced files in local data folders detected"
    # Loop over files and ask for deletion options
    for file in misplacedfiles
      println("Delete $file?")
      print("(y/n/remaining/all/none): ")
      confirm = readline()
      if startswith(lowercase(confirm), "y")
        # Delete current file
        rm(file, recursive=true)
      elseif lowercase(confirm) == "all"
        # Delete ALL files
        rm.(misplacedfiles, recursive=true)
        break
      elseif lowercase(confirm) == "remaining"
        # Delete REMAINING files
        i = findfirst(misplacedfiles.==file)
        rm.(misplacedfiles[i:end], recursive=true)
        break
      elseif lowercase(confirm) == "none"
        # DON'T delete REMAINING files
        break
      end
    end
  elseif cleandata
    # Delete all data, if cleandata flag is set
    rm.(misplacedfiles, recursive=true)
  end
end #function rm_misplacedfiles


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
  topline(logio, logger)
  # Connect to ICARE server
  ftp.ftp_init()
  icare = ftp.FTP(hostname = "ftp.icare.univ-lille1.fr",
    username = user, password = password)
  # Error on different remote and local file definitions
  length(remotefiles) ≠ length(localfiles) &&
    @error "Different number of local and remote files defined"
  # Loop over remotefiles and download to local machine as localfiles
  tstart = Dates.now()
  @pm.showprogress 5 "download..." for (rem, loc) in zip(remotefiles, localfiles)
    download(icare, rem, loc)
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
  bottomline(logio, logger)
  close(logio)
end #function download_data


topline(logio::IOStream, logger::logg.SimpleLogger) = logg.with_logger(logger) do
  println(logio, "̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅̅")
end


bottomline(logio::IOStream, logger::logg.SimpleLogger) = logg.with_logger(logger) do
  println(logio, "____________________________________________________________")
end
