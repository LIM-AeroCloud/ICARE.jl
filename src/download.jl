## Routines related to downloading ICARE data and folder syncing with ICARE

## API functions
#* Main function for download from server
"""
    sftp_download(
        user::String,
        password::String,
        product::String,
        startdate::Int,
        enddate::Int=-1;
        version::Union{Nothing,Real} = 5,
        remoteroot::String = "/SPACEBORNE/CALIOP/",
        localroot::String = ".",
        converter::Union{Nothing,String} = "",
        resync::Bool = false,
        update::Bool = false,
        logfile::String = "downloads.log",
       loglevel::Symbol = :Debug
   )

Download satellite data from the Aeris/ICARE server.

To use `sftp_download`, an Aeris/ICARE account is needed that is available for free at
https://www.icare.univ-lille.fr.

# Positional arguments

- `user::String`/`password::String`: Aeris/ICARE account credentials
- `product::String`: The desired product to download (matches the folder name
  excluding the version number, e.g., `05kmCPro`)
- `startdate::Int`/`enddate::Int`: The start/end date for the download period as `Int`
  (format: `yyyy[mm[dd]]`);

In the dates, the day and month part can be omitted. In this case, the earliest possible start
date is selected and the latest possible end date, e.g. `202003` will give a start date of
`2020-03-01` and an end date of `2020-03-31`. The end date is optional, if omitted, the period
defined by `startdate` is downloaded, either a day, or a month (if the day part is omitted)
or a year (if both day and month are omitted).

# Keyword arguments

- `version::Union{Nothing,Real}`: The version number of the product (default: `4.51`).
- `remoteroot::String`: The root path on the remote server (default: `"/SPACEBORNE/CALIOP/"`).
- `localroot::String`: The root path on the local machine (default: `"."`).
- `converter::Union{Nothing,String}`: The converter to use for the downloaded files (default: `""`).
- `resync::Bool`: Whether to re-synchronize the local inventory with the remote server (default: `false`).
- `update::Bool`: Whether to update the local files if newer versions are available
  on the remote server (default: `false`).
- `logfile::String`: The name of the log file (default: `"downloads.log"`; the name will be appended
  by the current date and time).
- `loglevel::Symbol`: The log level for the download process (default: `:Debug`).

For maximum flexibility to donwload formats ICARE.jl is not intended to, the `version` can be
set to `nothing`. Use the `product` positional argument to define the whole name of the product
folder. By default, the product folder is constructed as `<product>.v<X.XX>` with the version as
float with two decimal places independent of the input format.

Bu default, hdf files (version 4) are assumed as download source, which will be converted to
`.h5` (HDF5) files. The `converter` kwarg allows you to specify the path to a personalised
conversion script to manage other file formats. If, `converter` is set to `nothing`, files
will be downloaded from the ICARE server and the original file format is kept.

# The local inventory

The first time, a `product` is downloaded, a product folder is created with an `inventory.yaml`
in the `localroot` that holds all information about the folder and file structure.
The creation of the inventory will take several minutes. After the initial sync, the inventory
will be updated automatically during subsequent downloads only appending new data unless
the `resync` option is used, which will force the inventory to be rebuilt from scratch.

The `update` option can be used to update downloaded files with more recent data from the server,
but the inventory will have to be resynced, which will take a considerable time.
"""
function sftp_download(
    user::String,
    password::String,
    product::String,
    startdate::Int,
    enddate::Int=-1;
    version::Union{Nothing,Real} = 4.51,
    remoteroot::String = "/SPACEBORNE/CALIOP/",
    localroot::String = ".",
    converter::Union{Nothing,String} = "",
    resync::Bool = false,
    update::Bool = false,
    logfile::String = "downloads.log",
    loglevel::Symbol = :Debug
)::Nothing
    ## Setup
    # Create product folder, if not existent
    product = isnothing(version) ? product : @sprintf("%s.v%.2f", product, version)
    productpath = set_localroot(localroot, product)
    # Convert integer dates to dates
    startdate, enddate = convertdates(startdate, enddate)
    daterange = (start = startdate, stop = enddate)
    # Enforce database updatee, if file update is selected
    resync |= update
    #* Start logging
    logfile, level = init_logging(logfile, productpath, loglevel)
    @info "logging to '$logfile'"
    open(logfile, "w") do logio
        logger = Logging.ConsoleLogger(logio, level, show_limited=false)
        Logging.with_logger(logger) do
            @info "downloading '$product' data to '$productpath'"
        end
        #* Syncing local and remote database
        # Get connection to server, go to product folder on remote
        ts = Dates.now()
        Logging.with_logger(logger) do
            @info "initialising databse @$ts"
        end
        icare = icare_connect(user, password, remoteroot, product, logger)
        # ℹ Make inventory available for catch block
        inventory = OrderedDict{String,Any}()
        # Get available server dates
        try
            product_database!(icare, inventory, localroot, product, daterange, resync, logger)
            Logging.with_logger(logger) do
                te = Dates.now()
                @info "setup of database completed in $(Dates.canonicalize(te - ts))) @$te"
            end
        catch error
            Logging.with_logger(logger) do
                @error "failed to load local inventory" error
            end
            save_inventory(inventory, ts)
            return
        end
        # Log download session
        t0 = Dates.now()
        Logging.with_logger(logger) do
            not = resync ? "" : " not"
            @info "starting up to $(Threads.nthreads()) parallel downloads @$(t0)"
            @info "files will$not be updated, if newer files are available on the server"
            flush(logio)
        end

        ## Download
        #* Download missing data from server
        @info "downloading data from ICARE server"
        @info("up to $(Threads.nthreads()) parallel downloads available\n"*
            "start julia with `julia -t <number>` to change `<number>` of parallel downloads")
        counter = Counter()
        # Match folder structure with server
        try sync!(icare, inventory, daterange, converter, update, resync, logger, logio, counter)
        finally
            #* Log end of download session and save inventory
            save_inventory(inventory, t0)
            log_counter(counter, logger, logio, t0)
            @info "download session closed"
        end
    end #logging to file
end #function ftp_download


## Functions for syncing with server and setting up a local structure, and

"""
    icare_connect(
        user::String,
        password::String,
        root::String,
        product::String
    ) -> SFTP.Client

Securely connect to the server with SFTP using the credentials `user` and `password`
and changing to the `product` folder in the `root` directory.

Several checks are performed about the connection and folder structure and a
`SFTP.Client` type with all the relevant information about the server is returned.
"""
function icare_connect(
    user::String,
    password::String,
    root::String,
    product::String,
    logger::Logging.ConsoleLogger,
    __counter__::Int=0
)::SFTP.Client
    # Connect to server and go to root of selected data
    wait = 60
    icare = SFTP.Client("sftp://sftp.icare.univ-lille.fr", user, password)
    try cd(icare, root)
    catch error
        if error isa RequestError && error.code == 6
            if __counter__ == 5
                Logging.with_logger(logger) do
                    @error "failed to connect to ICARE server; abort downloads"
                end
                throw(ConnectionError("failed to connect to ICARE server 5 times"))
            else
                __counter__ += 1
                @warn "failed to connect to server; attempting again in $wait seconds"
                # Wait a minute, then reconnect
                sleep(wait)
                icare_connect(user, password, root, product, logger, __counter__)
                cd(icare, root) # ℹ Needed so that the icare uses the root path after recursive calls
            end
        elseif error isa RequestError && error.code == 9
            Logging.with_logger(logger) do
                @warn "remote root not verified"
            end
            @warn("unable to verify remote root due to restricted access of parent folder",
                _module=nothing, _file=nothing, _line=nothing)
            icare.uri = SFTP.URI(icare.uri, path=root)
        elseif error isa RequestError && error.code == 67
            Logging.with_logger(logger) do
                @error "unable to connect to server; check user credentials"
            end
            throw(Base.IOError("could not connect to ICARE server; check user name and password", Integer(SFTP.EC_DIR_NOT_FOUND)))
        else
            Logging.with_logger(logger) do
                @error "unknown connection error when trying to connect to ICARE server"
            end
            rethrow(error)
        end
    end

    # Go to product main folder
    try cd(icare, product)
    catch
        throw(Base.IOError("incorrect product name or version number", 2))
    end
    return icare
end


"""
    set_localroot(localroot::String, mainfolder::String) -> String

Define the product folder on the local system from the `localroot` and the `mainfolder`
containing all the year folders for the ICARE data.
"""
function set_localroot(localroot::String, mainfolder::String)::String
    productpath = joinpath(localroot, mainfolder)
    if !isdir(localroot)
        # Confirm to create non-exiting local root
        @warn "root directory $localroot does not exist" _module=nothing _file=nothing _line=nothing
        print("Create? (y/n) ")
        create = readline()
        if startswith(lowercase(create), "y")
            mkpath(productpath)
        else
            throw(Base.IOError("path for local root and/or product folder does not exist; create path and restart ftp_download", 1))
        end
    else
        # Make sure product folder exists, if localroot already exists
        mkpath(productpath)
    end
    # Change to productpath and return absolute path as String
    return realpath(productpath)
end


"""
    convertdates(startdate::Int, enddate::Int) -> startdate::Date, enddate::Date

Convert `startdate` and `enddate` from `Int` to `Date`.
If the day and/or month in `startdate` are missing, `startdate` is completed with
the earliest possible date (day = `01` and month = `01`).
If the day and/or month in `enddate` are missing, `enddate` is completed with
the latest possible date (month = `12` and day = last day of that month).
"""
function convertdates(startdate::Int, enddate::Int)::Tuple{Date,Date}
    enddate > 0 || (enddate = startdate)
    startdate = Date(string(startdate), "yyyymmdd")
    enddate = string(enddate)
    enddate = if length(enddate) == 8
        Date(enddate, "yyyymmdd")
    else
        Dates.lastdayofmonth(Date(enddate*"12", "yyyymmdd"))
    end

    return startdate, enddate
end


## Function for sftp download

"""
    sync!(
        icare::SFTP.Client,
        inventory::OrderedDict,
        daterange::@NamedTuple{start::Date, stop::Date},
        converter::String,
        update::Bool,
        resync::Bool,
        logger::Logging.ConsoleLogger,
        logio::IO,
        counter::Counter
    )

Synchronize the files for the selected `daterange` from the `icare` server with the local system.
Use the `converter` to change the file format.
If set, `update` files to the latest version available on the server. Dates and files are
compared to the `inventory` and the `inventory` is updated, if necessary.
Increase the respective counter for each sync action and log `logger` events to a log file
in the `logio` I/O stream.
"""
function sync!(
    icare::SFTP.Client,
    inventory::OrderedDict,
    daterange::@NamedTuple{start::Date, stop::Date},
    converter::Union{Nothing,String},
    update::Bool,
    resync::Bool,
    logger::Logging.ConsoleLogger,
    logio::IO,
    counter::Counter
)::Nothing
    #* Define all files for download
    converter = converterpath(converter)
    dates = inventory["dates"].keys |> filter(d -> daterange.start ≤ d ≤ daterange.stop)
    files = vcat([File.(Ref(icare), Ref(inventory), date, inventory["dates"][date].keys, converter)
        for date in dates]...)
    Logging.with_logger(logger) do
        if isempty(converter)
            @info "no file conversion after download"
        else
            @info "file conversion to new format for all downloads" converter
        end
    end

    prog = pm.Progress(length(files), desc="downloading...")
    @threads for file in files
        #* Check for previous downloads
        if downloaded(inventory, file, update)
            lock(thread) do
                #* Log skipped files
                Logging.with_logger(logger) do
                    @debug "skipping $(file.name), already downloaded" _module=nothing _file=nothing _line=nothing
                end
                counter.skipped += 1
                flush(logio)
            end
            pm.next!(prog)
            continue
        end
        t0 = Dates.now()
        orig = isfile(file.location.download)
        #* Download file and optionally convert to another format
        try
            download(icare, inventory, file, update)
            convert!(inventory, file, converter, logger)
        catch error
            lock(thread) do
                #* Log download errors
                Logging.with_logger(logger) do
                    @error "failed to download $(file.name)" error _module=nothing _file=nothing _line=nothing
                end
            end
        end
        #* Error handling/Re-download, if unsuccessful
        if !downloaded(inventory, file, update)
            # Check connection to ICARE server
            lock(thread) do
                icare = icare_connect(icare.username, icare.password, inventory["metadata"]["server"]["root"],
                    inventory["metadata"]["server"]["product"], logger)
            end
            # Check for correct server-side file stats
            update_stats!(icare, inventory, file, resync, logger)
            try
                download(icare, inventory, file, update)
                convert!(inventory, file, converter, logger)
            catch error
                lock(thread) do
                    #* Log second download attempt errors
                    Logging.with_logger(logger) do
                        @error("Second download attempt failed for $(file.name); no further attempts",
                            error, _module=nothing, _file=nothing, _line=nothing)
                    end
                end
                lock(thread) do
                    counter.failed += 1
                end
                throw(@error("Second download attempt failed for $(file.name); no further attempts",
                    error, _module=nothing, _file=nothing, _line=nothing))
            end
        end
        #* Clean-up
        if downloaded(inventory, file, update)
            # Remove original downloads unless no conversion is selected or original file already existed
            orig &= filesize(file.location.download) == inventory["dates"][file.date][file.name]["size"]
            isempty(converter) || orig || rm(file.location.download, force=true)
            # Log download success
            t1 = Dates.now()
            if orig
                lock(thread) do
                    counter.conversions += 1
                    Logging.with_logger(logger) do
                        @debug("$(file.name) already downloaded; converted in $(Dates.canonicalize(t1 - t0)) @$t1",
                            _module=nothing, _file=nothing, _line=nothing)
                    end
                end
            else
                lock(thread) do
                    # Log successful downloads
                    counter.downloads += 1
                    Logging.with_logger(logger) do
                        @debug("downloaded $(file.name) in $(Dates.canonicalize(t1 - t0)) @$t1",
                            _module=nothing, _file=nothing, _line=nothing)
                    end
                end
            end
        end
        lock(thread) do
            flush(logio)
        end
        pm.next!(prog) # Update progress meter
    end # loop over files
    pm.finish!(prog)
end


"""
    download!(
        icare::SFTP.Client,
        inventory::OrderedDict,
        file::File,
        update
    )

Download the `file` from the `icare` server and update the `inventory`.
Only download newer files on the server, if `update` is set to `true`.
"""
function download(
    icare::SFTP.Client,
    inventory::OrderedDict,
    file::File,
    update
)::Nothing
    downloaded(inventory, file, update, true) && return
    SFTP.download(icare, file.location.remote, file.dir.dst, force=true)
    return
end


"""
    downloaded(
        inventory::OrderedDict,
        file::File,
        update::Bool,
        orig::Bool=false
    ) -> Bool

Check, whether the `file.target` has already been downloaded from the server to the local
directory by comparing it to the `filestats` of the remote server in the `inventory`. If `update`
is set, downloaded returns `false`, if newer versions of the `file` exist on the server.
When `orig` is set to `true`, downloaded checks against the downloaded instead of the target file.
"""
function downloaded(
    inventory::OrderedDict,
    file::File,
    update::Bool,
    orig::Bool=false
)::Bool
    filestats = inventory["dates"][file.date][file.name]
    # Check, if file exists (orig: checks download of original file from server, not converted file)
    file = orig ? file.location.download : file.location.target
    isfile(file) || return false
    # Get file stats and type
    localstats = stat(file)
    size = if splitext(file)[2] == ".h5" && inventory["metadata"]["file"]["ext"] ≠ ".h5" # h5 converted files
        # ℹ Compare h5 size or return false for unknown h5 size in inventory
        haskey(filestats, "converted") && (localstats.size == filestats["converted"])
    else # original file from server
        localstats.size == filestats["size"]
    end
    # Compare stats
    size || return false
    # Check, if newer files are available on the server
    (update && (Date∘Dates.unix2datetime)(localstats.mtime) < filestats["mtime"]) && return false
    # Return true, if all checks passed
    return true
end


"""
    convert!(
        inventory::OrderedDict,
        file::File,
        converter::String,
        logged::Logging.ConsoleLogger
    )

Convert the `file` to a new file format using the `converter` script unless `file` is already
up-to-date. Log events to `logger`.
"""
function convert!(
    inventory::OrderedDict,
    file::File,
    converter::String,
    logger::Logging.ConsoleLogger
)::Nothing
    converted!(inventory, file, converter) && return
    rm(file.location.target, force=true)
    run(`julia $converter $(file.location.download)`)
    set_converted_size!(inventory, file, logger)
end


"""
    converted!(inventory::OrderedDict, file::File, converter::String) -> Bool

Check, whether the size of the converted `file` is known in the `data` dictionary and matches the
actual file size. Return also `true`, if no `converter` is selected.
"""
function converted!(inventory::OrderedDict, file::File, converter::String)::Bool
    if haskey(inventory["dates"][file.date][file.name], "converted")
        # Compare file size with inventory
        inventory["dates"][file.date][file.name]["converted"] == filesize(file.location.target)
    else
        return isempty(converter)
    end
end


"""
    set_converted_size!(
        inventory::OrderedDict,
        file::File,
        logger::Logging.ConsoleLogger
    )

Set the size of the converted `file` in the `inventory` and mark the `inventory` as updated.
Log events to `logger`.
"""
function set_converted_size!(
    inventory::OrderedDict,
    file::File,
    logger::Logging.ConsoleLogger
)::Nothing
    # Initial checks
    haskey(inventory["dates"][file.date][file.name], "converted") && return
    if !isfile(file.location.target)
        lock(thread) do
            # Log error, if converted file does not exist
            Logging.with_logger(logger) do
                @error("cannot determine size of '$(file.location.target)'",
                    _module=nothing, _file=nothing, _line=nothing)
            end
        end
        return
    end
    # Save converted file size to inventory
    lock(thread) do
        inventory["dates"][file.date][file.name]["converted"] = filesize(file.location.target)
        inventory["metadata"]["database"]["updated"] = Dates.now()
    end
    return
end


"""
    converterpath(converter::Union{Nothing,String}) -> String

Return the path to the converter script for file format conversion.
If `converter` is `nothing`, return an empty string.
If `converter` is an empty string, return the default path to the converter script.
If `converter` is a string, return it or throw an error for invalid paths.
"""
function converterpath(converter::Union{Nothing,String})::String
    if isnothing(converter)
        ""
    elseif isempty(converter)
        realpath(joinpath(@__DIR__, "..", "data", "h4toh5.jl"))
    else
        realpath(converter)
    end
end


## Functions for logging

"""
    log_counter(counter::Counter, logger::Logging.ConsoleLogger, t0::DateTime)

Log the number of downloaded, skipped, and converted files saved in `counter` to `logger`
together with the time it took since `t0`.
"""
function log_counter(counter::Counter, logger::Logging.ConsoleLogger, logio::IO, t0::DateTime)::Nothing
    t1 = Dates.now()
    Logging.with_logger(logger) do
        if counter.downloads > 0
            s = counter.downloads == 1 ? "" : "s"
            @info "$(counter.downloads) file$s downloaded in $(Dates.canonicalize(t1-t0)) @$(t1)"
        end
        if counter.conversions > 0
            s = counter.conversions == 1 ? " was" : "s were"
            @info "$(counter.conversions) file$s already downloaded and converted to a new file format"
        end
        if counter.skipped > 0
            s = counter.skipped == 1 ? " was" : "s were"
            @info "$(counter.skipped) file$s already previously downloaded"
        end
        if counter.failed > 0
            s = counter.failed == 1 ? "" : "s"
            @info "$(counter.failed) file$s failed to download"
        end
        flush(logio)
    end
end
