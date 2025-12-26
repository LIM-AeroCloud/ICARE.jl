## Routines related to syncing local and remote directories

## API functions
"""
    clean!(
        root::AbstractString=".",
        erase::Extension=none;
        keepext::Union{AbstractString,Vector{<:AbstractString}}="",
        logfile::String = "clean.log",
        loglevel::Symbol = :Debug
    ) -> SortedDict

    clean!(
        inventory::SortedDict,
        erase::Extension=none;
        keepext::Union{AbstractString,Vector{<:AbstractString}}="",
        logfile::String = "clean.log",
        loglevel::Symbol = :Debug
    ) -> SortedDict

Clean a product folder recursively from all content not listed in the inventory, i.e. not
available on the ICARE server, or not flagged as extra files in the `inventory` extra section
with the `attach!` function. The function has two methods – you can either provide an
`AbstractString` with the path of the product folder or the inventory as `SortedDict` of the
product. The latter is more performant as the inventory doesn't need to be loaded first.

Both methods allow an optional second argument that specifies whether either the `original`
or `converted` files should be additionally cleaned from the local database. The optional
parameter values are predefined constants from the `Extension` enum.
Both methods return the updated `inventory` for reference.

See also: [`attach!`](@ref), [`detach!`](@ref), [`ignore!`](@ref), [`unignore!`](@ref),
[`convert!`](@ref), [`convert(::String)`](@ref), [`sftp_download`](@ref)

# Keyword Arguments

- `keepext::Union{AbstractString,Vector{<:AbstractString}}`: One or multiple (as vector)
  file extensions (e.g. `".log"`, `[".yaml", ".log"]`) to keep during clean-up even if not part of
  the inventory. Can be used to keep log or metadata files.
- `logfile::String`: The name of the log file (default: `"clean.log"`; the name will be appended
  by the current date and time).
- `loglevel::Symbol`: The log level for the download process (default: `:Debug`).
"""
function clean! end

function clean!(
    root::AbstractString=".",
    erase::Extension=none;
    keepext::Union{AbstractString,Vector{<:AbstractString}}="",
    logfile::String = "clean.log",
    loglevel::Symbol = :Debug
)::SortedDict
    # Load the inventory from the yaml in the given root
    path = joinpath(root, ".inventory.yaml") |> realpath
    inventory = SortedDict()
    load_inventory!(inventory, path)
    # Call the clean method for the inventory
    clean!(inventory; keepext, erase, logfile, loglevel)
end

function clean!(
    inventory::SortedDict,
    erase::Extension=none;
    keepext::Union{AbstractString,Vector{<:AbstractString}}="",
    logfile::String = "clean.log",
    loglevel::Symbol = :Debug
)::SortedDict
    # Start
    t0 = Dates.now()
    logfile, level = init_logging(logfile, inventory["metadata"]["local"]["path"], loglevel)
    @info "logging to '$logfile'"
    open(logfile, "w") do logio
        logger = Logging.ConsoleLogger(logio, level, show_limited=false)
        # Rearrange inventory for better processing
        @info "analyse inventory and local database"
        database = inventory_dates(inventory, erase)
        # Scan inventory for additional files and folders
        waste = extrascan(inventory, inventory["metadata"]["local"]["path"], database)
        # Remove current logfile from extra files
        filter!(!isequal(logfile), waste.files)
        # Keep specified extensions
        if !isempty(keepext)
            keepext isa Vector || (keepext = [keepext])
            for ext in keepext
                filter!(!endswith(ext), waste.files)
            end
        end
        # Clean up local database
        if confirm(waste)
            Logging.with_logger(logger) do
                s = length(waste.files) == 1 ? "" : "s"
                s_ = length(waste.folders) == 1 ? "" : "s"
                @warn("cleaning $(length(waste.files)) file$s and $(length(waste.folders)) folder$s_",
                    folders = waste.folders |> collect |> sort, files = waste.files |> collect |> sort)
            end
            rm.(waste.files, force=true)
            rm.(waste.folders, recursive=true, force=true)
            reference = get.(splitext.(database.files), 1, "").*inventory["metadata"]["file"]["ext"]
            isdisjoint(reference, waste.files) || begin
                inventory["metadata"]["database"]["updated"] = Dates.now()
                save_inventory(inventory, t0)
            end
            @info "clean-up completed"
            Logging.with_logger(logger) do
                @info "cleaning completed"
            end
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
        inventory::SortedDict,
        dates::AbstractDict{Date, Any};
        logfile::String = "clean.log",
        loglevel::Symbol = :Debug
    ) -> SortedDict

Flag the `dates` as ignored in the `inventory` and ensure they will not get downloaded.
Log events with the specified `loglevel` to the `logfile`. A timestamp is appended to the log
file name automatically. The function returns the updated `inventory`.

See also: [`unignore!`](@ref), [`attach!`](@ref), [`detach!`](@ref), [`sftp_download`](@ref)
"""
function ignore!(
    inventory::SortedDict,
    dates::AbstractDict{Date,<:Any};
    logfile::String = "ingore.log",
    loglevel::Symbol = :Debug
)::SortedDict
    # Setup
    t0 = Dates.now()
    haskey(inventory, "ignore") || (inventory["ignore"] = SortedDict{Date, Any}())
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
                isempty(granules) || (inventory["ignore"][date] = SortedDict())
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


"""
    unignore!(
        inventory::SortedDict,
        dates::AbstractDict{Date, Any}=Dict{Date,Any}();
        logfile::String = "ignore.log",
        loglevel::Symbol = :Debug
    ) -> SortedDict

Unflag the `dates` from being ignored in the `inventory` and allow them to be downloaded again.
Log events with the specified `loglevel` to the `logfile`. A timestamp is appended to the log
file name automatically. The function returns the updated `inventory`.

See also: [`ignore!`](@ref), [`attach!`](@ref), [`detach!`](@ref), [`sftp_download`](@ref)
"""
function unignore!(
    inventory::SortedDict,
    dates::AbstractDict{Date,<:Any}=Dict{Date,Any}();
    logfile::String = "ignore.log",
    loglevel::Symbol = :Debug
)::SortedDict
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
                isempty(granules) || (inventory["dates"][date] = SortedDict())
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


"""
    list_inventory(
        inventory::SortedDict;
        list_dates::Bool=true,
        list_gaps::Bool=true,
        list_ignored::Bool=true,
        list_extras::Bool=true
    )

List the content of the `inventory` in a simplified tree structure showing available and already
downloaded folders and files and statistics about the inventory content. Additionally, missing dates
(gaps), ignored files, and extra files are listed.

For all but the overall stats, printing can be switched off with keyword arguments
(`list_dates`, `list_gaps`, `list_ignored`, `list_extras`).
"""
function list_inventory(
    inventory::SortedDict;
    list_dates::Bool=true,
    list_gaps::Bool=true,
    list_ignored::Bool=true,
    list_extras::Bool=true
)::Nothing
    dates = collect(Date, keys(inventory["dates"]))
    years = Dates.year.(dates) |> unique
    date_range = [findall(d -> Dates.year(d) == year, dates) for year in years]
    list_dates && begin
        println(inventory["metadata"]["remote"]["product"])
        for d = 1:length(date_range) - 1
            print_year_stats(inventory, years[d], dates[date_range[d]])
        end
        print_year_stats(inventory, years[end], dates[date_range[end]], true)
    end
    list_gaps && begin
        printstyled("Missing dates\n\n", bold=true, underline=true)
        gaps = combine_gaps(inventory, (start = inventory["metadata"]["database"]["start"],
            stop = inventory["metadata"]["database"]["stop"]), Logging.ConsoleLogger(Logging.Warn, show_limited=false))
        if !isempty(gaps)
            [println(gap) for gap in gaps]
            println('\n')
        end
    end
    list_ignored && haskey(inventory, "ignore") && begin
        printstyled("Ignored files\n\n", bold=true, underline=true)
        print_ignored_tree(inventory)
        println('\n')
    end
    list_extras && haskey(inventory, "extras") && begin
        printstyled("Extras\n\n", bold=true, underline=true)
        print(inventory["metadata"]["remote"]["product"], "\n├─ ")
        println(join(inventory["extras"], "\n├─ ", "\n└─ "), '\n')
    end
    printstyled("Overall statistics\n\n", bold=true, underline=true)
    println("date range:    ", inventory["metadata"]["database"]["start"], " ... ",
        inventory["metadata"]["database"]["stop"])
    println("dates:         ", length(dates))
    println("missing dates: ", inventory["metadata"]["database"]["missing"])
    println("granules:      ", inventory["metadata"]["file"]["downloads"],"/",
        inventory["metadata"]["file"]["conversions"], " of ", inventory["metadata"]["file"]["count"])
    println("size:          ", display_size(inventory["metadata"]["database"]["downloaded size"]),
        "/", display_size(inventory["metadata"]["database"]["converted size"]), " of ",
        display_size(inventory["metadata"]["database"]["size"]), '\n')
    @info "file sizes are displayed as <downloads in original format>/<converted size> of <total size in original format>"
end


## Functions for attaching and detaching extra data

"""
    attach!(
        inventory::SortedDict,
        extras::Union{AbstractString,Vector{<:AbstractString}};
        logfile::String = "extras.log",
        loglevel::Symbol = :Debug
    ) -> SortedDict

Attach extra files and folders to the `inventory` that should be kept during `clean` operations.
Files nested in foreign folders are recognised as well keeping the parent folders during `clean`
operations. The `extras` can be provided as a single `AbstractString` or as a vector of
`AbstractString`s. The function returns the updated `inventory` and logs events with the
specified `loglevel` to the `logfile`. A timestamp is appended to the log file name automatically.

See also: [`detach!`](@ref), [`clean!`](@ref), [`ignore!`](@ref), [`unignore!`](@ref)
"""
function attach!(
    inventory::SortedDict,
    extras::Union{AbstractString,Vector{<:AbstractString}};
    logfile::String = "extras.log",
    loglevel::Symbol = :Debug
)::SortedDict
    # Init
    t0 = Dates.now()
    extras isa AbstractString && (extras = [extras])
    haskey(inventory, "extras") || (inventory["extras"] = Vector{String}())
    root = inventory["metadata"]["local"]["path"]
    logfile, level = init_logging(logfile, root, loglevel)
    @info "logging to '$logfile'"
    open(logfile, "w") do logio
        logger = Logging.ConsoleLogger(logio, level, show_limited=false)
        Logging.with_logger(logger) do
            @info "prepare attachment of extras" extras
        end
        for path in extras
            #* Prepare path, ensure relative paths to the product folder, get relative tree for base
            # Normalize path name
            # ℹ relpath ensures no trailing slash in the path, normpath ensures direct path
            path = normpath(relpath(path))
            if isabspath(path)
                if startswith(path, root)
                    r = length(root) + 2 # ℹ next index after slash
                    path = path[r:end]
                else
                    @warn "'$path' is outside the product folder, skipping"
                    Logging.with_logger(logger) do
                        @warn "'$path' is outside the product folder, skip attaching"
                    end
                    continue
                end
            end
            # Save parent tree before tempering with path
            tree = splitpath(path)[1:end-1]
            # Only attach existing paths within the product folder
            abspath = try realpath(joinpath(root, path))
            catch err
                if err isa Base.IOError
                    @warn "'$path' does not exist in the product folder, skipping"
                    Logging.with_logger(logger) do
                        @warn "'$path' not found in the product folder, skip attaching"
                    end
                else
                    @warn "unexpected error when accessing '$path' in the product folder, skipping path" err
                    Logging.with_logger(logger) do
                        @warn "unexpected error when accessing '$path' in the product folder, skip attaching" err
                    end
                end
                continue
            end
            if path in inventory["extras"]
                @info "'$path' already in extras, skipping"
                Logging.with_logger(logger) do
                    @info "'$path' already in extras, skip attaching"
                end
                continue
            elseif !startswith(abspath, root)
                @warn "'$path' is outside the product folder, skipping"
                Logging.with_logger(logger) do
                    @warn "'$path' is outside the product folder, skip attaching"
                end
                continue
            end
            Logging.with_logger(logger) do
                @debug "attaching '$path' to extras"
            end
            # Save path after successful checks
            attach_path!(inventory, path, logger)
            # Ignore parent tree as well
            for i = length(tree):-1:1
                # Check, if parent is already ignored or known as parent
                parent = normpath(tree[1:i]...)
                parent in inventory["extras"] && break
                parent = joinpath(parent, "")
                parent in inventory["extras"] && break
                push!(inventory["extras"], parent)
                Logging.with_logger(logger) do
                    @debug "attaching parent folder '$parent' to extras"
                end
            end
        end
        # Sort file list
        sort!(inventory["extras"])
        # Save inventory if updated
        save_inventory(inventory, t0)
    end
    return inventory
end


"""
    detach!(
        inventory::SortedDict,
        extras::Union{AbstractString,Vector{<:AbstractString}}=String[];
        logfile::String = "extras.log",
        loglevel::Symbol = :Debug
    ) -> SortedDict

Detach files and folders from the `inventory` that were previously marked as extra data to
be kept during `clean` operations. If no `extras` are provided, all extra data will be detached.
For nested files and folders, the parent will be detached as well, if it contains no other extra
data.

The function returns the updated `inventory` and logs events with the specified `loglevel`
to the `logfile`. A timestamp is appended to the log file name automatically.

See also: [`attach!`](@ref), [`clean!`](@ref), [`ignore!`](@ref), [`unignore!`](@ref)
"""
function detach!(
    inventory::SortedDict,
    extras::Union{AbstractString,Vector{<:AbstractString}}=String[];
    logfile::String = "extras.log",
    loglevel::Symbol = :Debug
)::SortedDict
    # Initial checks
    t0 = Dates.now()
    sleep(0.001) # ℹ ensure different updated time from t0
    if !haskey(inventory, "extras")
        @info "no extras section found in the inventory, nothing to detach"
        return inventory
    elseif extras isa AbstractString
        extras = [extras]
    elseif isempty(extras)
        delete!(inventory, "extras")
        @info "all extras detached from the inventory"
        inventory["metadata"]["database"]["updated"] = Dates.now()
        save_inventory(inventory, t0)
        return inventory
    end
    # Start logging
    logfile, level = init_logging(logfile, inventory["metadata"]["local"]["path"], loglevel)
    @info "logging to '$logfile'"
    open(logfile, "w") do logio
        logger = Logging.ConsoleLogger(logio, level, show_limited=false)
        # Detach all paths and parent folders exclusive to the given path
        for path in extras
            # ℹ relpath ensures no trailing slash in the path
            isabspath(path) && (path = relpath(path, inventory["metadata"]["local"]["path"]))
            detach_path!(inventory, path, logger) || continue
            detach_parents!(inventory, path, logger)
            inventory["metadata"]["database"]["updated"] = Dates.now()
        end
        # Remove empty extras section
        isempty(inventory["extras"]) && delete!(inventory, "extras")
        # Save inventory if updated
        save_inventory(inventory, t0)
    end
    return inventory
end


## Helper functions to scan and manipulate the database

"""
    inventory_dates(
        inventory::SortedDict,
        erase::Extension,
        date_filter=keys(inventory["dates"])
    ) -> @NamedTuple{folders::Set{String},files::Set{String}}

Rearrange the `inventory` for better processing as a named tuple with sets of absolute file and
folder paths, filtering by `date_filter` (an iterable of Date objects). Either `original` or
`converted` files might be removed based on the choice of `erase`. By default, all dates in the
inventory are included.
"""
function inventory_dates(
    inventory::SortedDict,
    erase::Extension,
    date_filter=keys(inventory["dates"])
)::@NamedTuple{folders::Set{String},files::Set{String}}
    # Init
    folders, files = Set{String}(), Set{String}()
    root = inventory["metadata"]["local"]["path"]
    ext, newext = inventory["metadata"]["file"]["ext"], inventory["metadata"]["file"]["newext"]
    # Define inventory as part of files to be kept
    push!(files, joinpath(root, ".inventory.yaml"))
    # Create year set for folder tracking
    years = Set{Int}()
    # Loop over filtered dates and granules
    for date in date_filter
        haskey(inventory["dates"], date) || continue
        granules = inventory["dates"][date]
        # Track years
        push!(years, Dates.year(date))
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
    extrascan(
        inventory::SortedDict,
        path::String,
        database::@NamedTuple{folders::Set{String},files::Set{String}},
        waste::NamedTuple = (folders=Set{String}(),files=Set{String}())
    ) -> @NamedTuple{folders::Set{String},files::Set{String}}

Recursively scan the `path` for files and folders not present in the `database` and save them
to `waste`. Allow paths listed as extras in the `inventory`. The function returns the `waste`.
"""
function extrascan(
    inventory::SortedDict,
    path::String,
    database::@NamedTuple{folders::Set{String},files::Set{String}},
    waste::NamedTuple = (folders=Set{String}(),files=Set{String}())
)::@NamedTuple{folders::Set{String},files::Set{String}}
    # Scan path for extra files
    path_waste = localscan(database, path, setdiff)
    # Check extras, if available
    if haskey(inventory, "extras")
        # Filter out allowed extras
        extrapaths = joinpath.(inventory["metadata"]["local"]["path"], inventory["extras"])
        filter!(!in(extrapaths), path_waste.folders)
        filter!(!in(extrapaths), path_waste.files)
        # Scan for possible parent folders with allowed nested extras
        extras = joinpath.(path_waste.folders, "")
        filter!(in(extrapaths), extras)
        filter!(x -> !in(realpath(x), path_waste.folders), path_waste.folders)
    else
        extras = String[]
    end
    # Save waste of current path to overall waste
    union!(waste.folders, path_waste.folders)
    union!(waste.files, path_waste.files)
    # Recursively scan for nested extras
    for extra in extras
        extrascan(
            inventory,
            extra,
            database,
            waste
        )
    end
    return waste
end


"""
    localscan(
        database::@NamedTuple{folders::Set{String},files::Set{String}},
        root::String,
        combine::Function
    ) -> @NamedTuple{folders::Set{String},files::Set{String}}

Scan the local directory recursively and compare it to the `database`, i.e. re-arranged inventory.
Depending on the `combine` function, `localscan` can be used to identify files and folders not
present in the `database` by passing `setdiff` or to identify the downloaded part of the `database`
with the `intersect` function.
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
        scanned::NamedTuple{(:folders, :files)},
        root::String,
        combine::Function
    )

Recursive helper function for `localscan`. This allows a simpler API for `localscan`, where
`database` does not have to be defined outside the function.
"""
function _localscan!(
    database::@NamedTuple{folders::Set{String},files::Set{String}},
    scanned::NamedTuple{(:folders, :files)},
    root::String,
    combine::Function
)::Nothing
    # Get files and folders in root
    content = readdir(root, join=true)
    files = filter(isfile, content)
    folders = filter(isdir, content)
    # Save extra files and folders
    union!(scanned.folders, combine(folders, database.folders))
    union!(scanned.files, combine(files, database.files))
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


"""
    attach_path!(
        inventory::SortedDict,
        path::AbstractString,
        logger::Logging.AbstractLogger
    )

Attach a `path` to the `inventory` extras unless a parent folder is already ignored.
Remove possible sub-folders of `path` previously attached to the `inventory`.
Log events to the provided `logger`.
"""
function attach_path!(
    inventory::SortedDict,
    path::AbstractString,
    logger::Logging.AbstractLogger
)::Nothing
    # Check parent folders are not already attached
    parts = splitpath(path)[1:end-1]
    paths = [joinpath(parts[1:i]...) for i in 1:length(parts)]
    if !isdisjoint(inventory["extras"], paths)
        @info "parent folder of '$path' already attached, skipping"
        Logging.with_logger(logger) do
            @info "parent folder of '$path' already attached, skip attaching"
        end
        return
    end
    # Remove previously ignored subpaths from inventory extras
    paths = filter(startswith(path), inventory["extras"])
    if !isempty(paths)
        @info "removing previously attached sub-paths of '$path'" paths
        Logging.with_logger(logger) do
            @info "removing previously attached sub-paths of '$path'" paths
        end
        filter!(!in(paths), inventory["extras"])
    end
    # Attach path
    push!(inventory["extras"], path)
    @debug "attached '$path' to extras"
    Logging.with_logger(logger) do
        @debug "attached '$path' to extras"
    end
    inventory["metadata"]["database"]["updated"] = Dates.now()
    return
end


"""
    detach_path!(
        inventory::SortedDict,
        path::AbstractString,
        logger::Logging.AbstractLogger
    ) -> Bool

Detach the given `path` from the `inventory` extras including any sub-folders within the `path`.
The function returns `true` if the path was detached, `false` otherwise.
Log events to the provided `logger`.
"""
function detach_path!(
    inventory::SortedDict,
    path::AbstractString,
    logger::Logging.AbstractLogger
)::Bool
    #* Check for path in inventory extras
    # Check, if path itself is attached or if path is a parent folder to an attached path
    parent = if path in inventory["extras"]
        false
    else
        path = joinpath(path, "")
        true
    end
    # Skip missing paths
    if path ∉ inventory["extras"]
        @info "'$path' not found in extras, skipping"
        Logging.with_logger(logger) do
            @info "'$path' not found in extras, skip detaching"
        end
        return false
    end
    #* Remove path and child paths from extras
    extras = filter(startswith(path), inventory["extras"])
    filter!(!in(extras), inventory["extras"])
    if parent
        @warn "detached a parent folder including other extras" extras
        Logging.with_logger(logger) do
            @info "detached a parent folder including other extras" extras
        end
    else
        @warn "detached '$path' from extras"
        Logging.with_logger(logger) do
            @info "detached '$path' from extras"
        end
    end
    #* Ensure inventory updates are saved later
    inventory["metadata"]["local"]["updated"] = Dates.now()
    return true
end


"""
    detach_parents!(
        inventory::SortedDict,
        path::AbstractString,
        logger::Logging.AbstractLogger
    )

Detach parent folders that are exclusive to the given `path` from the `inventory` extras.
Log events to the provided `logger`.
"""
function detach_parents!(
    inventory::SortedDict,
    path::String,
    logger::Logging.AbstractLogger,
)::Nothing
    parts = splitpath(path)[1:end-1]
    paths = [joinpath(parts[1:i]..., "") for i in length(parts):-1:1]
    for path in paths
        parents = filter(startswith(path), inventory["extras"])
        length(parents) == 1 || continue
        filter!(!isequal(parents[1]), inventory["extras"])
        @info "detached parent '$(parents[1])' from extras"
        Logging.with_logger(logger) do
            @info "detached parent '$(parents[1])' from extras"
        end
    end
end


## Helper functions for user interaction

"""
    log_ignore(
        logger::Logging.AbstractLogger,
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
    logger::Logging.AbstractLogger,
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


## Helper functions for display

"""
    display_size(size::Integer) -> String

Convert a size in bytes to a human-readable string with appropriate unit (B, kB, MB, GB, TB).
"""
function display_size(size::Integer)::String
    s = (size |> digits |> length) - 1
    s = min(s÷3, 4)
    unit = Dict(0=>"B", 1=>"kB", 2=>"MB", 3=>"GB", 4=>"TB")
    return string(round(size / 10^3s, digits=2), unit[s])
end


"""
    print_ignored_tree(inventory::SortedDict)

Print a tree structure showing all ignored granules in the `inventory`, organised by year
and date. Use box-drawing characters to show the hierarchy.
"""
function print_ignored_tree(inventory::SortedDict)::Nothing
    # Get all ignored dates and sort them
    ignore_dates = collect(keys(inventory["ignore"]))
    isempty(ignore_dates) && return
    # Group by year
    years = unique(Dates.year.(ignore_dates))

    # Print product
    println(inventory["metadata"]["remote"]["product"])
    # Iterate through years
    for (year_idx, year) in enumerate(years)
        year_dates = filter(d -> Dates.year(d) == year, ignore_dates)
        is_last_year = year_idx == length(years)
        year_prefix = is_last_year ? "└─" : "├─"
        year_continue = is_last_year ? "   " : "│  "
        println("$year_prefix $year")

        # Iterate through dates in this year
        for (date_idx, date) in enumerate(year_dates)
            is_last_date = date_idx == length(year_dates)
            date_prefix = is_last_date ? "└─" : "├─"
            date_continue = is_last_date ? "   " : "│  "

            println("$year_continue$date_prefix $(Dates.format(date, "yyyy_mm_dd"))")

            # Iterate through granules in this date
            granules = collect(keys(inventory["ignore"][date]))
            for (granule_idx, granule) in enumerate(granules)
                is_last_granule = granule_idx == length(granules)
                granule_prefix = is_last_granule ? "└─" : "├─"
                println("$year_continue$date_continue$granule_prefix $granule")
            end
        end
    end
    return
end


"""
    print_year_stats(
        inventory::SortedDict,
        year::Integer,
        dates::Vector{Date},
        finish::Bool = false
    )

Print the statistics for a given `year` in the `inventory` based on the provided `dates`.
Use slightly different formatting for the last year with the `finish` flag.
"""
function print_year_stats(
    inventory::SortedDict,
    year::Integer,
    dates::Vector{Date},
    finish::Bool = false
)::Nothing
    stats = inventory_stats(inventory, dates, by_year=true)
    y = finish ? "└─" : "├─"
    d = finish ? " " : "│"
    println("$y $year")
    println("$d  └─ $(Dates.format(dates[1], "yyyy_mm_dd")) ... $(stats["dates"]) dates: $(stats["downloaded files"])/",
        "$(stats["converted files"]) of $(stats["filecount"]) files – ",
        "$(display_size(stats["downloaded size"]))/$(display_size(stats["converted size"])) ",
        "of $(display_size(stats["size"])) ... $(Dates.format(dates[end], "yyyy_mm_dd"))")
    finish && println('\n')
    return
end
