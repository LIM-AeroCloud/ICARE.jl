using Test

# user = get(ENV, "ICARE_USER", (print("ICARE user name: "), readline()))
# password = get(ENV, "ICARE_PASSWORD", (print("ICARE password: "), readline()))

@testset "ICARE_USER secret test" begin
    icare_user = get(ENV, "ICARE_USER", nothing)
    @test !isnothing(icare_user)  # Check that ICARE_USER is set
    # You can add further tests using icare_user
    # e.g. @test icare_user == "expected_value"
end
