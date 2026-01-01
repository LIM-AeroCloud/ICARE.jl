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
        version::Union{Nothing,Real} = 4.51,
        remoteroot::String = "/SPACEBORNE/CALIOP/",
        localroot::String = ".",
        convert::Bool = true,
        resync::Bool = false,
        update::Bool = false,
        logfile::String = "downloads.log",
        loglevel::Symbol = :Debug
    ) -> SortedDict

Download satellite data from the Aeris/ICARE server. The function returns a dictionary with
the inventory of available online data for the given product.

!!! note
    To use `sftp_download`, an [Aeris/ICARE account](https://www.icare.univ-lille.fr) is needed
    that is available for free for non-commercial use.

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

See also: [`list_inventory`](@ref), [`convert!`](@ref), [`convert(::AbstractString)`](@ref),
[`ignore!`](@ref), [`unignore!`](@ref), [`clean!`](@ref)

# Keyword arguments

- `version::Union{Nothing,Real}`: The version number of the product (default: `4.51`).
- `remoteroot::String`: The root path on the remote server (default: `"/SPACEBORNE/CALIOP/"`).
- `localroot::String`: The root path on the local machine containing the product folder (default: `"."`).
- `convert::Bool`: Whether or not to convert the downloaded files to another file format (default: `true`).
- `resync::Bool`: Whether to re-synchronize the local inventory with the remote server (default: `false`).
- `update::Bool`: Whether to update the local files if newer versions are available
  on the remote server (default: `false`). Converted file sizes will be deleted for any updates.
- `logfile::String`: The name of the log file (default: `"downloads.log"`; the name will be appended
  by the current date and time).
- `loglevel::Symbol`: The log level for the download process (default: `:Debug`).

!!! warning
    The `update` option automatically resynchronises the inventory as well.

    Re-synchronisation of the inventory will take several minutes up to hours!

For custom version formats, the `version` can be set to `nothing` and included in the `product`
string. By default, the product folder is constructed as `<product>.v<X.XX>` with the version as
float with two decimal places independent of the input format.

By default, hdf files (version 4) are assumed as download source, which will be converted to
`.h5` (HDF5) file unless `convert` is set to `false`.
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
    convert::Bool = true,
    resync::Bool = false,
    update::Bool = false,
    logfile::String = "downloads.log",
    loglevel::Symbol = :Debug
)::SortedDict
    ## Setup
    # Save original parameters for logging
    prod, start, stop, resynchronisation = product, startdate, enddate, resync
    # Create product folder, if not existent
    product = isnothing(version) ? product : @sprintf("%s.v%.2f", product, version)
    productpath = set_localroot(localroot, product)
    # Convert integer dates to dates
    startdate, enddate = convertdates(startdate, enddate)
    daterange = (start = startdate, stop = enddate)
    # Enforce database update, if file update is selected
    resync |= update
    #* Start logging
    logger = init_logging(logfile, productpath, loglevel)
    logex.with_logger(logger.file) do
        range = daterange.start == daterange.stop ? daterange.start :
            string(daterange.start, " – ", daterange.stop)
        @info "downloading '$product' data to '$(realpath(localroot))' for $range"
        @debug("parameters", product=prod, version=version, startdate=start, enddate=stop,
            remoteroot=remoteroot, localroot=localroot, convert=convert,
            resync=resynchronisation, update=update, loglevel=loglevel)
    end
    #* Syncing local and remote database
    # Get connection to server, go to product folder on remote
    ts = Dates.now()
    logex.with_logger(logger.file) do
        @info "initialising database @$ts"
    end
    icare = icare_connect(user, password, remoteroot, product, logger.tee)
    # ℹ Make inventory available for catch block
    inventory = SortedDict()
        # Get available server dates
        try
            product_database!(icare, inventory, localroot, product, daterange, convert, resync, logger)
            logex.with_logger(logger.file) do
                te = Dates.now()
                @info "setup of database completed in $(Dates.canonicalize(te - ts))) @$te"
            end
        catch error
            logex.with_logger(logger.tee) do
                @error "failed to load local inventory" exception=(error, catch_backtrace())
            end
            data_gaps!(inventory)
            close(logger.file.logger.stream)
            return inventory
        finally
            # Ensure that inventory is saved even in case of errors
            save_inventory(inventory, logger.tee, ts)
        end
    # Log download session
    t0 = Dates.now()
    @info("starting up to $(Threads.nthreads()) parallel downloads\n"*
        "start julia with `julia -t <number>` to change the `<number>` of parallel downloads")
    logex.with_logger(logger.file) do
        @info "starting up to $(Threads.nthreads()) parallel downloads @$(t0)"
    end

    ## Download
    #* Download missing data from server
    counter = Counter()
    # Match folder structure with server
    try
        sync!(icare, inventory, daterange, convert, update, resync, logger, counter)
    catch error
        logex.with_logger(logger.tee) do
            @error "failed to sync with ICARE server" exception=(error, catch_backtrace())
        end
    finally
        #* Log end of download session and save inventory
        save_inventory(inventory, logger.tee, ts)
        log_counter(counter, logger.tee, t0)
        close(logger.file.logger.stream)
        @info "download session closed, see log file for details"
        # Return inventory for further investigation after download
        return inventory
    end
end #function ftp_download


## Functions for syncing with server and setting up a local structure

"""
    icare_connect(
        user::String,
        password::String,
        root::String,
        product::String,
        logger::logex.AbstractLogger
    ) -> SFTP.Client

Securely connect to the server with SFTP using the credentials `user` and `password`
and changing to the `product` folder in the `root` directory.

Several checks are performed about the connection and folder structure and a
`SFTP.Client` type with all the relevant information about the server is returned.
Connection issues are logged to `logger`.
"""
function icare_connect(
    user::String,
    password::String,
    root::String,
    product::String,
    logger::logex.AbstractLogger,
    __counter__::Int=0
)::SFTP.Client
    # Connect to server and go to root of selected data
    wait = 60
    icare = SFTP.Client("sftp://sftp.icare.univ-lille.fr", user, password)
    try cd(icare, root)
    catch error
        if error isa RequestError && error.code == 6
            if __counter__ == 5
                logex.with_logger(logger) do
                    @error "failed to connect to ICARE server; abort downloads"
                end
                throw(ConnectionError("failed to connect to ICARE server 5 times"))
            else
                __counter__ += 1
                logex.with_logger(logger) do
                    @warn "failed to connect to ICARE server; attempting again in $wait seconds"
                end
                # Wait a minute, then reconnect
                sleep(wait)
                icare_connect(user, password, root, product, logger, __counter__)
                cd(icare, root) # ℹ Needed so that the icare uses the root path after recursive calls
            end
        elseif error isa RequestError && error.code == 9
            logex.with_logger(logger) do
                @warn "unable to verify remote root due to restricted access of parent folder"
            end
            icare.uri = SFTP.URI(icare.uri, path=root)
        elseif error isa RequestError && error.code == 67
            logex.with_logger(logger) do
                @error "unable to connect to server; check user credentials"
            end
            throw(Base.IOError("could not connect to ICARE server; check user name and password", Integer(SFTP.EC_DIR_NOT_FOUND)))
        else
            logex.with_logger(logger) do
                @error "unknown connection error when trying to connect to ICARE server" error
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
        @warn "root directory $localroot does not exist"
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
    path = realpath(productpath)
    pathparts = splitpath(path)
    if any(isfile.([joinpath(pathparts[1:i]..., "inventory.yaml") for i = 1:length(pathparts) - 1]))
        throw(Base.IOError("nested inventories are not allowed", Integer(SFTP.EC_FILE_EXISTS)))
    end
    # Change to productpath and return absolute path as String
    return path
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
        inventory::SortedDict,
        daterange::@NamedTuple{start::Date, stop::Date},
        convert::Bool,
        update::Bool,
        resync::Bool,
        logger::NamedTuple{(:file, :tee)},
        counter::Counter
    )

Synchronize the files for the selected `daterange` from the `icare` server with the local system.
If set, `update` and `convert` files to the latest version available on the server and a predefined
file format. Dates and files are compared to the `inventory` and the `inventory` is updated, if necessary.
Increase the respective counter for each sync action and log events to `logger`.
"""
function sync!(
    icare::SFTP.Client,
    inventory::SortedDict,
    daterange::@NamedTuple{start::Date, stop::Date},
    convert::Bool,
    update::Bool,
    resync::Bool,
    logger::NamedTuple{(:file, :tee)},
    counter::Counter
)::Nothing
    #* Define all files for download
    dates = filter(d -> d ∉ inventory["gaps"] &&
        inventory["metadata"]["database"]["start"] ≤ d ≤ inventory["metadata"]["database"]["stop"],
        daterange.start:daterange.stop
    )
    files = vcat([File.(Ref(icare), Ref(inventory), date, collect(String, keys(inventory["dates"][date])), convert)
        for date in dates]...)
    # Exit prematurely for no downloads in selected range
    if isempty(files)
        logex.with_logger(logger.tee) do
            @warn "no data available for download in selected date range" daterange
        end
        return
    end
    # Log planned downloads
    stats =inventory_stats(inventory, dates)
    logex.with_logger(logger.tee) do
        @info("$(stats["filecount"] - stats["downloaded files"])/$(stats["filecount"]) files "*
            "($(display_size(stats["size"] - stats["downloaded size"]))/$(display_size(stats["size"]))) "*
            "planned for download, $(stats["downloaded files"]) files "*
            "($(display_size(stats["downloaded size"]))) already downloaded")
        not = resync ? "" : " not"
        @info "files will$not be updated, if newer files are available on the server"
    end

    prog = pm.Progress(length(files), desc="downloading...")
    @threads for file in files
        #* Check for previous downloads
        if downloaded(inventory, file, update)
            lock(thread) do
                #* Log skipped files
                logex.with_logger(logger.file) do
                    @debug "skipping $(file.name), already downloaded"
                end
                counter.skipped += 1
            end
            pm.next!(prog)
            continue
        end
        t0 = Dates.now()
        orig = isfile(file.location.download) && filesize(file.location.download) ==
            inventory["dates"][file.date][file.name]["size"]
        #* Download file and optionally convert to another format
        try
            download(icare, inventory, file, update)
            _convert!(inventory, file, convert, logger.tee)
        catch error
            lock(thread) do
                #* Log download errors
                logex.with_logger(logger.file) do
                    @error "failed to download $(file.name)" exception = (error, catch_backtrace())
                end
            end
        end
        #* Error handling/Re-download, if unsuccessful
        if !downloaded(inventory, file, update)
            # Check connection to ICARE server
            logex.with_logger(logger.file) do
                @warn "download failed for $(file.name); attempting a second download"
            end
            icare = icare_connect(icare.username, icare.password, inventory["metadata"]["remote"]["root"],
                inventory["metadata"]["remote"]["product"], logger.tee)
            # Check for correct server-side file stats
            update_stats!(icare, inventory, file, resync, logger.file)
            try
                download(icare, inventory, file, update)
                _convert!(inventory, file, convert, logger.tee)
            catch error
                lock(thread) do
                    #* Log second download attempt errors
                    logex.with_logger(logger.tee) do
                        @error("second download attempt failed for $(file.name); no further attempts",
                            error)
                    end
                end
                lock(thread) do
                    counter.failed += 1
                end
            end
        end
        #* Clean-up
        if downloaded(inventory, file, update)
            # Remove original downloads unless no conversion is selected or original file already existed
            !convert || orig || rm(file.location.download, force=true)
            # Log download success
            t1 = Dates.now()
            if orig
                lock(thread) do
                    counter.conversions += 1
                    logex.with_logger(logger.file) do
                        @debug "$(file.name) already downloaded; converted in $(Dates.canonicalize(t1 - t0)) @$t1"
                    end
                end
            else
                lock(thread) do
                    # Log successful downloads
                    counter.downloads += 1
                    logex.with_logger(logger.file) do
                        fsize = inventory["dates"][file.date][file.name]["size"]
                        msg = @sprintf("%s: downloaded %0.2f MB in %s with %0.2f MB/s @%s", file.name,
                            fsize / 1e6, Dates.canonicalize(t1 - t0), fsize / (t1 - t0).value / 1e3, t1)
                        @debug msg
                    end
                end
            end
        end
        pm.next!(prog) # Update progress meter
    end # loop over files
    pm.finish!(prog)
end


"""
    download!(
        icare::SFTP.Client,
        inventory::SortedDict,
        file::File,
        update
    )

Download the `file` from the `icare` server and update the `inventory`.
Only download newer files on the server, if `update` is set to `true`.
"""
function download(
    icare::SFTP.Client,
    inventory::SortedDict,
    file::File,
    update
)::Nothing
    # Check, if file was already downloaded
    downloaded(inventory, file, update, true) && return
    # Remove incomplete downloads
    rm(file.location.download, force=true)
    # Download file from server
    SFTP.download(icare, file.location.remote, file.dir.dst, force=true)
    return
end


"""
    downloaded(
        inventory::SortedDict,
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
    inventory::SortedDict,
    file::File,
    update::Bool,
    orig::Bool=false
)::Bool
    filestats = inventory["dates"][file.date][file.name]
    # Check, if file exists (orig: checks download of original file from server, not converted file)
    dbfile = orig ? file.location.download : file.location.target
    isfile(dbfile) || return false
    # Get file stats and type
    localstats = stat(dbfile)
    size = if splitext(dbfile)[2] == ".h5" && inventory["metadata"]["file"]["ext"] ≠ ".h5" # h5 converted files
        # ℹ Compare h5 size or return false for unknown h5 size in inventory
        haskey(filestats, "size"*file.newext) && (localstats.size == filestats["size"*file.newext])
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
