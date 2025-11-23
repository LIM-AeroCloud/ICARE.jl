"""
# Module ICARE

Module related to retrieving data from the AERIS/ICARE server (http://www.icare.univ-lille1.fr/).
Currently, the only exported function is `ftp_download` to retrieve missing
CALIOP data files in a specified time frame.
"""
module ICARE

## Import Julia Packages and Types
# Distributed work
using Distributed
import Base.Threads: @threads
# File processing and transfer
import SFTP
import SFTP: Downloads.RequestError
import YAML
import DataStructures: SortedDict, OrderedDict
# Display and Logging
import ProgressMeter as pm
import Printf: @sprintf
import Logging
# Date and Time handling
import Dates
import Dates: Date, DateTime


## Setup package
# global thread lock
const thread = ReentrantLock()

# Initialize workers with package environment
function __init__()
    # Activate package environment on all workers (silently)
    pkg_dir = joinpath(@__DIR__, "..")
    @sync for p in workers()
        @async remotecall_wait(Core.eval, p, Main, :(import Pkg; Pkg.activate($pkg_dir, io=devnull)))
    end
    # Load required packages on all workers
    @sync for p in workers()
        @async remotecall_wait(Core.eval, p, Main, quote
            import SFTP
            import DataStructures: SortedDict, OrderedDict
            import Logging
            import Dates
            import Dates: Date, DateTime
        end)
    end
end

# Export functions
export sftp_download, hdfupgrade

## Include source files
include("types.jl") # types and exceptions
include("inventory.jl") # routines related to the local inventory
include("download.jl") # routines related to syncing with ICARE
include("conversion.jl") # routines related to hdf4 > hdf5 conversion
# TODO include("sync.jl") # routines related to syncing local and remote directories

end #module ICARE
