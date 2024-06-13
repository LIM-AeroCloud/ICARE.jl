## Routines related to converting different HDF versions

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
    )::Nothing

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
You can change the `logfile` name (including a different directory). The timestamp
will be added automatically on creation. The number of log entries can be changed
by setting the severity level to:

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
  logfile, level = init_logging(logfile, loglevel)
  open(logfile,"w") do logio
    logger = Logging.ConsoleLogger(logio, level, show_limited=false)
    # Security check
    if clean
      @warn "clean is set to true: all HDF4 files will be deleted" _module=nothing _file=nothing _line=nothing
      @warn "you will have to re-download deleted HDF4 files – continue(yes/no)?" _module=nothing _file=nothing _line=nothing
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


"""
    init_logging(logfile::String, loglevel::Symbol)::Tuple{String,Logging.LogLevel}

Add a timestamp to the `logfile` and return the `loglevel` as `Logging.LogLevel`.
"""
function init_logging(logfile::String, loglevel::Symbol)::Tuple{String,Logging.LogLevel}
  # Set log level
  loglevels = Dict(
    :Debug => Logging.Debug,
    :Info => Logging.Info,
    :Warn => Logging.Warn,
    :Error => Logging.Error
  )
  level = loglevels[loglevel]
  # Define log file with timestamp
  logfile, logext = splitext(logfile)
  logfile *= "_" * Dates.format(Dates.now(), Dates.dateformat"yyyy_mm_dd_HH_MM_SS") * logext
  return logfile, level
end


"""
    find_hdffiles(
      rootdir::String,
      recursive::Bool,
      ext::Union{String,Vector{String}},
      h5ext::String
    )::Tuple{Vector{String},Vector{String}}

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
    )::Vector{Int}

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
    )::Vector{String}

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
    )::Nothing

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
      flush(logio)
    end
  end
end


"""
    h4cleanup(h4files::Vector{String}, clean::Bool, logger::Logging.ConsoleLogger)::Nothing

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
