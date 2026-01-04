## Routines related to converting different HDF versions

## API functions

"""
    convert_inventory(
        root::AbstractString=".";
        sizecheck::Bool=false,
        logfile::AbstractString = "conversions.log",
        loglevel::Symbol = :Debug
    ) -> SortedDict

Convert all files in `root` that are part of the inventory to a new format as defined in the inventory.
If files of the new format already exist, they are skipped unless `sizecheck` is set to `true`,
which will reconvert any file whose size differs from that listed in the inventory.
Logging is written to `logfile` with the specified `loglevel`. A timestamp is added to the log
file name to avoid overwriting existing logs. The function returns the updated `inventory`.

See also: [`convert_inventory!`](@ref), [`sftp_download`](@ref), [`ignore!`](@ref), [`unignore!`](@ref)
"""
function convert_inventory(
    root::String=".";
    sizecheck::Bool=false,
    logfile::String = "conversions.log",
    loglevel::Symbol = :Debug
)::SortedDict
    # Load the inventory from the yaml in the given root
    logger = init_logging(logfile, root, loglevel)
    logex.with_logger(logger.tee) do
        @debug "parameters" root sizecheck loglevel
    end
    inventory = load_inventory(root, logger.tee)
    # Call the conversion method for the inventory
    _convert!(inventory, sizecheck, logger)
end


"""
    convert_inventory!(
        inventory::SortedDict,
        sizecheck::Bool,
        logfile::AbstractString = "conversions.log",
        loglevel::Symbol = :Debug
    ) -> SortedDict

Convert all files in the local database that are part of the `inventory` to a new format as defined
in the `inventory`. If files of the new format already exist, they are skipped unless `sizecheck`
is set to `true`, which will reconvert any file whose size differs from that listed in the
`inventory`.
Logging is written to `logfile` with the specified `loglevel`. A timestamp is added to the log
file name to avoid overwriting existing logs. The function returns the updated `inventory`.

See also: [`convert_inventory`](@ref), [`sftp_download`](@ref), [`ignore!`](@ref), [`unignore!`](@ref)
"""
function convert_inventory!(
    inventory::SortedDict;
    sizecheck::Bool=false,
    logfile::AbstractString = "conversions.log",
    loglevel::Symbol = :Debug
)::SortedDict
    logger = init_logging(String(logfile), inventory["metadata"]["local"]["path"], loglevel)
    logex.with_logger(logger.tee) do
        @debug "parameters" sizecheck loglevel
    end
    _convert!(inventory, sizecheck, logger)
end


## Helper functions for file conversions of inventory data

#* Helper function for batch conversions without download

"""
    _convert!(
        inventory::SortedDict,
        sizecheck::Bool,
        logger::NamedTuple{(:file,:tee,:start)}
    ) -> SortedDict

Implementation of file conversions for wrapper functions `convert_inventory` and `convert_inventory!`.
"""
function _convert!(
    inventory::SortedDict,
    sizecheck::Bool,
    logger::NamedTuple{(:file,:tee,:start)}
)::SortedDict
    # Rearrange inventory for better processing
    @info "analyse inventory and local database"
    database = inventory_dates(inventory, none)
    # Scan inventory for additional files and folders
    root = inventory["metadata"]["local"]["path"]
    db = localscan(database, root, intersect)
    # Clean up local database and save inventory
    conversion(inventory, db.files, sizecheck, logger.file)
    save_inventory(inventory, logger.tee, logger.start)
    close(logger.file.logger.stream)
    @info "conversion session completed"
    return inventory
end


#* Functions for conversions during download

"""
    _convert!(
        inventory::SortedDict,
        file::File,
        convert::Bool,
        logger::logex.AbstractLogger
    )

Convert the `file` to a new file format as defined in the `inventory` unless `file` is already
up-to-date or it was opted out to `convert` the file. Log events to `logger`.
"""
function _convert!(
    inventory::SortedDict,
    file::File,
    convert::Bool,
    logger::logex.AbstractLogger
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
        logger::logex.AbstractLogger
    )

Set the size of the converted `file` in the `inventory` and mark the `inventory` as updated.
Log events to `logger`.
"""
function set_converted_size!(
    inventory::SortedDict,
    file::File,
    convert::Bool,
    logger::logex.AbstractLogger
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
            logex.with_logger(logger) do
                @error "cannot determine size of '$(file.location.target)'"
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
        logger::logex.AbstractLogger
    )

Convert all `files` part of the `inventory` to a new format as defined in the `inventory`.
Conversions are skipped, if files of the new format already exist and either their size matches
the one listed in the `inventory` or `sizecheck` is set to `false`. Log events to `logger`.
"""
function conversion(
    inventory::SortedDict,
    files::Set{String},
    sizecheck::Bool,
    logger::logex.AbstractLogger
)::Nothing
    # Remove .inventory.yaml from files to convert
    ext = inventory["metadata"]["file"]["ext"]
    newext = inventory["metadata"]["file"]["newext"]
    input = filter(endswith(ext), files)
    logex.with_logger(logger) do
        @info "found $(length(input)) files in local database for conversion" files=input
    end
    if !sizecheck
        input = setdiff(getindex.(splitext.(input), 1),
            getindex.(splitext.(filter(endswith(newext), files)), 1)).*ext
        logex.with_logger(logger) do
            @debug "ignoring already converted files without size check, $(length(input)) files to convert" files=input
        end
    end
    input = File.(Ref(inventory), input)
    t0 = Dates.now()
    @info("starting up to $(Threads.nthreads()) parallel conversions of $(length(input)) files\n"*
        "start julia with `julia -t <number>` to change the `<number>` of parallel downloads")
    logex.with_logger(logger) do
        @info "starting up to $(Threads.nthreads()) parallel conversions of $(length(input)) files @$t0"
    end
    prog = pm.Progress(length(input), desc="converting...")
    @threads for file in input
        lock(thread) do
            # Log converted files
            logex.with_logger(logger) do
                @debug "convert '$(file.name)'"
            end
        end
        _convert!(inventory, file, true, logger)
        pm.next!(prog)
    end
    pm.finish!(prog)
    t = Dates.now()
    logex.with_logger(logger) do
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
