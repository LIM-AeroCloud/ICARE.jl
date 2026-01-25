using Logging

# Get the released version from environment variable
released_version_str = get(ENV, "RELEASED_VERSION", "")
if isempty(released_version_str)
    @error "RELEASED_VERSION environment variable is not set"
    exit(1)
end
released_version = VersionNumber(released_version_str)
@info "Released version" released_version

# Parse main Project.toml
project = joinpath(@__DIR__, "..", "Project.toml")
lines = readlines(project)

# Find version line
vstring = "version = "
i = findfirst(startswith(vstring), lines)
vstart, vend = findall(isequal('"'), lines[i])
vstart += 1
vend -= 1
@info "Current version on dev" version=lines[i][vstart:vend]

# Bump to next minor DEV version
minor = released_version.minor + 1
new_version = string(VersionNumber(released_version.major, minor, 0), "-DEV")
lines[i] = vstring * '"' * new_version * '"'
@info "Set version to next minor" new_version

# Save to Project.toml
open(project, "w+") do io
    println.(io, lines)
end
