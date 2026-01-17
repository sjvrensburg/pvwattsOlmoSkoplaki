# pvflux

[![License: GPL-3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

An R package implementing a solar PV power forecasting pipeline with multiple transposition and cell temperature models, PVWatts DC output, and simple AC inverter clipping. Defaults are based on the Trina TSM-PC05 (230W) module and the De Aar solar plant in South Africa.

**Note:** This package is not intended for CRAN submission and is maintained as a GitHub-only package.

## Public Data Notice

The parameters and specifications for the Mulilo De Aar PV plant used in this package are **assumed values** based on information documented at the [HAWI Knowledge Database](https://hawiknowledge.org/solar_power_stations_2.html#DeAarMulilo). These assumed parameters were compiled by HAWI from publicly available documents, including Environmental Impact Assessment (EIA) submissions and similar regulatory filings.

## Features

### Transposition Models
- **Hay-Davies Model** (default): Anisotropic sky model using decomposition (GHI→DNI/DHI) then Hay-Davies transposition
- **Reindl Model**: Anisotropic sky model with circumsolar and horizon brightening components
- **Perez Model**: Anisotropic sky model using 8-bin classification system for sky conditions
- **Olmo et al. Model**: Converts GHI to POA using clearness index method without decomposition (Olmo et al., 1999)

**Note:** The Olmo model was calibrated for Granada, Spain and has been shown to produce
significant errors (RMSE of 21-52%) at other locations. The Hay-Davies model is recommended
for most applications. See `?olmo_transposition` for details.

### Decomposition Models
- **Erbs Model** (default): Piecewise polynomial diffuse fraction model (Erbs et al., 1982)
- **Boland-Ridley Model**: Logistic function diffuse fraction model (Boland et al., 2001)

**Note:** Decomposition models are only used when transposition_model is not "olmo".

### Cell Temperature Models
- **Skoplaki Model**: Two variants based on NOCT with different wind convection coefficients
  - Model 1: `h_w = 8.91 + 2.00*v_f`
  - Model 2: `h_w = 5.7 + 3.8*v_w` where `v_w = 0.68*v_f - 0.5`
- **Faiman Model**: Simple empirical model adopted in IEC 61853 standards

### Clear-Sky Models
- **Ineichen-Perez Clear-Sky Model** (default): Estimates clear-sky irradiance (GHI, DNI, DHI) based on:
  - Solar zenith angle
  - Linke turbidity coefficient (supports automatic database lookup)
  - Altitude-based atmospheric corrections
  - Optional Perez enhancement factor
- **Haurwitz Clear-Sky Model**: Simple model requiring only solar position
  - No turbidity or altitude parameters needed
  - Suitable for quick estimates when atmospheric data is unavailable
- **Clear-Sky Model Selection**: Choose between models via `clearsky_model` parameter
- **Clear-Sky Pipelines**: Complete DC and AC power estimation under clear-sky conditions
- **Performance Metrics**: Clear-sky index (CSI) and performance ratio calculations
- **Solar Elevation Filtering**: `filter_solar_elevation()` filters time series by sun height above horizon

### Additional Features
- **Incidence Angle Modifier (IAM)**: Optional optical loss correction using power-law model
- **PVWatts DC Power Model**: Calculates DC power with temperature correction
- **AC Inverter Clipping**: Simple inverter efficiency and power clipping model
- **Ensemble Analysis**: Run all 8 transposition × cell temperature model combinations
- **Solar Position Calculations**: Internal implementation from the insol package

## Installation

You can install the development version of pvflux from GitHub:

```r
# install.packages("devtools")
devtools::install_github("sjvrensburg/pvflux", build_vignettes = TRUE)
```

## Quick Start

### Complete Pipeline (DC + AC) with Default Models

The convenience function `pv_power_pipeline()` calculates both DC and AC power using Hay-Davies transposition and Skoplaki cell temperature (default):

```r
library(pvflux)

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

# Calculate DC and AC power for complete plant
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
  inverter_kw = 500
)

head(result)
```

### Using Alternative Models

Select any combination of transposition and cell temperature models:

```r
# Olmo transposition + Skoplaki cell temperature
result_alt <- pv_power_pipeline(
  transposition_model = "olmo",
  cell_temp_model = "skoplaki",
  time = time,
  lat = lat,
  lon = lon,
  GHI = GHI,
  T_air = T_air,
  wind = wind,
  tilt = tilt,
  azimuth = azimuth,
  P_dc0 = 44880 * 230,
  n_inverters = 20,
  inverter_kw = 500
)
```

### Ensemble Analysis

Run all 8 model combinations (4 transposition × 2 cell temperature) for uncertainty quantification:

```r
# Get all model combinations with AC power
ensemble <- pv_power_ensemble(
  time = time,
  lat = lat,
  lon = lon,
  GHI = GHI,
  T_air = T_air,
  wind = wind,
  tilt = tilt,
  azimuth = azimuth,
  P_dc0 = 44880 * 230,
  n_inverters = 20,
  inverter_kw = 500
)

# Calculate ensemble statistics
library(dplyr)
ensemble_stats <- ensemble %>%
  group_by(time) %>%
  summarise(
    P_ac_mean = mean(P_ac),
    P_ac_sd = sd(P_ac),
    P_ac_min = min(P_ac),
    P_ac_max = max(P_ac)
  )
```

## Available Models

| Transposition | Cell Temperature | Identifier |
|---------------|------------------|------------|
| Hay-Davies | Skoplaki | `haydavies_skoplaki` |
| Hay-Davies | Faiman | `haydavies_faiman` |
| Reindl | Skoplaki | `reindl_skoplaki` |
| Reindl | Faiman | `reindl_faiman` |
| Perez | Skoplaki | `perez_skoplaki` |
| Perez | Faiman | `perez_faiman` |
| Olmo | Skoplaki | `olmo_skoplaki` |
| Olmo | Faiman | `olmo_faiman` |

## Function Reference

### Modular Pipeline Functions

#### `pv_power_pipeline()`

Complete DC + AC pipeline with independent model selection:

```r
pv_power_pipeline(
  time, lat, lon, GHI, T_air, wind, tilt, azimuth,
  transposition_model = c("haydavies", "reindl", "perez", "olmo"),
  decomposition_model = c("erbs", "boland"),
  cell_temp_model = c("skoplaki", "faiman"),
  iam_exp = 0.05,  # Set to FALSE to disable IAM
  ...
)
```

**Note:** Default is now "haydavies" instead of "olmo" due to validation issues
with the Olmo model outside its calibration region (Granada, Spain).

#### `pv_dc_pipeline()`

DC-only pipeline with independent model selection:

```r
pv_dc_pipeline(
  time, lat, lon, GHI, T_air, wind, tilt, azimuth,
  transposition_model = "haydavies",
  cell_temp_model = "skoplaki",
  ...
)
```

#### `pv_power_ensemble()` / `pv_dc_ensemble()`

Run all 8 model combinations for ensemble analysis:

```r
pv_power_ensemble(time, lat, lon, GHI, T_air, wind, tilt, azimuth, ...)
pv_dc_ensemble(time, lat, lon, GHI, T_air, wind, tilt, azimuth, ...)
```

### Clear-Sky Pipeline Functions

#### `ineichen_clearsky()`

Calculate clear-sky irradiance using the Ineichen-Perez model:

```r
clearsky <- ineichen_clearsky(
  time, lat, lon,
  linke_turbidity = 3.0,  # Or NULL for automatic database lookup
  altitude = 1233,       # De Aar altitude (m)
  perez_enhancement = FALSE
)
```

**Returns:** Data frame with ghi_clearsky, dni_clearsky, dhi_clearsky, zenith, airmass

#### `haurwitz_clearsky()`

Calculate clear-sky irradiance using the simple Haurwitz model (no turbidity needed):

```r
clearsky_simple <- haurwitz_clearsky(
  time, lat, lon,
  altitude = 1233
)
```

**Returns:** Data frame with ghi_clearsky, dni_clearsky, dhi_clearsky, zenith, airmass

#### `pv_clearsky_power_pipeline()`

Calculate expected AC power under clear-sky conditions with model selection:

```r
# Using Ineichen-Perez (default, requires turbidity)
clearsky_result <- pv_clearsky_power_pipeline(
  time, lat, lon, T_air, wind, tilt, azimuth,
  clearsky_model = "ineichen",  # or "haurwitz"
  linke_turbidity = 3.0,
  altitude = 1233,
  transposition_model = "haydavies",
  cell_temp_model = "skoplaki",
  n_inverters = 20,
  inverter_kw = 500
)

# Using Haurwitz (simpler, no turbidity parameter)
clearsky_result_simple <- pv_clearsky_power_pipeline(
  time, lat, lon, T_air, wind, tilt, azimuth,
  clearsky_model = "haurwitz"
)
```

**Returns:** Data frame with clear-sky irradiance, DC power, AC power, and all intermediate values

#### `pv_clearsky_dc_pipeline()`

DC-only clear-sky pipeline (same as above, without AC conversion).

#### `clearsky_index()` / `clearsky_performance_ratio()`

Calculate performance metrics using clear-sky reference:

```r
# Clear-sky index (ratio of measured to clear-sky GHI)
csi <- clearsky_index(GHI_measured, clearsky$ghi_clearsky)

# Performance ratio (ratio of measured to clear-sky power)
pr <- clearsky_performance_ratio(P_measured, clearsky_result$P_ac)
```

#### `filter_solar_elevation()`

Filter time series by solar elevation angle (sun height above horizon):

```r
# Filter out observations when solar elevation < 10 degrees
is_valid <- filter_solar_elevation(time, lat, lon, min_elevation = 10)
filtered_data <- your_data[is_valid, ]

# Common thresholds:
# min_elevation = 0:  All daylight hours
# min_elevation = 10: Full daylight (default)
# min_elevation = 15: Good for PV applications
# min_elevation = 30: High sun only
```

**Returns:** Logical vector (TRUE when elevation ≥ threshold, FALSE otherwise)

### Individual Model Functions

#### `olmo_transposition()`

Converts GHI to POA using Olmo et al. (1999) clearness index method.

```r
olmo_transposition(time, lat, lon, GHI, tilt, azimuth, albedo = 0.2)
```

**Returns:** Data frame with G_poa, zenith, sun_azimuth, incidence, k_t, I_0

#### `erbs_decomposition()`

Decomposes GHI into DNI and DHI using the Erbs model:

```r
erbs_decomposition(time, lat, lon, GHI)
```

**Returns:** Data frame with DNI, DHI, kt, zenith

#### `boland_decomposition()`

Decomposes GHI into DNI and DHI using the Boland-Ridley logistic model:

```r
boland_decomposition(
  time, lat, lon, GHI,
  a_coeff = 7.997,   # 1-hour coefficients (default)
  b_coeff = 0.586    # 1-hour coefficients (default)
)
```

**Returns:** Data frame with DNI, DHI, kt, zenith, df

#### `haydavies_transposition()`

Converts GHI, DNI, DHI to POA using Hay-Davies anisotropic sky model:

```r
haydavies_transposition(
  time, lat, lon, GHI, DNI, DHI, tilt, azimuth,
  albedo = 0.2
)
```

**Returns:** Data frame with poa_global, poa_beam, poa_sky_diffuse, poa_ground_diffuse, ai, rb

#### `skoplaki_cell_temperature()`

Estimates cell temperature using the Skoplaki NOCT-based model:

```r
skoplaki_cell_temperature(
  G_poa, T_air, wind,
  variant = c("model1", "model2"),
  gamma = -0.0043, T_NOCT = 45, ...
)
```

**Returns:** Numeric vector of cell temperatures (°C)

#### `faiman_cell_temperature()`

Estimates cell temperature using the Faiman empirical model:

```r
faiman_cell_temperature(
  poa_global, temp_air, wind_speed,
  u0 = 25.0, u1 = 6.84
)
```

**Returns:** Numeric vector of cell temperatures (°C)

#### `pvwatts_dc()`

Calculates DC power with optional IAM correction:

```r
pvwatts_dc(
  G_poa, T_cell,
  incidence = NULL,  # Optional: for IAM
  iam_exp = 0.05,    # Set to FALSE to disable
  P_dc0 = 230,
  gamma = -0.0043
)
```

**Returns:** Numeric vector of DC power (W)

#### `pv_ac_simple_clipping()`

Applies inverter efficiency and clipping:

```r
pv_ac_simple_clipping(
  P_dc,
  n_inverters = 20,
  inverter_kw = 500,
  eta_inv = 0.97
)
```

**Returns:** List with P_ac, clipped flag, and P_ac_rated

### Legacy Convenience Functions

**Warning:** The following functions use the Olmo transposition model, which has known
accuracy issues outside of its calibration region (Granada, Spain). Consider using
`pv_dc_pipeline()` or `pv_power_pipeline()` with `transposition_model = "haydavies"` instead.

#### `pv_dc_olmo_skoplaki_pvwatts()`

DC pipeline with Olmo + Skoplaki (maintained for backward compatibility).

#### `pv_dc_haydavies_faiman_pvwatts()`

DC pipeline with Hay-Davies + Faiman (recommended for most applications).

## Vignette

For a complete example using the De Aar solar plant with model comparisons, see the vignette:

```r
vignette("de_aar", package = "pvflux")
```

## Default Parameters

The package includes sensible defaults based on:

- **PV Module**: Trina TSM-PC05 (230W polycrystalline)
  - Nameplate power: 230 W
  - Temperature coefficient: -0.0043 /K (-0.43%/K)
  - Efficiency at STC: 14.1%
  - NOCT: 45°C

- **IAM (Incidence Angle Modifier)**:
  - Model: `cos(θ)^b` with `b = 0.05`
  - Corrects for optical losses at high incidence angles
  - Reduces 1-3% underestimation at low sun angles

- **Faiman Cell Temperature**:
  - u0: 25.0 W/(m²·°C)
  - u1: 6.84 W/(m²·°C·m/s)
  - From IEC 61853 standard

- **NOCT Conditions** (for Skoplaki model):
  - Ambient temperature: 20°C
  - Irradiance: 800 W/m²
  - Wind speed: 1 m/s

- **Boland-Ridley Decomposition**:
  - a_coeff: 7.997 (1-hour data coefficients)
  - b_coeff: 0.586 (1-hour data coefficients)
  - Alternative 15-minute coefficients: a = 8.645, b = 0.613

- **Skoplaki Cell Temperature Models**:
  - Model 1 (default): h_w = 8.91 + 2.00*v_f
  - Model 2: h_w = 5.7 + 3.8*v_w
  - τα (tau_alpha): 0.9

- **Inverter**:
  - Efficiency: 97%
  - Configuration: 20 inverters × 500 kW

- **Clear-Sky Models**:
  - **Ineichen-Perez** (default): Atmospheric turbidity-based model
    - Altitude: 1233 m (De Aar, South Africa)
    - Linke turbidity: 3.0 (clean rural conditions) - or `NULL` for automatic database lookup
    - Perez enhancement: FALSE (disabled by default)
    - Solar constant: 1366.1 W/m²
  - **Haurwitz**: Solar geometry-only model (no turbidity required)
    - Suitable for quick estimates when atmospheric data is unavailable

## Code Attribution

**Important:** Much of the code in this package is ported or adapted from the [**pvlib-python**](https://github.com/pvlib/pvlib-python) library, which is distributed under the BSD 3-Clause License. The pvlib-python project is a collaborative effort by researchers worldwide to provide validated solar energy modeling tools.

Key components adapted from pvlib-python include:
- Ineichen-Perez clear-sky model
- Haurwitz clear-sky model
- Perez transposition model
- Reindl transposition model
- Hay-Davies transposition model
- Erbs decomposition model
- Boland-Ridley decomposition model
- PVWatts DC power model
- Kasten-Young airmass formula
- Various helper functions and validation approaches

We gratefully acknowledge the pvlib development community for their rigorous implementation and testing of these solar models. Users of this package should also cite the appropriate pvlib references when using these models.

**pvlib-python References:**
> Holmgren, W. F., Hansen, C. W., & Mikofski, M. A. (2018). pvlib python: a python package for modeling solar energy systems. *Journal of Open Source Software*, 3(29), 884. https://doi.org/10.21105/joss.00884

> Anderson, K., et al. (2023). pvlib python: 2023 project update. *Journal of Open Source Software*, 8(92), 5994. https://doi.org/10.21105/joss.05994

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

- Porting pvlib-python models to R:
  - Ineichen-Perez clear-sky model
  - Perez, Reindl, and Hay-Davies transposition models
  - Erbs and Boland-Ridley decomposition models
  - PVWatts DC power model
- Implementing the Olmo et al. (1999) transposition model equations
- Implementing the Skoplaki and Faiman cell temperature models
- Implementing the Incidence Angle Modifier (IAM)
- Developing clear-sky pipeline functions and performance metrics
- Refactoring code into modular functions with independent model selection
- Adding ensemble analysis capabilities
- Writing documentation and roxygen2 comments
- Drafting the vignette and README content

All AI-generated code and documentation was reviewed, validated against the original published equations and pvlib-python implementations, and approved by the package author.

## References

- **Ayvazoğluyüksel, Ö., & Başaran Filik, Ü. (2018).** Estimation methods of global solar radiation, cell temperature and solar power forecasting: A review and case study in Eskişehir. *Renewable and Sustainable Energy Reviews*, 91, 639-653. [https://doi.org/10.1016/j.rser.2018.03.084](https://doi.org/10.1016/j.rser.2018.03.084)

- **Corripio, J. G. (2003).** Vectorial algebra algorithms for calculating terrain parameters from DEMs and the position of the sun for solar radiation modelling in mountainous terrain. *International Journal of Geographical Information Science*, 17(1), 1-23.

- **Driesse, A., et al.** PVLib Python documentation and source code.

- **Erbs, D. G., Klein, S. A., & Duffie, J. A. (1982).** Estimation of the diffuse radiation fraction for hourly, daily and monthly-average global radiation. *Solar Energy*, 28(4), 293-302.

- **Faiman, D. (2008).** Assessing the outdoor operating temperature of photovoltaic modules. *Progress in Photovoltaics*, 16(4), 307-315. [https://doi.org/10.1002/pip.813](https://doi.org/10.1002/pip.813)

- **Hay, J. E., & Davies, J. A. (1980).** Calculations of the solar radiation incident on an inclined surface. In *Proc. of First Canadian Solar Radiation Data Workshop* (pp. 59). Ministry of Supply and Services, Canada.

- **Holmgren, W. F., Hansen, C. W., & Mikofski, M. A. (2018).** pvlib python: a python package for modeling solar energy systems. *Journal of Open Source Software*, 3(29), 884. [https://doi.org/10.21105/joss.00884](https://doi.org/10.21105/joss.00884)

- **Ineichen, P., & Perez, R. (2002).** A new airmass independent formulation for the Linke turbidity coefficient. *Solar Energy*, 73(3), 151-157. [https://doi.org/10.1016/S0038-092X(02)00045-2](https://doi.org/10.1016/S0038-092X(02)00045-2)

- **Kasten, F., & Young, A. T. (1989).** Revised optical air mass tables and approximation formula. *Applied Optics*, 28(22), 4735-4738. [https://doi.org/10.1364/AO.28.004735](https://doi.org/10.1364/AO.28.004735)

- **Martin, N., & Ruiz, J. M. (2001).** Calculation of the PV modules angular losses under field conditions by means of an analytical model. *Solar Energy Materials and Solar Cells*, 70(1), 25-38. [https://doi.org/10.1016/S0927-0248(00)00408-6](https://doi.org/10.1016/S0927-0248(00)00408-6)

- **Olmo, F. J., Vida, J., Foyo, I., Castro-Diez, Y., & Alados-Arboledas, L. (1999).** Prediction of global irradiance on inclined surfaces from horizontal global irradiance. *Energy*, 24(8), 689-704. [https://doi.org/10.1016/S0360-5442(99)00025-0](https://doi.org/10.1016/S0360-5442(99)00025-0)

- **Evseev, E. G., & Kudish, A. I. (2009).** An assessment of a revised Olmo et al. model to predict solar global radiation on a tilted surface at Beer Sheva, Israel. *Renewable Energy*, 34(1), 112-119. [https://doi.org/10.1016/j.renene.2008.04.012](https://doi.org/10.1016/j.renene.2008.04.012)

- **Ruiz, E., Soler, A., & Robledo, L. (2002).** Comparison of the Olmo model with global irradiance measurements on vertical surfaces at Madrid. *Energy*, 27(10), 975-986.

- **Skoplaki, E., Boudouvis, A. G., & Palyvos, J. A. (2008).** A simple correlation for the operating temperature of photovoltaic modules of arbitrary mounting. *Solar Energy Materials and Solar Cells*, 92(11), 1393-1402. [https://doi.org/10.1016/j.solmat.2008.05.016](https://doi.org/10.1016/j.solmat.2008.05.016)

## Contributing

Contributions, bug reports, and feature requests are welcome! Please open an issue or submit a pull request.

## Citation

If you use this package in your research, please cite:

```r
citation("pvflux")
```
