#' @title PV DC Power Pipeline: Olmo + Skoplaki + PVWatts
#'
#' @description Computes DC power using the Olmo et al. transposition model for POA irradiance,
#' Skoplaki cell temperature (Equation 41), and PVWatts DC power model.
#'
#' The Olmo et al. transposition model (Olmo et al., 1999) converts horizontal global
#' irradiance to plane-of-array irradiance without decomposing into direct and diffuse
#' components. The model uses:
#' \deqn{I_{\gamma} = I \cdot \psi_o \cdot F_c}
#' where \eqn{\psi_o = \exp(-k_t(\theta^2 - \theta_z^2))} is the conversion function based on
#' clearness index \eqn{k_t} and the difference between incidence angle \eqn{\theta} and
#' zenith angle \eqn{\theta_z} (in radians), and \eqn{F_c = 1 + \rho \sin^2(\theta/2)} is
#' the ground reflection multiplying factor.
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
#' @param albedo Ground albedo (default 0.2). Note: Olmo et al. used 0.25 in their original
#' study at Granada, Spain.
#'
#' @param P_dc0 DC nameplate power (W, default 230 for Trina TSM-230 PC05 module)
#'
#' @param gamma Temperature coefficient of max power (1/K, default -0.0043 for TSM-230)
#'
#' @param skoplaki_variant Either "model1" or "model2" (default "model1"). Model 1 uses
#' h_w = 8.91 + 2.00*v_f (Equation 42), Model 2 uses h_w = 5.7 + 3.8*v_w where
#' v_w = 0.68*v_f - 0.5 (Equations 43-44).
#'
#' @param T_NOCT Nominal Operating Cell Temperature in °C (default 45 for TSM-230)
#'
#' @param T_a_NOCT Ambient temperature at NOCT conditions in °C (default 20)
#'
#' @param I_NOCT Irradiance at NOCT conditions in W/m² (default 800)
#'
#' @param v_NOCT Wind speed at NOCT conditions in m/s (default 1)
#'
#' @param eta_STC Module efficiency at STC (default 0.141 for TSM-230)
#'
#' @param tau_alpha Product of transmittance and absorption coefficient (default 0.9)
#'
#' @return Data frame with columns: time, GHI, G_poa, T_air, wind, T_cell, P_dc,
#' zenith, sun_azimuth, incidence, skoplaki
#'
#' @references
#' Olmo, F. J., Vida, J., Foyo, I., Castro-Diez, Y., & Alados-Arboledas, L. (1999).
#' Prediction of global irradiance on inclined surfaces from horizontal global irradiance.
#' Energy, 24(8), 689-704. \doi{10.1016/S0360-5442(99)00025-0}
#'
#' Ayvazoğluyüksel, Ö., & Başaran Filik, Ü. (2018). Estimation methods of global
#' solar radiation, cell temperature and solar power forecasting: A review and
#' case study in Eskişehir. Renewable and Sustainable Energy Reviews, 91, 639-653.
#' \doi{10.1016/j.rser.2018.03.084}
#'
#' Skoplaki, E., Boudouvis, A. G., & Palyvos, J. A. (2008). A simple correlation
#' for the operating temperature of photovoltaic modules of arbitrary mounting.
#' Solar Energy Materials and Solar Cells, 92(11), 1393-1402.
#' \doi{10.1016/j.solmat.2008.05.016}
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
  skoplaki_variant = c("model1", "model2"),
  T_NOCT = 45,
  T_a_NOCT = 20,
  I_NOCT = 800,
  v_NOCT = 1,
  eta_STC = 0.141,
  tau_alpha = 0.9
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

  # Extract zenith and azimuth from sunpos (column 2 = zenith, column 1 = azimuth)
  theta_z_deg <- sp[, 2]  # Solar zenith angle in degrees
  sun_az_deg <- sp[, 1]   # Solar azimuth angle in degrees
  theta_z <- theta_z_deg * pi / 180  # Convert to radians

  # Calculate panel normal vector
  beta <- tilt * pi / 180
  az <- azimuth * pi / 180
  n <- c(
    sin(beta) * sin(az),
    sin(beta) * cos(az),
    cos(beta)
  )

  # Calculate angle of incidence (theta)
  theta <- acos(pmax(-1, pmin(1, sv %*% n)))  # Incidence angle in radians
  theta_deg <- theta * 180 / pi  # Convert to degrees

  # =========================================================================
  # Olmo et al. (1999) Transposition Model - Equations 33-39 from paper
  # Reference: Olmo et al., Energy 24(8):689-704, 1999
  # As described in Ayvazoğluyüksel & Başaran Filik (2018), Section 3.2.1
  # =========================================================================

  # Solar constant (W/m²)
  I_sol <- 1367

  # Day of year
  doy <- as.numeric(format(time, "%j"))

  # Solar declination (radians) - using more accurate formula
  day_angle <- 2 * pi * (doy - 1) / 365
  declination <- (180 / pi) * (0.006918 - 0.399912 * cos(day_angle) +
                                 0.070257 * sin(day_angle) -
                                 0.006758 * cos(2 * day_angle) +
                                 0.000907 * sin(2 * day_angle) -
                                 0.002697 * cos(3 * day_angle) +
                                 0.00148 * sin(3 * day_angle))
  delta <- declination * pi / 180  # Convert to radians

  # Hour angle (from solar time)
  # For simplicity, we'll derive it from the sun vector calculation
  # cos(theta_z) = sin(phi)*sin(delta) + cos(phi)*cos(delta)*cos(omega)
  phi <- lat * pi / 180  # Latitude in radians

  # Equation 33: Extraterrestrial radiation on horizontal surface
  # I_0 = I_sol * (1 + 0.033*cos(360*d/365)) * (cos(phi)*cos(delta)*cos(W) + sin(phi)*sin(delta))
  # Note: cos(phi)*cos(delta)*cos(W) + sin(phi)*sin(delta) = cos(theta_z)
  eccentricity <- 1 + 0.033 * cos(2 * pi * doy / 365)
  cosz <- cos(theta_z)
  I_0 <- I_sol * eccentricity * pmax(0, cosz)

  # Equation 36: Clearness index
  # k_t = I / I_0 (only when I_0 > 0)
  k_t <- ifelse(I_0 > 0, pmin(GHI / I_0, 1), 0)

  # Equation 37: Multiplying factor (ground reflection)
  # F_c = 1 + rho * sin^2(theta/2)
  F_c <- 1 + albedo * sin(theta / 2)^2

  # Equation 38: Conversion function psi_o
  # psi_o = exp(-k_t * ((theta)^2 - (theta_z)^2))
  # where theta and theta_z are in radians
  psi_o <- exp(-k_t * (theta^2 - theta_z^2))

  # Equation 39: Global radiation on inclined surface
  # I_gamma = I * psi_o * F_c
  G_poa <- pmax(0, GHI * psi_o * F_c)

  # Handle nighttime (when sun is below horizon)
  G_poa[cosz <= 0] <- 0

  # =========================================================================
  # Skoplaki Cell Temperature Model - Equation 41 from paper
  # Reference: Skoplaki et al., Solar Energy Materials and Solar Cells 92:1393-1402, 2008
  # =========================================================================

  # Calculate wind convection coefficient at NOCT
  if (skoplaki_variant == "model1") {
    # Equation 42: h_w = 8.91 + 2.00 * v_f
    h_w_NOCT <- 8.91 + 2.00 * v_NOCT
    h_w <- 8.91 + 2.00 * wind
  } else {  # model2
    # Equations 43-44: v_w = 0.68 * v_f - 0.5; h_w = 5.7 + 3.8 * v_w
    v_w_NOCT <- pmax(0, 0.68 * v_NOCT - 0.5)
    h_w_NOCT <- 5.7 + 3.8 * v_w_NOCT
    v_w <- pmax(0, 0.68 * wind - 0.5)
    h_w <- 5.7 + 3.8 * v_w
  }

  # Skoplaki cell temperature model (Equation 41 from paper)
  # Reference: Ayvazoğluyüksel & Başaran Filik (2018), Equation 41
  T_STC <- 25  # Standard test condition temperature

  # Equation 41:
  # T_c = (T_a + (I/I_NOCT)(T_NOCT - T_a,NOCT)(h_w,NOCT/h_w)(1 - (eta_STC/tau_alpha)(1 - beta*T_STC)))
  #       / (1 - (beta*eta_STC/tau_alpha)(I/I_NOCT)(T_NOCT - T_a,NOCT)(h_w,NOCT/h_w))
  #
  # Note: beta (gamma) is negative, so (1 - gamma*T_STC) > 1 for typical values

  irrad_ratio <- G_poa / I_NOCT
  temp_diff <- T_NOCT - T_a_NOCT
  wind_ratio <- h_w_NOCT / h_w

  # Numerator term: (1 - (eta_STC/tau_alpha) * (1 - gamma * T_STC))
  numerator_factor <- 1 - (eta_STC / tau_alpha) * (1 - gamma * T_STC)

  numerator <- T_air + irrad_ratio * temp_diff * wind_ratio * numerator_factor

  # Denominator: 1 - (gamma * eta_STC / tau_alpha) * (I/I_NOCT) * (T_NOCT - T_a,NOCT) * (h_w,NOCT/h_w)
  denominator <- 1 - (gamma * eta_STC / tau_alpha) * irrad_ratio * temp_diff * wind_ratio

  T_cell <- numerator / denominator

  # =========================================================================
  # PVWatts DC Power Model
  # =========================================================================

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
    zenith = theta_z_deg,
    sun_azimuth = sun_az_deg,
    incidence = theta_deg,
    skoplaki = skoplaki_variant
  )
}
