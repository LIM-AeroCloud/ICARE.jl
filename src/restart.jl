# Routines related to restarting a download session


"""
    init_restart(savelog::String) -> DateFrame

Check for existing download session logs (dsl files), and initiate a restart
after user confirmation. The re-entry point of the download is based on the previous
`savelog`. Returns a `DataFrame` with the file names on the `remote` and `home`
server.
"""
function init_restart(savelog::String)
  # Scan for download session logs and select a session
  dir = isempty(dirname(savelog)) ? "." : dirname(savelog)
  files = joinpath.(dir, readdir(dir)[endswith.(readdir(dir), ".dsl")])
  isempty(files) && return DataFrame(home = String[], remote = String[])
  session = if length(files) == 1
    files[1]
  elseif length(files) > 1
    println("Select session to restart:\n0 — no restart")
    println.(join.(enumerate(files), " — "))
    sel = parse(Int, readline())
    try files[sel]
    catch; ""
    end
  else
    ""
  end
  # Confirm actions
  session = if splitext(basename(session))[1] == splitext(basename(savelog))[1]
    println("Resume last download session (y/n)?")
    println("- 'y' resume old download session, abort new download")
    println("- 'n' delete old download session log, continue current session")
    confirm(readline(), session)
  elseif !isempty(session)
    println("Unfinished download session detected. Resume? (y/n/l)")
    println("- 'y' resume old download session, abort new download")
    println("- 'n' delete old download session log, continue current session")
    println("- 'l' keep old download session log for later use, continue current session")
    confirm(readline(), session, true)
  end
  # Select subset of remaining files to download
  if isempty(session)
    DataFrame(home = String[], remote = String[])
  else
    lastsave = try
      open(splitext(session)[1]*".log") do f
        readlines(f)[end-1]
      end
    catch; ""
    end
    downloads = CSV.read(session, DataFrame)
    i = isempty(lastsave) ? 1 : findfirst(lastsave .== basename.(downloads.remote)) + 1
    downloads[i:end,:]
  end
end #function init_restart


"""
    confirm(answer::String, session::String, later::Bool=false) -> String

Based on the user input `answer`, return either the file name of the previous
`session` or an empty `String` and remove the previous download session log,
if `answer` was no (`"n"`). If `later` is set to `true`, `"l"` is allowed as
user input, which is like no, but without removing the `dsl` file.
"""
function confirm(answer::String, session::String, later::Bool=false)
  if startswith(lowercase(answer), "y")
    session
  elseif startswith(lowercase(answer), "n")
    rm(session, force = true)
    @info "previous download session log deleted"
    ""
  elseif later
    ""
  else
    print("Please select 'y', 'n' (or 'l' if later is allowed): ")
    confirm(readline(), session, later)
  end
end #function confirm
