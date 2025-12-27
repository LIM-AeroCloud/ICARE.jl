## Routines related to converting different HDF versions

## API functions

"""
    convert(
        root::AbstractString=".";
        sizecheck::Bool=false,
        logfile::String = "conversions.log",
        loglevel::Symbol = :Debug
    ) -> SortedDict

Convert all files in `root` and part of the inventory to a new format as defined in the inventory.
If files of the new format already exist, they are skipped unless `sizecheck` is set to `true`,
which will reconvert any file whose size differs from that listed in the inventory.
Logging is written to `logfile` with the specified `loglevel`. A timestamp is added to the log
file name to avoid overwriting existing logs. The function returns the updated `inventory`.

See also: [`convert!`](@ref), [`sftp_download`](@ref), [`ignore!`](@ref), [`unignore!`](@ref)
"""
function Base.convert(
    root::AbstractString=".";
    sizecheck::Bool=false,
    logfile::String = "conversions.log",
    loglevel::Symbol = :Debug
)::SortedDict
    # Load the inventory from the yaml in the given root
    path = joinpath(root, ".inventory.yaml") |> realpath
    inventory = SortedDict()
    load_inventory!(inventory, path)
    # Call the conversion method for the inventory
    convert!(inventory; sizecheck, logfile, loglevel)
end


"""
    convert!(
        inventory::SortedDict;
        sizecheck::Bool=false,
        logfile::String = "conversions.log",
        loglevel::Symbol = :Debug
    ) -> SortedDict

Convert all files in the local database and part of the `inventory` to a new format as defined
in the `inventory`. If files of the new format already exist, they are skipped unless `sizecheck`
is set to `true`, which will reconvert any file whose size differs from that listed in the
`inventory`.
Logging is written to `logfile` with the specified `loglevel`. A timestamp is added to the log
file name to avoid overwriting existing logs. The function returns the updated `inventory`.

See also: [`convert`](@ref), [`sftp_download`](@ref), [`ignore!`](@ref), [`unignore!`](@ref)
"""
function convert!(
    inventory::SortedDict;
    sizecheck::Bool=false,
    logfile::String = "conversions.log",
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
        database = inventory_dates(inventory, none)
        # Scan inventory for additional files and folders
        root = inventory["metadata"]["local"]["path"]
        db = localscan(database, root, intersect)
        # Clean up local database and save inventory
        conversion(inventory, db.files, sizecheck, logger)
        save_inventory(inventory, t0)
    end
    return inventory
end


## Helper functions for file conversions of inventory data

#* Functions for conversions during download


"""
    _convert!(
        inventory::SortedDict,
        file::File,
        convert::Bool,
        logger::Logging.AbstractLogger
    )

Convert the `file` to a new file format as defined in the `inventory` unless `file` is already
up-to-date or it was opted out to `convert` the file. Log events to `logger`.
"""
function _convert!(
    inventory::SortedDict,
    file::File,
    convert::Bool,
    logger::Logging.AbstractLogger
)::Nothing
    converted!(inventory, file, convert) && return
    rm(file.location.target, force=true)
    convert_file(file.location.download, file.location.target, convert)
    set_converted_size!(inventory, file, convert, logger)
end


"""
    converted!(inventory::SortedDict, file::File, convert::Bool) -> Bool

Check, whether the size of the converted `file` is known in the `inventory` and matches the
actual file size. Return also `true`, if it was opted out to `convert` the file.
"""
function converted!(inventory::SortedDict, file::File, convert::Bool)::Bool
    if convert
        # Thread-safe check of inventory and file size
        has_size_entry = lock(thread) do
            haskey(inventory["dates"][file.date][file.name], "size"*file.newext)
        end
        if has_size_entry
            expected_size = lock(thread) do
                inventory["dates"][file.date][file.name]["size"*file.newext]
            end
            return expected_size == filesize(file.location.target)
        else
            return false
        end
    else
        return true
    end
end


"""
    set_converted_size!(
        inventory::SortedDict,
        file::File,
        convert::Bool,
        logger::Logging.AbstractLogger
    )

Set the size of the converted `file` in the `inventory` and mark the `inventory` as updated.
Log events to `logger`.
"""
function set_converted_size!(
    inventory::SortedDict,
    file::File,
    convert::Bool,
    logger::Logging.AbstractLogger
)::Nothing
    # Initial checks
    convert || return
    # Thread-safe check if size already exists
    already_has_size = lock(thread) do
        haskey(inventory["dates"][file.date][file.name], "size"*file.newext)
    end
    already_has_size && return
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
        inventory["dates"][file.date][file.name]["size"*file.newext] = filesize(file.location.target)
        inventory["metadata"]["database"]["updated"] = Dates.now()
    end
    return
end


#* Functions for separate batch conversions

"""
    conversion(
        inventory::SortedDict,
        files::Set{String},
        sizecheck::Bool,
        logger::Logging.AbstractLogger
    )

Convert all `files` part of the `inventory` to a new format as defined in the `inventory`.
Conversions are skipped, if files of the new format already exist and either their size matches
the one listed in the `inventory` or `sizecheck` is set to `false`. Log events to `logger`.
"""
function conversion(
    inventory::SortedDict,
    files::Set{String},
    sizecheck::Bool,
    logger::Logging.AbstractLogger
)::Nothing
    # Remove .inventory.yaml from files to convert
    ext = inventory["metadata"]["file"]["ext"]
    newext = inventory["metadata"]["file"]["newext"]
    input = filter(endswith(ext), files)
    if !sizecheck
        input = setdiff(getindex.(splitext.(input), 1),
            getindex.(splitext.(filter(endswith(newext), files)), 1)).*ext
    end
    input = File.(Ref(inventory), input)
    t0 = Dates.now()
    Logging.with_logger(logger) do
        @info "starting up to $(Threads.nthreads()) parallel conversions of $(length(input)) files @$t0"
    end
    prog = pm.Progress(length(input), desc="converting...")
    @threads for file in input
        lock(thread) do
            # Log converted files
            Logging.with_logger(logger) do
                @debug("convert '$(file.name)'",
                    _module=nothing, _file=nothing, _line=nothing)
            end
        end
        _convert!(inventory, file, true, logger)
        pm.next!(prog)
    end
    pm.finish!(prog)
    t = Dates.now()
    Logging.with_logger(logger) do
        @info "finished conversion @$t in $(Dates.canonicalize(t-t0))"
    end
    return
end


#* Actual conversion routines (can be overloaded from outside for different formats)

"""
    convert_file(input::String, output::String[, convert::Bool])

Convert the `input` to the `output` format unless `convert` is `false` (if provided).
Both `input` and `output` can be absolute or relative paths.
"""
function convert_file end

function convert_file(input::String, output::String, convert::Bool)::Nothing
    convert || return
    convert_file(input, output)
end

function convert_file(input::String, output::String)::Nothing
    # Return, if input file doesn't exist
    isfile(input) || return
    # Ensure, h5 file does not exist before conversion
    rm(splitext(input)[1]*".h5", force=true)
    # Chose exe for current OS and convert to h5
    bin = Sys.isapple() ? "h4toh5_mac" : "h4toh5_linux"
    converter = realpath(joinpath(@__DIR__, "..", "assets", bin))
    run(`$converter $input $output`)
    return
end


"""
    newext() -> String

Return the extension of the converted file.
"""
newext()::String = ".h5"
