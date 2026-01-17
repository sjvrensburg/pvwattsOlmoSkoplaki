# Solar position calculation functions from the insol package
#
# These functions are extracted from the insol package (version 1.2.2)
# which was removed from CRAN.
#
# Original package information:
#   Package: insol
#   Version: 1.2.2
#   Date: 2021-02-10
#   Author: Javier G. Corripio
#   Maintainer: Javier G. Corripio <jgc@meteoexploration.com>
#   License: GPL-2
#   URL: https://meteoexploration.com/R/insol/index.html
#
# Reference:
#   Corripio, J. G. (2003). Vectorial algebra algorithms for calculating
#   terrain parameters from DEMs and the position of the sun for solar
#   radiation modelling in mountainous terrain. International Journal of
#   Geographical Information Science, 17(1), 1-23.
#
# These functions are included here under GPL-2 license terms.

#' Convert between degrees and radians
#' @param degree Angle in degrees
#' @return Angle in radians
#' @keywords internal
radians <- function(degree) {
  radian <- degree * (pi/180.0)
  return(radian)
}

#' Convert between radians and degrees
#' @param radian Angle in radians
#' @return Angle in degrees
#' @keywords internal
degrees <- function(radian) {
  degree <- radian * (180.0/pi)
  return(degree)
}

#' Julian Day conversion
#' @param x POSIXct time object or Julian Day numeric
#' @param inverse Logical, if TRUE convert from JD to POSIXct
#' @return Julian Day (numeric) or POSIXct time
#' @keywords internal
JD <- function(x, inverse=FALSE) {
  if (inverse) {
    return(as.POSIXct((x-2440587.5)*86400, origin=ISOdate(1970,01,01,0,0,0),
                      format="%Y-%m-%d %H:%M:%S"))
  } else {
    return(as.numeric(x)/86400 + 2440587.5)
  }
}

#' Equation of time
#' @param jd Julian Day
#' @return Equation of time in minutes
#' @keywords internal
eqtime <- function(jd) {
  if (nargs() < 1) {
    cat("USAGE: eqtime(jd)\n")
    return()
  }
  jdc <- (jd - 2451545.0)/36525.0
  sec <- 21.448 - jdc*(46.8150 + jdc*(0.00059 - jdc*(0.001813)))
  e0 <- 23.0 + (26.0 + (sec/60.0))/60.0
  ecc <- 0.016708634 - jdc * (0.000042037 + 0.0000001267 * jdc)
  oblcorr <- e0 + 0.00256 * cos(radians(125.04 - 1934.136 * jdc))
  y <- (tan(radians(oblcorr)/2))^2
  l0 <- 280.46646 + jdc * (36000.76983 + jdc*(0.0003032))
  l0 <- (l0-360*(l0%/%360))%%360
  rl0 <- radians(l0)
  gmas <- 357.52911 + jdc * (35999.05029 - 0.0001537 * jdc)
  gmas <- radians(gmas)
  EqTime <- y*sin(2*rl0) - 2.0*ecc*sin(gmas) + 4.0*ecc*y*sin(gmas)*cos(2*rl0) -
    0.5*y^2*sin(4*rl0) - 1.25*ecc^2*sin(2*gmas)
  return(degrees(EqTime)*4)
}

#' Solar declination
#' @param jd Julian Day
#' @return Solar declination in degrees
#' @keywords internal
declination <- function(jd) {
  if (nargs() < 1) {
    cat("USAGE: declination(jd) \n jd = Julian day \n")
    return()
  }
  # Julian Centuries (Meeus, Astronomical Algorithms 1999. (24.1))
  T <- (jd - 2451545)/36525.0
  # mean obliquity of the ecliptic (21.2)
  epsilon <- (23+26/60.0+21.448/3600.0) - (46.8150/3600.0)*T -
    (0.00059/3600.0)*T^2 + (0.001813/3600.0)*T^3
  # geometric mean longitude of the sun (24.2)
  L0 <- 280.46645 + 36000.76983*T + 0.0003032*T^2
  # mean anomaly of the Sun (24.3)
  M <- 357.52910 + 35999.05030*T - 0.0001559*T^2 - 0.00000048*T^3
  # eccentricity of the Earth's orbit (24.4)
  e <- 0.016708617 - 0.000042037*T - 0.0000001236*T^2
  # Sun's equation of center
  C <- (1.914600 - 0.004817*T - 0.000014*T^2)*sin(radians(M)) +
    (0.019993 - 0.000101*T)*sin(2*radians(M)) +
    0.000290*sin(3*radians(M))
  # Sun's true longitude
  Theta <- L0 + C
  # Sun's true anomaly
  v <- M + C
  #  Longitude of the ascending node of the moon
  Omega <- 125.04452 - 1934.136261*T + 0.0020708*T^2 + (T^3)/450000
  # Apparent longitude of the sun
  lambda <- Theta - 0.00569 - 0.00478*sin(radians(Omega))
  # Sun's declination (24.7)
  delta <- asin(sin(radians(epsilon)) * sin(radians(lambda)))
  return(degrees(delta))
}

#' Hour angle
#' @param jd Julian Day
#' @param longitude Longitude in degrees
#' @param timezone Timezone in hours (west is negative)
#' @return Hour angle in radians
#' @keywords internal
hourangle <- function(jd, longitude, timezone) {
  if (nargs() < 3) {
    cat("USAGE: hourangle(jd,longitude,timezone)\n julian day, degrees, hours. Return radians \n")
    return()
  }
  hour <- ((jd-floor(jd))*24+12) %% 24
  eqtime_val <- eqtime(jd)
  stndmeridian <- timezone*15
  deltalontime <- longitude-stndmeridian
  deltalontime <- deltalontime * 24.0/360.0
  omegar <- pi*( ( (hour + deltalontime + eqtime_val/60)/12.0 ) - 1.0)
  return(omegar)
}

#' Solar vector
#' @param jd Julian Day
#' @param latitude Latitude in degrees
#' @param longitude Longitude in degrees
#' @param timezone Timezone in hours (west is negative)
#' @return 3-column matrix with x, y, z coordinates of sun vector
#' @keywords internal
sunvector <- function(jd, latitude, longitude, timezone) {
  if (nargs() < 4) {
    cat("USAGE: sunvector(jd,latitude,longitude,timezone)\n values in jd, degrees, hours\n")
    return()
  }
  omegar <- hourangle(jd, longitude, timezone)
  deltar <- radians(declination(jd))
  lambdar <- radians(latitude)
  svx <- -sin(omegar)*cos(deltar)
  svy <- sin(lambdar)*cos(omegar)*cos(deltar) - cos(lambdar)*sin(deltar)
  svz <- cos(lambdar)*cos(omegar)*cos(deltar) + sin(lambdar)*sin(deltar)
  return(cbind(svx, svy, svz))
}

#' Solar position (azimuth and zenith)
#' @param sunv Sun vector (3-column matrix from sunvector())
#' @return 2-column matrix with azimuth and zenith in degrees
#' @keywords internal
sunpos <- function(sunv) {
  # no refraction, center of disc
  if (nargs() < 1) {
    cat("USAGE: sunpos(sunvector)\n 3D vector\n")
    return()
  }
  azimuth <- degrees(pi - atan2(sunv[,1], sunv[,2]))
  zenith <- degrees(acos(sunv[,3]))
  return(cbind(azimuth, zenith))
}

#' Filter times by solar elevation angle
#'
#' @description
#' Create a logical filter vector indicating times when the solar zenith angle
#' is below a specified threshold. This is useful for filtering out times when
#' the sun is too low on the horizon, such as during early morning, late evening,
#' twilight, or nighttime conditions.
#'
#' The function calculates solar position using the same algorithms as the
#' clear-sky models, ensuring consistency with the rest of the package. All
#' time handling follows the package's timezone conventions, with input times
#' converted to UTC for solar position calculations.
#'
#' @details
#' Solar zenith angle is the angle between the vertical (directly overhead) and
#' the sun. A zenith angle of 0° means the sun is directly overhead, while 90°
#' means the sun is on the horizon. Solar elevation angle is the complement:
#' elevation = 90° - zenith.
#'
#' Common values for \code{max_zenith}:
#' \itemize{
#'   \item 80°: Sun above 10° elevation (full daylight, minimal atmospheric effects)
#'   \item 75°: Sun above 15° elevation (good for most PV applications)
#'   \item 70°: Sun above 20° elevation (avoiding low-angle irradiance)
#'   \item 90°: Any time the sun is above the horizon (includes all daylight hours)
#' }
#'
#' This function uses the solar position calculations from the insol package
#' (GPL-2 licensed) that are included in pvflux for solar position computations.
#'
#' @param time Timestamps as POSIXct, POSIXlt, character, or numeric. If a timezone
#'   is specified, times are internally converted to UTC for solar position
#'   calculations. If no timezone is specified, UTC is assumed. See
#'   \code{\link{time_utils}} for details.
#' @param lat Latitude in degrees (negative for southern hemisphere)
#' @param lon Longitude in degrees (east positive, west negative)
#' @param max_zenith Maximum allowed solar zenith angle in degrees.
#'   Times with zenith angles greater than this value will return FALSE.
#'   Default: 80 degrees (solar elevation > 10 degrees)
#'
#' @return Logical vector of the same length as time, where TRUE indicates
#'   the solar zenith angle is less than max_zenith (i.e., the sun is above
#'   the specified elevation threshold).
#'
#' @examples
#' \dontrun{
#' # Create sample data for a full day in South Africa
#' time <- seq(as.POSIXct("2026-01-15 00:00", tz = "Africa/Johannesburg"),
#'             by = "hour", length.out = 24)
#' lat <- -30.6279  # De Aar, South Africa
#' lon <- 24.0054
#'
#' # Filter for daytime hours (sun above horizon)
#' is_daytime <- filter_solar_elevation(time, lat, lon, max_zenith = 90)
#' daytime_hours <- time[is_daytime]
#' print(daytime_hours)
#'
#' # Filter for good solar conditions (elevation > 15 degrees)
#' is_good <- filter_solar_elevation(time, lat, lon, max_zenith = 75)
#'
#' # Apply filter to measurement data
#' # ghi_data <- data.frame(time = time, GHI = measured_ghi)
#' # good_data <- ghi_data[is_good, ]
#'
#' # Use with clear-sky pipeline to get only high-sun periods
#' result <- pv_clearsky_dc_pipeline(
#'   time = time[is_good],
#'   lat = lat,
#'   lon = lon,
#'   T_air = rep(25, sum(is_good)),
#'   wind = rep(3, sum(is_good)),
#'   tilt = 30,
#'   azimuth = 0
#' )
#' }
#'
#' @name filter_solar_elevation
#' @rdname filter_solar_elevation
#' @export
filter_solar_elevation <- function(time, lat, lon, max_zenith = 80) {
  # Prepare time: convert to UTC for calculations (package standard)
  time_info <- prepare_time_utc(time)
  time_utc <- time_info$time_utc

  # Calculate solar position
  jd <- JD(time_utc)
  sv <- sunvector(jd, lat, lon, 0)
  sp <- sunpos(sv)
  zenith_angles <- sp[, 2]

  # Create filter (TRUE when zenith is less than threshold)
  zenith_angles < max_zenith
}
