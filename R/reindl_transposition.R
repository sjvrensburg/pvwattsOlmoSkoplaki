#' Reindl (1990) Anisotropic Transposition Model
#'
#' @description
#' Convert horizontal irradiance to plane-of-array (POA) irradiance using the
#' Reindl et al. (1990) anisotropic sky model.
#'
#' The Reindl model determines the total POA irradiance by combining:
#' \itemize{
#'   \item Beam component: Direct normal irradiance projected onto the tilted surface
#'   \item Sky diffuse component: Anisotropic model with circumsolar, isotropic, and horizon brightening parts
#'   \item Ground diffuse component: Isotropic reflection from the ground
#' }
#'
#' The sky diffuse irradiance is calculated as:
#' \deqn{I_{d} = DHI \left( A \cdot R_b + (1 - A) \left(\frac{1 + \cos\beta}{2}\right) \left(1 + \sqrt{\frac{BHI}{GHI}} \sin^3(\beta/2)\right) \right)}
#'
#' where \eqn{A = DNI / I_{extra}} is the anisotropy index, \eqn{R_b} is the
#' projection ratio (cosine of angle of incidence to cosine of zenith angle),
#' \eqn{BHI} is the beam horizontal irradiance, and \eqn{\beta} is the tilt angle.
#'
#' The Reindl model extends the Hay-Davies model by adding a horizon brightening
#' correction factor that accounts for increased diffuse radiation near the horizon.
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
#' @param min_cos_zenith Minimum value of cos(zenith) for Rb calculation. Default: 0.01745
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
#'   \item{ai}{Anisotropy index}
#'   \item{rb}{Projection ratio}
#' }
#'
#' @references
#' Reindl, D. T., Beckmann, W. A., & Duffie, J. A. (1990a). Diffuse fraction
#' correlations. Solar Energy, 45(1), 1-7. \doi{10.1016/0038-092X(90)90060-P}
#'
#' Reindl, D. T., Beckmann, W. A., & Duffie, J. A. (1990b). Evaluation of hourly
#' tilted surface radiation models. Solar Energy, 45(1), 9-17.
#' \doi{10.1016/0038-092X(90)90061-G}
#'
#' Loutzenhiser, P. G., et al. (2007). Empirical validation of models to
#' compute solar irradiance on inclined surfaces for building energy simulation.
#' Solar Energy, 81, 254-267. \doi{10.1016/j.solener.2006.03.009}
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
#' # Then apply Reindl transposition
#' result <- reindl_transposition(
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
reindl_transposition <- function(
  time,
  lat,
  lon,
  GHI,
  DNI,
  DHI,
  tilt,
  azimuth,
  albedo = 0.2,
  min_cos_zenith = 0.01745,
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
  # This is the dot product of panel normal and solar position unit vectors
  cos_aoi <- (cos(beta) * cos(theta_z) +
                sin(beta) * sin(theta_z) * cos(sun_az - panel_az))
  cos_aoi <- pmax(-1, pmin(1, cos_aoi))  # Clip to valid range

  # Angle of incidence in degrees
  aoi_deg <- acos(cos_aoi) * 180 / pi

  # =========================================================================
  # Calculate Projection Ratio (Rb)
  # =========================================================================

  cos_z <- cos(theta_z)
  cos_aoi <- pmax(0, cos_aoi)  # Negative values when sun is behind panel
  rb <- cos_aoi / pmax(cos_z, min_cos_zenith)

  # =========================================================================
  # Calculate Extraterrestrial Radiation and Anisotropy Index
  # =========================================================================

  doy <- as.numeric(format(time, "%j"))
  dni_extra <- get_extra_radiation_spencer(doy, solar_constant)

  # Anisotropy index: ratio of beam irradiance to extraterrestrial irradiance
  ai <- DNI / dni_extra
  ai <- pmax(0, pmin(1, ai))  # Constrain to [0, 1]

  # =========================================================================
  # Reindl (1990) Sky Diffuse Model
  # =========================================================================
  # Equation from Loutzenhiser et al. (2007), Eq. 8
  # I_d = DHI * (A * Rb + (1 - A) * ((1 + cos(beta))/2) * (1 + sqrt(BHI/GHI) * sin^3(beta/2)))

  # Beam horizontal irradiance (BHI)
  # BHI = GHI - DHI = DNI * cos(zenith)
  bhi <- GHI - DHI

  # Horizon brightening factor
  # Avoid division by zero and negative values under sqrt
  horizon_factor <- 1 + pmax(0, sqrt(pmax(0, bhi) / pmax(GHI, 1))) * sin(beta / 2)^3

  # Isotropic component term
  isotropic_term <- (1 - ai) * 0.5 * (1 + cos(beta)) * horizon_factor

  # Sky diffuse components
  poa_circumsolar <- pmax(0, DHI * ai * rb)
  poa_isotropic <- pmax(0, DHI * isotropic_term)

  # Total sky diffuse
  poa_sky_diffuse <- poa_circumsolar + poa_isotropic

  # =========================================================================
  # Beam Component (Direct Normal Irradiance projected onto tilted surface)
  # =========================================================================

  # Only beam irradiance when sun is in front of panel
  poa_beam <- DNI * pmax(0, cos_aoi)

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
    ai = ai,
    rb = rb
  )
}
