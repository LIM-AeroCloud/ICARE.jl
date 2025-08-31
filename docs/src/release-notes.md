```@meta
EditURL = "https://github.com/LIM-AeroCloud/ICARE.jl/blob/master/CHANGELOG.md"
```

# Release Notes

This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The format of the release notes follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [UNRELEASED]

### Added

- Use a local `.inventory.yaml` to store stats of the server-side file structure
  in the root of the product folder and reduce communication with the server
- Support of parallel downloads
- Support of file format conversions with focus on HDF4 > HDF5
- Add routines just for conversions of local downloads
- Add Documenter documentation page and this CHANGELOG (release notes)
- Add GitHub workflows for CI/CD

### Changed

- Switched from FTP to SFTP protocol for downloads
- Complete refactoring of the code, simplify download and restart routines
- Improved logging
- Reorganise downloads in a single loop
- Conversion routines are now directly included in the code and not called as script with the
  `run` command; they may be overloaded with custom routines for other conversions

## [v0.4.0](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.4.0)

### Changed

- Use `Int` to define start/end dates or periods for downloads

## [v0.3.3](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.3.3)

### Added

- New option to restart a download session by kwarg
- Set `v1.0.0` as minimum requirement for Julia

### Changed

- Better error handling

## [v0.3.2](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.3.2)

### Changed

- Update package dependencies
- Internal refactoring for changes in `CSV.read`

## [v0.3.1](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.3.1)

### Added

- Checks for product name and version number

## [v0.3.0](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.3.0)

### Added

- New option to append log files
- Ability to restart interrupted download sessions

### Changed

- Update log file format

## [v0.2.2](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.2.2)

### Added

- New flag to suppress downloads in a run

### Fixed

- Fix corrupted Project.toml

## [v0.2.1](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.2.1)

### Added

- New option `none` to remove no displaced files

## [v0.2.0](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.2.0)

### Added

- Option to warn and clean data folders of alien files

### Changed

- Revised FTP connection and download of files

## [v0.1.2](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.1.2)

### Added

- Add `Logging` as dependency

## [v0.1.1](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.1.1)

### Added

- Improved error handling
- Improved README

### Changed

- Add leading slash to caliopdir to generate absolute paths with joinpath
rather than relative paths

### Fixed

- Reconnect to ICARE and create a new FTP object for every subfolder to
prevent LibCurl error 9

## [v0.1.0](https://github.com/LIM-AeroCloud/ICARE.jl/releases/tag/v0.1.0)

### Added

- Initial download routine using [FTPClient](https://github.com/invenia/FTPClient.jl.git)
