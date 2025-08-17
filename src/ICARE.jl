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
import Logging
import OrderedCollections: OrderedDict
import Printf: @sprintf

# Export functions
export sftp_download, hdfupgrade

# Include source files
include("types.jl") # types and exceptions
include("inventory.jl") # routines related to the local inventory
include("download.jl") # routines related to syncing with ICARE
include("conversion.jl") # routines related to hdf4 > hdf5 conversion
# TODO include("sync.jl") # routines related to syncing local and remote directories

end #module ICARE
