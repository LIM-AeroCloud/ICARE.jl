## Types

"""
struct Counter
==============

Stores a counter for `downloads`, `conversions`, and `skipped` data files
as well as `failed` downloads.
By default, all counter parts are initialised with zero, but can be adjusted
by positional or individually by keyword arguments during instantiation.
"""
mutable struct Counter
    downloads::Int
    conversions::Int
    skipped::Int
    failed::Int
end


"""
struct File
===========

Stores relevant data about file name, extension, and paths on the local and remote system.
"""
struct File
    name::String
    ext::String
    date::Date
    location::@NamedTuple{
        target::String,
        download::String,
        remote::String
    }
    dir::@NamedTuple{
        dst::String,
        src::String
    }
end

Base.show(io::IO, file::File)::Nothing = print(io, "File($(file.name)$(file.ext))")


#* Exceptions

"""
ConnectionError
===============

Thrown with a message as parameter, when no connection to the server can be established.
"""
struct ConnectionError <: Exception
    msg::String
end

Base.show(io::IO, error::ConnectionError)::Nothing = println(io, "ConnectionError: $(error.msg)")


#* External constructors

"""
    Counter(;downloads::Int=0, conversions::Int=0, skipped::Int=0, failed::Int=0) -> Counter

Constructor for `Counter` with default init values `0` for all sub-counters.
Other values can be initialised with keyword arguments for the respective sub-counter.
"""
Counter(;downloads::Int=0, conversions::Int=0, skipped::Int=0, failed::Int=0)::Counter = Counter(downloads,conversions,skipped,failed)


"""
    File(
        icare::SFTP.Client,
        inventory::OrderedDict,
        date::Date,
        name::String,
    ) -> File

Constructor for a `File` struct with fields for  the file `name`, `ext`ension, `location`
(including `target`, `download`, and `remote` location) and `dir`ectory (`dst` and `src`);
`location` includes the file name, `dir` does not.
"""
function File(
    icare::SFTP.Client,
    inventory::OrderedDict,
    date::Date,
    name::String
)::File
    datadir = Dates.format.(date, ["yyyy", "yyyy_mm_dd"])
    path = mkpath(joinpath(inventory["metadata"]["local"]["path"], datadir...))
    ext = inventory["metadata"]["file"]["ext"]
    download = joinpath(path, name*ext)
    newext = Base.invokelatest(CONVERTER[].newext)
    newext = isempty(newext) ? ext : newext
    target = splitext(download)[1]*newext
    remote = joinpath(icare.uri, datadir..., name*ext).path
    File(name, ext, date, (;target, download, remote), (dst=path, src=joinpath(icare.uri, datadir...).path))
end
