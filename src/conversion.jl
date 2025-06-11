## Routines related to converting different HDF versions

## API functions

"""
    hdfupgrade(
        product::String,
        version::Float64 = 4.51;
        localroot::String = ".",
        remoteroot::String = "/SPACEBORNE/CALIOP",
        user::String = "",
        password::String = "",
        clean::Bool = false,
        h4ext::String = ".hdf",
        h5ext::String = ".h5",
        logfile::String = "conversions.log",
        loglevel::Symbol = :Debug
    )

Convert all HDF4 data files to HDF5 files (with `h4ext`/`h5ext` file extensions, respectively)
that are part of specified `product` in the given `version`.

To check, whether hdf files are part of the `product`, the are compared to the inventory file
in the product folder in the `localroot`. Additional checks against the ICARE server can be
performed with a significant increase in processing time, if the ICARE `user` name and
`password` are given as well as the `remoteroot` of the product folder on the server.

By default, files are upgraded to HDF5 standard and original files are kept. If `clean`
is set to `true`, the original files are deleted upon confirmation.
**This means that data files will have to be re-downloaded, if data files in the original
HDF4 format are needed!**

Events of the desired `loglevel` will be logged to `logfile`. A timestamp will be added
to each logfile so that a unique logfile is created for every run and logfiles are not
overwritten.
"""
function hdfupgrade(
    product::String,
    version::Float64 = 4.51;
    localroot::String = ".",
    remoteroot::String = "/SPACEBORNE/CALIOP",
    user::String = "",
    password::String = "",
    clean::Bool = false,
    h4ext::String = ".hdf",
    h5ext::String = ".h5",
    logfile::String = "conversions.log",
    loglevel::Symbol = :Debug
)::Nothing
    # Define product folder and path
    product = @sprintf "%s.v%.2f" product version
    productpath = realpath(joinpath(localroot, product))
    start = length(productpath) + 2 # start index of remaining path (+1 for `\`, +1 for next char in string)
    # Start logging
    logfile, level = init_logging(logfile, productpath, loglevel)
    open(logfile,"w") do logio
        logger = Logging.ConsoleLogger(logio, level, show_limited=false)
        Logging.with_logger(logger) do
            @info "Upgrading all HDF4 files listed in inventory for $product to HDF5"
        end
        # Security check
        confirm(clean, logger) || return
        # Load inventory, optionally connect to server
        icare, inventory = load_database(product, localroot, remoteroot, user, password, logger)
        # Recursively search productpath for hdf files to upgrade
        @info "start file conversions"
        for (path, dirs, files) in collect(walkdir(productpath))
            # Check folder structure
            path = path[start:end]
            valid_dir(path, inventory["metadata"], logger) || continue
            # Get h4/h5 files in current folder
            h4files = getindex.(splitext.(filter(endswith(h4ext), files)), 1)
            h5files = getindex.(splitext.(filter(endswith(h5ext), files)), 1)
            # Loop over h4 files and upgrade to h5, if not already existing
            date = Date(basename(path), "yyyy_mm_dd")
            pm.@showprogress dt=1 desc="$date:" for file in h4files
                EC = in_database(inventory, icare, productpath, path, file, h5files)
                convert_hdffile!(inventory, file, path, productpath, EC, clean, logger; h4ext, h5ext)
                flush(logio)
            end
        end
    end
end


"""
    hdfupgrade(
        rootdir::String=".",
        ext::Union{String,Vector{String}}=[".hdf", ".h4", ".hdf4"];
        recursive::Bool=true,
        h5exists::Symbol=:skip,
        h5ext::String=".h5",
        clean::Bool=false,
        logfile::String=joinpath(rootdir, "hdfupgrades.log"),
        loglevel::Symbol=:Debug
    )

Convert all HDF4 files (identified by their file `ext`ension) to HDF5 files with
extension `h5ext`. By default, all files in `rootdir` and the containing subfolders
are converted. The recursive search of subdirectories can be switched by setting
the `recursive` flag to `false`.

If an h5 file already exists, the following options exist for the HDF4 conversion
(given as `Symbol` to the `h5exists` flag):

- `skip` (default): skips conversion and leaves existing HDF5 file
- `overwrite`: overwrites the existing HDF5 file
- `cancel`: stops on the first existing HDF5 file
- `abort`: same as `cancel`, but does not convert HDF4 files up to this point

THe original HDF4 files are kept, unless `clean` is set to `true` and the deletion
is confirmed at the beginning of the function call.

By default, the `logfile` is created as `rootdir/hdfupgrades_<timestamp>.log`.
You can change the `logfile` name (including a different directory). If no path is
given in the logfile, it will be saved to `rootdir`. The timestamp will be added a
utomatically on creation. The number of log entries can be changed by setting the
severity level to:

- `:Error`: Only errors (and severe warnings) are shown.
- `:Warn`: Warnings and errors are shown.
- `:Info`: Info messages are shown additionally.
- `:Debug`: All log messages are shown.

This changes only the behaviour in the logfile, not on-screen logging.
"""
function hdfupgrade(
    rootdir::String=".",
    ext::Union{String,Vector{String}}=[".hdf", ".h4", ".hdf4"];
    recursive::Bool=true,
    h5exists::Symbol=:skip,
    h5ext::String=".h5",
    clean::Bool=false,
    logfile::String=joinpath(rootdir, "hdfupgrades.log"),
    loglevel::Symbol=:Debug
)::Nothing
    # Setup logging
    logfile, level = init_logging(logfile, rootdir, loglevel)
    open(logfile,"w") do logio
    logger = Logging.ConsoleLogger(logio, level, show_limited=false)
    # Security check
    if clean
        @warn "clean is set to true: all HDF4 files will be deleted" _module=nothing _file=nothing _line=nothing
        @warn "deleted HDF4 files will have to re-downloaded from server – continue(yes/no)?" _module=nothing _file=nothing _line=nothing
        confirm = readline()
            if confirm == lowercase("yes")
                Logging.with_logger(logger) do
                    @warn "Deleting all HDF4 files"
                end
            else
                @info "conversion aborted"
                return
            end
        end
        # Find HDF4 files and corresponding HDF5 files
        h4files, h5files = find_hdffiles(rootdir, recursive, ext, h5ext)
        # Identify already existing HDF5 files
        h5 = find_conflicts(h5files, logger)
        # Convert HDF4 files to HDF5 files
        h4deletions = setup_conversion!(h4files, h5files, h5, h5exists, logger)
        convert_hdffiles(h4files, h5files, logger, logio)
        # Remove hdf4 files, if clean is set to true
        h4cleanup(h4deletions, clean, logger)
    end #close log file
end


## Setup functions

"""
    init_logging(logfile::String, rootdir::String, loglevel::Symbol) -> Tuple{String,Logging.LogLevel}

Add a timestamp to the `logfile`. If no path is given in the file name, save logfile to
`rootdir`. Return the updated logfile and the `loglevel` as `Logging.LogLevel`.
"""
function init_logging(logfile::String, rootdir::String, loglevel::Symbol)::Tuple{String,Logging.LogLevel}
    # Set log level
    level = try getproperty(Logging, loglevel)
    catch
        @warn "unknown log level $loglevel; using Debug as default" _module=nothing _file=nothing _line=nothing
        loglevel = :Debug
    end
    # Define log file with timestamp
    contains(logfile, Base.Filesystem.path_separator) || (logfile = joinpath(rootdir, logfile))
    logfile, logext = splitext(logfile)
    logfile *= "_" * Dates.format(Dates.now(), Dates.dateformat"yyyy_mm_dd_HH_MM_SS") * logext
    return logfile, level
end


"""
    confirm(clean::Bool, logger::Logging.ConsoleLogger) -> Bool

Confirm to delete HDF4 files, if `clean` is set to `true` with terminal input
and log events to `logger`.
Return `true`, if `clean` is `false`, or `clean` is `true` and the user confirmed with `"yes"`.
Return `false`, if clean is `true` and user did not confirm with `"yes"`.
"""
function confirm(clean::Bool, logger::Logging.ConsoleLogger)::Bool
    clean || return true
    @warn "clean is set to true: all HDF4 files will be deleted" _module=nothing _file=nothing _line=nothing
    @warn "deleted HDF4 files will have to re-downloaded from server – continue(yes/no)?" _module=nothing _file=nothing _line=nothing
    confirmation = readline()
    if confirmation == lowercase("yes")
        Logging.with_logger(logger) do
        @warn "Deleting all HDF4 files"
        end
        true
    else
        @info "conversion aborted; set `clean` to `false` or confirm with `\"yes\"` to continue"
        false
    end
end


## Helper functions for h4 to h5 conversions of inventory data only
#* Database checks

"""
    load_database(
      productfolder::String,
      localroot::String,
      remoteroot::String,
      user::String,
      password::String,
      logger::Logging.ConsoleLogger
    ) -> Tuple{Union{SFTP.Client,Nothing},OrderedDict}

Load the inventory in the given `productfolder` of the `localroot`.
Additionally, access ICARE server data, if the `user` name, `password`, and `remoteroot`
are given. One or the other must be given or an `IOError` will be thrown.
All events are logged to `logger`.
"""
function load_database(
  productfolder::String,
  localroot::String,
  remoteroot::String,
  user::String,
  password::String,
  logger::Logging.ConsoleLogger
)::Tuple{Union{SFTP.Client,Nothing},OrderedDict}
    # Setup
    icare = nothing
    productpath = joinpath(localroot, productfolder)
    # Check available sync options and get local inventory
    ifile = joinpath(productpath, "inventory.yaml")
    inventory = if isfile(ifile) && credentials(user, password)
        icare = icare_connect(user, password, remoteroot, productfolder)
        Logging.with_logger(logger) do
            @info "checking against local inventory and server"
        end
        load_inventory(ifile)
    elseif isfile(ifile)
        @warn "checking against local inventory only; give icare `user` name and `password` to allow extended checks against server data" _module=nothing _file=nothing _line=nothing
        Logging.with_logger(logger) do
            @info "checking against local inventory only"
        end
        load_inventory(ifile)
    elseif credentials(user, password)
        @warn "no inventory.yaml; syncing with server" _module=nothing _file=nothing _line=nothing
        @warn "missing inventory.yaml means poor performance due to long sync times with the server" _module=nothing _file=nothing _line=nothing
        icare = icare_connect(user, password, remoteroot, productfolder)
        Logging.with_logger(logger) do
            @info "local inventory missing, checking against server only"
        end
        product_database(icare, remoteroot, localroot, productfolder, Date(0), Date(9999), false, logger)
    else
        throw(Base.IOError("missing inventory.yaml and ICARE user credentials; one or the other needed to proceed", 3))
    end
    return icare, inventory
end


"""
    valid_dir(
        path::String,
        metadata::OrderedDict,
        logger::Logging.ConsoleLogger
    ) -> Bool

Check that the `path` is a valid directory within the ICARE folder structure.
Return `true`, if the folder meets the ICARE standard, `false` otherwise.
Log events to `logger` (using `metadata` if needed).
"""
function valid_dir(
    path::String,
    metadata::OrderedDict,
    logger::Logging.ConsoleLogger
)::Bool
    # Analyse curent path
    directory = splitpath(path)
    # Check correct folder structure
    ok = length(directory) == 2
    ok = ok && directory[1] == directory[2][1:4]
    # Check folder is a valid date
    date = try Date(directory[2], "yyyy_mm_dd")
    catch
        return false
    end
    # Check date is in expected range
    ok &= if date in metadata["database"]["gaps"]
        Logging.with_logger(logger) do
            @warn "no data reported for $date in inventory; skipping all conversions for this date" _module=nothing _file=nothing _line=nothing
        end
        false
    elseif date < metadata["database"]["start"] || date > metadata["database"]["stop"]
        Logging.with_logger(logger) do
            @warn "date $date outside expected range $(metadata["database"]["start"]) – $(metadata["database"]["stop"]); skipping all conversions for this date" _module=nothing _file=nothing _line=nothing
        end
        false
    else
        Logging.with_logger(logger) do
            @info "processing date $date"
        end
        true
    end
    return ok && date ≤ Dates.today()
end


"""
    in_database(
        inventory::OrderedDict,
        icare::SFTP.Client,
        root::String,
        path::String,
        file::String,
        h5files::Vector{String}
    ) -> Int8

Determine, whether the `file` in the given `path` of the `root` directory is part
of the `inventory`. Check the `icare` server, if files for a given date are unavailable.
Check against available `h5files` in the same folder for already converted files.
Return an error code for possible events:

- `-1`: corrupt inventory (should not happen)
- `0`: file in database
- `1`: h5 already exists; conversion skipped
- `2`: existing h5 file/inventory need update
- `3`: not in local inventory
- `4`: file not on server
- `5`: no data reported for date (should already be caught elsewhere)
- `6`: date outside expected date range (should already be caught elsewhere)
"""
function in_database(
    inventory::OrderedDict,
    icare::SFTP.Client,
    root::String,
    path::String,
    file::String,
    h5files::Vector{String}
)::Int8
    # Check date and file are in inventory
    d = Date(splitpath(path)[2], "yyyy_mm_dd")
    ok1 = haskey(inventory, d)
    ok2 = ok1 && haskey(inventory[d], file)
    if ok2
        h5 = findfirst(isequal(file), h5files)
        if isnothing(h5)
            return 0 # ℹ EC0: no error; h4 file found without converted h5 file
        else
            h4stats = stat(joinpath(root, path, file*".hdf"))
            h5stats = stat(joinpath(root, path, h5files[h5]*".h5"))
            if !haskey(inventory[d][file], "h5size") ||
                h5stats.size ≠ inventory[d][file]["h5size"] || h5stats.mtime < h4stats.mtime
                return 2 # ℹ EC2: existing h5 file/inventory need update
            else
                return 1 # ℹ EC1: h5 already exists; conversion skipped
            end
        end
    elseif ok1
        if isnothing(icare)
            return 3 # ℹ EC3: not in local inventory
        else
            remotefiles!(icare, inventory, path, d)
            ok2 = haskey(inventory[d], file)
            if ok2 && file in h5files
                return 2 # ℹ EC2: existing h5 file/inventory need update
            elseif ok2
                return 0 # ℹ EC0: no error; h4 file found without converted h5 file
            else
                return 4 # ℹ EC4: file not on server
            end
        end
    # issue: The following errors should not occur (and be caught elsewhere)
    elseif d in inventory["metadata"]["database"]["gaps"]
        return 5 # ℹ EC5: no data reported for date
    elseif d < inventory["metadata"]["database"]["start"] || d > inventory["metadata"]["database"]["stop"]
        return 6 # ℹ EC6: date outside expected date range
    end
    return -1 # ℹ EC-1: corrupt inventory
end


"""
    credentials(user::String, password::String) -> Bool

Return `true`, if the `user` name and `password` for the ICARE server are set, otherwise `false`.
Credentials are not checked for validity, only that they are not empty.
"""
credentials(user::String, password::String)::Bool = !isempty(user) && !isempty(password)


#* Conversion routines

"""
    convert_hdffile!(
        inventory::OrderedDict,
        file::String,
        path::String,
        root::String,
        error_code::Int8,
        clean::Bool,
        logger::Logging.ConsoleLogger;
        h4ext::String=".hdf",
        h5ext::String=".h5"
    )

Convert the `file` in the given `path` of the `root` directory from HDF4 to HDF5 standard
(using `h4ext` and `h5ext` file extensions, respectively) and update the `inventory`
by the file size of the new h5 file.
Handle conversions and log events to `logger` based on the given `error_code`.
Delete HDF4 after successful conversion, if `clean` is set to `true`.
"""
function convert_hdffile!(
    inventory::OrderedDict,
    file::String,
    path::String,
    root::String,
    error_code::Int8,
    clean::Bool,
    logger::Logging.ConsoleLogger;
    h4ext::String=".hdf",
    h5ext::String=".h5"
)::Nothing
    # Define date in current data file
    date = Date(splitpath(path)[2], "yyyy_mm_dd")
    # @debug error_code _module=nothing _file=nothing _line=nothing
    # Convert files and log events based on error code
    h4file = joinpath(root, path, file*h4ext)
    h5file = joinpath(root, path, file*h5ext)
    if error_code == 0
        Logging.with_logger(logger) do
            @debug "converting $file$h4ext > $file$h5ext" _module=nothing _file=nothing _line=nothing
        end
        h5upgrade!(inventory, date, h4file, h5file)
    elseif error_code == 1
        Logging.with_logger(logger) do
            @debug "skipping conversion of already existing file $file$h5ext" _module=nothing _file=nothing _line=nothing
        end
    elseif error_code == 2
        Logging.with_logger(logger) do
            @debug "updating h5 file $file$h5ext" _module=nothing _file=nothing _line=nothing
        end
        h5upgrade!(inventory, date, h4file, h5file, force=true)
    elseif error_code == 3
        Logging.with_logger(logger) do
            @warn "skipping conversion of $file$h4ext; not in local inventory; consider updating inventory" _module=nothing _file=nothing _line=nothing
        end
    elseif error_code == 4
        Logging.with_logger(logger) do
            @info "skipping conversion of $file$h4ext; file not found on server"
        end
    # issue: The following errors should not occur and by caught by valid_dir
    elseif error_code == 5
        Logging.with_logger(logger) do
            @warn "skipping conversion of $file$h4ext; no data reported for $date in inventory" _module=nothing _file=nothing _line=nothing
        end
    elseif error_code == 6
        Logging.with_logger(logger) do
            @warn("date $date outside expected range $(inventory["metadata"]["database"]["start"]) – $(inventory["metadata"]["database"]["stop"]); skipping $file$h4ext",
                _module=nothing, _file=nothing, _line=nothing)
        end
    else
        Logging.with_logger(logger) do
            @warn("could not convert $file$h4ext; local inventory might be corrupted; consider erasing $(joinpath(inventory["metadata"]["local"]["path"], "inventory.yaml"))",
                _module=nothing, _file=nothing, _line=nothing)
        end
    end
    # Delete h4 file after successful conversion, if option is selected
    isfile(h5file) && rmh4(h4file, clean, logger)
    return
end


"""
    h5upgrade!(
      inventory::OrderedDict,
      date::Date,
      h4file::String,
      h5file::String="";
      force::Bool=false
    )

Upgrade the `h4file` to `h5file` for the given `date` and add the size of the new
HDF5 file to the `inventory`. Overwrite any existing `h5file`, if `force` is set
to `true`.
"""
function h5upgrade!(
    inventory::OrderedDict,
    date::Date,
    h4file::String,
    h5file::String="";
    force::Bool=false
)::Nothing
    # Define default hdf5 file
    file = splitext(h4file)[1]
    isempty(h5file) && (h5file = file * ".h5")
    # Make sure, previous h5 versions are overwritten
    force && rm("$h5file"; force)
    # Convert hdf4 to hdf5
    run(`h4toh5 $h4file $h5file`)
    # Add new file size to inventory
    inventory[date][basename(file)]["h5size"] = filesize(h5file)
    save_inventory(inventory)
end


"""
    rmh4(
        file::String,
        clean::Bool,
        logger::Logging.ConsoleLogger
    )

Delete the HDF4 `file`, if `clean` is set to `true` and log the event to `logger`.
"""
function rmh4(
    file::String,
    clean::Bool,
    logger::Logging.ConsoleLogger
)::Nothing
    clean || return
    rm(file)
    Logging.with_logger(logger) do
        @debug "$file deleted" _module=nothing _file=nothing _line=nothing
    end
end


## Helper functions for general h4 to h5 conversions

"""
    find_hdffiles(
        rootdir::String,
        recursive::Bool,
        ext::Union{String,Vector{String}},
        h5ext::String
    ) -> Tuple{Vector{String},Vector{String}}

Search for HDF4 files with the specified `ext`ension(s) in the `rootdir` and any
subdirectories, if `recursive` is set to `true`.

Return vectors with the absolute paths and file names of the HDF4 files and the
respective HDF5 counterparts exchanging the file extension to `h5ext`.
"""
function find_hdffiles(
    rootdir::String,
    recursive::Bool,
    ext::Union{String,Vector{String}},
    h5ext::String
)::Tuple{Vector{String},Vector{String}}
    # Setup
    ext isa String && (ext = [ext])
    rootdir = abspath(rootdir)
    # Find HDF4 files
    if recursive
        h4files = String[]
        for (dir, folders, files) in walkdir(rootdir)
        push!(h4files, filter(x->splitext(x)[2] ∈ ext, joinpath.(dir, files))...)
        end
    else
        h4files = filter(x->splitext(x)[2] ∈ ext, readdir(rootdir, join=true))
    end
    # Find already existing HDF5 files
    h5files = isempty(h4files) ? String[] : getindex.(splitext.(h4files), 1) .* h5ext

    return h4files, h5files
end


"""
    find_conflicts(
        h5files::Vector{String},
        logger::Logging.ConsoleLogger
    ) -> Vector{Int}

Search for existing `h5files` and return a vector of indices of the existing files
in `h5files`.
"""
function find_conflicts(
    h5files::Vector{String},
    logger::Logging.ConsoleLogger
)::Vector{Int}
    h5=findall(isfile, h5files)
    h5conflicts = h5files[h5]
    isempty(h5conflicts) || Logging.with_logger(logger) do
        @warn "The following HDF5 files already exist" h5conflicts _module=nothing _file=nothing _line=nothing
    end
    return h5
end


"""
    setup_conversion!(
        h4files::Vector{String},
        h5files::Vector{String},
        h5::Vector{Int},
        h5exists::Symbol,
        logger::Logging.ConsoleLogger
    ) -> Vector{String}

Adjust the list of existing `h4files` and target `h5files` using the indexes of
existing `h5` files based on the choices, if `h5exists`. Conversions with existing
`h5` files can either be skipped or cancelled on the first encounter (deleting the
respective entries in `h4files` and `h5files`), overwritten or aborted (emptying
the `h5files` vector).
Choices and number of conversions are logged to `logger`.
"""
function setup_conversion!(
    h4files::Vector{String},
    h5files::Vector{String},
    h5::Vector{Int},
    h5exists::Symbol,
    logger::Logging.ConsoleLogger
)::Vector{String}
    # Define files to convert based on option for existing HDF5 files
    if h5exists == :skip
        # Remove files from h4 list, where h5 files already exist
        h4deletions = copy(h4files)
        deleteat!(h4files, h5)
        deleteat!(h5files, h5)
        Logging.with_logger(logger) do
            @info "conversions for existing HDF5 files will be skipped"
            @info "conversion of $(length(h4files)) HDF4 files" h4files
        end
        return h4deletions
    elseif h5exists == :overwrite
        # Remove existing h5 files
        rm.(h5files[h5])
        Logging.with_logger(logger) do
            @warn "Existing HDF5 files will be overwritten" _module=nothing _file=nothing _line=nothing
            @info "conversion of $(length(h4files)) HDF4 files" h4files
        end
    elseif h5exists == :cancel && !isempty(h5)
        # Remove all h4 files starting at the first existing h5 file
        deleteat!(h4files, h5[1]:length(h4files))
        deleteat!(h5files, h5[1]:length(h5files))
        Logging.with_logger(logger) do
            @error "only $(h5[1]-1) HDF4 files will be upgraded due to already existing HDF5 file(s)"  _module=nothing _file=nothing _line=nothing
            @info "conversion of $(length(h4files)) HDF4 files" h4files
        end
    elseif h5exists == :abort && !isempty(h5)
        # Skip conversion
        empty!(h4files)
        Logging.with_logger(logger) do
            @error " HDF4 file upgrades aborted due to already existing HDF5 file(s)"  _module=nothing _file=nothing _line=nothing
        end
    end
    return h4files
end


"""
    convert_hdffiles(
        h4files::Vector{String},
        h5files::Vector{String},
        logger::Logging.ConsoleLogger,
        logio::IOStream
    )

Convert `h4files` to `h5files` and log successful conversions to `logger`.
Successes are immediately flushed to `logio` to always have an up-to-date
"""
function convert_hdffiles(
    h4files::Vector{String},
    h5files::Vector{String},
    logger::Logging.ConsoleLogger,
    logio::IOStream
)::Nothing
    # Initial log entry for conversion debug logs
    if isempty(h4files)
        Logging.with_logger(logger) do
            @debug "No conversions attempted" _module=nothing _file=nothing _line=nothing
        end
    else
        Logging.with_logger(logger) do
            @debug "The following entries show all successful conversions" _module=nothing _file=nothing _line=nothing
        end
    end
    # Loop over files, convert to h5 and log to logger
    pm.@showprogress 1 "convert h4>h5..." for i = 1:length(h4files)
        run(`h4toh5 $(h4files[i]) $(h5files[i])`)
        Logging.with_logger(logger) do
            @debug "$(basename(h4files[i])) > $(basename(h5files[i]))" _module=nothing _file=nothing _line=nothing
        end
        flush(logio)
    end
end


"""
    h4cleanup(h4files::Vector{String}, clean::Bool, logger::Logging.ConsoleLogger)

Delete all `h4files`, if `clean` is set to `true` and log deletions to `logger`.
"""
function h4cleanup(h4files::Vector{String}, clean::Bool, logger::Logging.ConsoleLogger)::Nothing
    # Cancel removal of HDF4 files, if no HDF4 files found or clean is false
    if !clean || isempty(h4files)
        return
    end
    # Delete HDF4 files
    Logging.with_logger(logger) do
        @debug "The following HDF4 files were successfully deleted" _module=nothing _file=nothing _line=nothing
        for file in h4files
            rm(file)
            @debug "$(basename(file))" _module=nothing _file=nothing _line=nothing
        end
    end
end
