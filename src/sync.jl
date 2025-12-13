## Routines related to syncing local and remote directories

## API functions
"""
    clean(
        root::AbstractString=".";
        keepext::Union{AbstractString,Vector{<:AbstractString}}="",
        erase::Extension=none,
        logfile::String = "clean.log",
        loglevel::Symbol = :Debug
    ) -> SortedDict{String,<:Any}

    clean(
        inventory::SortedDict{String,<:Any};
        keepext::Union{AbstractString,Vector{<:AbstractString}}="",
        erase::Extension=none,
        logfile::String = "clean.log",
        loglevel::Symbol = :Debug
    ) -> SortedDict{String,<:Any}

Clean a product folder recursively from all content not listed in the inventory, i.e. not
available on the ICARE server. The function has two methods – you can either provide an
`AbstractString` with the path of the product folder or the inventory as `SortedDict` of the
product. Both methods return the `inventory` for reference.

# Keyword Arguments

- `keepext::Union{AbstractString,Vector{<:AbstractString}}`: One or multiple (as vector)
  file extensions (e.g. `".log"`, `[".yaml", ".log"]`) to keep during clean-up even if not part of
  the inventory. Can be used to keep log or metadata files.
- `erase::Extension`: Allows to clean up the database itself. You can choose to erase
  `original` files (defined by `"ext"` in the inventory metadata), `converted` files
  (defined by `"newext"` in the inventory metadata) or `none` of the file types.
- `logfile::String`: The name of the log file (default: `"clean.log"`; the name will be appended
  by the current date and time).
- `loglevel::Symbol`: The log level for the download process (default: `:Debug`).
"""
function clean end

function clean(
    root::AbstractString=".";
    keepext::Union{AbstractString,Vector{<:AbstractString}}="",
    erase::Extension=none,
    logfile::String = "clean.log",
    loglevel::Symbol = :Debug
)::SortedDict{String,<:Any}
    # Load the inventory from the yaml in the given root
    path = joinpath(root, ".inventory.yaml") |> realpath
    inventory = SortedDict{String,<:Any}()
    load_inventory!(inventory, path)
    # Call the clean method for the inventory
    clean(inventory; keepext, erase, logfile, loglevel)
end

function clean(
    inventory::SortedDict{String,<:Any};
    keepext::Union{AbstractString,Vector{<:AbstractString}}="",
    erase::Extension=none,
    logfile::String = "clean.log",
    loglevel::Symbol = :Debug
)::SortedDict{String,<:Any}
    # Start
    logfile, level = init_logging(logfile, inventory["metadata"]["local"]["path"], loglevel)
    @info "logging to '$logfile'"
    open(logfile, "w") do logio
        logger = Logging.ConsoleLogger(logio, level, show_limited=false)
        # Rearrange inventory for better processing
        @info "analyse inventory and local database"
        database = inventory_dates(inventory, erase)
        # Scan inventory for additional files and folders
        root = inventory["metadata"]["local"]["path"]
        extra = localscan(database, root, setdiff)
        # Remove current logfile from extra files
        filter!(!isequal(logfile), extra.files)
        # Keep specified extensions
        if !isempty(keepext)
            keepext isa Vector || (keepext = [keepext])
            for ext in keepext
                filter!(!endswith(ext), extra.files)
            end
        end
        # Clean up local database
        if confirm(extra)
            Logging.with_logger(logger) do
                s = length(extra.files) == 1 ? "" : "s"
                s_ = length(extra.folders) == 1 ? "" : "s"
                @warn("cleaning $(length(extra.files)) file$s and $(length(extra.folders)) folder$s_",
                    extra.files, extra.folders)
            end
            rm.(extra.files, force=true)
            rm.(extra.folders, recursive=true, force=true)
        else
            @info "aborting clean-up"
            Logging.with_logger(logger) do
                @info "cleaning cancelled"
            end
        end
    end
    return inventory
end


"""
    ignore!(
        inventory::SortedDict{String,<:Any},
        dates::AbstractDict{Date, Any};
        logfile::String = "clean.log",
        loglevel::Symbol = :Debug
    ) -> SortedDict{String,<:Any}

Flag the `dates` as ignored in the `inventory` and ensure they will not get downloaded.
Log events with the specified `loglevel` to the `logfile`. A timestamp is appended to the log
file name automatically. The function returns the updated `inventory`.
"""
function ignore!(
    inventory::SortedDict{String,<:Any},
    dates::AbstractDict{Date,<:Any};
    logfile::String = "ingore.log",
    loglevel::Symbol = :Debug
)::SortedDict{String,<:Any}
    # Setup
    t0 = Dates.now()
    if !haskey(inventory, "ignore")
        inventory["ignore"] = SortedDict{Date, Any}()
    end
    logfile, level = init_logging(logfile, inventory["metadata"]["local"]["path"], loglevel)
    @info "logging to '$logfile'"
    open(logfile, "w") do logio
        logger = Logging.ConsoleLogger(logio, level, show_limited=false)
        # Loop over dates and granules to be ignored
        for (date, granules) in dates
            # Skip dates not in the inventory
            if !haskey(inventory["dates"], date)
                @warn "$date is not part of the inventory, only dates actually present in the inventory can be ignored"
                Logging.with_logger(logger) do
                    @warn "$date not found in inventory, skip ignoring"
                end
                continue
            end
            # Split granules in outliers, duplicates, and valid granules
            granules isa AbstractString && (granules = [granules])
            granules, outliers = split_outliers(granules, keys(inventory["dates"][date]))
            if haskey(inventory["ignore"], date)
                duplicates, outliers = split_outliers(outliers, keys(inventory["ignore"][date]))
            else
                duplicates = String[]
                isempty(granules) || (inventory["ignore"][date] = SortedDict{String,<:Any}())
            end
            log_ignore(logger, outliers, "skipping granules not found in the inventory",
                level=Logging.Warn)
            log_ignore(logger, duplicates, "skipping granules that were already ignored")
            for g in granules
                # Move all valid granules to the ignore section
                inventory["ignore"][date][g] = inventory["dates"][date][g]
                delete!(inventory["dates"][date], g)
                isempty(inventory["dates"][date]) && delete!(inventory["dates"], date)
            end
            isempty(granules) || (inventory["metadata"]["database"]["updated"] = Dates.now())
            msg = "ignoring granules on $date"
            log_ignore(logger, granules, msg, msg*"; data moved from dates to ignore section")
        end
        # Save inventory if updated
        save_inventory(inventory, t0)
    end
    return inventory
end


function unignore!(
    inventory::SortedDict{String,<:Any},
    dates::AbstractDict{Date,<:Any}=Dict{Date,Any}();
    logfile::String = "ignore.log",
    loglevel::Symbol = :Debug
)::SortedDict{String,<:Any}
    # Setup
    t0 = Dates.now()
    if !haskey(inventory, "ignore")
        @info "no ignore section found in the inventory, nothing to unignore"
        return inventory
    end
    # Unignore everything, if no dates are provided
    if isempty(dates)
        for (key, values) in inventory["ignore"]
            dates[key] = collect(keys(values))
        end
    end
    logfile, level = init_logging(logfile, inventory["metadata"]["local"]["path"], loglevel)
    @info "logging to '$logfile'"
    open(logfile, "w") do logio
        logger = Logging.ConsoleLogger(logio, level, show_limited=false)
        # Loop over dates and granules to be unignored
        for (date, granules) in dates
            # Skip dates not in the ignore section
            if !haskey(inventory["ignore"], date)
                log_ignore(logger, granules, "no ignored data for $date, nothing to unignore",
                    level=Logging.Warn)
                continue
            end
            # Split granules in outliers, duplicates, and valid granules
            granules isa AbstractString && (granules = [granules])
            granules, outliers = split_outliers(granules, keys(inventory["ignore"][date]))
            if haskey(inventory["dates"], date)
                duplicates, outliers = split_outliers(outliers, keys(inventory["dates"][date]))
            else
                duplicates = String[]
                isempty(granules) || (inventory["dates"][date] = SortedDict{String,<:Any}())
            end
            log_ignore(logger, outliers, "skipping granules not found in the ignore section",
                level=Logging.Warn)
            log_ignore(logger, duplicates, "skipping granules that were already unignored")
            for g in granules
                # Move all valid granules to the dates section
                inventory["dates"][date][g] = inventory["ignore"][date][g]
                delete!(inventory["ignore"][date], g)
                isempty(inventory["ignore"][date]) && delete!(inventory["ignore"], date)
            end
            isempty(inventory["ignore"]) && delete!(inventory, "ignore")
            isempty(granules) || (inventory["metadata"]["database"]["updated"] = Dates.now())
            msg = "unignoring granules on $date"
            log_ignore(logger, granules, msg, msg*"; data moved from ignore to dates section")
        end
        # Save inventory if updated
        save_inventory(inventory, t0)
    end
    return inventory
end


## Helper functions to scan and manipulate the database

"""
    inventory_dates(
        inventory::SortedDict{String,<:Any}, erase::Extension
    ) -> @NamedTuple{folders::Set{String},files::Set{String}}

Rearrange the `inventory` for better processing as a named tuple with sets of absolute file and
folder paths. Either `original` or `converted` files might be removed based on the choice of
`erase`.
"""
function inventory_dates(
    inventory::SortedDict{String,<:Any}, erase::Extension
)::@NamedTuple{folders::Set{String},files::Set{String}}
    # Init
    folders, files = Set{String}(), Set{String}()
    root = inventory["metadata"]["local"]["path"]
    ext, newext = inventory["metadata"]["file"]["ext"], inventory["metadata"]["file"]["newext"]
    # Define inventory as part of files to be kept
    push!(files, joinpath(root, ".inventory.yaml"))
    # Loop over dates and granules
    for (date, granules) in inventory["dates"]
        # Define folders of the inventory
        yfolder = joinpath(root, Dates.format(date, "yyyy"))
        dfolder = joinpath(yfolder, Dates.format(date, "yyyy_mm_dd"))
        push!(folders, yfolder)
        push!(folders, dfolder)
        # Define files of the inventory
        for file in keys(granules)
            push!(files, joinpath(dfolder, file*ext))
        end
    end
    # Set the file types of the inventory, allow original and/or converted files
    if Integer(erase) == 0
        union!(files, replace.(files, ext => newext))
    elseif Integer(erase) == 1
        files = Set(replace.(files, ext => newext))
    end
    # Return inventory in a revised format
    return (;folders, files)
end


"""
    localscan(
        database::@NamedTuple{folders::Set{String},files::Set{String}},
        root::String,
        combine::Function
    ) -> @NamedTuple{folders::Set{String},files::Set{String}}

Scan the local directory recursively and compare it to the inventory. Depending on the `combine`
function, `localscan` can be used to identify files and folders not present in the database by
passing `setdiff` or to identify the downloaded part of the inventory with the `intersect` function.
"""
function localscan(
    database::@NamedTuple{folders::Set{String},files::Set{String}},
    root::String,
    combine::Function
)::@NamedTuple{folders::Set{String},files::Set{String}}
    # Setup
    root = realpath(root)
    scanned = (folders = Set{String}(), files = Set{String}())
    # Get files and folders within root recursively
    _localscan!(database, scanned, root, combine)
    return scanned
end


"""
    _localscan!(
        database::@NamedTuple{folders::Set{String},files::Set{String}},
        scanned::@NamedTuple{folders::Set{String},files::Set{String}},
        root::String,
        combine::Function
    )

Recursive helper function for `localscan`. This allows a simpler API for `localscan`, where
`database` does not have to be defined outside the function.
"""
function _localscan!(
    database::@NamedTuple{folders::Set{String},files::Set{String}},
    scanned::@NamedTuple{folders::Set{String},files::Set{String}},
    root::String,
    combine::Function
)::Nothing
    # Get files and folders in root
    content = readdir(root, join=true)
    files = filter(isfile, content)
    folders = filter(isdir, content)
    # Save extra files and folders
    foreach(f -> push!(scanned.folders, f), combine(folders, database.folders))
    foreach(f -> push!(scanned.files, f), combine(files, database.files))
    # Search recursively in database folders
    foreach(i -> _localscan!(database, scanned, i, combine), intersect(folders, database.folders))
    return
end


"""
    split_outliers(
        container::AbstractVector{String},
        comparison::AbstractSet{String}
    ) -> Tuple{Vector{String},Vector{String}}

Split the `container` of strings into two vectors: one with members present in the
`comparison` set and one with outliers not present in the `comparison`.
"""
function split_outliers(container, comparison)::Tuple{Vector{String},Vector{String}}
    members = Vector{String}()
    outliers = Vector{String}()
    for item in container
        item in comparison ? push!(members, item) : push!(outliers, item)
    end
    return (members, outliers)
end


## Helper functions for user interaction

"""
    log_ignore(
        logger::Logging.ConsoleLogger,
        granules::Vector{String},
        msg::AbstractString,
        screenmsg::AbstractString="";
        level::Logging.LogLevel=Logging.Info
    )

For non-empty `granules`, log the `msg` to the `logger` and print `screenmsg` to the console.
If `screenmsg` is empty, `msg` is used for both logging and console output.
The log level can be specified with `level`.
"""
function log_ignore(
    logger::Logging.ConsoleLogger,
    granules::Vector{String},
    msg::AbstractString,
    screenmsg::AbstractString="";
    level::Logging.LogLevel=Logging.Info
)::Nothing
    isempty(granules) && return
    isempty(screenmsg) && (screenmsg = msg)
    Logging.@logmsg level screenmsg granules _module=nothing _file=nothing _line=nothing
    Logging.with_logger(logger) do
        Logging.@logmsg level granules msg _module=nothing _file=nothing _line=nothing
    end
end


"""
    confirm(extra::@NamedTuple{folders::Set{String},files::Set{String}}) -> Bool

Prompt the user to confirm the deletion of files and folders listed in `extra`.
Returns `true`, if the user confirmed with `"yes"`, `false` otherwise.
"""
function confirm(extra::@NamedTuple{folders::Set{String},files::Set{String}})::Bool
    # Nothing to clean
    isempty(extra.folders) && isempty(extra.files) && return true
    # Initial warning
    @warn("The following paths are not part of the inventory and will be removed.",
        _module=nothing, _file=nothing, _line=nothing)
    # List folders
    if !isempty(extra.folders)
        printstyled("Folders:\n", color=:yellow, bold=true)
        print("- ")
        println(join(extra.folders |> collect |> sort, "\n- "))
    end
    # List files
    if !isempty(extra.files)
        printstyled("Files:\n", color=:yellow, bold=true)
        print("- ")
        println(join(extra.files |> collect |> sort, "\n- "))
    end
    # Prompt for confirmation
    printstyled("Proceed (yes/no)? ", color=:yellow, bold=true)
    proceed = readline()
    # Return user decision
    return startswith(lowercase(proceed), "y")
end
