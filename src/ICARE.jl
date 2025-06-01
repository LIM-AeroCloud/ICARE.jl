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
import Bits: bits
import ProgressMeter as pm
import Dates
import Dates: Date
import Printf: @sprintf
import YAML
import Logging
import OrderedCollections: OrderedDict

# Export functions
export sftp_download, hdfupgrade, pwd, readdir


"""
    __init__()

Called at the beginning of loading the module. Will create a tools folder in the
home dir with the h4toh5 conversion tool and add the tool to the PATH.
"""
function __init__()::Nothing
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

# Include source files
include("download.jl") # routines related to syncing with ICARE
include("conversion.jl") # routines related to hdf4 > hdf5 conversion
# TODO include("sync.jl") # routines related to syncing local and remote directories

end #module ICARE
