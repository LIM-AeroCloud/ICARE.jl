using Dates


"""
    get_version() -> String

Get the release version from the release branch name.
"""
function get_version()
    # Read current branch name
    out = Pipe()
    run(pipeline(ignorestatus(`git rev-parse --abbrev-ref HEAD`), stdout=out))
    close(out.in)
    rel = @async String(read(out))
    rel = String(read(out)) |> chomp
    return rel[5:end]
end


# Parse main Project.toml
project = joinpath(@__DIR__, "..", "Project.toml")
lines = readlines(project)
# Set release version
vstring = "version = "
version = get_version()
i = findfirst(startswith(vstring), lines)
lines[i] = vstring * '"' * version * '"'
println("set version to ", version)

# Save to Project.toml
open(project, "w+") do io
    println.(io, lines)
end

# Update Changelog
changelog = joinpath(@__DIR__, "..", "CHANGELOG.md")
lines = readlines(changelog)
# Update WIP to new version
i = findfirst(isequal("## [unreleased]"), lowercase.(lines))
if isnothing(i)
    throw(ArgumentError("No unreleased version found in changelog"))
else
    lines[i] = "## [v$version] - $(Dates.today())"
    open(changelog, "w+") do io
        println.(io, lines)
    end
end
