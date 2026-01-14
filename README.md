# pvwattsOlmoSkoplaki

[![License: GPL-3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

An R package implementing a solar PV power forecasting pipeline with Olmo transposition, Skoplaki cell temperature models (two variants), PVWatts DC output, and simple AC inverter clipping. Defaults are based on the Trina TSM-PC05 (230W) module and the De Aar solar plant in South Africa.

**Note:** This package is not intended for CRAN submission and is maintained as a GitHub-only package.

## Public Data Notice

The parameters and specifications for the Mulilo De Aar PV plant used in this package are **assumed values** based on information documented at the [HAWI Knowledge Database](https://hawiknowledge.org/solar_power_stations_2.html#DeAarMulilo). These assumed parameters were compiled by HAWI from publicly available documents in the public domain, including Environmental Impact Assessment (EIA) submissions and similar regulatory filings.

## Features

- **Olmo et al. Transposition Model**: Converts global horizontal irradiance (GHI) to plane-of-array (POA) irradiance using the clearness index method (Olmo et al., 1999). Unlike traditional models, this approach does not require decomposition into direct and diffuse components.
- **Skoplaki Cell Temperature Models**: Two variants for calculating PV cell temperature based on NOCT (Nominal Operating Cell Temperature)
  - Model 1: Uses wind convection coefficient `h_w = 8.91 + 2.00*v_f`
  - Model 2: Uses wind convection coefficient `h_w = 5.7 + 3.8*v_w` where `v_w = 0.68*v_f - 0.5`
  - Both models use Equation 41 from Ayvazoğluyüksel & Başaran Filik (2018)
- **PVWatts DC Power Model**: Calculates DC power output with temperature correction
- **AC Inverter Clipping**: Simple inverter efficiency and power clipping model
- **Solar Position Calculations**: Internal implementation of solar position algorithms (from the archived insol package)

## Installation

You can install the development version of pvwattsOlmoSkoplaki from GitHub:

```r
# install.packages("devtools")
devtools::install_github("sjvrensburg/pvwattsOlmoSkoplaki", build_vignettes = TRUE)
```

## Quick Start

### Complete Pipeline (DC + AC)

The convenience function `pv_power_pipeline()` calculates both DC and AC power in a single call:

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

# Calculate DC and AC power for complete plant (44,880 modules = 10.32 MW)
result <- pv_power_pipeline(
  time = time,
  lat = lat,
  lon = lon,
  GHI = GHI,
  T_air = T_air,
  wind = wind,
  tilt = tilt,
  azimuth = azimuth,
  P_dc0 = 44880 * 230,  # Total DC capacity (W)
  n_inverters = 20,
  inverter_kw = 500,
  eta_inv = 0.97
)

head(result)
```

### Separate DC and AC Calculations

Alternatively, you can call the DC and AC functions separately for more control:

```r
# Calculate DC power only
dc_out <- pv_dc_olmo_skoplaki_pvwatts(
  time = time,
  lat = lat,
  lon = lon,
  GHI = GHI,
  T_air = T_air,
  wind = wind,
  tilt = tilt,
  azimuth = azimuth,
  P_dc0 = 44880 * 230,
  skoplaki_variant = "model1"
)

# Add AC power conversion
ac_out <- pv_ac_simple_clipping(
  P_dc = dc_out$P_dc,
  n_inverters = 20,
  inverter_kw = 500,
  eta_inv = 0.97
)

dc_out$P_ac <- ac_out$P_ac
dc_out$clipped <- ac_out$clipped

head(dc_out)
```

## Function Reference

### Individual Model Functions

These functions implement individual models and can be used independently for maximum flexibility:

#### `olmo_transposition()`

Converts GHI to POA irradiance using the Olmo et al. (1999) clearness index method.

```r
olmo_transposition(time, lat, lon, GHI, tilt, azimuth, albedo = 0.2)
```

**Returns:** Data frame with G_poa, zenith, sun_azimuth, incidence, k_t, I_0

#### `skoplaki_cell_temperature()`

Estimates cell temperature using the Skoplaki model (Equation 41).

```r
skoplaki_cell_temperature(G_poa, T_air, wind, variant = "model1", ...)
```

**Returns:** Numeric vector of cell temperatures (°C)

#### `pvwatts_dc()`

Calculates DC power using the PVWatts model with temperature correction.

```r
pvwatts_dc(G_poa, T_cell, P_dc0 = 230, gamma = -0.0043)
```

**Returns:** Numeric vector of DC power (W)

#### `pv_ac_simple_clipping()`

Applies inverter efficiency and power clipping to convert DC to AC power.

```r
pv_ac_simple_clipping(P_dc, n_inverters = 20, inverter_kw = 500, eta_inv = 0.97)
```

**Returns:** List with P_ac, clipped flag, and P_ac_rated

### Convenience Pipeline Functions

These functions chain multiple models together for common workflows:

#### `pv_dc_olmo_skoplaki_pvwatts()`

DC power pipeline combining Olmo transposition → Skoplaki cell temperature → PVWatts DC.

```r
pv_dc_olmo_skoplaki_pvwatts(time, lat, lon, GHI, T_air, wind, tilt, azimuth, ...)
```

**Returns:** Data frame with G_poa, T_cell, P_dc, and solar position data

#### `pv_power_pipeline()`

Complete pipeline (DC + AC) combining all four models. **Recommended for most users.**

```r
pv_power_pipeline(time, lat, lon, GHI, T_air, wind, tilt, azimuth,
                  P_dc0 = 230, n_inverters = 20, inverter_kw = 500, ...)
```

**Returns:** Data frame with G_poa, T_cell, P_dc, P_ac, clipped flag, and solar position

## Vignette

For a complete example using the De Aar solar plant, see the vignette:

```r
vignette("de_aar", package = "pvwattsOlmoSkoplaki")
```

## Default Parameters

The package includes sensible defaults based on:

- **PV Module**: Trina TSM-PC05 (230W polycrystalline)
  - Nameplate power: 230 W
  - Temperature coefficient: -0.0043 /K (-0.43%/K)
  - Efficiency at STC: 14.1%
  - NOCT: 45°C

- **NOCT Conditions** (standard):
  - Ambient temperature: 20°C
  - Irradiance: 800 W/m²
  - Wind speed: 1 m/s

- **Skoplaki Cell Temperature Models**:
  - Model 1 (default): h_w = 8.91 + 2.00*v_f
  - Model 2: h_w = 5.7 + 3.8*v_w
  - τα (tau_alpha): 0.9

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

## AI Use Declaration

This package was developed with assistance from Claude (Anthropic), an AI assistant. Claude was used for:

- Implementing the Olmo et al. (1999) transposition model equations from the source paper
- Implementing the Skoplaki cell temperature model (Equation 41) with both wind coefficient variants
- Refactoring code into modular functions
- Writing documentation and roxygen2 comments
- Drafting the vignette and README content

All AI-generated code and documentation was reviewed, validated against the original published equations, and approved by the package author.

## References

- **Ayvazoğluyüksel, Ö., & Başaran Filik, Ü. (2018).** Estimation methods of global solar radiation, cell temperature and solar power forecasting: A review and case study in Eskişehir. *Renewable and Sustainable Energy Reviews*, 91, 639-653. [https://doi.org/10.1016/j.rser.2018.03.084](https://doi.org/10.1016/j.rser.2018.03.084)

- **Corripio, J. G. (2003).** Vectorial algebra algorithms for calculating terrain parameters from DEMs and the position of the sun for solar radiation modelling in mountainous terrain. *International Journal of Geographical Information Science*, 17(1), 1-23.

- **Olmo, F. J., Vida, J., Foyo, I., Castro-Diez, Y., & Alados-Arboledas, L. (1999).** Prediction of global irradiance on inclined surfaces from horizontal global irradiance. *Energy*, 24(8), 689-704. [https://doi.org/10.1016/S0360-5442(99)00025-0](https://doi.org/10.1016/S0360-5442(99)00025-0)

- **Skoplaki, E., Boudouvis, A. G., & Palyvos, J. A. (2008).** A simple correlation for the operating temperature of photovoltaic modules of arbitrary mounting. *Solar Energy Materials and Solar Cells*, 92(11), 1393-1402. [https://doi.org/10.1016/j.solmat.2008.05.016](https://doi.org/10.1016/j.solmat.2008.05.016)

## Contributing

Contributions, bug reports, and feature requests are welcome! Please open an issue or submit a pull request.

## Citation

If you use this package in your research, please cite:

```r
citation("pvwattsOlmoSkoplaki")
```
