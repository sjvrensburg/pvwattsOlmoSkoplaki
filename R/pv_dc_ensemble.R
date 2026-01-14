#' @title PV DC Power Ensemble - All Model Combinations
#'
#' @description Computes DC power using all combinations of transposition
#' and cell temperature models, returning results in a format suitable for
#' ensemble analysis.
#'
#' This function runs 4 model combinations:
#' \enumerate{
#'   \item Olmo transposition + Skoplaki cell temperature
#'   \item Olmo transposition + Faiman cell temperature
#'   \item Hay-Davies transposition + Skoplaki cell temperature
#'   \item Hay-Davies transposition + Faiman cell temperature
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
#' @param iam_exp IAM exponent for power-law model. Default 0.05. Set to NA or
#'   FALSE to disable IAM correction.
#' @param P_dc0 DC nameplate power (W, default 230 for Trina TSM-230 PC05 module)
#' @param gamma Temperature coefficient of max power (1/K, default -0.0043)
#' @param min_cos_zenith Minimum value of cos(zenith) for Hay-Davies Rb calculation.
#'   Default: 0.01745.
#' @param skoplaki_variant Either "model1" or "model2" (default "model1").
#' @param T_NOCT Nominal Operating Cell Temperature (deg C, default 45).
#' @param T_a_NOCT Ambient temperature at NOCT conditions (deg C, default 20).
#' @param I_NOCT Irradiance at NOCT conditions (W/m^2, default 800).
#' @param v_NOCT Wind speed at NOCT conditions (m/s, default 1).
#' @param eta_STC Module efficiency at STC (default 0.141).
#' @param tau_alpha Product of transmittance and absorption coefficient (default 0.9).
#' @param u0 Combined heat loss factor coefficient for Faiman model.
#'   Default 25.0 W/(m²·°C).
#' @param u1 Combined heat loss factor influenced by wind for Faiman model.
#'   Default 6.84 W/(m²·°C·m/s).
#'
#' @return Data frame with columns:
#' \itemize{
#'   \item time, GHI, T_air, wind - Input data
#'   \item model - Model combination identifier (e.g., "olmo_skoplaki")
#'   \item transposition - Transposition model used
#'   \item cell_temp - Cell temperature model used
#'   \item G_poa - Plane-of-array irradiance (W/m^2)
#'   \item T_cell - Cell temperature (deg C)
#'   \item P_dc - DC power output (W)
#'   \item iam - Incidence angle modifier (if IAM enabled)
#' }
#'
#' @examples
#' \dontrun{
#' time <- seq(as.POSIXct("2026-01-15 08:00", tz = "UTC"),
#'             by = "hour", length.out = 6)
#' GHI <- c(450, 700, 850, 950, 850, 700)
#' T_air <- c(26, 29, 32, 34, 32, 29)
#' wind <- c(3, 4, 4.5, 5, 4.5, 4)
#'
#' ensemble_result <- pv_dc_ensemble(
#'   time = time,
#'   lat = -30.6279,
#'   lon = 24.0054,
#'   GHI = GHI,
#'   T_air = T_air,
#'   wind = wind,
#'   tilt = 20,
#'   azimuth = 0
#' )
#'
#' # Calculate ensemble statistics
#' ensemble_stats <- aggregate(P_dc ~ time, data = ensemble_result,
#'                            FUN = function(x) c(mean = mean(x), sd = sd(x)))
#' }
#'
#' @seealso
#' \code{\link{pv_dc_pipeline}} for single model combination
#' \code{\link{pv_power_ensemble}} for full ensemble including AC power
#'
#' @export
#'
pv_dc_ensemble <- function(
  time,
  lat, lon,
  GHI,
  T_air,
  wind,
  tilt,
  azimuth,
  albedo = 0.2,
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
  skoplaki_variant <- match.arg(skoplaki_variant)

  # Define all model combinations
  combinations <- expand.grid(
    transposition = c("olmo", "haydavies"),
    cell_temp = c("skoplaki", "faiman"),
    stringsAsFactors = FALSE
  )

  # Run each combination
  results <- lapply(seq_len(nrow(combinations)), function(i) {
    combo <- combinations[i, ]

    result <- pv_dc_pipeline(
      time = time,
      lat = lat,
      lon = lon,
      GHI = GHI,
      T_air = T_air,
      wind = wind,
      tilt = tilt,
      azimuth = azimuth,
      albedo = albedo,
      transposition_model = combo$transposition,
      cell_temp_model = combo$cell_temp,
      iam_exp = iam_exp,
      P_dc0 = P_dc0,
      gamma = gamma,
      min_cos_zenith = min_cos_zenith,
      skoplaki_variant = skoplaki_variant,
      T_NOCT = T_NOCT,
      T_a_NOCT = T_a_NOCT,
      I_NOCT = I_NOCT,
      v_NOCT = v_NOCT,
      eta_STC = eta_STC,
      tau_alpha = tau_alpha,
      u0 = u0,
      u1 = u1
    )

    # Add model identifier
    result$model <- paste(combo$transposition, combo$cell_temp, sep = "_")

    # Return only common columns for ensemble comparison
    cols_to_keep <- c("time", "GHI", "T_air", "wind", "model", "transposition",
                      "cell_temp", "G_poa", "T_cell", "P_dc")
    if (!isFALSE(iam_exp) && !is.na(iam_exp)) {
      cols_to_keep <- c(cols_to_keep, "iam")
    }

    result[, cols_to_keep]
  })

  # Combine all results
  do.call(rbind, results)
}
