# Routines related to restarting a download session


"""
    init_restart(savelog::String, restart::String, dir::String=".") -> DateFrame

Check for existing download session logs (dsl files) first in `dir`, then in the
directory of `savelog`, and initiate a restart after user confirmation.
If `restart` is set to `"ask"` (default), user confirmation is through the REPL/terminal,
but can be given by `restart` (values `"y"`, `"n"` or `"l"`) to ensure an uninterrupted run.
The re-entry point of the download is based on the previous `savelog` and an existing
`dsl` file. Returns a `DataFrame` with the file names on the `remote` and `home` server.
"""
function init_restart(savelog::String, restart::String, dir::String=".")
  # Scan for download session logs
  files = [joinpath.(dir, filter(endswith(".dsl"), readdir(dir)));
    joinpath.(dirname(savelog), filter(endswith(".dsl"), readdir(dirname(savelog))))]
  # Define default dsl file
  deffile = basename(splitext(savelog)[1]*".dsl")
  # Seletct a session
  isempty(files) && return DataFrame(home = String[], remote = String[])
  session = if length(files) == 1
    files[1]
  elseif length(files) > 1
    sel = findfirst(basename.(files) .== deffile)
    if isnothing(sel)
      println("Select session to restart:\n0 — no restart")
      println.(join.(enumerate(files), " — "))
      sel = parse(Int, readline())
    end
    try files[sel]
    catch; ""
    end
  else
    ""
  end #session selection
  # Confirm actions
  session = if restart ≠ "ask"
    confirm(restart, session)
  elseif session == deffile
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
  end #confirmation
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
  end #subset selection
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
