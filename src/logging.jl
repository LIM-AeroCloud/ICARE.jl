## Helper functions for logging

## Setup functions


"""
    init_logging(logfile::String, rootdir::String, loglevel::Symbol)
        -> @NamedTuple{file::logex.AbstractLogger,tee::logex.AbstractLogger}

Add a timestamp to the `logfile`. If no path is given in the file name, save logfile to
`rootdir`. Return the file logger and tee logger for dual logging as `NamedTuple` with fields
`file` and `tee`.
"""
function init_logging(
    logfile::String, rootdir::String, loglevel::Symbol
)::@NamedTuple{file::PrettyFileLogger,tee::logex.TeeLogger}
    # Set log level
    level = try getproperty(@__MODULE__, loglevel)
    catch
        @warn "unknown log level $loglevel; using Debug as default"
        getproperty(@__MODULE__, :Debug)
    end
    # Define log file with timestamp
    contains(logfile, Base.Filesystem.path_separator) || (logfile = joinpath(rootdir, logfile))
    logfile, logext = splitext(logfile)
    logfile *= "_" * Dates.format(Dates.now(), Dates.dateformat"yyyy_mm_dd_HH_MM_SS") * logext
    logfile = expanduser(logfile)
    @info "logging to '$logfile'"
    file_logger = PrettyFileLogger(logfile, level)
    tee_logger = create_tee_logger(file_logger)
    return (file = file_logger, tee = tee_logger)
end

## Custom file logger
struct PrettyFileLogger <: logex.AbstractLogger
    logger::logex.ConsoleLogger
    always_flush::Bool
end

"""
    PrettyFileLogger(
        path::AbstractString,
        level::Base.CoreLogging.LogLevel=Base.CoreLogging.BelowMinLevel;
        append::Bool=false,
        kwargs...
    ) -> PrettyFileLogger

Create a logger sink that writes messages to a file specified with `path`.
All messages with a level greater than or equal to `level` are logged.
To append to the file (rather than truncating the file first), use `append=true`.
If `always_flush=true` the stream is flushed after every handled log message.

!!! note
    `PrettyFileLogger` uses the same output formatting as `ConsoleLogger` with module, file,
    and line information suppressed by default, `show_limited` is set to `false` giving
    expanded array displayed of attached data. If you want default behaviour, set the following
    kwargs: `_module=@__MODULE__, _file=@__FILE__, _line=@__LINE__, show_limited=true`.

"""
function PrettyFileLogger(
    path::AbstractString,
    level::Base.CoreLogging.LogLevel=Base.CoreLogging.BelowMinLevel;
    append::Bool=false,
    kwargs...
)::PrettyFileLogger
    filehandle = open(path, append ? "a" : "w")
    PrettyFileLogger(filehandle; kwargs...)
end

"""
    PrettyFileLogger(
        filehandle::IOStream,
        level::Base.CoreLogging.LogLevel=Base.CoreLogging.BelowMinLevel;
        always_flush::Bool=true,
        kwargs...
    )::PrettyFileLogger

Create a logger sink that write messages to the `io::IOStream`. The stream
is expected to be open and writeable.
If `always_flush=true` the stream is flushed after every handled log message.

!!! note
    `PrettyFileLogger` uses the same output formatting as `ConsoleLogger` with module, file,
    and line information suppressed by default, `show_limited` is set to `false` giving
    expanded array displayed of attached data. If you want default behaviour, set the following
    kwargs: `_module=@__MODULE__, _file=@__FILE__, _line=@__LINE__, show_limited=true`.


# Examples
```julia
io = open("path/to/file.log", "a") # append to the file
logger = PrettyFileLogger(io)
```
"""
function PrettyFileLogger(
    filehandle::IOStream,
    level::Base.CoreLogging.LogLevel=Base.CoreLogging.BelowMinLevel;
    always_flush::Bool=true,
    kwargs...
)::PrettyFileLogger
    # Create ConsoleLogger with show_limited=false for expanded array display
    PrettyFileLogger(logex.ConsoleLogger(filehandle, level; show_limited=false), always_flush)
end

function logex.handle_message(filelogger::PrettyFileLogger, level, message, _module, group, id, file, line; kwargs...)
    # Override module/file/line to suppress source location
    logex.handle_message(filelogger.logger, level, message, nothing, group, id, nothing, nothing; kwargs...)
    filelogger.always_flush && flush(filelogger.logger.stream)
end
logex.shouldlog(filelogger::PrettyFileLogger, arg...) = true
logex.min_enabled_level(filelogger::PrettyFileLogger) = logex.BelowMinLevel
logex.catch_exceptions(filelogger::PrettyFileLogger) = logex.catch_exceptions(filelogger.logger)


## Custom loggers for LoggingExtras

"""
    custom_console_logger(log_args)

A custom logger transformer that suppresses source location information such as
module, file, and line number for console logging.
"""
function custom_console_logger(log_args)
    # Suppress source info
    return merge(log_args, (
        _module = nothing,
        file = nothing,
        line = nothing
    ))
end


"""
    create_tee_logger(file_logger::logex.AbstractLogger) -> TeeLogger

Create a TeeLogger that combines the `file_logger` with a console logger wrapped with
custom_console_logger transformer. This allows logging to both the screen and file
simultaneously with consistent formatting.
"""
function create_tee_logger(file_logger::logex.AbstractLogger)
    # Wrap console logger with transformer to suppress source info
    console_logger = logex.TransformerLogger(custom_console_logger, logex.ConsoleLogger(stderr, logex.Info))
    return logex.TeeLogger(console_logger, file_logger)
end


## Functions for writing logs

"""
    log_counter(counter::Counter, logger::logex.AbstractLogger, t0::DateTime)

Log the number of downloaded, skipped, and converted files saved in `counter` to `logger`
together with the time it took since `t0`.
"""
function log_counter(counter::Counter, logger::logex.AbstractLogger, t0::DateTime)::Nothing
    t1 = Dates.now()
    logex.with_logger(logger) do
        if counter.downloads > 0
            s = counter.downloads == 1 ? "" : "s"
            @info "$(counter.downloads) file$s downloaded in $(Dates.canonicalize(t1-t0)) @$(t1)"
        end
        if counter.conversions > 0
            s = counter.conversions == 1 ? " was" : "s were"
            @info "$(counter.conversions) file$s already downloaded and converted to a new file format"
        end
        if counter.skipped > 0
            s = counter.skipped == 1 ? " was" : "s were"
            @info "$(counter.skipped) file$s already previously downloaded"
        end
        if counter.failed > 0
            s = counter.failed == 1 ? "" : "s"
            @warn "$(counter.failed) file$s failed to download"
        end
    end
end
