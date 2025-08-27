## Routines related to creating and processing the local inventory
## Functions for loading and setting up the inventory

"""
    product_database!(
        icare::SFTP.Client,
        inventory::OrderedDict,
        root::String,
        product::String,
        daterange::@NamedTuple{start::Date,stop::Date},
        resync::Bool,
        logger::Logging.ConsoleLogger
    )

Return the inventory of `icare` server-side data files for the `product` in the `remoteroot`
directory. Either read the database from the yaml file in the `product` folder or initialise
a new database. If the `daterange` of the selected dates is (partly) outside the
`inventory` date range, the `inventory` is updated for these extended periods.
The whole inventory can be updated by setting `resync` to `true`.
Additional checks are performed, whether the `root` folder was moved. In that case, the
inventory is updated and a warning is issued.
Updates are logged to the screen and the log file with `logger`.
"""
function product_database!(
    icare::SFTP.Client,
    inventory::OrderedDict,
    root::String,
    product::String,
    daterange::@NamedTuple{start::Date,stop::Date},
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
    sync_database!(icare, inventory, years, daterange, logger)
end


"""
    load_inventory!(inventory::OrderedDict, file::AbstractString)

Load data from a yaml `file` to the `inventory`.
"""
function load_inventory!(inventory::OrderedDict, file::AbstractString)::Nothing
    @info "loading local inventory"
    for (key, value) in YAML.load_file(file, dicttype=OrderedDict)
        inventory[key] = value
    end
end


"""
    new_inventory!(
        icare::SFTP.Client,
        inventory::OrderedDict,
        root::String,
        product::String,
        logger::Logging.ConsoleLogger
    )

Initialise a new and empty inventory.
"""
function new_inventory!(
    icare::SFTP.Client,
    inventory::OrderedDict,
    root::String,
    product::String,
    logger::Logging.ConsoleLogger
)::Nothing
    @info "initialising new inventory"
    Logging.with_logger(logger) do
        @info "initialising new, empty inventory"
    end
    inventory["metadata"] = OrderedDict{String,Any}(
        "file" => OrderedDict{String,Any}("count" => 0, "converted" => 0),
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
            "updated" => Dates.now()
        )
    )
    inventory["dates"] = OrderedDict{Date,OrderedDict}()
    inventory["gaps"] = Vector{Date}()
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

Filter `years` to keep only years within the `daterange` and outside the known date range of
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
        inventory["metadata"]["file"]["converted"] = 0
        inventory["metadata"]["database"]["dates"] = 0
        inventory["metadata"]["database"]["missing"] = 0
        inventory["metadata"]["database"]["start"] = Date(9999)
        inventory["metadata"]["database"]["stop"] = Date(0)
    end
    return
end


## Functions for synchronisation

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
)::Nothing
    # Monitor updates
    updated = false
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
        pm.@showprogress dt=0.1 desc="$year:" for date in dates
            updated |= new_date!(inventory, date)
            updated |= remotefiles!(icare, inventory, date)
        end
        # Ensure complete years get saved in the local inventory, if something during database setups happens
        updated && (inventory["metadata"]["database"]["updated"] = Dates.now())
        inventory["metadata"]["database"]["start"] = minimum(inventory["dates"].keys)
        inventory["metadata"]["database"]["stop"] = maximum(inventory["dates"].keys)
    end
    # Delete possible temporary inventory data
    delete!(inventory, "temp")
    # Save data gaps to inventory
    data_gaps!(inventory)
    display_gaps(inventory, daterange, logger)

    updated && Logging.with_logger(logger) do
        @info "inventory synced with ICARE server in date range $(database["start"]) – $(database["stop"])"
        inventory["metadata"]["database"]["updated"] = Dates.now()
    end
    return
end


"""
    remotefiles!(
        icare::SFTP.Client,
        inventory::OrderedDict,
        date::Date
    ) -> Bool

Add file stats for all granules of the `date` based on the `icare` server data. File stats are
only added for dates with no file data. Indicate updates in the `inventory` by the returned `Bool`.
"""
function remotefiles!(
    icare::SFTP.Client,
    inventory::OrderedDict,
    date::Date
)::Bool
    # Entry checks
    date in inventory["gaps"] && return false
    isempty(inventory["dates"][date]) || return false
    # Get stats of remote files (without the current and parent folders)
    stats = SFTP.statscan(icare, Dates.format(date, "yyyy/yyyy_mm_dd"))
    files = [splitext(s.desc)[1] for s in stats]
    sortorder = sortperm(files)
    # Save file stats to new inventory entry
    for i in sortorder
        inventory["dates"][date][files[i]] = OrderedDict(
            "size" => stats[i].size,
            "mtime" => Date(Dates.unix2datetime(stats[i].mtime))
        )
        # Restore converted file sizes during resynchronisaton
        haskey(inventory, "temp") && haskey(inventory["temp"], files[i]) &&
            (inventory["dates"][date][files[i]]["converted"] = inventory["temp"][files[i]])
    end
    # Update inventory metadata
    file = inventory["metadata"]["file"]
    haskey(file, "ext") || (file["ext"] = splitext(stats[1].desc)[2])
    return true
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
    update_stats!(
        icare::SFTP.Client,
        inventory::OrderedDict,
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
    inventory::OrderedDict,
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
    obsolete = setdiff(inventory["dates"][file.date].keys, names)
    lock(thread) do
        for file in obsolete
            inventory["dates"][file.date][file]["size"] = 0
            delete!(inventory["dates"][file.date][file], "converted")
        end
        if !isempty(obsolete)
            Logging.with_logger(logger) do
                @warn "resetting file stats for date $(file.date)" obsolete
            end
        end
    end
    # Sort files by names (equals to time)
    sortorder = sortperm(names)

    # Update file stats in inventory
    updated = false
    for i in sortorder
        # Compare inventory with remote
        dbfile = inventory["dates"][file.date][names[i]]
        if stats[i].size == dbfile["size"] &&
            (Date∘Dates.unix2datetime)(stats[i].mtime) == dbfile["mtime"]
            lock(thread) do
                updated = true
                inventory["dates"][file.date][names[i]] = OrderedDict(
                    "size" => stats[i].size,
                    "mtime" => Date(Dates.unix2datetime(stats[i].mtime))
                )
            end
        end
        # Compare h5 size with current conversion
        if isfile(file.location.target) && haskey(dbfile, "converted") &&
            dbfile["converted"] ≠ filesize(file.location.target)
            lock(thread) do
                updated = true
                dbfile["converted"] = filesize(file.location.target)
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
    data_gaps!(inventory::OrderedDict, dates::Vector{Date})

Add missing data gaps to the `inventory` from gaps in `dates`.
"""
function data_gaps!(inventory::OrderedDict)::Nothing
    # Determine data gaps in the date range
    db = inventory["metadata"]["database"]
    new_gaps = setdiff(db["start"]:db["stop"], inventory["dates"].keys)
    union!(inventory["gaps"], new_gaps) |> sort!
    db["missing"] = length(inventory["gaps"])
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
    clear_dates!(inventory::OrderedDict)

Clear all data for dates in the `inventory`, but save the converted file sizes in a temp entry.
"""
function clear_dates!(inventory::OrderedDict)::Nothing
    # Save converted sizes to suppress involuntary Downloads
    converted = Dict{String,Int}()
    for date in inventory["dates"].vals, granule in date
        haskey(granule[2], "converted") && (converted[granule[1]] = granule[2]["converted"])
    end
    inventory["temp"] = converted
    # Delete all dates
    empty!(inventory["dates"])
    return
end


"""
    save_inventory(inventory::OrderedDict, t::DateTime)

Save the `inventory` to `<product path>/.inventory.yaml` if changes occurred since time `t`.
"""
function save_inventory(inventory::OrderedDict, t::DateTime)::Nothing
    # Return, if no changes occured since time `t`
    inventory["metadata"]["database"]["updated"] > t || return
    # Define inventory file
    file = joinpath(inventory["metadata"]["local"]["path"], ".inventory.yaml")
    @info "saving inventory to '$file'"
    # Update statistics
    inventory["metadata"]["database"]["dates"] = length(inventory["dates"])
    inventory["metadata"]["file"]["count"] = sum(length.(inventory["dates"][date] for date in inventory["dates"].keys))
    filedata = vcat([d.vals for d in [inventory["dates"][date] for date in inventory["dates"].keys]]...)
    inventory["metadata"]["file"]["converted"] = haskey.(filedata, "converted") |> count
    inventory["metadata"]["database"]["updated"] = Dates.now()
    # Save invetory with updated mtime
    YAML.write_file(file, inventory)
end


## Functions for validations

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
        inventory["metadata"]["database"]["updated"] = Dates.now()
    end
    return
end
