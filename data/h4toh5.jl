function convert(file::String)::Nothing
    # Return, if file doesn't exist
    isfile(file) || return
    # Ensure, h5 file does not exist before conversion
    rm(splitext(file)[1]*".h5", force=true)
    # Chose exe for current OS and convert to h5
    bin = Sys.isapple() ? "h4toh5_mac" : "h4toh5_linux"
    converter = realpath(joinpath(@__DIR__, bin))
    run(`$converter $file`)
    return
end

convert(ARGS[1])
