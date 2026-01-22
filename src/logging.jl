## Helper functions for logging

## Setup functions


"""
    init_logging(logfile::AbstractString, rootdir::AbstractString, loglevel::Symbol) -> Logger

Add a timestamp for the start time to the `logfile`. Save logfile relative to `rootdir` or
consider any absolute paths in `logfile`. Return a `Logger` struct with the two loggers for
file logging and tee logging (simultaneous file and console logging) together with the
log `filename` and the `start` time.
"""
function init_logging(
    logfile::AbstractString, rootdir::AbstractString, loglevel::Symbol
)::Logger
    # Set log level
    level = try getproperty(Logging, loglevel)
    catch
        @warn "unknown log level $loglevel; using Debug as default"
        getproperty(Logging, :Debug)
    end
    # Check folder to log to
    folder = dirname(logfile)
    if folder == "logs"
        mkpath(joinpath(rootdir, folder))
    elseif !isempty(folder)
        isdir(joinpath(rootdir, folder)) || throw(ArgumentError(
            "cannot save log files to non-existing folder\n$(abspath(rootdir, folder))")
        )
    end
    # Define log file with timestamp of start time
    start = Dates.now()
    logfile = normpath(rootdir, expanduser(logfile))
    logfile, logext = splitext(logfile)
    logfile *= "_" * Dates.format(start, Dates.dateformat"yyyy_mm_dd_HH_MM_SS") * logext
    @info "logging to '$logfile'"
    # Remember log file in inventory logs
    open(joinpath(rootdir, ".inventory.logs"), "a") do io
        println(io, relpath(logfile, rootdir))
    end
    # Init loggers and return as NamedTuple
    file_logger = PrettyFileLogger(logfile, level)
    tee_logger = create_tee_logger(file_logger)
    return Logger(file_logger, tee_logger, logfile, start)
end


## Custom file logger

"""
# PrettyFileLogger

A logger sink for file logging based on `ConsoleLogger` with better formatting options.
"""
struct PrettyFileLogger <: Logging.AbstractLogger
    logger::Logging.ConsoleLogger
    always_flush::Bool
end

"""
    PrettyFileLogger(
        path::AbstractString,
        level::Logging.LogLevel=Logging.BelowMinLevel;
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
    level::Logging.LogLevel=Logging.BelowMinLevel;
    append::Bool=false,
    kwargs...
)::PrettyFileLogger
    filehandle = open(path, append ? "a" : "w")
    PrettyFileLogger(filehandle, level; kwargs...)
end

"""
    PrettyFileLogger(
        filehandle::IOStream,
        level::Logging.LogLevel=Logging.BelowMinLevel;
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
    level::Logging.LogLevel=Logging.BelowMinLevel;
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
logex.shouldlog(filelogger::PrettyFileLogger, args...) = logex.shouldlog(filelogger.logger, args...)
logex.min_enabled_level(filelogger::PrettyFileLogger) = logex.min_enabled_level(filelogger.logger)
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
    create_tee_logger(file_logger::logex.AbstractLogger) -> Logger

Create a custom logger that combines the `file_logger` with a console logger wrapped with
custom_console_logger transformer. This allows logging to both the screen and file
simultaneously with consistent formatting. Console output always respects the global logger's
minimum level (typically Info), while file output uses the file logger's configured level.

The console logger is filtered to ensure Debug/lower messages never appear on console,
regardless of the file logger's level.
"""
function create_tee_logger(file_logger::logex.AbstractLogger)
    # Get the global logger's minimum level for console output (typically Info)
    console_level = Logging.min_enabled_level(logex.global_logger())

    # Create a filtered console logger that strictly enforces the console level
    # Use the more restrictive level between console and file to ensure proper filtering
    file_level = Logging.min_enabled_level(file_logger)
    effective_level = max(console_level, file_level)

    # Create console logger
    console_base = logex.ConsoleLogger(stderr, effective_level)
    console_transformed = logex.TransformerLogger(custom_console_logger, console_base)

    # Filter console to only show messages at console_level or above
    console_filtered = logex.ActiveFilteredLogger(console_transformed) do log
        log.level >= console_level
    end

    return logex.TeeLogger(console_filtered, file_logger)
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
