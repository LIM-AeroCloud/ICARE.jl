## Routines related to syncing local and remote directories

# TODO function clean for removing files other than hdf and h5
# TODO function tidy to remove anything other than on the ICARE server

function clean(
    user::String,
    password::String,
    what::Symbol=:ask,
    hdfversion::UInt8=0x03;
    # product::String,
    # startdate::Int=-1,
    # enddate::Int=-1,
    # version::Float64 = 4.20,
    remoteroot::String = "/SPACEBORNE/CALIOP/",
    localroot::String = ".",
    # remoteext::String = ".hdf",
    logfile::String = "clean.log",
    loglevel::Symbol = :Debug
)::Nothing
    # Get connection to server, go to product folder on remote
    icare = connect(user, password, "", 0.0, remoteroot, "")
    # Create product folder, if not existent
    productfolder = set_localroot(localroot, icare.productfolder)
    # Start logging
    logfile, level = init_logging(logfile, productfolder, loglevel)
    open(logfile, "w") do logio
        logger = Logging.ConsoleLogger(logio, level, show_limited=false)
        Logging.with_logger(logger) do
        @info "downloading \"$product\" data, version $version to \"$productfolder\"" icare.productpath
        end
        # Read server data, if available
        inventory = product_database(icare, productfolder)
    end
end
