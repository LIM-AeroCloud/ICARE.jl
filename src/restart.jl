# Routines related to restarting a download session

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
    downloads = CSV.read(session)
    i = isempty(lastsave) ? 1 : findfirst(lastsave .== basename.(downloads.remote)) + 1
    downloads[i:end,:]
  end
end

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
end
