## Routines related to creating and processing the local inventory
## API functions

"""
    load_inventory(path::AbstractString, logger::logex.AbstractLogger=logex.global_logger()) -> SortedDict

Load the database inventory from the `path` to the product folder (and a hidden yaml file)
to a `SortedDict`, which can be processed by other ICARE functions.

If a `logger` is provided, events are logged to it in addition to the global logger
(typically the console).

See also: [`list_inventory`](@ref)
"""
function load_inventory(path::AbstractString, logger::logex.AbstractLogger=logex.global_logger())::SortedDict
    inventory = SortedDict{String,Any}()
    file = joinpath(path, ".inventory.yaml")
    isfile(file) || throw(ArgumentError(string("no inventory found in '$path', ",
        "check that the path to the product folder exists and that the inventory has been created")))
    load_inventory!(inventory, file, logger)
end


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
        logger::Logger
    )

Initiate the inventory of `icare` server-side data files for the `product` in the `remoteroot`
directory. Either read the database from the yaml file in the `product` folder or initialise
a new database. If the `daterange` of the selected dates is (partly) outside the
`inventory` date range, the `inventory` is updated for these extended periods.
The whole inventory can be updated by setting `resync` to `true`.
Additional checks are performed, whether the `root` folder was moved. In that case, the
inventory is updated and a warning is issued.
The target file extension for converted files is set based on the `convert` option.
The `logger` parameter should be a NamedTuple with `file` and `tee` logger fields.
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
    logger::Logger
)::Nothing
    # Defining inventory source file and available years on server
    database = joinpath(root, product, ".inventory.yaml")
    years = parse.(Int, readdir(icare))
    if isfile(database)
        # Read available inventory
        load_inventory!(inventory, database, logger.tee)
        check_localroot!(inventory, root, product, logger.tee)
        # Update years of interest based on inventory and update options
        filter_years!(inventory, years, daterange, resync, logger.tee)
    else
        # Init empty inventory, if yaml is missing
        new_inventory!(icare, inventory, root, product, logger.tee)
    end
    sync_database!(icare, inventory, years, daterange, convert, resync, logger.tee)
end


"""
    load_inventory!(
        inventory::SortedDict,
        file::AbstractString,
        logger::logex.AbstractLogger=logex.global_logger()
    ) -> SortedDict

Load data from a yaml `file` to the `inventory`.
If a `logger` is provided, events are logged to this logger rather than the global logger.
The function returns an additional reference to the modified `inventory`.
"""
function load_inventory!(
    inventory::SortedDict,
    file::AbstractString,
    logger::logex.AbstractLogger=logex.global_logger()
)::SortedDict
    # Load inventory with sorted entries
    for (key, value) in YAML.load_file(file, dicttype=SortedDict)
        inventory[key] = value
    end
    # Reorder database metadata entries in a more logical order
    inventory["metadata"]["database"] = OrderedDict(
        "dates" => inventory["metadata"]["database"]["dates"],
        "missing" => inventory["metadata"]["database"]["missing"],
        "size" => inventory["metadata"]["database"]["size"],
        "downloaded size" => inventory["metadata"]["database"]["downloaded size"],
        "converted size" => inventory["metadata"]["database"]["converted size"],
        "start" => inventory["metadata"]["database"]["start"],
        "stop" => inventory["metadata"]["database"]["stop"],
        "created" => inventory["metadata"]["database"]["created"],
        "updated" => inventory["metadata"]["database"]["updated"]
    )
    inventory["metadata"]["file"] = OrderedDict(
        "count" => inventory["metadata"]["file"]["count"],
        "downloads" => inventory["metadata"]["file"]["downloads"],
        "conversions" => inventory["metadata"]["file"]["conversions"],
        "ext" => inventory["metadata"]["file"]["ext"],
        "newext" => inventory["metadata"]["file"]["newext"]
    )
    inventory["metadata"]["remote"] = OrderedDict(
        "product" => inventory["metadata"]["remote"]["product"],
        "path" => inventory["metadata"]["remote"]["path"],
        "root" => inventory["metadata"]["remote"]["root"]
    )
    # Convert version to version number
    inventory["metadata"]["version"] = VersionNumber(inventory["metadata"]["version"])
    # Note: In the future, add migrations here for older inventory versions
    # Logg success and return inventory
    logex.with_logger(logger) do
        @info "inventory loaded from '$file'"
    end
    return inventory
end


"""
    new_inventory!(
        icare::SFTP.Client,
        inventory::SortedDict,
        root::String,
        product::String,
        convert::Bool,
        logger::logex.AbstractLogger
    )

Initialise a new and empty inventory.
"""
function new_inventory!(
    icare::SFTP.Client,
    inventory::SortedDict,
    root::String,
    product::String,
    logger::logex.AbstractLogger
)::Nothing
    logex.with_logger(logger) do
        @info "initialising new inventory"
    end
    inventory["dates"] = SortedDict{Date,SortedDict}()
    inventory["gaps"] = Vector{Date}()
    inventory["metadata"] = SortedDict(
        "database" => OrderedDict{String,Any}(
            "dates" => 0,
            "missing" => 0,
            "size" => 0,
            "downloaded size" => 0,
            "converted size" => 0,
            "start" => Date(9999),
            "stop" => Date(0),
            "created" => Dates.now(),
            "updated" => Dates.now()
        ),
        "file" => OrderedDict(
            "count" => 0,
            "downloads" => 0,
            "conversions" => 0,
            "ext" => "",
            "newext" => ""
        ),
        "local" => SortedDict{String,String}(
            "path" => realpath(joinpath(root, product)),
            "root" => realpath(root)
        ),
        "remote" => OrderedDict{String,String}(
            "product" => product,
            "path" => icare.uri.path,
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
        logger::logex.AbstractLogger
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
    logger::logex.AbstractLogger
)::Nothing
    if !resync
        # Default option: update outside known date range
        logex.with_logger(logger) do
            @info "checking for new data not yet considered in the inventory"
        end
        # ℹ border years are only considered, if the new date is outside the known date range
        # ℹ of the inventory
        start, stop = inventory["metadata"]["database"]["start"], inventory["metadata"]["database"]["stop"]
        lt = daterange.start ≥ start || Dates.dayofyear(start) == 1 ? (<) : (≤)
        gt = daterange.stop ≤ stop || Dates.dayofyear(stop) == Dates.daysinyear(stop) ? (>) : (≥)
        filter!(t -> lt(t, Dates.year(start)) || gt(t, Dates.year(stop)), years)
    else # force update
        logex.with_logger(logger) do
            @info "checking inventory dates for updates"
        end
        clear_dates!(inventory)
        empty!(inventory["gaps"])
        inventory["metadata"]["file"]["count"] = 0
        inventory["metadata"]["file"]["conversions"] = 0
        inventory["metadata"]["database"]["dates"] = 0
        inventory["metadata"]["database"]["missing"] = 0
        inventory["metadata"]["database"]["size"] = 0
        inventory["metadata"]["database"]["downloaded size"] = 0
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
        resync::Bool,
        convert::Bool,
        logger::logex.AbstractLogger
    )

Sync the `inventory` with the `icare` server for the given `daterange` and `years`.
Consider conversion to a new file format based on the `convert` option.
Ensure converted file sizes are not lost during `resync`. Log events to `logger`.
"""
function sync_database!(
    icare::SFTP.Client,
    inventory::SortedDict,
    years::Vector{Int},
    daterange::@NamedTuple{start::Date,stop::Date},
    convert::Bool,
    resync::Bool,
    logger::logex.AbstractLogger
)::Nothing
    # Monitor updates
    updated = false
    # Define views on metadata and save current date range
    database = inventory["metadata"]["database"]
    # Enforce to continue any interrupted resync
    haskey(inventory, "temp") && (resync |= true)
    #* Loop over dates in online database
    @info "syncing database with ICARE server and identifying files to download"
    for year in years
        # Save new years to inventory and sync dates with server
        folders = readdir(icare, string(year))
        dates = Date.(folders, "yyyy_mm_dd")
        isempty(dates) && continue
        #* Loop over dates in the current year and add missing dates to inventory
        pm.@showprogress dt=0.1 desc="$year:" for date in dates
            updated |= remotefiles!(icare, inventory, date, resync)
        end
        # Ensure complete years get saved in the local inventory, if something during database setups happens
        updated && (inventory["metadata"]["database"]["updated"] = Dates.now())
        inventory["metadata"]["database"]["start"] = minimum(keys(inventory["dates"]))
        inventory["metadata"]["database"]["stop"] = maximum(keys(inventory["dates"]))
    end
    # Save extension types to inventory
    ext!(icare, inventory)
    newext!(inventory, convert)
    # Delete possible temporary inventory data
    delete!(inventory, "temp")
    # Ignore flagged granules
    if resync && haskey(inventory, "ignore")
        for (date, granules) in inventory["ignore"], granule in keys(granules)
            if haskey(inventory["dates"], date) && haskey(inventory["dates"][date], granule)
                delete!(inventory["dates"][date], granule)
            end
            if isempty(inventory["dates"][date])
                delete!(inventory["dates"], date)
            end
        end
    end
    # Save data gaps to inventory
    data_gaps!(inventory)
    gaps = combine_gaps(inventory, daterange, logger)

    updated && logex.with_logger(logger) do
        @info "inventory synced with ICARE server in date range $(database["start"]) – $(database["stop"])"
        inventory["metadata"]["database"]["updated"] = Dates.now()
    end
    return
end


"""
    ext!(icare::SFTP.Client, inventory::SortedDict)

Add the original file extension to the inventory metadata if missing.
"""
function ext!(icare::SFTP.Client, inventory::SortedDict)::Nothing
    isempty(inventory["metadata"]["file"]["ext"]) || return
    # Get first date in inventory
    d = inventory["dates"] |> first |> first
    # Check folder of first date for file extension
    stats = SFTP.statscan(icare, Dates.format(d, "yyyy/yyyy_mm_dd"))
    ext = splitext(stats[1].desc)[2]
    inventory["metadata"]["file"]["ext"] = ext
    return
end


"""
    newext!(inventory::SortedDict, convert::Bool)

Check and update the converted file extension in the inventory.
If `convert` is `false`, the target extension is set to the original file extension.
"""
function newext!(inventory::SortedDict, convert::Bool)::Nothing
    # Ignore newext, if no conversion is requested
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
        icare::SFTP.Client,
        inventory::SortedDict,
        date::Date,
        resync::Bool
    ) -> Bool

Add file stats for all granules of the `date` based on the `icare` server data. File stats are
only added for dates not previously checked. Ensure proper data recovery during `resync`.
Indicate updates in the `inventory` by the returned `Bool`.
"""
function remotefiles!(
    icare::SFTP.Client,
    inventory::SortedDict,
    date::Date,
    resync::Bool
)::Bool
    # Entry checks
    date in inventory["gaps"] && return false
    haskey(inventory["dates"], date) && return false
    # Get stats of remote files (without the current and parent folders)
    stats = SFTP.statscan(icare, Dates.format(date, "yyyy/yyyy_mm_dd"))
    granules = SortedDict{String,SortedDict}()
    for stat in stats
        desc = splitext(stat.desc)[1]
        # Update inventory with current file/granule stats
        granules[desc] = SortedDict(
            "size" => stat.size,
            "mtime" => Date(Dates.unix2datetime(stat.mtime))
        )
        # Restore converted file sizes during re-synchronisation
        if resync && haskey(inventory, "temp") && haskey(inventory["temp"], desc) &&
            inventory["temp"][desc]["size"] == granules[desc]["size"]
            newext = "size"*inventory["metadata"]["file"]["newext"]
            granules[desc][newext] = inventory["temp"][desc][newext]
        end
    end
    # Only save complete dates to ensure no loss of data during crashes
    inventory["dates"][date] = granules
    return true
end


"""
    update_stats!(
        icare::SFTP.Client,
        inventory::SortedDict,
        file::File,
        resync::Bool,
        logger::logex.AbstractLogger
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
    logger::logex.AbstractLogger
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
            logex.with_logger(logger) do
                @warn "deleting obsolete files for $(file.date) in inventory" obsolete
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
        logex.with_logger(logger) do
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
    combine_gaps(
        inventory::SortedDict,
        daterange::@NamedTuple{start::Date,stop::Date},
        logger::logex.AbstractLogger
    ) -> Vector{String}

Combine data gaps with single dates in the `inventory` in the given `daterange` to date ranges
and return a vector of strings with beautified ranges. Log warnings, when out of `daterange`
to `logger`.
"""
function combine_gaps(
    inventory::SortedDict,
    daterange::@NamedTuple{start::Date,stop::Date},
    logger::logex.AbstractLogger
)::Vector{String}
    #* Get gaps in current date range
    database = inventory["metadata"]["database"]
    current_gaps = inventory["gaps"] |> filter(d -> daterange.start ≤ d ≤ daterange.stop)
    isempty(current_gaps) && return String[]
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
    # Log out-of-range warnings
    logex.with_logger(logger) do
        Date(0) < daterange.start < database["start"] &&
            @warn "no data available before $(database["start"])"
        Date(9999) > daterange.stop > database["stop"] &&
            @warn "no data available after $(database["stop"])"
        length(gaps) > 0 && @info "there are data gaps in the current date range" gaps
    end
    return gaps
end


##  Functions for resetting or saving the inventory

"""
    clear_dates!(inventory::SortedDict)

Clear all data for dates in the `inventory`, but save the converted file sizes in a temp entry.
"""
function clear_dates!(inventory::SortedDict)::Nothing
    # Save converted sizes to suppress involuntary Downloads
    converted = SortedDict{String,SortedDict}()
    for date in values(inventory["dates"]), granule in date
        newext = "size"*inventory["metadata"]["file"]["newext"]
        haskey(granule[2], newext) &&
            (converted[granule[1]] = SortedDict(
                "size" => granule[2]["size"],
                newext => granule[2][newext]
            ))
    end
    inventory["temp"] = converted
    # Delete all dates
    empty!(inventory["dates"])
    return
end


"""
    save_inventory(inventory::SortedDict, logger::logex.AbstractLogger, t::DateTime)::Nothing

Save the `inventory` to `<product path>/.inventory.yaml` if changes occurred since time `t`.
Log success to `logger`.
"""
function save_inventory(inventory::SortedDict, logger::logex.AbstractLogger, t::DateTime)::Nothing
    # Return, if no changes occured since time `t`
    inventory["metadata"]["database"]["updated"] > t || return
    # Update statistics
    stats = inventory_stats(inventory, collect(Date, keys(inventory["dates"])))
    inventory["metadata"]["database"]["dates"] = stats["dates"]
    inventory["metadata"]["database"]["size"] = stats["size"]
    inventory["metadata"]["database"]["downloaded size"] = stats["downloaded size"]
    inventory["metadata"]["database"]["converted size"] = stats["converted size"]
    inventory["metadata"]["file"]["count"] = stats["filecount"]
    inventory["metadata"]["file"]["downloads"] = stats["downloaded files"]
    inventory["metadata"]["file"]["conversions"] = stats["converted files"]
    inventory["metadata"]["database"]["updated"] = Dates.now()
    # Save inventory to file
    file = joinpath(inventory["metadata"]["local"]["path"], ".inventory.yaml")
    YAML.write_file(file, inventory)
    logex.with_logger(logger) do
        @info "inventory saved to '$file'"
    end
end


"""
    inventory_stats(
        inventory::SortedDict,
        dates::Vector{Date};
        by_year::Bool=false
    ) -> Dict{String,Any}

Calculate statistics for the given `dates` in the `inventory`. If `by_year` is set to `true`,
`dates` are expected to be of the same year and statistics are calculated only for that year.
Return a dictionary with the statistics.
"""
function inventory_stats(
    inventory::SortedDict,
    dates::Vector{Date};
    by_year::Bool=false
)::Dict{String,Any}
    # Pre-extract metadata
    newext = inventory["metadata"]["file"]["newext"]
    ext = inventory["metadata"]["file"]["ext"]
    newext_key = "size"*newext

    # Calculate all inventory-based stats in a single pass
    filecount = 0
    conversions = 0
    size_sum = 0
    for date in dates
        granules = inventory["dates"][date]
        filecount += length(granules)
        for granule_data in values(granules)
            size_sum += get(granule_data, "size", 0)
            if haskey(granule_data, newext_key)
                conversions += 1
            end
        end
    end

    # Scan the local database (restrict to the given year, if by_year is true)
    db = by_year ? inventory_dates(inventory, none, dates) : inventory_dates(inventory, none)
    data = localscan(db, inventory["metadata"]["local"]["path"], intersect)
    num_years = by_year ? 1 : Dates.year.(dates) |> unique |> length
    # Get file and size statistics
    downloaded_files = 0
    converted_files = 0
    downloaded_size = 0
    converted_size = 0
    for file in data.files
        if endswith(file, ext)
            downloaded_files += 1
            downloaded_size += filesize(file)
        elseif !isempty(newext) && endswith(file, newext)
            converted_files += 1
            converted_size += filesize(file)
        end
    end

    # Build stats dict
    return Dict{String,Any}(
        "dates" => length(dates),
        "filecount" => filecount,
        "conversions" => conversions,
        "size" => size_sum,
        "converted size" => converted_size,
        "downloaded files" => downloaded_files,
        "converted files" => converted_files,
        "downloaded size" => downloaded_size
    )
end


## Functions for validations

"""
    check_localroot!(
        inventory::SortedDict,
        root::AbstractString,
        product::AbstractString,
        logger::logex.AbstractLogger
    )

Check, if the `root` has changed and update the root path and the path to the
`product` main folder in the `inventory`. Log changes to `logger`.
"""
function check_localroot!(
    inventory::SortedDict,
    root::AbstractString,
    product::AbstractString,
    logger::logex.AbstractLogger
)::Nothing
    # Define paths and update status
    root = realpath(root)
    origin = inventory["metadata"]["local"]["root"]
    # Correct and log differences between current paths and inventory paths
    if root ≠ origin
        origin = joinpath(origin, product)
        update = joinpath(root, product)
        logex.with_logger(logger) do
            @warn "product folder was recently moved; updating inventory" origin update
        end
        inventory["metadata"]["local"]["root"] = root
        inventory["metadata"]["local"]["path"] = update
        inventory["metadata"]["database"]["updated"] = Dates.now()
    end
    return
end
