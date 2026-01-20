using Dates, Logging

## Helper functions

"""
    get_version() -> String

Get the release version from the release branch name.
"""
function get_version()::VersionNumber
    # Read current branch name
    out = Pipe()
    run(pipeline(ignorestatus(`git rev-parse --abbrev-ref HEAD`), stdout=out))
    close(out.in)
    rel = @async String(read(out))
    rel = String(read(out)) |> chomp
    return VersionNumber(rel[5:end])
end


"""
    check_update(v_old::VersionNumber, v_new::VersionNumber, type::AbstractString)

Check whether the version update from `v_old` to `v_new` is valid for the given `type`
and inform with console logs.
"""
function check_update(v_old::VersionNumber, v_new::VersionNumber, type::AbstractString)::Nothing
    if v_old.major == v_new.major && v_old.minor == v_new.minor && v_new.patch == v_old.patch
        if v_old.prerelease != v_new.prerelease
            msg = isempty(v_new.prerelease) ?
                "setting $type prerelease to stable from v$v_old to v$v_new" :
                "$type prerelease update from v$v_old to v$v_new"
            @info msg
        elseif v_old.build != v_new.build
            @info "$type release with new build metadata" v_old v_new
        else
            level = type == "inventory" ? Logging.Info : Logging.Warn
            @logmsg level "no $type version update" v_old
        end
    elseif v_new.major == v_old.major + 1 && v_new.minor == 0 && v_new.patch == 0
        @info "major $type update from v$v_old to v$v_new"
    elseif v_new.major == v_old.major && v_new.minor == v_old.minor + 1 && v_new.patch == 0
        @info "minor $type update from v$v_old to v$v_new"
    elseif v_new.major == v_old.major && v_new.minor == v_old.minor && v_new.patch == v_old.patch + 1
        @info "patch $type update from v$v_old to v$v_new"
    else
        @warn "invalid $type version update from v$v_old to v$v_new"
    end
end


## Update package version
# Parse main Project.toml
project = joinpath(@__DIR__, "..", "Project.toml")
lines = readlines(project)
# Set release version
vstring = "version = "
v_new = get_version()
i = findfirst(startswith(vstring), lines)
m = match(r"\"(?<version>[^\"]+)\"", lines[i])
v_old = VersionNumber(m["version"])
lines[i] = vstring * "\"$(v_new)\""
check_update(v_old, v_new, "package")

# Save to Project.toml
open(project, "w+") do io
    println.(io, lines)
end

## Update Changelog
changelog = joinpath(@__DIR__, "..", "CHANGELOG.md")
lines = readlines(changelog)
# Update WIP to new version
i = findfirst(isequal("## [unreleased]"), lowercase.(lines))
if isnothing(i)
    throw(ArgumentError("No unreleased version found in changelog"))
end
lines[i] = "## [v$v_new] - $(Dates.today())"
open(changelog, "w+") do io
    println.(io, lines)
end

## Update version badge
badge = joinpath(@__DIR__, "..", "docs", "src", "assets", "badge.svg")
lines = readlines(badge)
i = findfirst(contains(r"<text.*>v"), lines)
if isnothing(i)
    throw(ArgumentError("No version in badge found in docs/src/assets/badge.svg"))
end
lines[i] = replace(lines[i], r">v[0-9.]+" => ">v$v_new")
open(badge, "w+") do io
    println.(io, lines)
end

## Update link to stable version in README
readme = joinpath(@__DIR__, "..", "README.md")
lines = readlines(readme)
i = findfirst(contains("/v"), lines)
if isnothing(i)
    throw(ArgumentError("No version link found in README.md"))
end
lines[i] = replace(lines[i], r"/v[0-9.]+" => "/v$v_new")
open(readme, "w+") do io
    println.(io, lines)
end

## Update inventory changelog
# Read docs with inventory changelog
changelog = normpath(@__DIR__, "..", "docs", "src", "inventory.md")
lines = readlines(changelog)
start = findfirst(contains("## Inventory Changelog"), lines)

# Find current inventory version in source code
src = normpath(@__DIR__, "..", "src", "inventory.jl")
code = read(src, String)
m = match(r"\"version\"\s*=>\s*v\"(?<version>[0-9]+\.[0-9]+\.[0-9]+)\"", code)
v_new = VersionNumber(m["version"])

# Loop over inventory changelog, set new version and add links to issues
versions = VersionNumber[]
for i = start:length(lines)
    line = lines[i]
    # Set new version
    if occursin(r"\[unreleased\]"i, line)
        lines[i] = "### [v$v_new] - $(Dates.today())"
    end
    # Add links to issues
    for m in eachmatch(r"(?<!\])\[\#(?<id>[0-9]+)\](?![\[\(])", line)
        lines[i] = replace(lines[i], m.match =>
            "$(m.match)(https://github.com/LIM-AeroCloud/ICARE.jl/issues/$(m["id"]))")
    end
    # Find older versions
    for m in eachmatch(r"(?<!\])\[v(?<major>[0-9]+)\.(?<minor>[0-9]+)\.(?<patch>[0-9]+)\](?![\[\(])", line)
        push!(versions, VersionNumber("$(m["major"]).$(m["minor"]).$(m["patch"])"))
    end
end

# Check version update for consistency
v_old = isempty(versions) ? VersionNumber(0,0,0) : sort(versions)[end]
check_update(v_old, v_new, "inventory")

# Save updated documentation
open(changelog, "w+") do io
    println.(io, lines)
end
