# Parse command line argument for bump type (default: minor)
bump_type = length(ARGS) > 0 ? lowercase(ARGS[1]) : "minor"
if !(bump_type in ["minor", "major"])
    @error "BUMP_TYPE must be 'minor' or 'major', got: $bump_type" _module=nothing _file=nothing _line=nothing
    exit(1)
end

# Parse main Project.toml
project = joinpath(@__DIR__, "..", "Project.toml")
lines = readlines(project)
# Find Julia version
vstring = "version = "
i = findfirst(startswith(vstring), lines)
vstart, vend = findall(isequal('"'), lines[i])
vstart += 1
vend -= 1
println("current version: ", lines[i][vstart:vend])
version = VersionNumber(lines[i][vstart:vend])

# Set new stable version based on bump type
version = if bump_type == "major"
    major = version.major + 1
    string(VersionNumber(major, 0, 0), "-DEV")
else
    minor = version.minor + 1
    string(VersionNumber(version.major, minor, 0), "-DEV")
end
lines[i] = vstring * '"' * version * '"'
println("set version to next $bump_type: ", version)

# Save to Project.toml
open(project, "w+") do io
    println.(io, lines)
end
