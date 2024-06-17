"""
# Module ICARE

Module related to retrieving data from the AERIS/ICARE server (http://www.icare.univ-lille1.fr/).
Currently, the only exported function is `ftp_download` to retrieve missing
CALIOP data files in a specified time frame.
"""
module ICARE

# Import Julia Packages and Types
import SFTPClient as sftp
import SFTPClient: SFTP
import Bits: bits
import ProgressMeter as pm
import Dates
import Dates: Date
import Printf: @sprintf
import YAML
import Logging
import DataStructures as data
import DataStructures: SortedDict

# Export functions
export sftp_download, hdfupgrade, pwd, readdir

# ¡ TODO multi-threading
# TODO routine to clean up h4 and/or h5 files
# TODO routine to clean up additional files (same with flags or different from above)
# * different levels of severity:
# - everything but hdf files
# - everything that is not matched with files on server
# - every hdf(4) that has not the same file size as on server (if hdf4)
# - everything that is older than files on server
# solution ✅ to long comparisons with server: inventory.yaml in each product folder
# TODO logging


"""
    __init__()

Called at the beginning of loading the module. Will create a tools folder in the
home dir with the h4toh5 conversion tool and add the tool to the PATH.
"""
function __init__()
  # Define dir for conversion tool and exe name and add to $PATH
  bindir = joinpath(homedir(), "tools")
  exec = joinpath(bindir, "h4toh5")
  if !contains(ENV["PATH"], bindir)
    @info "adding '$bindir' to PATH for current julia session"
    @info "add '$bindir' to PATH and export PATH in your rc-file to persistently use h4toh5 conversion from anywhere in the terminal"
    (ENV["PATH"] *= ":" * bindir)
  end
  if !isfile(exec)
    mkpath(bindir)
    if Sys.islinux()
      cp(joinpath(@__DIR__, "../data", "h4toh5_linux"), exec)
    elseif Sys.isapple()
      cp(joinpath(@__DIR__, "../data", "h4toh5_mac"), exec)
    else
      throw(SystemError("ICARE is only available for Linux and Mac"))
    end
    chmod(exec, 0o777)
    @info "created '~/tools/h4toh5' for hdf4 to hdf5 conversion"
    @info "'~/tools/' added to \$PATH for current julia session"
  end
end

__init__()


"""
    struct DataStorage

Holds the folders for a year to replicate the remote folder structure. The `start`
and `stop` date must be of the same year.

# Fields

`year::String` holding the year in the format `yyyy`

`dates::Vector{String}` holding all dates in the format `yyyy_mm_dd`

# Constructor

    DataStorage(start::Date, stop::Date)

Construct a `DataStorage` struct between the `start` and the `stop` date.
Missing dates on the remote server can be deleted at a later point.
"""
struct DataStorage
  year::String
  dates::Vector{String}

  function DataStorage(start::Date, stop::Date)
    if Dates.year(start) ≠ Dates.year(stop)
      @error "start end stop year must be equal" start stop
    end
    new(Dates.format(start, "yyyy"), [Dates.format(y,"yyyy_mm_dd") for y = start:Dates.Day(1):stop])
  end
end


"""
    struct Connection

Holds the connection to the server and relevant information about the folder structure.

# Constructor

    Connection(server::SFTP, root::String, productfolder::String, extension::String=".hdf")

Construct a `Connection` to the product folder from the `SFTP` connection to the server
as well as the `root` path, the `productfolder`, and the `extension` of the data files
stored at the server.

# Fields

`server::SFTP` connection to the server
`root::String` root path
`productfolder::String` product folder contained in root
`productpath::String` complete path to product folder
`extension::String` extension of data files on the server
"""
struct Connection
  server::SFTP
  root::String
  productfolder::String
  productpath::String
  extension::String

  function Connection(server::SFTP, root::String, productfolder::String, extension::String=".hdf")
    new(server, root, productfolder, joinpath(root, productfolder), extension)
  end
end

# Include source files
include("download.jl") # routines related to syncing with ICARE
include("conversion.jl") # routines related to hdf4 > hdf5 conversion

end #module ICARE
