#' @title PV DC Power Pipeline: Olmo + Skoplaki + PVWatts
#'
#' @description Computes DC power using Olmo transposition for POA irradiance, Skoplaki cell temperature, and PVWatts model.
#'
#' @param time POSIXct vector of times (UTC recommended)
#'
#' @param lat Latitude in degrees
#'
#' @param lon Longitude in degrees
#'
#' @param GHI Global horizontal irradiance (W/m^2)
#'
#' @param T_air Ambient air temperature (°C)
#'
#' @param wind Wind speed (m/s)
#'
#' @param tilt Panel tilt angle (degrees)
#'
#' @param azimuth Panel azimuth (degrees, 0 = north)
#'
#' @param albedo Ground albedo (default 0.2)
#'
#' @param P_dc0 DC nameplate power (W, default 230 for Trina module)
#'
#' @param gamma Temperature coefficient (1/K, default -0.0043)
#'
#' @param skoplaki_variant "linear" or "ratio" (default "linear")
#'
#' @param a Skoplaki linear a (default 28)
#'
#' @param b Skoplaki linear b (default -1)
#'
#' @param u0 Skoplaki ratio u0 (default 25)
#'
#' @param u1 Skoplaki ratio u1 (default 6)
#'
#' @return Data frame with G_poa, T_cell, P_dc, etc.
#'
#' @export
#'
pv_dc_olmo_skoplaki_pvwatts <- function(
  time,
  lat, lon,
  GHI,
  T_air,
  wind,
  tilt,
  azimuth,
  albedo = 0.2,
  P_dc0 = 230,
  gamma = -0.0043,
  skoplaki_variant = c("linear", "ratio"),
  a = 28,
  b = -1,
  u0 = 25,
  u1 = 6
) {
  skoplaki_variant <- match.arg(skoplaki_variant)
  stopifnot(
    length(time) == length(GHI),
    length(GHI) == length(T_air),
    length(T_air) == length(wind)
  )
  # Convert time to Julian Day
  jd <- JD(time)
  # Extract timezone from POSIXct object (in hours)
  # If time is UTC, tz_offset will be 0
  tz_offset <- as.numeric(format(time[1], "%z")) / 100
  # Calculate sun vector and position
  sv <- sunvector(jd, lat, lon, tz_offset)
  sp <- sunpos(sv)
  # Extract zenith from matrix (column 2)
  theta_z <- sp[, 2] * pi/180
  beta <- tilt * pi/180
  az <- azimuth * pi/180
  n <- c(
    sin(beta) * sin(az),
    sin(beta) * cos(az),
    cos(beta)
  )
  theta <- acos(pmax(-1, pmin(1, sv %*% n)))
  cosz <- cos(theta_z)
  cost <- cos(theta)
  R_T <- ifelse(
    cosz > 0,
    cost / cosz + albedo * (1 - cos(beta)) / 2,
    0
  )
  G_poa <- pmax(0, GHI * R_T)
  T_cell <- switch(
    skoplaki_variant,
    linear = T_air + (G_poa / 1000) * (a + b * wind),
    ratio = T_air + G_poa / (u0 + u1 * wind)
  )
  P_dc <- P_dc0 * (G_poa / 1000) * (1 + gamma * (T_cell - 25))
  P_dc[P_dc < 0] <- 0
  data.frame(
    time = time,
    GHI = GHI,
    G_poa = G_poa,
    T_air = T_air,
    wind = wind,
    T_cell = T_cell,
    P_dc = P_dc,
    zenith = sp[, 2],
    azimuth = sp[, 1],
    incidence = theta * 180/pi,
    skoplaki = skoplaki_variant
  )
}
