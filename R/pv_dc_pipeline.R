#' @title Modular PV DC Power Pipeline
#'
#' @description Computes DC power by combining independently selected
#' transposition and cell temperature models with the PVWatts DC model.
#'
#' This function allows any combination of:
#' \itemize{
#'   \item \strong{Transposition models}: "olmo" (Olmo et al.) or "haydavies" (Erbs + Hay-Davies)
#'   \item \strong{Cell temperature models}: "skoplaki" or "faiman"
#' }
#'
#' @param time POSIXct vector of times (UTC recommended)
#' @param lat Latitude in degrees
#' @param lon Longitude in degrees
#' @param GHI Global horizontal irradiance (W/m^2)
#' @param T_air Ambient air temperature (deg C)
#' @param wind Wind speed (m/s)
#' @param tilt Panel tilt angle (degrees)
#' @param azimuth Panel azimuth (degrees, 0 = north)
#' @param albedo Ground albedo (default 0.2)
#' @param transposition_model Transposition model: "olmo" or "haydavies" (default "olmo")
#' @param cell_temp_model Cell temperature model: "skoplaki" or "faiman" (default "skoplaki")
#' @param iam_exp IAM exponent for power-law model. Default 0.05. Set to NA or
#'   FALSE to disable IAM correction.
#' @param P_dc0 DC nameplate power (W, default 230 for Trina TSM-230 PC05 module)
#' @param gamma Temperature coefficient of max power (1/K, default -0.0043)
#' @param min_cos_zenith Minimum value of cos(zenith) for Hay-Davies Rb calculation.
#'   Default: 0.01745. Only used for "haydavies" transposition.
#' @param skoplaki_variant Either "model1" or "model2" (default "model1").
#'   Only used for "skoplaki" cell temperature model.
#' @param T_NOCT Nominal Operating Cell Temperature (deg C, default 45).
#'   Only used for "skoplaki" cell temperature model.
#' @param T_a_NOCT Ambient temperature at NOCT conditions (deg C, default 20).
#'   Only used for "skoplaki" cell temperature model.
#' @param I_NOCT Irradiance at NOCT conditions (W/m^2, default 800).
#'   Only used for "skoplaki" cell temperature model.
#' @param v_NOCT Wind speed at NOCT conditions (m/s, default 1).
#'   Only used for "skoplaki" cell temperature model.
#' @param eta_STC Module efficiency at STC (default 0.141).
#'   Only used for "skoplaki" cell temperature model.
#' @param tau_alpha Product of transmittance and absorption coefficient (default 0.9).
#'   Only used for "skoplaki" cell temperature model.
#' @param u0 Combined heat loss factor coefficient for Faiman model.
#'   Default 25.0 W/(m²·°C). Only used for "faiman" cell temperature model.
#' @param u1 Combined heat loss factor influenced by wind for Faiman model.
#'   Default 6.84 W/(m²·°C·m/s). Only used for "faiman" cell temperature model.
#'
#' @return Data frame with columns varying by model selection. Always includes:
#' time, GHI, G_poa, T_air, wind, T_cell, P_dc, zenith, incidence, iam (if IAM enabled).
#' May also include: sun_azimuth (olmo), azimuth/DNI/DHI/ai/rb (haydavies), skoplaki (skoplaki).
#'
#' @seealso
#' \code{\link{olmo_transposition}} for Olmo transposition model details
#' \code{\link{erbs_decomposition}} for Erbs decomposition model details
#' \code{\link{haydavies_transposition}} for Hay-Davies transposition details
#' \code{\link{skoplaki_cell_temperature}} for Skoplaki cell temperature details
#' \code{\link{faiman_cell_temperature}} for Faiman cell temperature details
#' \code{\link{pvwatts_dc}} for DC power model details
#' \code{\link{pv_dc_ensemble}} for ensemble estimates from all model combinations
#'
#' @export
#'
pv_dc_pipeline <- function(
  time,
  lat, lon,
  GHI,
  T_air,
  wind,
  tilt,
  azimuth,
  albedo = 0.2,
  transposition_model = c("olmo", "haydavies"),
  cell_temp_model = c("skoplaki", "faiman"),
  iam_exp = 0.05,
  P_dc0 = 230,
  gamma = -0.0043,
  min_cos_zenith = 0.01745,
  skoplaki_variant = c("model1", "model2"),
  T_NOCT = 45,
  T_a_NOCT = 20,
  I_NOCT = 800,
  v_NOCT = 1,
  eta_STC = 0.141,
  tau_alpha = 0.9,
  u0 = 25.0,
  u1 = 6.84
) {
  transposition_model <- match.arg(transposition_model)
  cell_temp_model <- match.arg(cell_temp_model)
  skoplaki_variant <- match.arg(skoplaki_variant)

  stopifnot(
    length(time) == length(GHI),
    length(GHI) == length(T_air),
    length(T_air) == length(wind)
  )

  # =========================================================================
  # Step 1: Transposition (GHI -> G_poa)
  # =========================================================================
  if (transposition_model == "olmo") {
    transp_out <- olmo_transposition(
      time = time,
      lat = lat,
      lon = lon,
      GHI = GHI,
      tilt = tilt,
      azimuth = azimuth,
      albedo = albedo
    )
    G_poa <- transp_out$G_poa
    zenith <- transp_out$zenith
    incidence <- transp_out$incidence
    sun_azimuth <- transp_out$sun_azimuth
    # For olmo, use zenith as sun_azimuth equivalent for consistency
    azimuth_out <- zenith
  } else {  # haydavies
    # First decompose GHI
    erbs_out <- erbs_decomposition(
      time = time,
      lat = lat,
      lon = lon,
      GHI = GHI
    )

    # Then apply Hay-Davies transposition
    transp_out <- haydavies_transposition(
      time = time,
      lat = lat,
      lon = lon,
      GHI = GHI,
      DNI = erbs_out$DNI,
      DHI = erbs_out$DHI,
      tilt = tilt,
      azimuth = azimuth,
      albedo = albedo,
      min_cos_zenith = min_cos_zenith
    )
    G_poa <- transp_out$poa_global
    zenith <- transp_out$zenith
    incidence <- transp_out$incidence
    azimuth_out <- transp_out$azimuth
    sun_azimuth <- transp_out$azimuth
  }

  # =========================================================================
  # Step 2: Cell Temperature (G_poa, T_air, wind -> T_cell)
  # =========================================================================
  if (cell_temp_model == "skoplaki") {
    T_cell <- skoplaki_cell_temperature(
      G_poa = G_poa,
      T_air = T_air,
      wind = wind,
      variant = skoplaki_variant,
      gamma = gamma,
      T_NOCT = T_NOCT,
      T_a_NOCT = T_a_NOCT,
      I_NOCT = I_NOCT,
      v_NOCT = v_NOCT,
      eta_STC = eta_STC,
      tau_alpha = tau_alpha
    )
  } else {  # faiman
    T_cell <- faiman_cell_temperature(
      poa_global = G_poa,
      temp_air = T_air,
      wind_speed = wind,
      u0 = u0,
      u1 = u1
    )
  }

  # =========================================================================
  # Step 3: PVWatts DC power (G_poa, T_cell, incidence -> P_dc)
  # =========================================================================
  if (isFALSE(iam_exp) || is.na(iam_exp)) {
    incidence_param <- NULL
    iam_exp_param <- NA
    iam_values <- NA
  } else {
    incidence_param <- incidence
    iam_exp_param <- iam_exp
    cos_theta <- pmax(0, cos(incidence * pi / 180))
    iam_values <- cos_theta ^ iam_exp
  }

  P_dc <- pvwatts_dc(
    G_poa = G_poa,
    T_cell = T_cell,
    incidence = incidence_param,
    iam_exp = iam_exp_param,
    P_dc0 = P_dc0,
    gamma = gamma
  )

  # =========================================================================
  # Step 4: Combine results
  # =========================================================================
  result <- data.frame(
    time = time,
    GHI = GHI,
    G_poa = G_poa,
    T_air = T_air,
    wind = wind,
    T_cell = T_cell,
    P_dc = P_dc,
    zenith = zenith,
    incidence = incidence
  )

  # Add model identifiers
  result$transposition <- transposition_model
  result$cell_temp <- cell_temp_model

  # Add model-specific columns
  if (transposition_model == "olmo") {
    result$sun_azimuth <- sun_azimuth
  } else {  # haydavies
    result$DNI <- transp_out$DNI
    result$DHI <- transp_out$DHI
    result$azimuth <- azimuth_out
    result$ai <- transp_out$ai
    result$rb <- transp_out$rb
  }

  if (cell_temp_model == "skoplaki") {
    result$skoplaki <- skoplaki_variant
  }

  # Add IAM column if IAM was enabled
  if (!isFALSE(iam_exp) && !is.na(iam_exp)) {
    result$iam <- iam_values
  }

  result
}
