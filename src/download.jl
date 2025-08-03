## Routines related to downloading ICARE data and folder syncing with ICARE

## Types

"""
struct Counter
==============

Stores a counter for `downloads`, `conversions`, and `skipped` data files.
By default, all counter parts are initialised with zero, but can be adjusted
by keyword or positional arguments during instantiation.
"""
mutable struct Counter
    downloads::Int
    conversions::Int
    skipped::Int
end


#* Exceptions

"""
ConnectionError
===============

Thrown with a message as parameter, when no connection to the server can be established.
"""
struct ConnectionError <: Exception
    msg::String
end

Base.show(io::IO, error::ConnectionError)::Nothing = println(io, "ConnectionError: $(error.msg)")


"""
    Counter(;downloads::Int=0, conversions::Int=0, skipped::Int=0) -> Counter

Constructor for `Counter` with default init values `0` for all sub-counters.
Other values can be initialised with keyword arguments for the respective sub-counter.
"""
Counter(;downloads::Int=0, conversions::Int=0, skipped::Int=0)::Counter = Counter(downloads,conversions,skipped)


## API functions
#* Main function for download from server
"""
    sftp_download(
        user::String,
        password::String,
        product::String,
        startdate::Int,
        enddate::Int=-1;
        version::String = 4.51,
        remoteroot::String = "/SPACEBORNE/CALIOP/",
        localroot::String = ".",
        format::UInt8 = 0x02,
        resync::Bool = false,
        logfile::String = "downloads.log",
        loglevel::Symbol = :Debug
    )

Download satellite data from the Aeris/ICARE server.

# General usage

To use `sftp_download`, an Aeris/ICARE account is needed that is available for free at
https://www.icare.univ-lille.fr. Download satellite data by giving the `user`name and `password`
of that account as the first two arguments.

By default, CALIOP data is downloaded. This can be changed by setting the `remoteroot`
keyword argument as long as the contained folder structure is in the format
`<product>.v<version>/yyyy/yyyy_mm_dd`. The root path can be found in the Aeris/ICARE database.
Files are assumed to be hdf4 files with extension `.hdf`. This can be changed to
other formats with the `remoteext` keyword argument.

In addition to the root, the desired `product` is needed as third positional argument,
e.g. `05kmCPro` or `01kmALay`. The name must match the name in the folder excluding
the version number, which is passed as string for maximum flexibility with the `version`
keyword argument (default = `"4.51"`).

Finally, the desired date range can be specified with the fourth and optional fifth
positional argument. Dates are passed as integer values in the format `yyyymmdd`.
Days and months are optional. If only one Date is passed, all files for that date are
downloaded, e.g. `20200101` will download all granules for the day January 1st, 2020.
If the date is omitted (`202001`) the whole January 2020 is downloaded and if just the year
is given, the whole year is downloaded. Date ranges can be specified by giving a start date
as fourth and end date as fifth argument. If days or days and months are omitted in the
start date, they are assumed to be the first of that period, if days and months are omitted
in the end date, the are the last of that period. E.g., `202007, 2020` will download the
second half of 2020 from 01.07.2020 to 31.12.2020.

It is necessary to specify where and how the data should be stored locally.
By default, data will be downloaded to the current folder (where julia was started from
or in which the julia script/REPL command changed). This can be overwritten with the
`localroot` keyword argument. Data is downloaded to the date folders within the product
folder contained directly in `localroot`. Missing folders will be created automatically
(confirmation for missing root folders is needed).

By default all data will be saved as `.h5` files in the HDF5 format regardless of the
file format on the server. This behaviour can be influenced with the `format` kwarg.
Format options are given as `UInt8`. The following options are available:

- HDF4: `0x01` or `0b01`
- HDF5: `0x02` or `0b10`
- both: `0x03` or `0b11`

If you download any other file format than HDF, this flag needs to be set to `0x01`.

Only missing files will be downloaded. Already downloaded files will be skipped.
To know the server structure and available data files for download, an `inventory.yaml`
will be created in every product folder. The inventory is automatically appended, if new
datas become available. An update of the whole inventory can be forced by setting the
`resync` flag to `true`. This can take several minutes, however.

A log file `downloads_<timestamp>.log` will be created in the `product` main folder,
where the timestamp in the format `yyyy_mm_dd_HH_MM_SS` is added automatically to the
file. You can change the file name (the timestamp will also be added to the new file name).
If the log file includes a path, it will be saved to that directory instead.
The number of log messages can be influenced with the `loglevel` keyword given as
a `Symbol`. The following options exist:

- `:Error`: Only errors (and severe warnings) are shown.
- `:Warn`: Warnings and errors are shown.
- `:Info`: Info messages are shown additionally.
- `:Debug`: All log messages are shown.
"""
function sftp_download(
    user::String,
    password::String,
    product::String,
    startdate::Int,
    enddate::Int=-1;
    version::String = "4.51",
    remoteroot::String = "/SPACEBORNE/CALIOP/",
    localroot::String = ".",
    converter::Union{Nothing,String} = "",
    resync::Bool = false,
    logfile::String = "downloads.log",
    loglevel::Symbol = :Debug
)::Nothing
    ## Setup
    # Create product folder, if not existent
    product = product*".v"*version
    productpath = set_localroot(localroot, product)
    # Convert integer dates to dates
    startdate, enddate = convertdates(startdate, enddate)
    daterange = (; start = startdate, stop = enddate)
    #* Start logging
    logfile, level = init_logging(logfile, productpath, loglevel)
    open(logfile, "w") do logio
        logger = Logging.ConsoleLogger(logio, level, show_limited=false)
        Logging.with_logger(logger) do
            @info "downloading \"$product\" data to \"$productpath\""
        end
        #* Syncing local and remote database
        # Get connection to server, go to product folder on remote
        ts = Dates.now()
        Logging.with_logger(logger) do
            @info "Initialising databse @$ts"
        end
        icare = icare_connect(user, password, remoteroot, product, logger)
        # Get available server dates
        inventory = product_database(
            icare, localroot, product, daterange, resync, logger
        )
        Logging.with_logger(logger) do
            te = Dates.now()
            @info "Setup of database completed in $(te - ts)) @$te"
        end
        # Log download session
        t0 = Dates.now()
        Logging.with_logger(logger) do
            formats = [".hdf", ".h5"]
            not = resync ? "" : " not"
            @info "data files downloaded in $(formats[bits(format)[1:2]]) format"
            @info "files will$not be updated, if newer files are available on the server"
            @info "starting downloads @$(t0)"
        end
        @info "Syncing data with ICARE server"

        ## Download
        #* Loop over folders, download missing data from server
        counter = Counter()
        try
            # Loop over available dates
            dates = inventory["dates"].keys |> filter(d -> daterange.start ≤ d ≤ daterange.stop)
            for date in dates
                # Match folder structure with server
                # // datadir = joinpath(string(Dates.year(date)), Dates.format(date, "yyyy_mm_dd"))
                # // mkpath(joinpath(productpath, datadir))
                # remotefiles!(icare, inventory, datadir, date) # DEPRECATED (done during database sync)
                # Change to ICARE folder and download files from server to local directory
                # cd(icare, joinpath(inventory["metadata"]["server"]["productpath"], datadir)) # DEPRECATE
                download!(icare, inventory, datadir, date, format, resync, logger, logio, counter) # TODO update
            end #loop over dates/data files
        finally
            #* Log end of download session and save inventory
            if inventory["metadata"]["updated"] > ts
                save_inventory(inventory)
            end
            log_counter(counter, logger, t0)
        end
    end #logging to file
end #function ftp_download



"""
    log_counter(counter::Counter, logger::Logging.ConsoleLogger, t0::DateTime)

Log the number of downloaded, skipped, and converted files saved in `counter` to `logger`
together with the time it took since `t0`.
"""
function log_counter(counter::Counter, logger::Logging.ConsoleLogger, t0::DateTime)::Nothing
    t1 = Dates.now()
    Logging.with_logger(logger) do
        if counter.downloads > 0
            s = counter.downloads == 1 ? "" : "s"
            @info "$(counter.downloads) file$s downloaded in $(Dates.canonicalize(t1-t0)) @$(t1)"
        end
        if counter.conversions > 0
            s = counter.conversions == 1 ? "" : "s"
            @info "$(counter.conversions) file$s  were already downloaded and upgraded to h5 standard in $(Dates.canonicalize(t1-t0)) @$(t1)"
        end
        if counter.downloads > 0
            s = counter.skipped == 1 ? "" : "s"
            @info "$(counter.skipped) file$s were already previously downloaded"
        end
    end
end


## Functions for syncing with server and setting up local structure

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
            @warn "unable to verify remote root due to restricted access of parent folder" _module=nothing _file=nothing _line=nothing
            icare.uri = URI(icare.uri, path=root)
        elseif error isa RequestError && error.code == 67
            Logging.with_logger(logger) do
                @error "unable to connect to server; check user credentials"
            end
            throw(Base.IOError("could not connect to ICARE server; check user name and password", 1))
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
        @warn "Root directory $localroot does not exist" _module=nothing _file=nothing _line=nothing
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
    product_database(
        icare::SFTP.Client,
        root::String,
        product::String,
        daterange::@NamedTuple{start::Date,stop::Date},
        resync::Bool,
        logger::Logging.ConsoleLogger
    ) -> OrderedDict

Return the inventory of `icare` server-side data files for the `product` in the `remoteroot`
directory. Either read the database from the yaml file in the `product` folder or initialise
a new empty database. If the `daterange` of the selected dates is (partly) outside the
`inventory` date range, the `inventory` is updated for these extended periods.
The whole inventory can be updated by setting `resync` to `true`.
Additional checks are performed, whether the `root` folder was moved. In that case, the
inventory is updated and a warning is issued.
Updates are logged to the screen and the log file with `logger`.
"""
function product_database(
    icare::SFTP.Client,
    root::String,
    product::String,
    daterange::@NamedTuple{start::Date,stop::Date},
    resync::Bool,
    logger::Logging.ConsoleLogger
)::OrderedDict
    # Defining inventory source file and available years on server
    @info "Syncing inventory with ICARE server"
    database = joinpath(root, product, "inventory.yaml")
    years = parse.(Int, readdir(icare))
    if isfile(database)
        # Read available inventory
        inventory = load_inventory(database)
        check_localroot!(inventory, root, product)
        # Update years of interest based on inventory and update options
        filter_years!(inventory, years, daterange, resync, logger)
    else
        # Init empty inventory, if yaml is missing
        inventory = new_inventory(icare, root, product, logger)
    end
    sync_database!(icare, inventory, years, daterange, logger)
    return inventory
end


"""
    load_inventory(file) -> OrderedDict

Load inventory data from a yaml `file` to an `OrderedDict`.
"""
function load_inventory(file)::OrderedDict
    @info "loading local inventory"
    YAML.load_file(file, dicttype=OrderedDict)
end


"""
    save_inventory(inventory::OrderedDict)

Save the `inventory` to `<product path>/inventory.yaml`.
"""
function save_inventory(inventory::OrderedDict)::Nothing
    # Define inventory file
    file = joinpath(inventory["metadata"]["local"]["path"], "inventory.yaml")
    @info "saving inventory to '$file'"
    # Update statistics
    inventory["metadata"]["database"]["dates"] = length(inventory["dates"])
    inventory["metadata"]["file"]["count"] = sum(length.(inventory["dates"][date] for date in inventory["dates"].keys))
    inventory["metadata"]["database"]["updated"] = Dates.now()
    # Save invetory with updated mtime
    YAML.write_file(file, inventory)
end


"""
    new_inventory(
        icare::SFTP.Client,
        root::String,
        product::String,
        logger::Logging.ConsoleLogger
    ) -> OrderedDict{Union{Date,String},OrderedDict}

Initialise a new and empty inventory.
"""
function new_inventory(
    icare::SFTP.Client,
    root::String,
    product::String,
    logger::Logging.ConsoleLogger
)::OrderedDict{Union{Date,String},OrderedDict}
    @info "initialising new inventory"
    Logging.with_logger(logger) do
        @info "initialising new, empty inventory"
    end
    OrderedDict{Union{Date,String},OrderedDict}(
        "metadata" => OrderedDict{String,OrderedDict}(
            "file" => OrderedDict{String,Any}("count" => 0),
            "server" => OrderedDict{String,String}(
                "product" => product,
                "root" => dirname(icare),
                "productpath" => icare.uri.path
            ),
            "local" => OrderedDict{String,String}(
                "root" => realpath(root),
                "path" => realpath(joinpath(root, product))
            ),
            "database" => OrderedDict{String,Any}(
                "dates" => 0,
                "missing" => 0,
                "start" => Date(9999),
                "stop" => Date(0),
                "created" => Dates.now(),
                "updated" => Dates.now(),
                "gaps" => Vector{Date}()
            )
        ),
        "dates" => OrderedDict{Date,OrderedDict}()
    )
end


"""
    check_localroot!(
        inventory::OrderedDict,
        root::AbstractString,
        product::AbstractString
    )

Check, if the `root` has changed and update the root path and the path to the
`product` main folder in the `inventory`.
"""
function check_localroot!(
    inventory::OrderedDict,
    root::AbstractString,
    product::AbstractString
)::Nothing
    # Define paths and update status
    root = realpath(root)
    origin = inventory["metadata"]["local"]["root"]
    # Correct and log differences between current paths and inventory paths
    if root ≠ origin
        origin = joinpath(origin, product)
        update = joinpath(root, product)
        @warn "product folder was recently moved; updating inventory" origin update
        inventory["metadata"]["local"]["root"] = root
        inventory["metadata"]["local"]["path"] = update
        inventory["metadata"]["updated"] = Dates.now()
    end
    return
end


"""
    filter_years!(
        inventory::OrderedDict,
        years::Vector{Int},
        daterange::@NamedTuple{start::Date,stop::Date},
        resync::Bool,
        logger::Logging.ConsoleLogger
    )

Filter `years` to keep only years within the `daterange` and outside th known date range of
the `inventory` unless `resync` is set to `true`. In this case, empty dates and reset
metadata. Log events to `logger`.
"""
function filter_years!(
    inventory::OrderedDict,
    years::Vector{Int},
    daterange::@NamedTuple{start::Date,stop::Date},
    resync::Bool,
    logger::Logging.ConsoleLogger
)::Nothing
    if !resync
        # Default option: update outside known date range
        Logging.with_logger(logger) do
            @info "Checking for new data not yet considered in the inventory"
        end
        # ℹ border years are only considered, if the new date is outside the known date range
        # ℹ of the inventory
        start, stop = inventory["metadata"]["database"]["start"], inventory["metadata"]["database"]["stop"]
        lt = daterange.start ≥ start || Dates.dayofyear(start) == 1 ? (<) : (≤)
        gt = daterange.stop ≤ stop || Dates.dayofyear(stop) == Dates.daysinyear(stop) ? (>) : (≥)
        filter!(t -> lt(t, Dates.year(start)) || gt(t, Dates.year(stop)), years)
    else # force update
        Logging.with_logger(logger) do
            @info "Checking inventory dates for updates"
        end
        empty!(inventory["dates"])
        empty!(inventory["metadata"]["database"]["gaps"])
        inventory["metadata"]["file"]["count"] = 0
        inventory["metadata"]["database"]["dates"] = 0
        inventory["metadata"]["database"]["missing"] = 0
        inventory["metadata"]["database"]["start"] = Date(9999)
        inventory["metadata"]["database"]["stop"] = Date(0)
    end
    return
end


"""
    sync_database!(
        icare::SFTP.Client,
        inventory::OrderedDict,
        years::Vector{Int},
        daterange::@NamedTuple{start::Date,stop::Date},
        logger::Logging.ConsoleLogger
    )

Sync the `inventory` with the `icare` server for the given `years`.
Return a `Bool`, whether updates in the `inventory` occured. Log events to `logger`.
"""
function sync_database!(
    icare::SFTP.Client,
    inventory::OrderedDict,
    years::Vector{Int},
    daterange::@NamedTuple{start::Date,stop::Date},
    logger::Logging.ConsoleLogger
)
    # Monitor updates
    updated = false
    # Define views on metadata and save current date range
    database = inventory["metadata"]["database"]
    #* Loop over dates in online database
    @info "Syncing database with ICARE server and identifying files to download"
    for year in years
        # Save new years to inventory and sync dates with server
        folders = readdir(icare, string(year))
        dates = Date.(folders, "yyyy_mm_dd")
        isempty(dates) && continue
        #* Loop over dates in the current year and add missing dates to inventory
        pm.@showprogress dt=0.1 desc="$year:" for date in dates
            updated |= new_date!(inventory, date)
            updated |= remotefiles!(icare, inventory, date)
        end
        # Ensure complete years get saved in the local inventory, if something during database setups happens
        updated && (inventory["metadata"]["updated"] = Dates.now())
    end
    # Save data gaps to inventory
    data_gaps!(inventory)
    display_gaps(inventory, daterange, logger)

    updated && Logging.with_logger(logger) do
        @info "inventory synced with ICARE server in date range $(database["start"]) – $(database["stop"])"
        inventory["metadata"]["updated"] = Dates.now()
    end
    return
end


"""
    new_date!(inventory::OrderedDict, date::Date) -> Bool

Add the given `date` to the `inventory`, if missing.
Return `true`, if the `date` was added, otherwise `false`.
"""
function new_date!(inventory::OrderedDict, date::Date)::Bool
    haskey(inventory["dates"], date) && return false
    inventory["dates"][date] = OrderedDict{String,OrderedDict}()
    return true
end


"""
    data_gaps!(inventory::OrderedDict, dates::Vector{Date})

Extent data gaps in the `inventory` by gaps in `dates`.
"""
function data_gaps!(inventory::OrderedDict)::Nothing
    # Define date range of the inventory
    start = inventory["metadata"]["database"]["start"] = minimum(inventory["dates"].keys)
    stop = inventory["metadata"]["database"]["stop"] = maximum(inventory["dates"].keys)
    # Determine data gaps in the date range
    new_gaps = setdiff(start:stop, inventory["dates"].keys)
    union!(inventory["metadata"]["database"]["gaps"], new_gaps) |> sort!
    inventory["metadata"]["database"]["missing"] = length(inventory["metadata"]["database"]["gaps"])
    return
end


"""
    display_gaps(
        inventory::OrderedDict,
        daterange::@NamedTuple{start::Date,stop::Date},
        logger::Logging.ConsoleLogger
    )

Log data gaps in the `inventory` in the given `daterange` to `logger`.
Combine single dates in the `inventory` metadata to date ranges.
"""
function display_gaps(
    inventory::OrderedDict,
    daterange::@NamedTuple{start::Date,stop::Date},
    logger::Logging.ConsoleLogger
)::Nothing
    #* Get gaps in current date range
    database = inventory["metadata"]["database"]
    current_gaps = database["gaps"] |> filter(d -> daterange.start ≤ d ≤ daterange.stop)
    isempty(current_gaps) && return
    #* Combine dates to ranges
    current_range = [current_gaps[1]]
    gaps = String[]
    for date in current_gaps[2:end]
        if date == current_range[end] + Dates.Day(1)
            push!(current_range, date)
        else
            msg = length(current_range) == 1 ? string(current_range[1]) : "$(current_range[1]) – $(current_range[end])"
            push!(gaps, msg)
            current_range = [date]
        end
    end
    # Complete last entry
    msg = length(current_range) == 1 ? string(current_range[1]) : "$(current_range[1]) – $(current_range[end])"
    push!(gaps, msg)
    #* Log missing data
    # Note: The whole date range can be selected by choosing start date 0 and stop date 9999
    # Note: Warnings for dates outside the date range are switched off for this case
    # Log to screen
    Date(0) < daterange.start < database["start"] &&
        @warn "no data available before $(database["start"])" _module=nothing _file=nothing _line=nothing
    Date(9999) > daterange.stop > database["stop"] &&
        @warn "no data available after $(database["stop"])" _module=nothing _file=nothing _line=nothing
    length(gaps) > 0 && @info "there are data gaps in the current date range (see log file for details)" gaps
    # Log to file
    Logging.with_logger(logger) do
        Date(0) < daterange.start < database["start"] &&
            @warn "no data available before $(database["start"])" _module=nothing _file=nothing _line=nothing
        Date(9999) > daterange.stop > database["stop"] &&
            @warn "no data available after $(database["stop"])" _module=nothing _file=nothing _line=nothing
        length(gaps) > 0 && @info "there are data gaps in the current date range" gaps
    end
end


"""
    remotefiles!(
        icare::SFTP.Client,
        inventory::OrderedDict,
        date::Date
    ) -> Bool

Add file stats for all granules of the `date` based on the `icare` server data in the `datadir`
path for the current `date`. File stats are only added for dates with no file data.
Indicate updates in the `inventory` by the returned `Bool`.
"""
function remotefiles!(
    icare::SFTP.Client,
    inventory::OrderedDict,
    date::Date
)::Bool
    # Entry checks
    date in inventory["metadata"]["database"]["gaps"] && return false
    isempty(inventory["dates"][date]) || return false
    # Get stats of remote files (without the current and parent folders)
    stats = SFTP.statscan(icare, Dates.format(date, "yyyy/yyyy_mm_dd"))
    files = [splitext(s.desc)[1] for s in stats]
    filesize = [s.size for s in stats]
    mtime = [s.mtime for s in stats]
    sortorder = sortperm(files)
    # Save file stats to new inventory entry
    for i in sortorder
        inventory["dates"][date][files[i]] = OrderedDict(
            "size" => filesize[i],
            "mtime" => Date(Dates.unix2datetime(mtime[i]))
        )
    end
    # Update inventory metadata
    file = inventory["metadata"]["file"]
    haskey(file, "ext") || (file["ext"] = splitext(stats[1].desc)[2])
    return true
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
    download!(
        icare::SFTP.Client,
        inventory::OrderedDict,
        datadir::String,
        date::Date,
        format::UInt8,
        update::Bool,
        logger::Logging.ConsoleLogger,
        logio::IOStream,
        counter::Counter
    ) -> Bool

Download the files for the selected `date` from the `icare` server and save in the
specified `format` to the given `datadir`. If set, `update` files to the latest
version available on the server. Dates and files are compared to the `inventory`
and the `inventory` is updated, if necessary.
Log `logger` events to a log file in the `logio` I/O stream.
Return a `Bool` indicating `updates` in the `inventory`.
"""
function download!(
    icare::SFTP.Client,
    inventory::OrderedDict,
    datadir::String,
    date::Date,
    format::UInt8,
    update::Bool,
    logger::Logging.ConsoleLogger,
    logio::IOStream,
    counter::Counter
)::Bool
    # TODO use several threads for parallel downloads
    try
        #* Init
        files = inventory["dates"][date]
        datapath = joinpath(inventory["metadata"]["local"]["path"], datadir)
        pulled = false
        updated = false
        #* Loop over files
        pm.@showprogress dt=1 desc="$date:" for file in files.keys
            datafile = joinpath(datapath, file)
            t0 = Dates.now()
            # Set flag for presence of hdf file
            h4 = isfile(datafile*".hdf") # Update: Generalize file extension (user choice with default)
            # Check download status (no directory needed, already in product directory)
            if downloaded(datafile, files[file], format, update)
                pulled = true
                Logging.with_logger(logger) do
                    @debug "$file already downloaded, skipping download" _module=nothing _file=nothing _line=nothing
                end
                flush(logio)
                counter.skipped += 1
                continue
            end
            #* Download data
            for i = 1:5
                # Download file
                if !file_pulled(inventory["metadata"]["file"]["ext"], datafile, inventory["dates"][date][file], update)
                    download(icare, file*inventory["metadata"]["file"]["ext"], downloadDir=datapath)
                end
                # Convert to h5, if option is set
                hdf_format = bits(format)
                if hdf_format[2]
                    # Make sure, previous h5 versions are overwritten
                    rm("$(datafile).h5", force=true) # Update: Generalize file extension
                    # Convert hdf4 to hdf5
                    run(`h4toh5 $datafile.hdf`) # Update: Generalize file extension
                    # Add new file size to inventory
                    h5size = filesize(joinpath(datafile*".h5")) # Update: Generalize file extension
                    updated = if h5size != inventory["dates"][date][file]["h5size"]
                        inventory["dates"][date][file]["h5size"] = h5size
                        true
                    end
                end
                # Delete HDF4 file, if hdf4 was unselected and file was not already present
                if !hdf_format[1] && !h4
                    rm(datafile*".hdf", force=true) # Update: Generalize file extension
                end
                # Abort download attempts after fifth try
                if downloaded(datafile, inventory["dates"][date][file], format, update)
                    t1 = Dates.now()
                    s = i > 1 ? "s" : ""
                    Logging.with_logger(logger) do
                        if pulled
                            @debug "$file converted in $(Dates.canonicalize(t1-t0)) @$t1" _module=nothing _file=nothing _line=nothing
                            counter.conversions += 1
                        else
                            @debug "$file downloaded in $i attempt$s in $(Dates.canonicalize(t1-t0)) @$t1" _module=nothing _file=nothing _line=nothing
                            counter.downloads +=1
                        end
                    end
                    flush(logio)
                    break
                elseif i == 2 && hdf_format[1]
                    # Update remote file stats after 2 failed download attempts
                    # to prevent re-downloads because of wrong file stats
                    stats = SFTP.statscan(icare)
                    n = findfirst(isequal(file*inventory["metadata"]["file"]["ext"]), f.desc for f in stats)
                    if inventory["dates"][date][file]["size"] != stats[n].size ||
                        inventory["dates"][date][file]["mtime"] != stats[n].mtime
                        updated = true
                    end
                    inventory["dates"][date][file]["size"] = stats[n].size
                    inventory["dates"][date][file]["mtime"] = stats[n].mtime
                elseif i == 5
                    throw(Base.IOError("Could not download $(file*inventory["metadata"]["file"]["ext"]); aborting further download attempts", 3))
                end
            end
        end
    finally
        return updated
    end
end


"""
    downloaded!(
        inventory::OrderedDict,
        dbfile::@NamedTuple{name::String,target::String,original::String,remote::String,ext::String},
        date::Date,
        update::Bool,
        orig::Bool=false
    ) -> Bool

Check, whether the `dbfile.target` for the given `date` has already been downloaded from the server
to the local directory by comparing it to the `filestats` of the remote server in the `inventory`.
If `update` is set, downloaded returns `false`, if newer versions of the `dbfile` exist on the
server.
When `orig` is set to `true`, downloaded checks against the original instead of the target file.

The `h5size` may be added to the `inventory`, if previously missing.
"""
function downloaded!(
    inventory::OrderedDict,
    dbfile::@NamedTuple{name::String,target::String,original::String,remote::String,ext::String},
    date::Date,
    update::Bool,
    orig::Bool=false
)::Bool
    filestats = inventory["dates"][date][dbfile.name]
    # Check, if file exists
    file = isfile(dbfile.target) ? dbfile.target : dbfile.original
    orig && (file = dbfile.original) # ℹ Check for the original file from the server, not the converted
    isfile(file) || return false
    # Get file stats and type
    localstats = stat(file)
    h5 = splitext(file)[2] == ".h5" && file ≠ dbfile.original
    size = if h5 #* h5 converted files
        # Compare h5 file size, if available in inventory
        # Otherwise, compare size of original file format
        h5key = haskey(filestats, "h5size")
        s = if h5key
            "h5size"
        else
            localstats = stat(dbfile.original)
            "size"
        end
        ok = localstats.size == filestats[s]
        # Update file size in inventory or return false for wrong file size
        if ok && !h5key
            # Update file stats for h5 files
            filestats["h5size"] = filesize(file)
            inventory["metadata"]["updated"] = Dates.now()
        end
        ok
    else #* original file from server
        localstats.size == filestats["size"]
    end
    # Compare stats
    size || return false
    (update && localstats.mtime > filestats["mtime"]) && return false
    # Return true, if all checks passed
    return true
end


"""
    database_files(
        icare::SFTP.Client,
        inventory::OrderedDict,
        date::Date,
        name::String,
        converter::String
    ) -> @NamedTuple{name::String,target::String,original::String,remote::String,ext::String}

Create a named tuple with the file paths for the target, original (local), and remote files
as well as the file `name` and the extension from the data of the `inventory`, the `icare` client,
the given `date`, the `name` of the file, and the path to the `converter` script.
"""
function database_files(
    icare::SFTP.Client,
    inventory::OrderedDict,
    date::Date,
    name::String,
    converter::String,xyhjm
)::@NamedTuple{name::String,target::String,original::String,remote::String,ext::String}
    datadir = Dates.format.(date, ["yyyy", "yyyy_mm_dd"])
    datapath = mkpath(joinpath(inventory["metadata"]["local"]["path"], datadir...))
    ext = inventory["metadata"]["file"]["ext"]
    original = joinpath(datapath, name*ext)
    target = isempty(converter) ? original : splitext(original)[1]*".h5"
    remote = joinpath(icare.uri, datadir..., name*ext).path
    return (;name, target, original, remote, ext)
end


"""
    converted(data::OrderedDict, file::String) -> Bool

Check, whether the size of the converted `file` is known in the `data` directory.
"""
converted(data::OrderedDict, file::String)::Bool = haskey(data[file], "h5size")


"""
    converterpath(converter::Union{Nothing,String}) -> String

Return the path to the converter script for HDF4 to HDF5 conversion.
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


#=
"""
    file_pulled(
        ext::String,
        file::String,
        filestats::OrderedDict,
        update::Bool
    ) -> Bool

Check, whether the `file` with the given `ext`ension was already downloaded by
comparing the stats to the `filestats` of the server. If `updated` is set,
downloaded returns `false`, if newer versions of the `targetfile` exist on the server.
"""
function file_pulled(
    ext::String,
    file::String,
    filestats::OrderedDict,
    update::Bool
)::Bool
    isfile(joinpath(file*ext)) || return false
    localstats = stat(joinpath(file*ext))
    hdf = if ext == ".h5"
        haskey(filestats, "h5size") || return false
        "h5size"
    else
        "size"
    end
    localstats.size == filestats[hdf] || return false
    (update && localstats.mtime > filestats["mtime"]) && return false
    return true
end
 =#
