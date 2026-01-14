# pvwattsOlmoSkoplaki

[![License: GPL-3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

An R package implementing a solar PV power forecasting pipeline with Olmo transposition, Skoplaki cell temperature models (two variants), PVWatts DC output, and simple AC inverter clipping. Defaults are based on the Trina TSM-PC05 (230W) module and the De Aar solar plant in South Africa.

**Note:** This package is not intended for CRAN submission and is maintained as a GitHub-only package.

## Features

- **Olmo Transposition Model**: Converts global horizontal irradiance (GHI) to plane-of-array (POA) irradiance
- **Skoplaki Cell Temperature Models**: Two variants for calculating PV cell temperature
  - Linear model: `T_cell = T_air + (G_poa/1000) * (a + b * wind)`
  - Ratio model: `T_cell = T_air + G_poa / (u0 + u1 * wind)`
- **PVWatts DC Power Model**: Calculates DC power output with temperature correction
- **AC Inverter Clipping**: Simple inverter efficiency and power clipping model
- **Solar Position Calculations**: Internal implementation of solar position algorithms (from the archived insol package)

## Installation

You can install the development version of pvwattsOlmoSkoplaki from GitHub:

```r
# install.packages("devtools")
devtools::install_github("yourusername/pvwattsOlmoSkoplaki", build_vignettes = TRUE)
```

## Quick Start

```r
library(pvwattsOlmoSkoplaki)

# Site parameters (De Aar, South Africa)
lat <- -30.6279
lon <- 24.0054
tilt <- 20  # degrees
azimuth <- 0  # degrees (north)

# Example weather data
time <- seq(as.POSIXct("2026-01-01 06:00", tz = "UTC"),
            by = "hour", length.out = 12)
GHI <- c(50, 150, 350, 550, 700, 800, 850, 800, 700, 550, 350, 150)
T_air <- c(20, 22, 25, 28, 30, 32, 33, 32, 30, 28, 25, 23)
wind <- c(2, 2.5, 3, 3.5, 4, 4, 3.5, 3, 2.5, 2, 2, 2)

# Calculate DC power for a single 230W module
dc_out <- pv_dc_olmo_skoplaki_pvwatts(
  time = time,
  lat = lat,
  lon = lon,
  GHI = GHI,
  T_air = T_air,
  wind = wind,
  tilt = tilt,
  azimuth = azimuth,
  P_dc0 = 230,  # Nameplate DC power (W)
  skoplaki_variant = "linear"
)

head(dc_out)

# For a complete plant (44,880 modules = 10.32 MW)
P_dc0_plant <- 44880 * 230  # 10,322,400 W

dc_plant <- pv_dc_olmo_skoplaki_pvwatts(
  time = time,
  lat = lat,
  lon = lon,
  GHI = GHI,
  T_air = T_air,
  wind = wind,
  tilt = tilt,
  azimuth = azimuth,
  P_dc0 = P_dc0_plant
)

# Add AC output with inverter clipping
ac_out <- pv_ac_simple_clipping(
  P_dc = dc_plant$P_dc,
  n_inverters = 20,
  inverter_kw = 500,
  eta_inv = 0.97
)

dc_plant$P_ac <- ac_out$P_ac
dc_plant$clipped <- ac_out$clipped

head(dc_plant)
```

## Function Reference

### `pv_dc_olmo_skoplaki_pvwatts()`

Main DC power pipeline combining Olmo transposition, Skoplaki cell temperature, and PVWatts model.

**Key Parameters:**
- `time`: POSIXct vector of times (UTC recommended)
- `lat`, `lon`: Site coordinates in degrees
- `GHI`: Global horizontal irradiance (W/m²)
- `T_air`: Ambient air temperature (°C)
- `wind`: Wind speed (m/s)
- `tilt`: Panel tilt angle (degrees)
- `azimuth`: Panel azimuth (degrees, 0 = north)
- `P_dc0`: DC nameplate power (W, default 230)
- `gamma`: Temperature coefficient (1/K, default -0.0043)
- `skoplaki_variant`: "linear" or "ratio" (default "linear")

**Returns:** Data frame with POA irradiance, cell temperature, DC power, and solar position

### `pv_ac_simple_clipping()`

Applies inverter efficiency and power clipping to convert DC to AC power.

**Key Parameters:**
- `P_dc`: DC power (W)
- `n_inverters`: Number of inverters (default 20)
- `inverter_kw`: kW rating per inverter (default 500)
- `eta_inv`: Inverter efficiency (default 0.97)

**Returns:** List with AC power, clipping flags, and rated AC power

## Vignette

For a complete example using the De Aar solar plant, see the vignette:

```r
vignette("de_aar", package = "pvwattsOlmoSkoplaki")
```

## Default Parameters

The package includes sensible defaults based on:

- **PV Module**: Trina TSM-PC05 (230W polycrystalline)
  - Temperature coefficient: -0.0043 /K

- **Skoplaki Linear Model** (default):
  - a = 28
  - b = -1

- **Skoplaki Ratio Model**:
  - u0 = 25
  - u1 = 6

- **Inverter**:
  - Efficiency: 97%
  - Configuration: 20 inverters × 500 kW

## Attribution

This package incorporates solar position calculation functions from the **insol** package (version 1.2.2) by Javier G. Corripio, which was removed from CRAN. These functions are used under the GPL-2 license.

**Reference for insol functions:**
> Corripio, J. G. (2003). Vectorial algebra algorithms for calculating terrain parameters from DEMs and the position of the sun for solar radiation modelling in mountainous terrain. *International Journal of Geographical Information Science*, 17(1), 1-23.

## License

GPL-3 (compatible with the GPL-2 licensed insol functions)

## Author

**Stéfan Janse van Rensburg**
Email: stefanj@mandela.ac.za
ORCID: [0000-0002-0749-2277](https://orcid.org/0000-0002-0749-2277)

## References

- Olmo transposition model
- Skoplaki cell temperature models
- PVWatts methodology
- Corripio, J. G. (2003). Solar position algorithms from insol package

## Contributing

Contributions, bug reports, and feature requests are welcome! Please open an issue or submit a pull request.

## Citation

If you use this package in your research, please cite:

```r
citation("pvwattsOlmoSkoplaki")
```
