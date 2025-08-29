"""
    convert_file(input::String, output::String)

Convert the `input` to the `output` format.
Both `input` and `output` can be absolute or relative paths.
"""
function convert_file(input::String, output::String)::Nothing
    # Return, if input file doesn't exist
    isfile(input) || return
    # Ensure, h5 file does not exist before conversion
    rm(splitext(input)[1]*".h5", force=true)
    # Chose exe for current OS and convert to h5
    bin = Sys.isapple() ? "h4toh5_mac" : "h4toh5_linux"
    converter = realpath(joinpath(@__DIR__, bin))
    run(`$converter $input $output`)
    return
end


"""
    newext() -> String

Return the extension of the converted file format.
"""
newext()::String = ".h5"
