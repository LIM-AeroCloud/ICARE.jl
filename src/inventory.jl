## Routines related to creating and processing the local inventory
## Functions for loading and setting up the inventory

"""
    product_database!(
        icare::SFTP.Client,
        inventory::SortedDict,
        root::String,
        product::String,
        daterange::@NamedTuple{start::Date,stop::Date},
        convert::Bool,
        resync::Bool,
        logger::Logging.ConsoleLogger
    )

Initiate the inventory of `icare` server-side data files for the `product` in the `remoteroot`
directory. Either read the database from the yaml file in the `product` folder or initialise
a new database. If the `daterange` of the selected dates is (partly) outside the
`inventory` date range, the `inventory` is updated for these extended periods.
The whole inventory can be updated by setting `resync` to `true`.
Additional checks are performed, whether the `root` folder was moved. In that case, the
inventory is updated and a warning is issued.
The target file extension for converted files is set based on the `convert` option.
Updates are logged to the screen and the log file with `logger`.
"""
function product_database!(
    icare::SFTP.Client,
    inventory::SortedDict,
    root::String,
    product::String,
    daterange::@NamedTuple{start::Date,stop::Date},
    convert::Bool,
    resync::Bool,
    logger::Logging.ConsoleLogger
)::Nothing
    # Defining inventory source file and available years on server
    database = joinpath(root, product, ".inventory.yaml")
    years = parse.(Int, readdir(icare))
    if isfile(database)
        # Read available inventory
        load_inventory!(inventory, database)
        check_localroot!(inventory, root, product)
        # Update years of interest based on inventory and update options
        filter_years!(inventory, years, daterange, resync, logger)
    else
        # Init empty inventory, if yaml is missing
        new_inventory!(icare, inventory, root, product, logger)
    end
    sync_database!(icare, inventory, years, daterange, convert, logger)
end


"""
    load_inventory!(inventory::SortedDict, file::AbstractString)

Load data from a yaml `file` to the `inventory`.
"""
function load_inventory!(inventory::SortedDict, file::AbstractString)::Nothing
    # Load inventory with sorted entries
    @info "loading local inventory"
    for (key, value) in YAML.load_file(file, dicttype=SortedDict)
        inventory[key] = value
    end
    # Reorder database metadata entries in a more logical order
    inventory["metadata"]["database"] = OrderedDict(
        "dates" => inventory["metadata"]["database"]["dates"],
        "missing" => inventory["metadata"]["database"]["missing"],
        "size" => inventory["metadata"]["database"]["size"],
        "converted size" => inventory["metadata"]["database"]["converted size"],
        "start" => inventory["metadata"]["database"]["start"],
        "stop" => inventory["metadata"]["database"]["stop"],
        "created" => inventory["metadata"]["database"]["created"],
        "updated" => inventory["metadata"]["database"]["updated"]
    )
    # Convert verstion to version number
    inventory["metadata"]["version"] = VersionNumber(inventory["metadata"]["version"])
    return
end


"""
    new_inventory!(
        icare::SFTP.Client,
        inventory::SortedDict,
        root::String,
        product::String,
        convert::Bool,
        logger::Logging.ConsoleLogger
    )

Initialise a new and empty inventory.
"""
function new_inventory!(
    icare::SFTP.Client,
    inventory::SortedDict,
    root::String,
    product::String,
    logger::Logging.ConsoleLogger
)::Nothing
    @info "initialising new inventory"
    Logging.with_logger(logger) do
        @info "initialising new, empty inventory"
    end
    inventory["dates"] = SortedDict{Date,SortedDict}()
    inventory["gaps"] = Vector{Date}()
    inventory["metadata"] = SortedDict{String,Any}(
        "database" => OrderedDict{String,Any}(
            "dates" => 0,
            "missing" => 0,
            "size" => 0,
            "converted size" => 0,
            "start" => Date(9999),
            "stop" => Date(0),
            "created" => Dates.now(),
            "updated" => Dates.now()
        ),
        "file" => SortedDict{String,Any}(
            "conversions" => 0,
            "count" => 0,
            "ext" => "",
            "newext" => ""
        ),
        "local" => SortedDict{String,String}(
            "path" => realpath(joinpath(root, product)),
            "root" => realpath(root)
        ),
        "remote" => SortedDict{String,String}(
            "product" => product,
            "productpath" => icare.uri.path,
            "root" => dirname(icare)
        ),
        "version" => v"1.0.0"
    )
    return
end


"""
    filter_years!(
        inventory::SortedDict,
        years::Vector{Int},
        daterange::@NamedTuple{start::Date,stop::Date},
        resync::Bool,
        logger::Logging.ConsoleLogger
    )

Filter `years` to keep only years within the `daterange` and outside the known date range of
the `inventory` unless `resync` is set to `true`. In this case, empty dates and reset
metadata. Log events to `logger`.
"""
function filter_years!(
    inventory::SortedDict,
    years::Vector{Int},
    daterange::@NamedTuple{start::Date,stop::Date},
    resync::Bool,
    logger::Logging.ConsoleLogger
)::Nothing
    if !resync
        # Default option: update outside known date range
        Logging.with_logger(logger) do
            @info "checking for new data not yet considered in the inventory"
        end
        # ℹ border years are only considered, if the new date is outside the known date range
        # ℹ of the inventory
        start, stop = inventory["metadata"]["database"]["start"], inventory["metadata"]["database"]["stop"]
        lt = daterange.start ≥ start || Dates.dayofyear(start) == 1 ? (<) : (≤)
        gt = daterange.stop ≤ stop || Dates.dayofyear(stop) == Dates.daysinyear(stop) ? (>) : (≥)
        filter!(t -> lt(t, Dates.year(start)) || gt(t, Dates.year(stop)), years)
    else # force update
        Logging.with_logger(logger) do
            @info "checking inventory dates for updates"
        end
        clear_dates!(inventory)
        empty!(inventory["gaps"])
        inventory["metadata"]["file"]["count"] = 0
        inventory["metadata"]["file"]["conversions"] = 0
        inventory["metadata"]["database"]["dates"] = 0
        inventory["metadata"]["database"]["missing"] = 0
        inventory["metadata"]["database"]["size"] = 0
        inventory["metadata"]["database"]["converted size"] = 0
        inventory["metadata"]["database"]["start"] = Date(9999)
        inventory["metadata"]["database"]["stop"] = Date(0)
    end
    return
end


## Functions for synchronisation

"""
    sync_database!(
        icare::SFTP.Client,
        inventory::SortedDict,
        years::Vector{Int},
        daterange::@NamedTuple{start::Date,stop::Date},
        convert::Bool,
        logger::Logging.ConsoleLogger
    )

Sync the `inventory` with the `icare` server for the given `daterange` and `years`.
Consider conversion to a new file format based on the `convert` option.
Log events to `logger`.
"""
function sync_database!(
    icare::SFTP.Client,
    inventory::SortedDict,
    years::Vector{Int},
    daterange::@NamedTuple{start::Date,stop::Date},
    convert::Bool,
    logger::Logging.ConsoleLogger
)::Nothing
    # Monitor updates
    updated = Threads.Atomic{Bool}(false)
    # Define views on metadata and save current date range
    database = inventory["metadata"]["database"]
    #* Loop over dates in online database
    @info "syncing database with ICARE server and identifying files to download"
    for year in years
        # Save new years to inventory and sync dates with server
        folders = readdir(icare, string(year))
        dates = Date.(folders, "yyyy_mm_dd")
        isempty(dates) && continue
        #* Loop over dates in the current year and add missing dates to inventory
        # Setup temporary storage for each thread
        granules = Dict{Int,Dict{Date,Vector{SFTP.StatStruct}}}()
        for i = 1:Threads.nthreads()
            granules[i] = Dict{Date,Vector{SFTP.StatStruct}}()
        end
        prog = pm.Progress(length(dates), dt=0.1, desc="$year")
        # Save file data for each date
        @threads for date in dates
            @show date
            # updated |= new_date!(inventory, date)
            updated_granules = datecheck!(icare, inventory, granules, date)
            Threads.atomic_or!(updated, updated_granules)
            pm.next!(prog)
        end
        pm.finish!(prog)
        if updated[]
            # Merge thread data into inventory
            remotefiles!(inventory, granules)
            # Ensure complete years get saved in the local inventory, if something during database setups happens
            inventory["metadata"]["database"]["updated"] = Dates.now()
            inventory["metadata"]["database"]["start"] = minimum(keys(inventory["dates"]))
            inventory["metadata"]["database"]["stop"] = maximum(keys(inventory["dates"]))
        end
    end

    # Save file extensions in inventory, if not done before
    if updated[]
        setext!(inventory, granules)
        @info "inventory synced with ICARE server in date range $(database["start"]) – $(database["stop"])"
    end
    newext!(inventory, convert)
    # Delete possible temporary inventory data
    delete!(inventory, "temp")
    # Save data gaps to inventory
    data_gaps!(inventory)
    display_gaps(inventory, daterange, logger)
end


"""
    setext!(
        inventory::SortedDict,
        granules::Dict{Int,Dict{Date,Vector{SFTP.StatStruct}}}
    )

Set the original file extension in the `inventory` based on the remote files in `granules`.
"""
function setext!(inventory::SortedDict, granules::Dict{Int,Dict{Date,Vector{SFTP.StatStruct}}})::Nothing
    isempty(inventory["metadata"]["file"]["ext"]) || return
    for  stats in values(granules), statdata in values(stats)
        inventory["metadata"]["file"]["ext"] = splitext(statdata[1].desc)[2]
    end
end


"""
    newext!(inventory::SortedDict, convert::Bool)

Check and update the converted file extension in the inventory.
If `convert` is `false`, the target extension is set to the original file extension.
"""
function newext!(inventory::SortedDict, convert::Bool)::Nothing
    # Ingnore newext, if no conversion is requested
    convert || return
    # Definitions
    target = newext()
    ext = inventory["metadata"]["file"]["ext"]
    new_ext = inventory["metadata"]["file"]["newext"]
    # Return, if target is identical to original extension
    target == ext && return
    if isempty(new_ext)
        # Save extension for conversion in inventory, if not done before
        target == ext && throw(ArgumentError("conversion to the same file type ($ext) is not allowed"))
        inventory["metadata"]["file"]["newext"] = target
    elseif target ≠ new_ext
        # Check previous extensions are consistent with current conversions
        throw(ArgumentError("only conversion to 1 new file type per inventory are allowed "*
            "(current: $new_ext, target: $target)"))
    end
    return
end


"""
    remotefiles!(
        inventory::SortedDict,
        granules::Dict{Int,Dict{Date,Vector{SFTP.StatStruct}}}
    )

Add file stats from `granules` to the `inventory`.
"""
function remotefiles!(
    inventory::SortedDict,
    granules::Dict{Int,Dict{Date,Vector{SFTP.StatStruct}}}
)::Nothing
    # Get stats of remote files (without the current and parent folders)
    for stats in values(granules), (date, statdata) in stats
        inventory["dates"][date] = SortedDict{String,SortedDict{String,Any}}()
        for stat in statdata
            inventory["dates"][date][stat.desc] = SortedDict(
                "size" => stat.size,
                "mtime" => Date(Dates.unix2datetime(stat.mtime))
            )
            haskey(inventory, "temp") && haskey(inventory["temp"], stat.desc) &&
                (inventory["dates"][date][stat.desc]["size"*inventory["metadata"]["file"]["newext"]] =
                    inventory["temp"][stat.desc])
        end
    end
end


"""
    datecheck!(
        icare::SFTP.Client,
        inventory::SortedDict,
        granules::Dict{Int,Dict{Date,Vector{SFTP.StatStruct}}},
        date::Date
    -> Bool

Add stats from the `icare` server of the given `date` to the `granules` dict, if missing in
the `inventory`. Indicate an update by the returned `Bool`.
"""
function datecheck!(
    icare::SFTP.Client,
    inventory::SortedDict,
    granules::Dict{Int,Dict{Date,Vector{SFTP.StatStruct}}},
    date::Date
)::Bool
    # Entry checks
    date in inventory["gaps"] && return false
    haskey(inventory["dates"], date) && return false
    # Save remote file stats to thread dict
    granules[Threads.threadid()][date] = SFTP.statscan(icare, Dates.format(date, "yyyy/yyyy_mm_dd"))
    return true
end


"""
    update_stats!(
        icare::SFTP.Client,
        inventory::SortedDict,
        file::File,
        resync::Bool,
        logger::Logging.ConsoleLogger
    )

Update the `file` stats in the `inventory` with the remote `icare` server.
If the size of the converted file does not match the `inventory`, it is updated, too.
Ignore already checked dates, if the `inventory` was already `resync`ed.
Reset data for files previously in the database, but currently not available on the server.
Log events to `logger`.
"""
function update_stats!(
    icare::SFTP.Client,
    inventory::SortedDict,
    file::File,
    resync::Bool,
    logger::Logging.ConsoleLogger
)::Nothing
    # Skip, if already updated at the beginning
    resync && return
    # Get stats of all files for the given date
    stats = SFTP.statscan(icare, file.dir.src)
    names = [splitext(s.desc)[1] for s in stats]
    # Set file sizes of possible obsolete files to zero, but keep files as reference
    obsolete = setdiff(keys(inventory["dates"][file.date]), names)
    lock(thread) do
        for obsolete_file in obsolete
            delete!(inventory["dates"][file.date], obsolete_file)
        end
        if !isempty(obsolete)
            Logging.with_logger(logger) do
                @warn "deleting obsolete files for $(file.date)" obsolete
                inventory["metadata"]["database"]["updated"] = Dates.now()
            end
        end
    end
    # Sort files by names (equals to time)
    sortorder = sortperm(names)

    # Update file stats in inventory
    updated = false
    for stat in stats
        desc = splitext(stat.desc)[1]
        # Compare inventory with remote
        if stat.size ≠ inventory["dates"][file.date][desc]["size"] ||
            (Date∘Dates.unix2datetime)(stat.mtime) ≠ inventory["dates"][file.date][desc]["mtime"]
            updated = true
            inventory["dates"][file.date][desc]["size"] = stat.size
            inventory["dates"][file.date][desc]["mtime"] = (Date∘Dates.unix2datetime)(stat.mtime)
        end
        # Compare h5 size with current conversion
        if haskey(inventory["dates"][file.date][desc], "size"*file.newext)
            if isfile(file.location.target) &&
                inventory["dates"][file.date][desc]["size"*file.newext] ≠ filesize(file.location.target)
                lock(thread) do
                    updated = true
                    inventory["dates"][file.date][desc]["size"*file.newext] = filesize(file.location.target)
                end
            else
                delete!(inventory["dates"][file.date][desc], "size"*file.newext)
            end
        end
    end
    updated && lock(thread) do
        Logging.with_logger(logger) do
            @info "updated file stats for $(file.date)"
            inventory["metadata"]["database"]["updated"] = Dates.now()
        end
    end
    return
end


## Functions processing data gaps

"""
    data_gaps!(inventory::SortedDict, dates::Vector{Date})

Add missing data gaps to the `inventory` from gaps in `dates`.
"""
function data_gaps!(inventory::SortedDict)::Nothing
    # Determine data gaps in the date range
    db = inventory["metadata"]["database"]
    new_gaps = setdiff(db["start"]:db["stop"], keys(inventory["dates"]))
    union!(inventory["gaps"], new_gaps) |> sort!
    db["missing"] = length(inventory["gaps"])
    return
end


"""
    display_gaps(
        inventory::SortedDict,
        daterange::@NamedTuple{start::Date,stop::Date},
        logger::Logging.ConsoleLogger
    )

Log data gaps in the `inventory` in the given `daterange` to `logger`.
Combine single dates in the `inventory` metadata to date ranges.
"""
function display_gaps(
    inventory::SortedDict,
    daterange::@NamedTuple{start::Date,stop::Date},
    logger::Logging.ConsoleLogger
)::Nothing
    #* Get gaps in current date range
    database = inventory["metadata"]["database"]
    current_gaps = inventory["gaps"] |> filter(d -> daterange.start ≤ d ≤ daterange.stop)
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


##  Functions for resetting or saving the inventory

"""
    clear_dates!(inventory::SortedDict)

Clear all data for dates in the `inventory`, but save the converted file sizes in a temp entry.
"""
function clear_dates!(inventory::SortedDict)::Nothing
    # Save converted sizes to suppress involuntary Downloads
    converted = Dict{String,Int}()
    for date in values(inventory["dates"]), granule in date
        haskey(granule[2], "size"*inventory["metadata"]["file"]["newext"]) &&
            (converted[granule[1]] = granule[2]["size"*inventory["metadata"]["file"]["newext"]])
    end
    inventory["temp"] = converted
    # Delete all dates
    empty!(inventory["dates"])
    return
end


"""
    save_inventory(inventory::SortedDict, t::DateTime)

Save the `inventory` to `<product path>/.inventory.yaml` if changes occurred since time `t`.
"""
function save_inventory(inventory::SortedDict, t::DateTime)::Nothing
    # Return, if no changes occured since time `t`
    inventory["metadata"]["database"]["updated"] > t || return
    # Define inventory file
    file = joinpath(inventory["metadata"]["local"]["path"], ".inventory.yaml")
    @info "saving inventory to '$file'"
    # Update statistics
    inventory["metadata"]["database"]["dates"] = length(inventory["dates"])
    inventory["metadata"]["file"]["count"] = sum(length.(inventory["dates"][date]
        for date in keys(inventory["dates"])))
    filedata = [d for date in keys(inventory["dates"]) for d in values(inventory["dates"][date])]
    inventory["metadata"]["file"]["conversions"] =
        haskey.(filedata, "size"*inventory["metadata"]["file"]["newext"]) |> count
    inventory["metadata"]["database"]["size"] = (get.(filedata, "size", 0) |> sum)/1e9
    inventory["metadata"]["database"]["converted size"] =
        (get.(filedata, "size"*inventory["metadata"]["file"]["newext"], 0) |> sum)/1e9
    inventory["metadata"]["database"]["updated"] = Dates.now()
    # Save invetory with updated mtime
    YAML.write_file(file, inventory)
end


## Functions for validations

"""
    check_localroot!(
        inventory::SortedDict,
        root::AbstractString,
        product::AbstractString
    )

Check, if the `root` has changed and update the root path and the path to the
`product` main folder in the `inventory`.
"""
function check_localroot!(
    inventory::SortedDict,
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
        inventory["metadata"]["database"]["updated"] = Dates.now()
    end
    return
end
