#!/usr/bin/env Rscript
# Test script for clear-sky implementation

library(pvflux)

# Test location: De Aar, South Africa (from vignette)
lat <- -30.6279
lon <- 24.0054
altitude <- 1233  # meters (Mulilo De Aar PV plant)

# Create time series for a clear day in January
time <- seq(
  as.POSIXct("2026-01-15 06:00", tz = "Africa/Johannesburg"),
  as.POSIXct("2026-01-15 18:00", tz = "Africa/Johannesburg"),
  by = "hour"
)

cat("Testing clear-sky implementation for De Aar, South Africa\n")
cat("Date: 2026-01-15\n")
cat("Location: lat =", lat, ", lon =", lon, ", altitude =", altitude, "m\n\n")

# Test 1: Basic clear-sky irradiance calculation
cat(strrep("=", 60), "\n")
cat("Test 1: Basic clear-sky irradiance (ineichen_clearsky)\n")
cat(strrep("=", 60), "\n\n")

clearsky <- ineichen_clearsky(
  time = time,
  lat = lat,
  lon = lon,
  linke_turbidity = 3.0,
  altitude = altitude
)

print(head(clearsky, 8))
cat("\nSummary statistics:\n")
cat("Max GHI:", max(clearsky$ghi_clearsky), "W/m²\n")
cat("Max DNI:", max(clearsky$dni_clearsky), "W/m²\n")
cat("Max DHI:", max(clearsky$dhi_clearsky), "W/m²\n\n")

# Test 2: Simple Linke turbidity function
cat(strrep("=", 60), "\n")
cat("Test 2: Simple Linke turbidity (simple_linke_turbidity)\n")
cat(strrep("=", 60), "\n\n")

time_monthly <- seq(
  as.POSIXct("2026-01-01", tz = "UTC"),
  by = "month",
  length.out = 12
)

tl_rural <- simple_linke_turbidity(
  time_monthly,
  location_type = "rural",
  hemisphere = "south"
)

tl_urban <- simple_linke_turbidity(
  time_monthly,
  location_type = "urban",
  hemisphere = "south"
)

month_names <- format(time_monthly, "%B")
df_tl <- data.frame(
  Month = month_names,
  Rural = round(tl_rural, 2),
  Urban = round(tl_urban, 2)
)
print(df_tl)
cat("\n")

# Test 3: Clear-sky DC power pipeline
cat(strrep("=", 60), "\n")
cat("Test 3: Clear-sky DC power (pv_clearsky_dc_pipeline)\n")
cat(strrep("=", 60), "\n\n")

# Typical summer conditions
T_air <- rep(30, length(time))
wind <- rep(2.5, length(time))

dc_clearsky <- pv_clearsky_dc_pipeline(
  time = time,
  lat = lat,
  lon = lon,
  T_air = T_air,
  wind = wind,
  tilt = 30,
  azimuth = 0,
  linke_turbidity = 3.0,
  altitude = altitude,
  transposition_model = "haydavies",
  cell_temp_model = "skoplaki",
  P_dc0 = 230
)

print(head(dc_clearsky[, c("time", "ghi_clearsky", "G_poa", "T_cell", "P_dc")], 8))
cat("\nMax DC power:", max(dc_clearsky$P_dc), "W\n")
cat("Total daily energy:", sum(dc_clearsky$P_dc) / 1000, "kWh (hourly resolution)\n\n")

# Test 4: Clear-sky AC power pipeline
cat(strrep("=", 60), "\n")
cat("Test 4: Clear-sky AC power (pv_clearsky_power_pipeline)\n")
cat(strrep("=", 60), "\n\n")

ac_clearsky <- pv_clearsky_power_pipeline(
  time = time,
  lat = lat,
  lon = lon,
  T_air = T_air,
  wind = wind,
  tilt = 30,
  azimuth = 0,
  linke_turbidity = 3.0,
  altitude = altitude,
  n_inverters = 20,
  inverter_kw = 500,
  P_dc0 = 230
)

print(head(ac_clearsky[, c("time", "P_dc", "P_ac", "clipped")], 8))
cat("\nMax AC power:", max(ac_clearsky$P_ac), "W\n")
cat("Total daily AC energy:", sum(ac_clearsky$P_ac) / 1000, "kWh (hourly resolution)\n")
cat("Any clipping?", any(ac_clearsky$clipped), "\n\n")

# Test 5: Clear-sky index and performance ratio
cat(strrep("=", 60), "\n")
cat("Test 5: Clear-sky index and performance ratio\n")
cat(strrep("=", 60), "\n\n")

# Simulate cloudy conditions (70% of clear-sky)
GHI_measured <- clearsky$ghi_clearsky * 0.7
csi <- clearsky_index(GHI_measured, clearsky$ghi_clearsky)

# Simulate system with 80% of clear-sky performance
P_measured <- ac_clearsky$P_ac * 0.8
pr <- clearsky_performance_ratio(P_measured, ac_clearsky$P_ac)

df_performance <- data.frame(
  time = time,
  CSI = round(csi, 3),
  PR = round(pr, 3)
)
print(head(df_performance[!is.na(df_performance$CSI), ], 8))

cat("\nMean CSI (daylight hours):", round(mean(csi, na.rm = TRUE), 3), "\n")
cat("Mean PR (daylight hours):", round(mean(pr, na.rm = TRUE), 3), "\n\n")

# Test 6: Comparison of turbidity levels
cat(strrep("=", 60), "\n")
cat("Test 6: Effect of turbidity on clear-sky irradiance\n")
cat(strrep("=", 60), "\n\n")

test_time <- as.POSIXct("2026-01-15 12:00", tz = "Africa/Johannesburg")
turbidity_levels <- c(2.0, 3.0, 4.0, 5.0, 6.0)

results <- lapply(turbidity_levels, function(tl) {
  cs <- ineichen_clearsky(
    time = test_time,
    lat = lat,
    lon = lon,
    linke_turbidity = tl,
    altitude = altitude
  )
  data.frame(
    Turbidity = tl,
    GHI = round(cs$ghi_clearsky),
    DNI = round(cs$dni_clearsky),
    DHI = round(cs$dhi_clearsky)
  )
})

df_turbidity <- do.call(rbind, results)
print(df_turbidity)

cat("\nAll tests completed successfully!\n")
