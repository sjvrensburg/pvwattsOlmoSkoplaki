#' Ineichen-Perez Clear Sky Model
#'
#' @description
#' Calculate clear-sky GHI, DNI, and DHI using the Ineichen and Perez clear sky model.
#'
#' This model estimates clear-sky irradiance components as a function of solar
#' zenith angle, atmospheric turbidity (Linke turbidity), and site altitude.
#' It includes an optional Perez enhancement factor for very clear conditions.
#'
#' The model is valid for solar zenith angles less than 90 degrees and
#' Linke turbidity values between 1 and 10.
#'
#' @param time Timestamps as POSIXct, POSIXlt, character, or numeric. If a timezone
#'   is specified, times are internally converted to UTC for solar position
#'   calculations and returned in the original timezone. If no timezone is
#'   specified, UTC is assumed. See \code{\link{time_utils}} for details.
#' @param lat Latitude in degrees
#' @param lon Longitude in degrees
#' @param linke_turbidity Linke turbidity coefficient (dimensionless). Typical values:
#'   - 2.0: Very clean, clear sky
#'   - 3.0: Clean, clear sky (rural)
#'   - 4.0: Moderately turbid (urban)
#'   - 5.0: Turbid
#'   - 6-7: Very turbid (polluted)
#'   Default: 3.0
#' @param altitude Altitude above sea level in meters. Default: 1233 (De Aar, South Africa)
#' @param dni_extra Extraterrestrial normal irradiance (W/m^2). If NULL (default),
#'   calculated using Spencer (1971) formula with solar_constant.
#' @param solar_constant Solar constant (W/m^2). Default: 1366.1. Only used if
#'   dni_extra is NULL.
#' @param perez_enhancement Logical. Apply Perez enhancement factor for very clear
#'   conditions. Default: FALSE
#' @param min_cos_zenith Minimum cosine of zenith angle for calculations.
#'   Default: 0.065 (equivalent to 86.3 degrees)
#'
#' @return Data frame with columns:
#' \describe{
#'   \item{time}{Input timestamps}
#'   \item{ghi_clearsky}{Clear-sky global horizontal irradiance (W/m^2)}
#'   \item{dni_clearsky}{Clear-sky direct normal irradiance (W/m^2)}
#'   \item{dhi_clearsky}{Clear-sky diffuse horizontal irradiance (W/m^2)}
#'   \item{zenith}{Solar zenith angle (degrees)}
#'   \item{airmass}{Relative optical airmass (dimensionless)}
#' }
#'
#' @references
#' Ineichen, P., and Perez, R. (2002). A new airmass independent formulation for
#' the Linke turbidity coefficient. Solar Energy, 73(3), 151-157.
#' \doi{10.1016/S0038-092X(02)00045-2}
#'
#' @examples
#' \dontrun{
#' time <- seq(as.POSIXct("2026-01-15 06:00", tz = "UTC"),
#'             by = "hour", length.out = 12)
#'
#' # Clean sky conditions
#' result <- ineichen_clearsky(
#'   time = time,
#'   lat = -30.6279,
#'   lon = 24.0054,
#'   linke_turbidity = 3.0,
#'   altitude = 1233
#' )
#' }
#'
#' @export
ineichen_clearsky <- function(
  time,
  lat,
  lon,
  linke_turbidity = 3.0,
  altitude = 1233,
  dni_extra = NULL,
  solar_constant = 1366.1,
  perez_enhancement = FALSE,
  min_cos_zenith = 0.065
) {
  # Prepare time: convert to UTC for calculations, store original timezone
  time_info <- prepare_time_utc(time)
  time_utc <- time_info$time_utc
  original_tz <- time_info$original_tz

  # Convert time to Julian Day (using UTC time)
  jd <- JD(time_utc)

  # Calculate sun position (timezone = 0 since we're using UTC)
  sv <- sunvector(jd, lat, lon, 0)
  sp <- sunpos(sv)
  theta_z_deg <- sp[, 2]  # Solar zenith angle in degrees

  # Calculate extraterrestrial radiation if not provided
  if (is.null(dni_extra)) {
    doy <- as.numeric(format(time_utc, "%j"))
    dni_extra <- get_extra_radiation_spencer(doy, solar_constant)
  }

  # Calculate airmass (absolute, pressure-corrected)
  cos_zenith <- pmax(cos(theta_z_deg * pi / 180), min_cos_zenith)
  airmass_relative <- kasten_young_airmass(theta_z_deg)
  airmass_absolute <- airmass_relative * atm_pressure_altitude_correction(altitude)

  # Ineichen-Perez model implementation
  # Altitude correction factors
  fh1 <- exp(-altitude / 8000)
  fh2 <- exp(-altitude / 1250)

  # Coefficients
  cg1 <- 5.09e-05 * altitude + 0.868
  cg2 <- 3.92e-05 * altitude + 0.0387

  # Clear sky global horizontal irradiance
  ghi <- cg1 * dni_extra * cos_zenith *
         exp(-cg2 * airmass_absolute * (fh1 + fh2 * (linke_turbidity - 1)))

  # Apply Perez enhancement if requested
  if (perez_enhancement) {
    ghi <- ghi * exp(0.01 * airmass_absolute^1.8)
  }

  # Direct normal irradiance
  b <- 0.664 + 0.163 / fh1
  bnci <- b * dni_extra * exp(-0.09 * airmass_absolute * (linke_turbidity - 1))

  # Alternative DNI calculation (constraint)
  bnci_constraint <- ghi / cos_zenith *
                     (1 - (0.1 - 0.2 * exp(-linke_turbidity)) / (0.1 + 0.882 / fh1))

  # Take minimum of the two DNI estimates
  dni <- pmin(bnci, bnci_constraint)

  # Diffuse horizontal irradiance
  dhi <- ghi - dni * cos_zenith

  # Handle nighttime and invalid conditions
  nighttime <- theta_z_deg >= 90
  ghi[nighttime] <- 0
  dni[nighttime] <- 0
  dhi[nighttime] <- 0

  # Ensure non-negative values
  ghi <- pmax(ghi, 0)
  dni <- pmax(dni, 0)
  dhi <- pmax(dhi, 0)

  # Restore original timezone for output
  time_out <- restore_time_tz(time_utc, original_tz)

  data.frame(
    time = time_out,
    ghi_clearsky = ghi,
    dni_clearsky = dni,
    dhi_clearsky = dhi,
    zenith = theta_z_deg,
    airmass = airmass_absolute
  )
}


#' Kasten-Young Airmass Formula
#'
#' @description
#' Calculate relative optical air mass using the Kasten and Young (1989) formula.
#' This is a widely-used approximation that is accurate for zenith angles up to 90 degrees.
#'
#' @param zenith_deg Solar zenith angle in degrees
#'
#' @return Relative optical air mass (dimensionless). Returns NA for zenith >= 90 degrees.
#'
#' @references
#' Kasten, F., and Young, A. T. (1989). Revised optical air mass tables and
#' approximation formula. Applied Optics, 28(22), 4735-4738.
#' \doi{10.1364/AO.28.004735}
#'
#' @keywords internal
kasten_young_airmass <- function(zenith_deg) {
  cos_z <- cos(zenith_deg * pi / 180)
  am <- 1 / (cos_z + 0.50572 * (96.07995 - zenith_deg)^(-1.6364))
  am[zenith_deg >= 90] <- NA
  return(am)
}


#' Atmospheric Pressure Altitude Correction
#'
#' @description
#' Calculate atmospheric pressure correction factor for air mass based on altitude.
#' Uses the barometric formula assuming standard atmosphere.
#'
#' @param altitude Altitude above sea level in meters
#'
#' @return Pressure correction factor (dimensionless). At sea level = 1.0.
#'
#' @keywords internal
atm_pressure_altitude_correction <- function(altitude) {
  # Standard atmosphere: P = P0 * exp(-altitude/8434.5)
  # Pressure correction factor relative to sea level
  return(exp(-altitude / 8434.5))
}


#' Simple Linke Turbidity Model
#'
#' @description
#' Provide simple Linke turbidity estimates based on month and location type.
#' This is a simplified approximation. For more accurate values, use site-specific
#' measurements or climatological databases.
#'
#' @param time Timestamps as POSIXct, POSIXlt, character, or numeric
#' @param location_type Character string describing location:
#'   - "clean_rural": Very clean, rural areas (TL = 2.0-3.0)
#'   - "rural": Clean rural areas (TL = 3.0-4.0)
#'   - "urban": Urban/suburban areas (TL = 4.0-5.0)
#'   - "polluted": Polluted urban areas (TL = 5.0-6.0)
#'   Default: "rural"
#' @param seasonal_variation Logical. Apply simple seasonal variation (+/- 0.5).
#'   Higher turbidity in summer (local), lower in winter. Default: TRUE
#' @param hemisphere Character string: "north" or "south". Used only if
#'   seasonal_variation is TRUE. Default: "north"
#'
#' @return Numeric vector of Linke turbidity values
#'
#' @details
#' This function provides rough estimates only. For research-grade work, use:
#' - Direct measurements from sun photometers
#' - Climatological databases (e.g., SoDa Linke turbidity database)
#' - Site-specific historical data
#'
#' @examples
#' \dontrun{
#' time <- seq(as.POSIXct("2026-01-15 00:00", tz = "UTC"),
#'             by = "month", length.out = 12)
#'
#' tl <- simple_linke_turbidity(time, location_type = "rural", hemisphere = "south")
#' }
#'
#' @export
simple_linke_turbidity <- function(
  time,
  location_type = c("rural", "clean_rural", "urban", "polluted"),
  seasonal_variation = TRUE,
  hemisphere = c("north", "south")
) {
  location_type <- match.arg(location_type)
  hemisphere <- match.arg(hemisphere)

  # Base turbidity values by location type
  base_tl <- switch(location_type,
    "clean_rural" = 2.5,
    "rural" = 3.5,
    "urban" = 4.5,
    "polluted" = 5.5
  )

  n <- length(time)
  tl <- rep(base_tl, n)

  if (seasonal_variation) {
    # Convert to POSIXlt to get month
    time_lt <- as.POSIXlt(time)
    month <- time_lt$mon + 1  # 1-12

    # Simple sinusoidal seasonal variation
    # Peak in summer (June/July in north, Dec/Jan in south)
    if (hemisphere == "north") {
      # Peak at month 6.5 (between June and July)
      seasonal_factor <- 0.5 * sin((month - 6.5) * pi / 6)
    } else {
      # Peak at month 0.5 (between Dec and Jan)
      # Shift by 6 months
      seasonal_factor <- 0.5 * sin((month - 0.5) * pi / 6)
    }

    tl <- tl + seasonal_factor
  }

  return(tl)
}
