#' PV DC Power Pipeline with Clear-Sky Irradiance
#'
#' @description
#' Calculate expected DC power under clear-sky conditions using the Ineichen-Perez
#' clear-sky model combined with the modular PV power pipeline.
#'
#' This function is useful for:
#' - Estimating maximum potential power output
#' - Comparing actual vs. clear-sky performance
#' - Fault detection and performance monitoring
#' - Resource assessment and capacity planning
#'
#' @param time Timestamps as POSIXct, POSIXlt, character, or numeric. If a timezone
#'   is specified, times are internally converted to UTC for solar position
#'   calculations and returned in the original timezone.
#' @param lat Latitude in degrees
#' @param lon Longitude in degrees
#' @param T_air Air temperature in degrees Celsius
#' @param wind Wind speed in m/s
#' @param tilt Panel tilt angle from horizontal in degrees (0 = horizontal, 90 = vertical)
#' @param azimuth Panel azimuth angle in degrees (0 = north, 90 = east, 180 = south, 270 = west)
#' @param linke_turbidity Linke turbidity coefficient. Default: 3.0 (clean rural).
#'   Can be a single value or vector matching length of time.
#' @param altitude Altitude above sea level in meters. Default: 0
#' @param albedo Ground albedo (reflectance). Default: 0.2
#' @param transposition_model Transposition model to use. Options: "haydavies", "reindl", "perez".
#'   Default: "haydavies"
#' @param cell_temp_model Cell temperature model. Options: "skoplaki", "faiman".
#'   Default: "skoplaki"
#' @param iam_exp Incidence angle modifier exponent for power-law model: cos(θ)^b.
#'   Set to NA or FALSE to disable IAM. Default: 0.05
#' @param P_dc0 Nameplate DC power rating in Watts at STC. Default: 230
#' @param gamma Temperature coefficient of power (1/K). Default: -0.0043
#' @param solar_constant Solar constant (W/m^2). Default: 1366.1
#' @param perez_enhancement Apply Perez enhancement factor for very clear conditions.
#'   Default: FALSE
#' @param ... Additional parameters passed to cell temperature and DC power models
#'   (e.g., T_NOCT, skoplaki_variant, eta_STC, tau_alpha, u0, u1)
#'
#' @return Data frame with columns:
#' \describe{
#'   \item{time}{Input timestamps}
#'   \item{ghi_clearsky}{Clear-sky global horizontal irradiance (W/m^2)}
#'   \item{dni_clearsky}{Clear-sky direct normal irradiance (W/m^2)}
#'   \item{dhi_clearsky}{Clear-sky diffuse horizontal irradiance (W/m^2)}
#'   \item{G_poa}{Plane-of-array irradiance (W/m^2)}
#'   \item{T_air}{Air temperature (°C)}
#'   \item{wind}{Wind speed (m/s)}
#'   \item{T_cell}{Cell temperature (°C)}
#'   \item{P_dc}{DC power output (W)}
#'   \item{zenith}{Solar zenith angle (degrees)}
#'   \item{incidence}{Angle of incidence on panel (degrees)}
#'   \item{airmass}{Relative optical airmass}
#'   \item{transposition}{Transposition model used}
#'   \item{cell_temp}{Cell temperature model used}
#' }
#'
#' @examples
#' \dontrun{
#' time <- seq(as.POSIXct("2026-01-15 06:00", tz = "UTC"),
#'             by = "hour", length.out = 12)
#' T_air <- rep(25, 12)
#' wind <- rep(2, 12)
#'
#' result <- pv_clearsky_dc_pipeline(
#'   time = time,
#'   lat = -30.6279,
#'   lon = 24.0054,
#'   T_air = T_air,
#'   wind = wind,
#'   tilt = 30,
#'   azimuth = 0,
#'   linke_turbidity = 3.0,
#'   altitude = 1287
#' )
#' }
#'
#' @export
pv_clearsky_dc_pipeline <- function(
  time,
  lat,
  lon,
  T_air,
  wind,
  tilt,
  azimuth,
  linke_turbidity = 3.0,
  altitude = 0,
  albedo = 0.2,
  transposition_model = c("haydavies", "reindl", "perez"),
  cell_temp_model = c("skoplaki", "faiman"),
  iam_exp = 0.05,
  P_dc0 = 230,
  gamma = -0.0043,
  solar_constant = 1366.1,
  perez_enhancement = FALSE,
  ...
) {
  # Match arguments
  transposition_model <- match.arg(transposition_model)
  cell_temp_model <- match.arg(cell_temp_model)

  # Calculate clear-sky irradiance
  clearsky <- ineichen_clearsky(
    time = time,
    lat = lat,
    lon = lon,
    linke_turbidity = linke_turbidity,
    altitude = altitude,
    solar_constant = solar_constant,
    perez_enhancement = perez_enhancement
  )

  # Use the modular DC pipeline with clear-sky GHI
  # Note: The pipeline needs GHI, not DNI/DHI separately for most transposition models
  dc_result <- pv_dc_pipeline(
    time = time,
    lat = lat,
    lon = lon,
    GHI = clearsky$ghi_clearsky,
    T_air = T_air,
    wind = wind,
    tilt = tilt,
    azimuth = azimuth,
    albedo = albedo,
    transposition_model = transposition_model,
    decomposition_model = "erbs",  # Use erbs for decomposition
    cell_temp_model = cell_temp_model,
    iam_exp = iam_exp,
    P_dc0 = P_dc0,
    gamma = gamma,
    ...
  )

  # Add clear-sky specific columns
  dc_result$ghi_clearsky <- clearsky$ghi_clearsky
  dc_result$dni_clearsky <- clearsky$dni_clearsky
  dc_result$dhi_clearsky <- clearsky$dhi_clearsky
  dc_result$airmass <- clearsky$airmass

  # Reorder columns to put clear-sky components first
  cols <- c("time", "ghi_clearsky", "dni_clearsky", "dhi_clearsky",
            setdiff(names(dc_result), c("time", "ghi_clearsky", "dni_clearsky", "dhi_clearsky")))
  dc_result <- dc_result[, cols]

  return(dc_result)
}


#' PV AC Power Pipeline with Clear-Sky Irradiance
#'
#' @description
#' Calculate expected AC power under clear-sky conditions using the Ineichen-Perez
#' clear-sky model combined with the full PV power pipeline (DC + AC conversion).
#'
#' This extends \code{\link{pv_clearsky_dc_pipeline}} by adding AC conversion with
#' inverter clipping.
#'
#' @inheritParams pv_clearsky_dc_pipeline
#' @param n_inverters Number of inverters. Default: 20
#' @param inverter_kw Rated power of each inverter in kW. Default: 500
#' @param eta_inv Inverter efficiency (0-1). Default: 0.97
#'
#' @return Data frame with all columns from \code{\link{pv_clearsky_dc_pipeline}} plus:
#' \describe{
#'   \item{P_ac}{AC power output (W)}
#'   \item{clipped}{Logical indicating whether power was clipped by inverter limit}
#'   \item{P_ac_rated}{Total rated AC power capacity (W)}
#' }
#'
#' @examples
#' \dontrun{
#' time <- seq(as.POSIXct("2026-01-15 06:00", tz = "UTC"),
#'             by = "hour", length.out = 12)
#' T_air <- rep(25, 12)
#' wind <- rep(2, 12)
#'
#' result <- pv_clearsky_power_pipeline(
#'   time = time,
#'   lat = -30.6279,
#'   lon = 24.0054,
#'   T_air = T_air,
#'   wind = wind,
#'   tilt = 30,
#'   azimuth = 0,
#'   linke_turbidity = 3.0,
#'   altitude = 1287,
#'   n_inverters = 20,
#'   inverter_kw = 500
#' )
#' }
#'
#' @export
pv_clearsky_power_pipeline <- function(
  time,
  lat,
  lon,
  T_air,
  wind,
  tilt,
  azimuth,
  linke_turbidity = 3.0,
  altitude = 0,
  albedo = 0.2,
  transposition_model = c("haydavies", "reindl", "perez"),
  cell_temp_model = c("skoplaki", "faiman"),
  iam_exp = 0.05,
  P_dc0 = 230,
  gamma = -0.0043,
  solar_constant = 1366.1,
  perez_enhancement = FALSE,
  n_inverters = 20,
  inverter_kw = 500,
  eta_inv = 0.97,
  ...
) {
  # Calculate DC power using clear-sky pipeline
  dc_out <- pv_clearsky_dc_pipeline(
    time = time,
    lat = lat,
    lon = lon,
    T_air = T_air,
    wind = wind,
    tilt = tilt,
    azimuth = azimuth,
    linke_turbidity = linke_turbidity,
    altitude = altitude,
    albedo = albedo,
    transposition_model = transposition_model,
    cell_temp_model = cell_temp_model,
    iam_exp = iam_exp,
    P_dc0 = P_dc0,
    gamma = gamma,
    solar_constant = solar_constant,
    perez_enhancement = perez_enhancement,
    ...
  )

  # Calculate AC power using simple clipping model
  ac_out <- pv_ac_simple_clipping(
    P_dc = dc_out$P_dc,
    n_inverters = n_inverters,
    inverter_kw = inverter_kw,
    eta_inv = eta_inv
  )

  # Combine results
  dc_out$P_ac <- ac_out$P_ac
  dc_out$clipped <- ac_out$clipped
  dc_out$P_ac_rated <- ac_out$P_ac_rated

  return(dc_out)
}


#' Calculate Clear-Sky Index (CSI)
#'
#' @description
#' Calculate the clear-sky index, which is the ratio of measured (or modeled)
#' GHI to clear-sky GHI. This is useful for:
#' - Assessing cloud cover and atmospheric conditions
#' - Performance monitoring (comparing actual vs. clear-sky)
#' - Data quality checking
#'
#' CSI values:
#' - CSI = 1.0: Clear sky conditions
#' - CSI < 1.0: Cloudy conditions (typical range 0.2-0.9)
#' - CSI > 1.0: Possible measurement error or cloud enhancement
#'
#' @param GHI_measured Measured or modeled global horizontal irradiance (W/m^2)
#' @param GHI_clearsky Clear-sky global horizontal irradiance (W/m^2)
#' @param min_clearsky_ghi Minimum clear-sky GHI threshold for calculation (W/m^2).
#'   CSI is set to NA when clear-sky GHI is below this threshold to avoid
#'   numerical issues at low sun angles. Default: 50
#'
#' @return Numeric vector of clear-sky index values (dimensionless)
#'
#' @examples
#' \dontrun{
#' # Calculate clear-sky conditions
#' clearsky <- ineichen_clearsky(time, lat, lon, linke_turbidity = 3.0)
#'
#' # Assume some measured GHI with clouds
#' GHI_measured <- clearsky$ghi_clearsky * 0.7  # 70% of clear-sky
#'
#' # Calculate CSI
#' csi <- clearsky_index(GHI_measured, clearsky$ghi_clearsky)
#' }
#'
#' @export
clearsky_index <- function(
  GHI_measured,
  GHI_clearsky,
  min_clearsky_ghi = 50
) {
  csi <- GHI_measured / GHI_clearsky

  # Set to NA when clear-sky GHI is too low (nighttime, low sun angles)
  csi[GHI_clearsky < min_clearsky_ghi] <- NA

  return(csi)
}


#' Calculate Performance Ratio Using Clear-Sky Reference
#'
#' @description
#' Calculate the performance ratio (PR) of a PV system using clear-sky power as
#' the reference. This is different from the traditional PR calculation which uses
#' incident irradiance at STC.
#'
#' Clear-sky PR is useful for:
#' - Identifying underperformance relative to clear-sky potential
#' - Comparing performance across different days/seasons
#' - Detecting system faults and degradation
#'
#' @param P_measured Measured AC or DC power output (W)
#' @param P_clearsky Expected clear-sky AC or DC power output (W)
#' @param min_clearsky_power Minimum clear-sky power threshold (W).
#'   PR is set to NA when clear-sky power is below this threshold.
#'   Default: 100
#'
#' @return Numeric vector of performance ratio values (dimensionless, 0-1 typical)
#'
#' @examples
#' \dontrun{
#' # Calculate clear-sky power
#' clearsky_result <- pv_clearsky_power_pipeline(
#'   time, lat, lon, T_air, wind, tilt, azimuth
#' )
#'
#' # Assume some measured power (actual conditions with clouds, soiling, etc.)
#' P_measured <- clearsky_result$P_ac * 0.65  # 65% of clear-sky
#'
#' # Calculate performance ratio
#' pr <- clearsky_performance_ratio(P_measured, clearsky_result$P_ac)
#' }
#'
#' @export
clearsky_performance_ratio <- function(
  P_measured,
  P_clearsky,
  min_clearsky_power = 100
) {
  pr <- P_measured / P_clearsky

  # Set to NA when clear-sky power is too low
  pr[P_clearsky < min_clearsky_power] <- NA

  return(pr)
}
