using Test, ICARE

# Get user credentials as secrets
user = get(ENV, "ICARE_USER", nothing)
password = get(ENV, "ICARE_PASSWORD", nothing)

if isnothing(user) || isnothing(password)
    @error "Either ICARE_USER or ICARE_PASSWORD not set as environment variable; test aborted"
    exit(1)
else
    user = ICARE.SFTP.URIs.unescapeuri(user)
    password = ICARE.SFTP.URIs.unescapeuri(password)
end

# Run tests
@testset "ICARE_USER secret test" begin
    mktempdir() do root
        @show root
        cp("data/05kmCPro.v4.51/", joinpath(root, "05kmCPro.v4.51/"), force=true)
        ICARE.sftp_download(user, password, "05kmCPro", 20060612, localroot = root, convert=false)
        ICARE.sftp_download(user, password, "05kmCPro", 20060612, localroot = root)
        @test all(isfile.(joinpath.(root, "05kmCPro.v4.51", "2006", "2006_06_12",
            "CAL_LID_L2_05kmCPro-Standard-V4-51.2006-06-12T00-53-43ZN".*[".hdf", ".h5"])))
    end
end
