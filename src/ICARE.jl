"""
# Module ICARE

Module related to retrieving data from the AERIS/ICARE server (http://www.icare.univ-lille1.fr/).
Currently, the only exported function is `ftp_download` to retrieve missing
CALIOP data files in a specified time frame.
"""
module ICARE

# Import Julia Packages and Types
import SFTP
import SFTP: Downloads.RequestError
import ProgressMeter as pm
import Dates
import Dates: Date, DateTime
import YAML
import LoggingExtras as logex
import DataStructures: SortedDict, OrderedDict
import Printf: @sprintf
import Base.Threads: @threads

# global constants
const Debug = Base.CoreLogging.Debug
const Info = Base.CoreLogging.Info
const Warn = Base.CoreLogging.Warn
const Error = Base.CoreLogging.Error

# global thread lock
const thread = ReentrantLock()

# Export functions and types
export sftp_download, convert_inventory, convert_inventory!, clean!, list_inventory, load_inventory,
    ignore!, unignore!, attach!, detach!, PrettyFileLogger, Extension, original, converted

# Include source files
include("types.jl") # types and exceptions
include("logging.jl") # routines related to logging
include("inventory.jl") # routines related to the local inventory
include("download.jl") # routines related to syncing with ICARE
include("conversion.jl") # routines related to hdf4 > hdf5 conversion
include("sync.jl") # routines related to syncing local and remote directories

end #module ICARE
