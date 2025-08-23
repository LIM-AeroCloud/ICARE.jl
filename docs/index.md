# ICARE.jl Documentation

<div align="center">
  <img src="assets/logo.svg" alt="ICARE.jl Logo" width="400"/>
</div>

## Overview

ICARE.jl is a Julia package for retrieving atmospheric data from the AERIS/ICARE server. The package specializes in downloading CALIOP (Cloud-Aerosol Lidar and Infrared Pathfinder Satellite Observation) data files for atmospheric research.

## Key Features

- 🛰️ **Satellite Data Retrieval**: Download CALIOP aerosol and cloud data from ICARE servers
- 📊 **Automated Synchronization**: Sync local directory structure with remote ICARE data
- 🔄 **Session Recovery**: Resume interrupted downloads with session recovery capabilities
- 📝 **Comprehensive Logging**: Monitor downloads and track missing or additional files
- 🧹 **Data Management**: Optional cleanup of misplaced files in local directories

## Logo Design

The ICARE.jl logo incorporates several elements that represent the package's core functionality:

- **Atmospheric Background**: Sky blue gradient representing Earth's atmosphere
- **Satellite**: Depicts the CALIOP satellite with solar panels and communication antenna
- **LIDAR Beams**: Green laser beams representing the Light Detection and Ranging technology
- **Clouds**: Representing aerosol and cloud data that CALIOP observes
- **Earth Curvature**: Green curve at the bottom representing Earth's surface
- **Julia Colors**: Three colored dots representing the Julia programming language ecosystem
- **Data Flow**: Golden dotted lines indicating data transmission and retrieval

## Installation

```julia
julia> ]
pkg> add https://github.com/LIM-AeroCloud/ICARE.jl.git
```

## Quick Start

```julia
import ICARE

# Download CALIOP data for 2010
ICARE.ftp_download(
    "username",
    "password",
    "05kmCPro",
    2010,
    dir = "/path/to/data/CALIOP/"
)
```

For detailed usage instructions, see the main [README](../README.md).