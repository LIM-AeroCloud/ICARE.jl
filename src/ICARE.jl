"""
# Module ICARE

Module related to retrieving data from the AERIS/ICARE server (http://www.icare.univ-lille1.fr/).
Currently only function `ftp_download` exists to retrieve missing CALIOP data files
in a specified timeframe.
"""
module ICARE

# Import Julia Packages and Types
import FTPClient; const ftp = FTPClient
import ProgressMeter; const pm = ProgressMeter
import Logging; const logg = Logging
import Dates
import Dates: Date
import Printf: @sprintf

export ftp_download

"""
    function ftp_download(
      user::String,
      password::String,
      product::String,
      startdate::Date,
      enddate::Date,
      version::Float64 = 4.20;
      dir::String = "."
    ) -> remotefiles

Download missing CALIOP hdf files of `product` type (e.g., `"05kmAPro"` or `"01kmCLay"`)
and `version` (e.g., `3.01` or `4.2`, default is `4.20`) from the ICARE server
using your `user` login name and `password`.

Data is downloaded for the specified time frame in the range `startdate` to `enddate`
to the local directory `dir`, where `dir` is the main folder containing the data folder
for `product` files. Folder structure in `dir` must be the same as on the ICARE server.

**Files are not synced, missing files are downloaded, but existing files are not checked
for file changes.**

Returns a `Vector{String}` with all the file names of the downloaded files.
"""
function ftp_download(
  user::String,
  password::String,
  product::String,
  startdate::Date,
  enddate::Date,
  version::Float64 = 4.20;
  dir::String = ".",
  logfile::String = "ftp_download.log"
)
  # Initialise
  logio = open(logfile, "w+")
  logger = logg.SimpleLogger(logio, logg.Debug)
  ftp.ftp_init()
  # Define main folder for selected data type
  caliopdir = "/SPACEBORNE/CALIOP/"
  datadir = @sprintf "%s.v%.2f" product version
  # Define dates in range
  years = [string(y) for y = Dates.year(startdate):Dates.year(enddate)]
  dates = [Dates.format(d, "yyyy_mm_dd") for d = startdate:Dates.Day(1):enddate]
  ## Sync data files
  localfiles = String[]
  prog = pm.Progress(length(dates), "download...")
  for year in years, date in dates
    # Only look for dates with matching years
    startswith(date, year) || continue
    # Define current remote directory from date
    remotedir = joinpath(caliopdir, datadir, year, date)
    try
      # Connect to ICARE server
      icare = ftp.FTP(hostname = "ftp.icare.univ-lille1.fr",
        username = user, password = password)
      # Get all data files in date range
      cd(icare, remotedir)
      remotefiles = readdir(icare)
      # Sync local folder structure with ftp server
      localdir = joinpath(dir, datadir, year, date)
      isdir(localdir) || mkpath(localdir)
      for file in remotefiles
        if !isfile(joinpath(localdir, file))
          download(icare, file, joinpath(localdir, file))
          push!(localfiles, file)
          # Log a task-specific message
          logg.with_logger(logger) do
            println(logio, file)
            println(logio, "-> download completed at $(Dates.now())")
          end
          flush(logio)
        end
      end
      # Close current FTP connection to ICARE server
      close(icare)
    catch err
      if isdir(remotedir)
        rethrow(err)
      else
        println("\n")
        @warn "no data for $date"
      end
    end
    # Monitor progress for progress bar
    pm.next!(prog, showvalues = [(:date,date)])
  end #loop over dates
  # Clean-up
  pm.finish!(prog)
  close(logio)
  ftp.ftp_cleanup()

  return localfiles
end #function download


"""
    setup_download(
      user::String,
      password::String,
      product::String,
      startdate::Date,
      enddate::Date,
      version::Float64 = 4.20;
      dir::String = ".",
      warnlog::String = "ICAREwarnings.log"
    ) -> remotefiles, localfiles, misplacedfiles

Connect to ICARE server with `user` login name and `password` and scan for available
files in the timeframe `startdate` to `enddate` for the `version` of the given `product`.
Sync the folder structure to the local `dir`ectory and warn of missing data folders
on the ICARE server or misplaced files in already existing local folders in the
`warnlog` file.

Returns a `Vector{String}` with absolute folder path and file names for remote
and local directory as well as for misplaced files in the local directories.
"""
function setup_download(
  user::String,
  password::String,
  product::String,
  startdate::Date,
  enddate::Date,
  version::Float64 = 4.20;
  dir::String = ".",
  warnlog::String = "ICAREwarnings.log"
)
  # Start file logger
  logio = open(warnlog, "w+")
  logger = logg.SimpleLogger(logio, logg.Debug)
  # Connect to ICARE server
  ftp.ftp_init()
  icare = ftp.FTP(hostname = "ftp.icare.univ-lille1.fr",
    username = user, password = password)
  # Define main folder for selected data type
  caliopdir = "/SPACEBORNE/CALIOP/"
  datadir = @sprintf "%s.v%.2f" product version
  # Define dates in range
  years = [string(y) for y = Dates.year(startdate):Dates.year(enddate)]
  dates = [Dates.format(d, "yyyy_mm_dd") for d = startdate:Dates.Day(1):enddate]
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
        mkpath(localdir)
        push!(remotefiles, joinpath.(remotedir, remfiles)...)
        push!(localfiles, joinpath.(localdir, remfiles)...)
      end
    catch err
      if isdir(remotedir)
        rethrow(err)
      else
        logg.with_logger(logger) do
          println(logio, "no data for $date")
        end
        flush(logio)
        isdir(localdir) && push!(misplacedfiles, localdir)
      end
    end
    # Monitor progress for progress bar
    pm.next!(prog, showvalues = [(:date,date)])
  end #loop over dates
  # Clean-up
  pm.finish!(prog)
  # Close current FTP connection to ICARE server
  close(icare)
  ftp.ftp_cleanup()
  # Warn of misplaced files in log file
  length(misplacedfiles) > 0 && logg.with_logger(logger) do
    println(logio, "\nThe following misplaced files have been detected in local data folders:")
    foreach(x -> println(logio, x), misplacedfiles)
  end
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
function rm_misplacedfiles(misplacedfiles::Vector{String})
  length(misplacedfiles) > 0 && @warn "misplaced files in local data folders detected"
  for file in misplacedfiles
    println("Delete $file?")
    print("(y/n/remaining/all): ")
    confirm = readline()
    if startswith(lowercase(confirm), "y")
      rm(file, recursive=true)
    elseif lowercase(confirm) == "all"
      rm.(misplacedfiles, recursive=true)
      break
    elseif lowercase(confirm) == "remaining"
      i = findfirst(misplacedfiles.==file)
      rm.(misplacedfiles[i:end], recursive=true)
      break
    elseif lowercase(confirm) == "none"
      break
    end
  end
end

end #module ICARE
