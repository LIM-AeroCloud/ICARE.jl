```@meta
EditURL = "https://github.com/LIM-AeroCloud/ICARE.jl/blob/master/CHANGELOG.md"
```

# Release Notes

This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The format of the release notes follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [UNRELEASED]

### Added

- Add [LoggingExtras.jl](https://github.com/JuliaLogging/LoggingExtras.jl) as dependency ([#35](https://github.com/LIM-AeroCloud/ICARE.jl/issues/35))
- New logger `PrettyFileLogger` based on `FileLogger` from
  [LoggingExtras.jl](https://github.com/JuliaLogging/LoggingExtras.jl)
  wrapping a `ConsoleLogger` instead of `SimpleLogger` ([#35](https://github.com/LIM-AeroCloud/ICARE.jl/issues/35))
  - the new logger suppresses module, file, and line information end expands the display of arrays

### Changed

- **Breaking:** Refine logging in `load_inventory` ([#35](https://github.com/LIM-AeroCloud/ICARE.jl/issues/35)). Rather than defining an additional
  logger with the second optional argument (for additional file logging), `global_logger` is
  now replaced by the logger in the second optional argument. If you want logging to console
  and file, use e.g. `TeeLogger` from
  [LoggingExtras](https://github.com/JuliaLogging/LoggingExtras.jl?tab=readme-ov-file).
  This allows logging in wrapper functions like `convert_inventory` for `convert_inventory!`.
- **Breaking:** change function names of `convert`/`convert!` to `convert_inventory[!]` to
  avoid type piracy ([#35](https://github.com/LIM-AeroCloud/ICARE.jl/issues/35))
- All API functions now accept `AbstractString` instead of the stricter `String`
- Improved Logging ([#35](https://github.com/LIM-AeroCloud/ICARE.jl/issues/35))
- Don't consider folder sizes for database size, this is too buggy and inaccurate
- Use thin spaces between size and unit to log to console and file

### Removed

- **Breaking:** Remove functions `convert`/`convert!` in favour of `convert_inventory[!]`
  to avoid type piracy ([#35](https://github.com/LIM-AeroCloud/ICARE.jl/issues/35))

## [v0.6.0](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.6.0) - 2025-12-27

### Added

- Improved error handling during download
- Methods `convert`/`convert!` for batch conversions of inventory data files separated from
  download sessions ([#16](https://github.com/LIM-AeroCloud/ICARE.jl/issues/16))
- Method `clean!` to clean the product folder recursively from any files not belonging to the
  inventory ([#16](https://github.com/LIM-AeroCloud/ICARE.jl/issues/16))
- Functions `ignore!` and `unignore!` to exclude database files in the inventory and include
  them again ([#17](https://github.com/LIM-AeroCloud/ICARE.jl/issues/17))
- Functions `attach!` and `detach!` to mark extra data exempt from `clean!` procedures ([#17](https://github.com/LIM-AeroCloud/ICARE.jl/issues/17))
- Function `list_inventory` to show a simplified folder and file tree and statistics about
  the inventory and the downloaded portion ([#17](https://github.com/LIM-AeroCloud/ICARE.jl/issues/17))
- Public method `load_inventory` to load the inventory saved in the product folder ([#32](https://github.com/LIM-AeroCloud/ICARE.jl/issues/32))

### Changed

- `sftp_download` now returns the inventory for further exploration ([#20](https://github.com/LIM-AeroCloud/ICARE.jl/issues/20))
- Refactored inventory internally to mostly use `SortedDict` instead of `OrderedDict`;
  change depencies from `OrderedCollections` to `DataStructures` ([#18](https://github.com/LIM-AeroCloud/ICARE.jl/issues/18))
- Updated inventory metadata ([#20](https://github.com/LIM-AeroCloud/ICARE.jl/issues/20))
  - **Breaking:** Added `size` and `converted size` fields to `metadata/database` with the overall
    file sizes of the original format and the size of already converted files ([#18](https://github.com/LIM-AeroCloud/ICARE.jl/issues/18))
  - Consider folders with a size of `4K` instead of `0` to estimate the maximum database size
  - **Breaking:** add a `version` number to `metadata` to allow better tracking of changes in
    the inventory ([#18](https://github.com/LIM-AeroCloud/ICARE.jl/issues/18))
  - **Breaking**: Rename `converted` field with the converted file size to `size.<ext>` in each date dict
  - Update dependencies in docs before using `make docs` ([#18](https://github.com/LIM-AeroCloud/ICARE.jl/issues/18))
  - **Breaking:** Add `"downloaded size"` entry to inventory database metadata to monitor the 
    actual downloaded part of the database ([#26](https://github.com/LIM-AeroCloud/ICARE.jl/issues/26))
- Simplify `favicon`
- Improved documentation and logging
- Rename previous method `convert!` to `_convert!` to avoid conflicts with the new method and
  leave the method internal and not part of the public API ([#16](https://github.com/LIM-AeroCloud/ICARE.jl/issues/16))
- **Breaking:** Rename `"productpath"` to `"path"` in `inventory["metadata"]["remote"]` to be more
  in line with the simpler `"local"` naming scheme ([#24](https://github.com/LIM-AeroCloud/ICARE.jl/issues/24))
- Make internal `load_inventory!` method return a reference to the modified inventory as well

### Removed

- Method `hdfupgrade` and all auxiliary code was removed and replaced by methods `convert` and `convert!`

## [v0.5.1](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.5.1) - 2025-09-07

### Fixed

- converted file sizes are only kept in the database after an update, if the original file size
  hasn't changed ([#20](https://github.com/LIM-AeroCloud/ICARE.jl/issues/20))
- Automatically update version number in the badge in the README and the link to the latest stable
  during pre-release
- Fixed an issue with the setup of the target extension that lead to errors during download sessions
  with conversions

## [v0.5.0](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.5.0) - 2025-08-31

### Added

- Use a local `.inventory.yaml` to store stats of the server-side file structure
  in the root of the product folder and reduce communication with the server
- Support of parallel downloads
- Support of file format conversions with focus on HDF4 > HDF5
- Add routines just for conversions of local downloads
- Add Documenter documentation page and this CHANGELOG (release notes)
- Add GitHub workflows for CI/CD
- Add Makefile and release-scripts for automated release processes

### Changed

- Switched from FTP to SFTP protocol for downloads
- Complete refactoring of the code, simplify download and restart routines
- Improved logging
- Reorganise downloads in a single loop
- Conversion routines are now directly included in the code and not called as script with the
  `run` command; they may be overloaded with custom routines for other conversions

## [v0.4.0](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.4.0) - 2021-08-04

### Changed

- Use `Int` to define start/end dates or periods for downloads

## [v0.3.3](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.3.3) - 2021-05-17

### Added

- New option to restart a download session by kwarg
- Set `v1.0.0` as minimum requirement for Julia

### Changed

- Better error handling

## [v0.3.2](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.3.2) - 2021-04-22

### Changed

- Update package dependencies
- Internal refactoring for changes in `CSV.read`

## [v0.3.1](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.3.1) - 2021-04-21

### Added

- Checks for product name and version number

## [v0.3.0](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.3.0) - 2020-04-14

### Added

- New option to append log files
- Ability to restart interrupted download sessions

### Changed

- Update log file format

## [v0.2.2](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.2.2) - 2020-04-07

### Added

- New flag to suppress downloads in a run

### Fixed

- Fix corrupted Project.toml

## [v0.2.1](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.2.1) - 2020-04-06

### Added

- New option `none` to remove no displaced files

## [v0.2.0](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.2.0) - 2020-04-06

### Added

- Option to warn and clean data folders of alien files

### Changed

- Revised FTP connection and download of files

## [v0.1.2](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.1.2) - 2020-04-05

### Added

- Add `Logging` as dependency

## [v0.1.1](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.1.1) - 2020-03-30

### Added

- Improved error handling
- Improved README

### Changed

- Add leading slash to caliopdir to generate absolute paths with joinpath
rather than relative paths

### Fixed

- Reconnect to ICARE and create a new FTP object for every subfolder to
prevent LibCurl error 9

## [v0.1.0](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.1.0) - 2020-03-30

### Added

- Initial download routine using [FTPClient](https://github.com/invenia/FTPClient.jl.git)


