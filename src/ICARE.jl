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
  # start file logger
  logio = open(logfile, "w+")
  logger = logg.SimpleLogger(logio, logg.Debug)
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
  end
  pm.finish!(prog)
  close(logio)

  return localfiles
end #function download

end #module ICARE
