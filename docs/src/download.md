# Downloading from the ICARE server

## Synchronising folder structure

_ICARE.jl_ is meant for data that is arranged by years and dates with the following structure:

    <root>/<product folder>/yyyy/yyyy_mm_dd

This folder structure is synchronised with the local system and data files are downloaded to
the date folders at the lowest level. To minimize server communication and speed up download
processes, a local `.inventory.yaml` file (hidden on Linux and MacOs) is created in the product
folder. The `.inventory.yaml` contains information about the folder structure and file stats
and should not be edited or deleted. The inventory is created before the first download of a
given product. This process takes several minutes up to hours in extreme cases. After the initial
setup, only dates outside the known date range are updated, which is much faster, unless a
complete resynchronisation is forced.

!!! warning "Important Notice"
    Don't edit or delete the `.inventory.yaml` file in each main product folder unless you know
    what you are doing! The creation or resynchronisation of the inventory takes several minutes
    or up to hours in extreme cases.

## Downloading data files

## Converting data files
