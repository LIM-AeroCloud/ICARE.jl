## Routines related to downloading ICARE data and folder syncing with ICARE

## Types

"""
struct Counter
==============

Stores a counter for `downloads`, `conversions`, and `skipped` data files.
By default, all counter parts are initialised with zero, but can be adjusted
by keyword arguments during instantiation.
"""
mutable struct Counter
    downloads::Int
    conversions::Int
    skipped::Int
end


"""
    Counter(;downloads::Int=0, conversions::Int=0, skipped::Int=0) -> Counter

Constructor for `Counter` with default init values `0` for all sub-counters.
Other values can be initialised with keyword arguments for the respective sub-counter.
"""
Counter(;downloads::Int=0, conversions::Int=0, skipped::Int=0)::Counter = Counter(downloads,conversions,skipped)


## API functions
#=
#* Overload Base functions for SFTP file system
"""
    pwd(server::SFTP.Client) -> String

Return the absolute path of the present working directory on the `server` as string.
"""
Base.pwd(server::SFTP.Client)::String = string(server.uri.path)


"""
    readdir(server::SFTP.Client, dir::String; join::Bool=false, change::Bool=false) -> Vector{String}

Read the files on the `server` in the given `dir`ectory.
If `join` is set to `true`, the absolute paths are returned.
If `change` is set to `true`, the working directory is change to the given `dir`.
"""
function Base.readdir(server::SFTP.Client, dir::String; join::Bool=false, change::Bool=false)::Vector{String}
    # Save current directory and change to dir
    change || (cwd = pwd(server))
    cd(server, dir)
    # Read contents of dir
    files = readdir(server, join)
    # Change back to previous directory and return contents
    change || cd(server, cwd)
    return files
end
=#

#* Main function for download from server
"""
    sftp_download(
        user::String,
        password::String,
        product::String,
        startdate::Int,
        enddate::Int=-1;
        version::Float64 = 4.51,
        remoteroot::String = "/SPACEBORNE/CALIOP/",
        localroot::String = ".",
        format::UInt8 = 0x02,
        update::Bool = false,
        update_inventory::Bool = false,
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
the version number, which is passed as float in the keyword argument `version` (default = `4.51`).

Finally, the desired date range can be specified with the fourth and optional fifth
positional argument. Dates are passed as integer values in the format `yyyymmdd`.
Days and months are optional. If only one Date is passed, all files for that date are
downloaded, e.g. `20200101` will download all granules for the day January 1st, 2020.
If the date is omitted (`202001`) the whole January 2020 is downloaded and if just the year
is given, the whole year is downloaded. Date ranges can be specified by giving a start date
as fourth and end date as fifth argument. If days or days and months are omitted in the
start date, the are assumed to be the first of that period, if days and months are omitted
in the end date, the are the last of that period. E.g., `202007, 2020` will download the
second half of 2020 from 01.07.2020 to 31.12.2020, `20220415, 20230103` will download
for the range 14.04.2022 to 03.01.2023 including the start and end date.

It is necessary to specify where and how the data should be stored locally.
By default, data will be downloaded to the current folder (where julia was started from
or in which the julia script/REPL command changed). This can be overwritten with the
`localroot` keyword argument. Data is downloaded to the date folders within the product
folder contained directly in `localroot`. Missing folders will be created automatically
(confirmation for missing root folders needed).

By default all data will be saved as `.h5` files in the HDF5 format regardless of the
file format on the server. This behaviour can be influended with the `format` kwarg.
Format options are given as `UInt8`. The following options are available:

- HDF4: `0x01` or `0b01`
- HDF5: `0x02` or `0b10`
- both: `0x03` or `0b11`

If you download any other file format the HDF, this flag needs to be set to `0x01`.

Only missing files will be downloaded. Already downloaded files will be skipped.
To know the server structure and available data files for download, an `inventory.xml`
will be created in every product folder. The inventory can be updated, if there were
updates on the server, by setting `update_inventory` to `true`.
If `update` is set to `true`, the modified dates of the local and remote files are
compared and newer files will be downloaded from the server.

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
    version::Float64 = 4.51,
    remoteroot::String = "/SPACEBORNE/CALIOP/",
    localroot::String = ".",
    format::UInt8 = 0x02,
    update::Bool = false,
    update_inventory::Bool = false,
    logfile::String = "downloads.log",
    loglevel::Symbol = :Debug
)::Nothing
    ## Setup
    # Get connection to server, go to product folder on remote
    product = @sprintf "%s.v%.2f" product version
    icare = icare_connect(user, password, remoteroot, product)
    # Create product folder, if not existent
    productpath = set_localroot(localroot, product)
    # Convert integer dates to dates
    startdate, enddate = convertdates(startdate, enddate)
    daterange = (; start = startdate, stop = enddate)
    #* Start logging
    logfile, level = init_logging(logfile, productpath, loglevel)
    open(logfile, "w") do logio
        logger = Logging.ConsoleLogger(logio, level, show_limited=false)
        Logging.with_logger(logger) do
            @info "downloading \"$product\" data, version $version, to \"$productpath\""
        end
        # Get available server dates
        inventory, updated = product_database(icare, remoteroot, localroot, product, daterange, update_inventory, logger)
        # Log download session
        t0 = Dates.now()
        Logging.with_logger(logger) do
            formats = [".hdf", ".h5"]
            not = update ? "" : " not"
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
            dates = keys(inventory["dates"]) |> filter(d -> daterange.start ≤ d ≤ daterange.stop) |> collect |> sort
            for date in dates
                # Match folder structure with server
                datadir = joinpath(string(Dates.year(date)), Dates.format(date, "yyyy_mm_dd"))
                mkpath(joinpath(productpath, datadir))
                # remotefiles!(icare, inventory, datadir, date) # DEPRECATED (done during database sync)
                # Change to ICARE folder and download files from server to local directory
                cd(icare, joinpath(inventory["metadata"]["server"]["productpath"], datadir)) # DEPRECATE
                updated |= download!(icare, inventory, datadir, date, format, update, logger, logio, counter)
            end #loop over dates/data files
        finally
            #* Log end of download session and save inventory
            updated && save_inventory(inventory)
            t1 = Dates.now()
            log_counter(counter, logger, t0, t1)
        end
    end #logging to file
end #function ftp_download



"""
    log_counter(counter::Counter, logger::Logging.ConsoleLogger, t0::DateTime, t1::DateTime)

Log the number of downloaded, skipped, and converted files saved in `counter` to `logger`
together with the time it took calculated from `t1 - t0`.
"""
function log_counter(counter::Counter, logger::Logging.ConsoleLogger, t0::DateTime, t1::DateTime)::Nothing
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
    product::String
)::SFTP.Client
    # Connect to server and go to root of selected data
    icare = SFTP.Client("sftp://sftp.icare.univ-lille.fr", user, password)
    try cd(icare, root)
    catch error
        if error isa RequestError && error.code == 9
            @warn "unable to verify remote root due to restricted access of parent folder" _module=nothing _file=nothing _line=nothing
            icare.uri = URI(icare.uri, path=root)
        elseif error isa RequestError && error.code == 67
            throw(Base.IOError("could not connect to ICARE server; check user name and password", 1))
        else
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
        remoteroot::String,
        localroot::String,
        product::String,
        startdate::Date,
        stopdate::Date,
        update_inventory::Bool,
        logger::Logging.ConsoleLogger
    ) -> OrderedDict, Bool

Return the inventory of `icare` server-side data files for the `product` in the `remoteroot`
directory and save it to the inventory.yaml in the `prodcut` folder in the `localroot`.
Additonally, return a `Bool` indicating whether the inventory was updated.
Either read the database from the yaml file in the `product` folder or initialise
a new empty database. If the `startdate` or `enddate` of the selected dates is
outside the `inventory` date range, the `inventory` is updated for these extended
periods. Updates are logged to the screen and the log file with `logger`.
# Update: Use of flags for inventory update
"""
function product_database(
    icare::SFTP.Client,
    remoteroot::String,
    localroot::String,
    product::String,
    daterange::@NamedTuple{start::Date,stop::Date},
    update::Bool,
    logger::Logging.ConsoleLogger
)::Tuple{OrderedDict,Bool}
    # Defining inventory source file and available years on server
    @info "Syncing inventory with ICARE server"
    database = joinpath(localroot, product, "inventory.yaml")
    years = parse.(Int, readdir(icare))
    if isfile(database)
        # Read available inventory
        inventory = load_inventory(database)
        # Update years of interest based on inventory and update options
        updated = filter_years!(inventory, years, daterange, localroot, product, update, logger)
    else
        # Init empty inventory, if yaml is missing
        inventory = new_inventory(remoteroot, localroot, product, logger)
        updated = true
    end
    updated |= sync_database!(icare, inventory, years, update, logger)
    return inventory, updated
end


"""
    load_inventory(file) -> OrderedDict

Load inventory data from yaml `file` to `OrderedDict`.
"""
function load_inventory(file)::OrderedDict
    @info "loading local inventory"
    YAML.load_file(file, dicttype=OrderedDict)
end


"""
    save_inventory(inventory::OrderedDict)::Nothing

Save inventory to a yaml file in the product path.
"""
function save_inventory(inventory::OrderedDict)::Nothing
    # Define inventory file
    file = joinpath(inventory["metadata"]["local"]["path"], "inventory.yaml")
    @info "saving inventory to '$file'"
    # Save invetory with updated mtime
    inventory["metadata"]["database"]["updated"] = Dates.now()
    YAML.write_file(file, inventory)
end


"""
    new_inventory(
        remoteroot::String,
        localroot::String,
        product::String,
        logger::Logging.ConsoleLogger
    ) -> OrderedDict{Union{Date,String},OrderedDict}

Initialise a new and empty inventory.
"""
function new_inventory(
    remoteroot::String,
    localroot::String,
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
                "root" => remoteroot,
                "productpath" => joinpath(remoteroot, product)
            ),
            "local" => OrderedDict{String,String}(
                "root" => realpath(localroot),
                "path" => realpath(joinpath(localroot, product))
            ),
            "database" => OrderedDict{String,Any}(
                "dates" => 0,
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
    filter_years!(
        inventory::OrderedDict,
        years::Vector{Int},
        localroot::String,
        product::String,
        update::Bool
    ) -> Bool

Check, if the `localroot` has changed and update the root path and the path to the
`product` main folder in the `inventory`. #REFACTOR
Filter for `years` outside the range of the inventory, to `update` the inventory.
Return a `Bool` whether the inventory has been updated.
"""
function filter_years!(
    inventory::OrderedDict,
    years::Vector{Int},
    daterange::@NamedTuple{start::Date,stop::Date},
    localroot::String,
    product::String,
    update::Bool,
    logger::Logging.ConsoleLogger
)::Bool
    # Consider years outside the range of the inventory, if update is not selected
    updated = false
    if !update
        Logging.with_logger(logger) do
            @info "Checking for new data not yet considered in the inventory"
        end
        #* Filter years outside date range
        # ℹ border years are only considered, if the new date is outside the known date of the
        # inventory
        start, stop = inventory["metadata"]["database"]["start"], inventory["metadata"]["database"]["stop"]
        lt = daterange.start ≥ start || Dates.dayofyear(start) == 1 ? (<) : (≤)
        gt = daterange.stop ≤ stop || Dates.dayofyear(stop) == Dates.daysinyear(stop) ? (>) : (≥)
        filter!(t -> lt(t, Dates.year(start)) || gt(t, Dates.year(stop)), years)
    end
    # Refactor into separate function
    # Check correct local root is saved (folder hasn't been moved)
    origin = inventory["metadata"]["local"]["root"]
    if localroot ≠ origin
        origin = joinpath(origin, product)
        update = joinpath(localroot, product)
        @warn "product folder was recently moved; updating inventory" origin update
        inventory["metadata"]["local"]["root"] = localroot
        inventory["metadata"]["local"]["path"] = update
        updated = true
    end
    return updated
end


"""
    sync_database!(
        icare::SFTP.Client,
        inventory::OrderedDict,
        years::Vector{Int},
        update_inventory::Bool
    ) -> Bool

Sync the `inventory` with the `icare` server for the given `years`.
Update the inventory, if `update_inventory` is set to `true`.
Return a `Bool`, whether updates in the `inventory` occured.
"""
function sync_database!(
    icare::SFTP.Client,
    inventory::OrderedDict,
    years::Vector{Int},
    update_inventory::Bool,
    logger::Logging.ConsoleLogger
)::Bool
    # Flag to treat first year differently than remaining years
    firstdate = true
    # Monitor updates
    updated = false
    # Define views on metadata and save current date range
    database = inventory["metadata"]["database"]
    server = inventory["metadata"]["server"]
    db = (;:start => database["start"], :stop => database["stop"])
    #* Loop over dates in online database
    for year in years
        # Save new years to inventory and sync dates with server
        folders = readdir(icare, joinpath(server["root"], server["product"], string(year)))
        dates = Date.(folders, "yyyy_mm_dd")
        update_inventory || filter!(d -> !(db.start ≤ d ≤ db.stop), dates)
        @debug "processing" dates
        # Save data gaps to inventory
        updated |= data_gaps!(inventory, dates)
        # Get date range in current year
        start, stop = dates[[begin, end]]
        if firstdate
            firstdate = false
            # Adjust start date in inventory metadata, if necessary
            if start < db.start
                database["start"] = start
                updated = true
            end
            # Add first date to inventory (needed for file extension) and update file metadata
            updated |= add_date!(inventory, dates[1])
            updated |= remotefiles!(icare, inventory, joinpath(string(year), folders[1]), dates[begin])
        end
        # Update stop date, if necessary
        if stop > db.stop
            database["stop"] = stop
            updated = true
        end
        #* Loop over dates in the current year and add missing dates to inventory
        for date in dates
            updated |= add_date!(inventory, date)
        end
    end
    display_gaps(inventory, db, logger)

    updated && Logging.with_logger(logger) do
        @info "inventory synced with ICARE server in date range $(db.start) – $(db.stop)"
    end
    return updated
end


"""
    add_date!(inventory::OrderedDict, date::Date) -> Bool

Add the given `date` to the `inventory`, if missing, and update the metadata of the inventory.
Return `true`, if date was added, otherwise `false`.
"""
function add_date!(inventory::OrderedDict, date::Date)::Bool
    haskey(inventory["dates"], date) && return false
    inventory["dates"][date] = OrderedDict{String,OrderedDict}()
    inventory["metadata"]["database"]["dates"] += 1
    return true
end


"""
    data_gaps!(inventory::OrderedDict, dates::Vector{Date}) -> Bool

Extent data gaps in the `inventory` by gaps in `dates`. Return a `Bool` indicating new gaps.
"""
function data_gaps!(inventory::OrderedDict, dates::Vector{Date})::Bool
    new_gaps = setdiff(dates, dates[begin]:dates[end])
    gaps = inventory["metadata"]["database"]["gaps"]
    gaps = union(gaps, new_gaps) |> sort
    return !isempty(new_gaps)
end


"""
    display_gaps(
        inventory::OrderedDict,
        daterange::@NamedTuple{start::Date,stop::Date},
        logger::Logging.ConsoleLogger
    )


Find dates with missing data and update the metadata of the `inventory`.
In the time period between `startdate` and `stopdate`, log those dates to`logger`.
"""
function display_gaps(
    inventory::OrderedDict,
    daterange::@NamedTuple{start::Date,stop::Date},
    logger::Logging.ConsoleLogger
)::Nothing
    #* Get gaps in current date range
    database = inventory["metadata"]["database"]
    current_gaps = database["gaps"] |> filter(d -> datarange.start ≤ d ≤ datarange.stop)
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
    length(gaps) > 0 && @info "there are data gaps in the current date range" gaps
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
        datadir::String,
        date::Date
    )

Check, if the files on the `icare` server in the `datadir` path for the current `date`
are already in the `inventory`, otherwise update the `inventory` (including the metadata).
Indicate updates in the `inventory` by the returned `Bool`.
"""
function remotefiles!(
    icare::SFTP.Client,
    inventory::OrderedDict,
    datadir::String,
    date::Date
)::Bool
    # Entry checks
    date in inventory["metadata"]["database"]["gaps"] && return false
    isempty(inventory["dates"][date]) || return false # ¿ Update option ?
    # Get stats of remote files (without the current and parent folders)
    stats = SFTP.statscan(icare, joinpath(inventory["metadata"]["server"]["productpath"], datadir))
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
    file["count"] += length(files)
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
        pm.@showprogress dt=1 desc="$date:" for file in keys(files)
            datafile = joinpath(datapath, file)
            t0 = Dates.now()
            # Set flag for presence of hdf file
            h4 = isfile(datafile*".hdf") # Update: Generalize file extension (user choice with default)
            # Check download status (no directory needed, already in product directory)
            if downloaded(datafile, inventory["dates"][date][file], format, update)
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
    downloaded(
        targetfile::String,
        filestats::OrderedDict,
        format::UInt8,
        update::Bool
    ) -> Bool

Check, whether the `targetfile` has already been downloaded from the server
to the local directory in the specified `format` by compoaring it to the `filestats`
of the remote server. If `updated` is set, downloaded returns `false`, if newer versions
of the `targetfile` exist on the server.
"""
function downloaded(
    targetfile::String,
    filestats::OrderedDict,
    format::UInt8,
    update::Bool
)::Bool
    # Get files in local director and verify HDF version
    hdf_version = bits(format)
    # Check hdf files for existance, size and modified date
    h4 = hdf_version[1] ? file_pulled( ".hdf", targetfile, filestats, update) : true
    h5 = hdf_version[2] ? file_pulled( ".h5", targetfile, filestats, update) : true
    # Return true if all checks passed
    return h4 & h5
end


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
