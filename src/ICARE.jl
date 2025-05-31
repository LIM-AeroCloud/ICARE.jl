"""
# Module ICARE

Module related to retrieving data from the AERIS/ICARE server (http://www.icare.univ-lille1.fr/).
Currently, the only exported function is `ftp_download` to retrieve missing
CALIOP data files in a specified time frame.
"""
module ICARE

# Import Julia Packages and Types
import SFTP
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

# ¡ TODO multi-threading !

# TODO routine to clean up h4 and/or h5 files
# TODO routine to clean up additional files (same with flags or different from above)
# * different levels of severity:
# - everything but hdf files
# - everything but specific (hdf/h5) hdf files
# - everything that is not matched with files on server
# - every hdf(4) that has not the same file size as on server (if hdf4)
# - everything that is older than files on server
# TODO search for missing files in present folders

# TODO function ignore to ignore folders and files for inventory
# TODO adds __IGNORE__ file to ignored inventory
# Alternative names: __KEEP__, __SAVE__
# // if filled with folders/files, only those are ignored
# TODO function list_inventory to show folder/file tree


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

# Include source files
include("download.jl") # routines related to syncing with ICARE
include("conversion.jl") # routines related to hdf4 > hdf5 conversion
# TODO include("sync.jl") # routines related to syncing local and remote directories

end #module ICARE
