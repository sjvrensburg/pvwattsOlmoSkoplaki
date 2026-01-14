#' Perez (1990) Anisotropic Transposition Model
#'
#' @description
#' Convert horizontal irradiance to plane-of-array (POA) irradiance using the
#' Perez et al. (1990) anisotropic sky model with the 'allsitescomposite1990'
#' coefficient set.
#'
#' The Perez model determines the total POA irradiance by combining:
#' \itemize{
#'   \item Beam component: Direct normal irradiance projected onto the tilted surface
#'   \item Sky diffuse component: Anisotropic model with circumsolar, isotropic, and horizon brightening parts
#'   \item Ground diffuse component: Isotropic reflection from the ground
#' }
#'
#' The sky diffuse irradiance is calculated as:
#' \deqn{I_{d} = DHI [(1 - F_1) (1 + \\cos\\beta)/2 + F_1 A/B + F_2 \\sin\\beta]}
#'
#' where \eqn{F_1} and \eqn{F_2} are brightness coefficients determined from
#' lookup tables based on the sky clearness (\eqn{\\epsilon}) and brightness
#' (\eqn{\\Delta}) parameters, \eqn{A} is the angle of incidence projection,
#' \eqn{B} is a function of the zenith angle, and \eqn{\\beta} is the tilt angle.
#'
#' The Perez model uses an 8-bin classification system for sky conditions:
#' \enumerate{
#'   \item \eqn{1.000 < \\epsilon < 1.065}: Overcast
#'   \item \eqn{1.065 < \\epsilon < 1.230}: Overcast
#'   \item \eqn{1.230 < \\epsilon < 1.500}: Intermediate
#'   \item \eqn{1.500 < \\epsilon < 1.950}: Intermediate
#'   \item \eqn{1.950 < \\epsilon < 2.800}: Intermediate
#'   \item \eqn{2.800 < \\epsilon < 4.500}: Clear
#'   \item \eqn{4.500 < \\epsilon < 6.200}: Clear
#'   \item \eqn{\\epsilon > 6.200}: Very clear
#' }
#'
#' @param time POSIXct vector of times (UTC recommended)
#' @param lat Latitude in degrees
#' @param lon Longitude in degrees
#' @param GHI Global horizontal irradiance (W/m^2)
#' @param DNI Direct normal irradiance (W/m^2)
#' @param DHI Diffuse horizontal irradiance (W/m^2)
#' @param tilt Panel tilt angle (degrees from horizontal)
#' @param azimuth Panel azimuth (degrees, 0 = north)
#' @param albedo Ground albedo (default 0.2)
#' @param solar_constant The solar constant (W/m^2). Default: 1366.1
#'
#' @return Data frame with columns:
#' \describe{
#'   \item{time}{Input timestamps}
#'   \item{GHI}{Input global horizontal irradiance (W/m^2)}
#'   \item{DNI}{Input direct normal irradiance (W/m^2)}
#'   \item{DHI}{Input diffuse horizontal irradiance (W/m^2)}
#'   \item{poa_global}{Total plane-of-array irradiance (W/m^2)}
#'   \item{poa_beam}{Beam (direct) component on tilted surface (W/m^2)}
#'   \item{poa_sky_diffuse}{Sky diffuse component on tilted surface (W/m^2)}
#'   \item{poa_ground_diffuse}{Ground reflected component on tilted surface (W/m^2)}
#'   \item{poa_diffuse}{Total diffuse (sky + ground) on tilted surface (W/m^2)}
#'   \item{zenith}{Solar zenith angle (degrees)}
#'   \item{azimuth}{Solar azimuth angle (degrees)}
#'   \item{incidence}{Angle of incidence on panel (degrees)}
#'   \item{epsilon}{Sky clearness parameter}
#'   \item{delta}{Sky brightness parameter}
#'   \item{ebin}{Epsilon bin index (1-8)}
#'   \item{F1}{Brightness coefficient F1}
#'   \item{F2}{Brightness coefficient F2}
#' }
#'
#' @references
#' Perez, R., Ineichen, P., Seals, R., Michalsky, J., Stewart, R., 1990.
#' Modeling daylight availability and irradiance components from direct and
#' global irradiance. Solar Energy 44 (5), 271-289.
#' \doi{10.1016/0038-092X(90)90055-G}
#'
#' Perez, R., Seals, R., Ineichen, P., Stewart, R., Menicucci, D., 1987.
#' A new simplified version of the Perez diffuse irradiance model for tilted
#' surfaces. Solar Energy 39(3), 221-232.
#' \doi{10.1016/0038-092X(87)90015-2}
#'
#' Loutzenhiser, P. G., et al. (2007). Empirical validation of models to
#' compute solar irradiance on inclined surfaces for building energy simulation.
#' Solar Energy, 81, 254-267.
#' \doi{10.1016/j.solener.2006.03.009}
#'
#' @examples
#' \dontrun{
#' time <- seq(as.POSIXct("2026-01-15 06:00", tz = "UTC"),
#'             by = "hour", length.out = 12)
#' GHI <- c(50, 200, 450, 700, 850, 950, 1000, 950, 850, 700, 450, 200)
#'
#' # First decompose GHI to get DNI and DHI
#' decomposed <- erbs_decomposition(time, lat = -30.6279, lon = 24.0054, GHI = GHI)
#'
#' # Then apply Perez transposition
#' result <- perez_transposition(
#'   time = time,
#'   lat = -30.6279,
#'   lon = 24.0054,
#'   GHI = GHI,
#'   DNI = decomposed$DNI,
#'   DHI = decomposed$DHI,
#'   tilt = 20,
#'   azimuth = 0
#' )
#' }
#'
#' @export
#'
perez_transposition <- function(
  time,
  lat,
  lon,
  GHI,
  DNI,
  DHI,
  tilt,
  azimuth,
  albedo = 0.2,
  solar_constant = 1366.1
) {
  stopifnot(length(time) == length(GHI))
  stopifnot(length(time) == length(DNI))
  stopifnot(length(time) == length(DHI))

  # Convert time to Julian Day
  jd <- JD(time)

  # Extract timezone from POSIXct object (in hours)
  tz_offset <- as.numeric(format(time[1], "%z")) / 100

  # Calculate sun vector and position
  sv <- sunvector(jd, lat, lon, tz_offset)
  sp <- sunpos(sv)

  # Extract zenith and azimuth
  theta_z_deg <- sp[, 2]  # Solar zenith angle in degrees
  sun_az_deg <- sp[, 1]   # Solar azimuth angle in degrees

  # =========================================================================
  # Calculate Angle of Incidence (AOI)
  # =========================================================================

  # Panel tilt and azimuth in radians
  beta <- tilt * pi / 180
  panel_az <- azimuth * pi / 180

  # Solar zenith and azimuth in radians
  theta_z <- theta_z_deg * pi / 180
  sun_az <- sun_az_deg * pi / 180

  # Calculate AOI projection (cosine of angle of incidence)
  cos_aoi <- (cos(beta) * cos(theta_z) +
                sin(beta) * sin(theta_z) * cos(sun_az - panel_az))
  cos_aoi <- pmax(-1, pmin(1, cos_aoi))  # Clip to valid range

  # Angle of incidence in degrees
  aoi_deg <- acos(cos_aoi) * 180 / pi

  # =========================================================================
  # Calculate Relative Airmass
  # =========================================================================
  # Use Kasten and Young (1989) formula
  cos_z <- cos(theta_z)
  airmass <- 1 / (cos_z + 0.50572 * (96.07995 - theta_z_deg)^-1.6364)
  airmass[theta_z_deg >= 90] <- NA  # Nighttime

  # =========================================================================
  # Calculate Extraterrestrial Radiation
  # =========================================================================

  doy <- as.numeric(format(time, "%j"))
  dni_extra <- get_extra_radiation_spencer(doy, solar_constant)

  # =========================================================================
  # Perez (1990) Sky Diffuse Model Parameters
  # =========================================================================

  # Delta: Sky brightness parameter
  # delta = DHI * airmass / dni_extra
  delta <- DHI * airmass / dni_extra

  # Epsilon: Sky clearness parameter
  # eps = (DHI + DNI) / DHI + kappa * z^3) / (1 + kappa * z^3)
  kappa <- 1.041  # For solar_zenith in radians
  z <- theta_z  # Zenith in radians

  eps <- ((DHI + DNI) / DHI + kappa * z^3) / (1 + kappa * z^3)

  # Bin epsilon into 8 categories
  # Perez et al define clearness bins according to specific rules
  # 1 = overcast ... 8 = clear
  ebin <- as.integer(cut(eps, breaks = c(-Inf, 1.065, 1.23, 1.5, 1.95, 2.8, 4.5, 6.2, Inf),
                         labels = FALSE, right = TRUE))

  # Set NA eps to bin 9 (will get NaN coefficients)
  # This matches pvlib's behavior where invalid eps gets NaN coefficients
  ebin[is.na(eps)] <- 9

  # =========================================================================
  # Get Perez Coefficients (allsitescomposite1990)
  # =========================================================================

  # F1 and F2 coefficients for each bin (8 rows x 3 columns)
  # Each row: [constant, delta_coef, zenith_coef]
  # Row 9 is for invalid epsilon values (all NaN)
  F1c <- matrix(c(
    -0.008,  0.588, -0.062,
     0.130,  0.683, -0.151,
     0.330,  0.487, -0.221,
     0.568,  0.187, -0.295,
     0.873, -0.392, -0.362,
     1.132, -1.237, -0.412,
     1.060, -1.600, -0.359,
     0.678, -0.327, -0.250,
     NA,     NA,     NA
  ), nrow = 9, ncol = 3, byrow = TRUE)

  F2c <- matrix(c(
    -0.060,  0.072, -0.022,
    -0.019,  0.066, -0.029,
     0.055, -0.064, -0.026,
     0.109, -0.152, -0.014,
     0.226, -0.462,  0.001,
     0.288, -0.823,  0.056,
     0.264, -1.127,  0.131,
     0.156, -1.377,  0.251,
     NA,     NA,     NA
  ), nrow = 9, ncol = 3, byrow = TRUE)

  # Calculate F1 and F2 for each observation
  # F1 = F1c[ebin, 1] + F1c[ebin, 2] * delta + F1c[ebin, 3] * z
  F1 <- F1c[ebin, 1] + F1c[ebin, 2] * delta + F1c[ebin, 3] * z
  F1 <- pmax(F1, 0)  # F1 must be >= 0

  # F2 = F2c[ebin, 1] + F2c[ebin, 2] * delta + F2c[ebin, 3] * z
  F2 <- F2c[ebin, 1] + F2c[ebin, 2] * delta + F2c[ebin, 3] * z

  # =========================================================================
  # Perez (1990) Sky Diffuse Calculation
  # =========================================================================
  # I_d = DHI * [(1 - F1) * (1 + cos(beta))/2 + F1 * A/B + F2 * sin(beta)]

  # A: cosine of angle of incidence (must be >= 0)
  A <- pmax(cos_aoi, 0)

  # B: cosine of zenith angle (lower limit to cos(85°))
  B <- pmax(cos_z, cos(85 * pi / 180))

  # Three components of sky diffuse
  # Isotropic component
  term1 <- 0.5 * (1 - F1) * (1 + cos(beta))

  # Circumsolar component
  term2 <- F1 * A / B

  # Horizon brightening component
  term3 <- F2 * sin(beta)

  # Total sky diffuse
  poa_sky_diffuse <- pmax(DHI * (term1 + term2 + term3), 0)

  # Set nighttime values to zero
  poa_sky_diffuse[is.na(airmass)] <- 0

  # =========================================================================
  # Beam Component (Direct Normal Irradiance projected onto tilted surface)
  # =========================================================================

  poa_beam <- DNI * pmax(cos_aoi, 0)

  # =========================================================================
  # Ground Reflected Diffuse Component (Isotropic)
  # =========================================================================

  poa_ground_diffuse <- GHI * albedo * 0.5 * (1 - cos(beta))

  # =========================================================================
  # Total POA Irradiance
  # =========================================================================

  poa_diffuse <- poa_sky_diffuse + poa_ground_diffuse
  poa_global <- poa_beam + poa_diffuse

  # Set nighttime values to zero
  nighttime <- cos_z <= 0
  poa_global[nighttime] <- 0
  poa_beam[nighttime] <- 0
  poa_sky_diffuse[nighttime] <- 0
  poa_ground_diffuse[nighttime] <- 0
  poa_diffuse[nighttime] <- 0

  data.frame(
    time = time,
    GHI = GHI,
    DNI = DNI,
    DHI = DHI,
    poa_global = poa_global,
    poa_beam = poa_beam,
    poa_sky_diffuse = poa_sky_diffuse,
    poa_ground_diffuse = poa_ground_diffuse,
    poa_diffuse = poa_diffuse,
    zenith = theta_z_deg,
    azimuth = sun_az_deg,
    incidence = aoi_deg,
    epsilon = eps,
    delta = delta,
    ebin = as.integer(ebin),
    F1 = F1,
    F2 = F2
  )
}
