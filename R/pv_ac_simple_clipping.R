#' @title Simple AC Inverter Clipping
#'
#' @description Applies efficiency and clipping to DC power for AC output.
#'
#' @param P_dc DC power (W)
#'
#' @param n_inverters Number of inverters (default 20)
#'
#' @param inverter_kw kW per inverter (default 500)
#'
#' @param eta_inv Inverter efficiency (default 0.97)
#'
#' @return List with P_ac, clipped flag, P_ac_rated
#'
#' @export
#'
pv_ac_simple_clipping <- function(
  P_dc,
  n_inverters = 20,
  inverter_kw = 500,
  eta_inv = 0.97
) {
  P_ac_rated <- n_inverters * inverter_kw * 1000
  P_ac_uncapped <- eta_inv * P_dc
  P_ac <- pmin(P_ac_uncapped, P_ac_rated)
  list(
    P_ac = P_ac,
    clipped = P_ac_uncapped > P_ac_rated,
    P_ac_rated = P_ac_rated
  )
}
