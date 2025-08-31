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

# Set new stable version
minor = version.minor + 1
version = string(VersionNumber(version.major, minor, 0), "-DEV")
lines[i] = vstring * '"' * version * '"'
println("set version to ", version)

# Save to Project.toml
open(project, "w+") do io
    println.(io, lines)
end
