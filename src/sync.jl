## Routines related to syncing local and remote directories

"""
    clean(root::String=".")
    clean(inventory::SortedDict{String, Any})

Cleans a product folder recursively from all content not listed in the inventory, i.e. not
available on the ICARE server. The function has to methods, you can either provide an
`AbstractString` with the path of the product folder or the inventory as `SortedDict` of the
product.
"""
function clean end

function clean(root::AbstractString=".")::Nothing
    # Load the inventory from the yaml in the given root
    path = joinpath(root, ".inventory.yaml") |> realpath
    inventory = SortedDict{String, Any}()
    load_inventory!(inventory, path)
    # Call the clean method for the inventory
    clean(inventory)
end

function clean(inventory::SortedDict{String, Any})::Nothing
    # Rearrange inventory for better processing
    database = inventory_dates(inventory)
    # Scan inventory for additional files and folders
    root = inventory["metadata"]["local"]["path"]
    extras = localscan(database, root)
    # Clean up local database
    if confirm(extras)
        rm.(extras.files, force=true)
        rm.(extras.folders, recursive=true, force=true)
    else
        @info "aborting cleanup"
    end
    return
end


"""
    inventory_dates(inventory::SortedDict{String, Any}) -> @NamedTuple{folders::Set{String},files::Set{String}}

Rearrange the `inventory` for better processing as a named tuples with sets of absolute file and
folder paths.
"""
function inventory_dates(inventory::SortedDict{String, Any})::@NamedTuple{folders::Set{String},files::Set{String}}
    # Init
    folders, files = Set{String}(), Set{String}()
    root = inventory["metadata"]["local"]["path"]
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
            push!(files, joinpath(dfolder, file*inventory["metadata"]["file"]["ext"]))
        end
    end
    # Define converted/upgraded files of the inventory
    union!(files, replace.(files, inventory["metadata"]["file"]["ext"] => inventory["metadata"]["file"]["newext"]))
    # Return inventory in a revised format
    return (;folders, files)
end


"""
    localscan(
        database::@NamedTuple{folders::Set{String},files::Set{String}}, root::String="."
    ) -> @NamedTuple{folders::Set{String},files::Set{String}}

Scan the local directory recursively and identify files and folders not present in the database.
"""
function localscan(
    database::@NamedTuple{folders::Set{String},files::Set{String}}, root::String="."
)::@NamedTuple{folders::Set{String},files::Set{String}}
    # Setup
    root = realpath(root)
    extras = (folders = Set{String}(), files = Set{String}())
    # Get files and folders within root recursively
    _localscan!(database, extras, root)
    return extras
end


"""
    _localscan!(
        database::@NamedTuple{folders::Set{String},files::Set{String}},
        extras::@NamedTuple{folders::Set{String},files::Set{String}},
        root::String="."
    )

Recursive helper function for `localscan`. This allows a simpler API for `localscan`, where
`database` does not have to be defined outside the function.
"""
function _localscan!(
    database::@NamedTuple{folders::Set{String},files::Set{String}},
    extras::@NamedTuple{folders::Set{String},files::Set{String}},
    root::String="."
)::Nothing
    # Get files and folders in root
    content = readdir(root, join=true)
    files = filter(isfile, content)
    folders = filter(isdir, content)
    # Save extra files and folders
    [push!(extras.folders, f) for f in setdiff(folders, database.folders)]
    [push!(extras.files, f) for f in setdiff(files, database.files)]
    # Search recursively in database folders
    [_localscan!(database, extras, i) for i in intersect(folders, database.folders)]
    return
end


"""
    confirm(extras::@NamedTuple{folders::Set{String},files::Set{String}}) -> Bool

Prompt the user to confirm the deletion of files and folders listed in `extras`.
Returns `true`, if the user confirmed with `"yes"`, `false` otherwise.
"""
function confirm(extras::@NamedTuple{folders::Set{String},files::Set{String}})::Bool
    # Nothing to clean
    isempty(extras.folders) && isempty(extras.files) && return true
    # Initial warning
    @warn("The following paths are not part of the inventory and will be removed.",
        _module=nothing, _file=nothing, _line=nothing)
    # List folders
    if !isempty(extras.folders)
        printstyled("Folders:\n", color=:yellow, bold=true)
        print("- ")
        println.(join(extras.folders |> collect |> sort, "\n- "))
    end
    # List files
    if !isempty(extras.files)
        printstyled("Files:\n", color=:yellow, bold=true)
        print("- ")
        println.(join(extras.files |> collect |> sort, "\n- "))
    end
    # File prompt for confirmation
    printstyled("Proceed (yes/no)? ", color=:yellow, bold=true)
    proceed = readline()
    # Return user decision
    return startswith(lowercase(proceed), "y")
end
