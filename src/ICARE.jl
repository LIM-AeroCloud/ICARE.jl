"""
# Module ICARE

Module related to retrieving data from the AERIS/ICARE server (http://www.icare.univ-lille1.fr/).
Currently, the only exported function is `ftp_download` to retrieve missing
CALIOP data files in a specified time frame.
"""
module ICARE

# Import Julia Packages and Types
import FTPClient; const ftp = FTPClient
import ProgressMeter; const pm = ProgressMeter
import Logging; const logg = Logging
import Dates
import Dates: Date
import Printf: @sprintf
import CSV
import DataFrames; const df = DataFrames
import DataFrames: DataFrame

# Export functions
export ftp_download


# Include source files
include("download.jl") # routines related to syncing with ICARE
include("restart.jl")  # routines related to restarting a previous session

end #module ICARE
