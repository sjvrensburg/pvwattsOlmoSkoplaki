#' Lookup Linke Turbidity from Climatological Database
#'
#' @description
#' Retrieve monthly climatological Linke turbidity values from the global
#' database distributed with pvlib-python. The database provides turbidity
#' values at 5 arcminute resolution (0.0833°) for any location worldwide.
#'
#' The Linke turbidity coefficient quantifies the atmospheric turbidity
#' (aerosols and water vapor) relative to a clean, dry atmosphere. Typical
#' values range from 2 (very clean) to 6+ (very polluted/humid).
#'
#' @param time Timestamps as POSIXct, POSIXlt, character, or numeric. Used to
#'   extract month for selecting appropriate turbidity values.
#' @param lat Latitude in decimal degrees (-90 to 90). Can be a single value
#'   or vector matching length of time.
#' @param lon Longitude in decimal degrees (-180 to 180). Can be a single value
#'   or vector matching length of time.
#' @param interp_turbidity Logical. If TRUE, interpolates monthly values to
#'   daily resolution using the day of year. If FALSE, returns the value for
#'   the month containing each timestamp. Default: TRUE
#' @param filepath Optional path to LinkeTurbidities.h5 file. If NULL (default),
#'   uses the file distributed with the package.
#'
#' @return Numeric vector of Linke turbidity values (dimensionless) matching
#'   the length of time.
#'
#' @details
#' The database contains monthly climatological values on a global 5 arcminute
#' grid (2160 × 4320 × 12 matrix). Values are interpolated from the nearest
#' grid point.
#'
#' **Data Source**: SoDa (Solar radiation Data) service, based on the worldwide
#' Linke turbidity database by Remund et al. (2003).
#'
#' **Grid Details**:
#' - Latitude: 90°N to 90°S (2160 points, 5 arcminute spacing)
#' - Longitude: -180° to 180° (4320 points, 5 arcminute spacing)
#' - Time: Monthly climatology (12 values per location)
#'
#' **Interpolation**: When \\code{interp_turbidity = TRUE}, monthly values are
#' interpolated to daily resolution using a sinusoidal fit through month
#' midpoints. This provides smooth daily variations.
#'
#' **Timezone Handling**: The month for turbidity lookup is determined from
#' the input time's \\strong{local timezone} (if specified), not UTC. For example:
#' \\itemize{
#'   \\item Input: "2026-01-15 23:00:00 SAST" (UTC+2) → Uses January's turbidity
#'   \\item Input: "2026-01-15 21:00:00 UTC" (same physical moment) → Uses January's turbidity
#' }
#' This approach is appropriate for monthly climatological data, where the calendar
#' month is the relevant index. Day-of-year interpolation (if enabled) also uses the
#' local date to determine position within the month.
#'
#' @references
#' Remund, J., Wald, L., Lefèvre, M., Ranchin, T., & Page, J. (2003).
#' Worldwide Linke turbidity information. Proceedings of the ISES Solar
#' World Congress, Göteborg, Sweden.
#'
#' @examples
#' \dontrun{
#' # Single location, multiple times
#' time <- seq(as.POSIXct("2026-01-01", tz = "UTC"),
#'             by = "month", length.out = 12)
#' tl <- lookup_linke_turbidity(time, lat = -30.6279, lon = 24.0054)
#'
#' # Multiple locations
#' time <- rep(as.POSIXct("2026-06-15", tz = "UTC"), 3)
#' lat <- c(-30.6, 40.7, 51.5)  # De Aar, New York, London
#' lon <- c(24.0, -74.0, -0.1)
#' tl <- lookup_linke_turbidity(time, lat, lon)
#'
#' # Without daily interpolation (monthly values only)
#' tl_monthly <- lookup_linke_turbidity(time, lat, lon, interp_turbidity = FALSE)
#' }
#'
#' @export
lookup_linke_turbidity <- function(
  time,
  lat,
  lon,
  interp_turbidity = TRUE,
  filepath = NULL
) {
  # Load hdf5r package
  if (!requireNamespace("hdf5r", quietly = TRUE)) {
    stop("Package 'hdf5r' is required for lookup_linke_turbidity(). ",
         "Install it with: install.packages('hdf5r')")
  }

  # Prepare time: standardize format and capture original timezone
  # Month selection uses local date (not UTC), which is appropriate for
  # climatological data indexed by calendar month
  time_info <- prepare_time_utc(time)
  time_utc <- time_info$time_utc
  original_tz <- time_info$original_tz

  # Convert back to local timezone for month/day extraction
  time_local <- restore_time_tz(time_utc, original_tz)
  time_lt <- as.POSIXlt(time_local)
  n <- length(time)

  # Recycle lat/lon if needed
  if (length(lat) == 1) lat <- rep(lat, n)
  if (length(lon) == 1) lon <- rep(lon, n)

  # Validate inputs
  stopifnot(length(lat) == n)
  stopifnot(length(lon) == n)
  stopifnot(all(lat >= -90 & lat <= 90))
  stopifnot(all(lon >= -180 & lon <= 180))

  # Get filepath to HDF5 file
  if (is.null(filepath)) {
    filepath <- system.file("extdata", "LinkeTurbidities.h5", package = "pvflux")
    if (filepath == "") {
      stop("LinkeTurbidities.h5 file not found in package installation")
    }
  }

  # Open HDF5 file and read data
  turbidity_values <- numeric(n)

  # Process each unique location to minimize file reads
  unique_coords <- unique(data.frame(lat = lat, lon = lon))

  # Open HDF5 file once
  h5file <- hdf5r::H5File$new(filepath, mode = "r")
  on.exit(h5file$close(), add = TRUE)

  # Read the LinkeTurbidity dataset
  lt_dataset <- h5file[["LinkeTurbidity"]]

  for (i in seq_len(nrow(unique_coords))) {
    # Get this location
    this_lat <- unique_coords$lat[i]
    this_lon <- unique_coords$lon[i]

    # Convert lat/lon to grid indices (1-based for R)
    # Note: File dimensions are [12 months, 4320 lon, 2160 lat]
    lat_index <- degrees_to_index(this_lat, 90, -90, 2160)
    lon_index <- degrees_to_index(this_lon, -180, 180, 4320)

    # Read 12 monthly values for this location
    # HDF5 indexing: [month, lon, lat]
    monthly_values <- lt_dataset[1:12, lon_index, lat_index]

    # Divide by 20 to get actual turbidity (stored as 20*TL)
    monthly_values <- as.numeric(monthly_values) / 20.0

    # Find all times at this location
    loc_mask <- lat == this_lat & lon == this_lon

    if (interp_turbidity) {
      # Interpolate to daily values
      turbidity_values[loc_mask] <- interpolate_turbidity(
        monthly_values,
        time_lt[loc_mask]
      )
    } else {
      # Use monthly values directly
      months <- time_lt$mon[loc_mask] + 1  # R months are 0-11, need 1-12
      turbidity_values[loc_mask] <- monthly_values[months]
    }
  }

  return(turbidity_values)
}


#' Convert Degrees to Grid Index
#'
#' @description
#' Convert latitude or longitude in degrees to array index for the
#' LinkeTurbidities grid.
#'
#' @param degrees Latitude or longitude in degrees
#' @param min_coord Minimum coordinate value (e.g., -90 for lat, -180 for lon)
#' @param max_coord Maximum coordinate value (e.g., 90 for lat, 180 for lon)
#' @param num_points Number of grid points (e.g., 2160 for lat, 4320 for lon)
#'
#' @return Integer index (1-based for R)
#'
#' @keywords internal
degrees_to_index <- function(degrees, min_coord, max_coord, num_points) {
  # Calculate grid spacing
  grid_spacing <- (max_coord - min_coord) / (num_points - 1)

  # Convert to index (1-based)
  # Add 0.5 for rounding to nearest grid point
  index <- round((degrees - min_coord) / grid_spacing) + 1

  # Clamp to valid range
  index <- pmax(1, pmin(num_points, index))

  return(as.integer(index))
}


#' Interpolate Monthly Turbidity to Daily Values
#'
#' @description
#' Interpolate 12 monthly Linke turbidity values to daily resolution using
#' day of year and sinusoidal fit through month midpoints.
#'
#' @param monthly_values Numeric vector of length 12 with monthly turbidity values
#' @param time_lt POSIXlt object with timestamps
#'
#' @return Numeric vector of daily interpolated turbidity values
#'
#' @keywords internal
interpolate_turbidity <- function(monthly_values, time_lt) {
  # Get day of year for each time (1-365/366)
  doy <- time_lt$yday + 1

  # Calculate month centers (day of year for middle of each month)
  # Assuming standard year (365 days)
  month_centers <- c(15, 46, 74, 105, 135, 166, 196, 227, 258, 288, 319, 349)

  # Extend to handle year wraparound
  # Add December at end and January at beginning
  extended_doys <- c(month_centers[12] - 365, month_centers, month_centers[1] + 365)
  extended_values <- c(monthly_values[12], monthly_values, monthly_values[1])

  # Linear interpolation
  interpolated <- approx(
    x = extended_doys,
    y = extended_values,
    xout = doy,
    method = "linear",
    rule = 2  # Use nearest value for extrapolation
  )$y

  return(interpolated)
}


#' Get Path to LinkeTurbidities Database
#'
#' @description
#' Returns the file path to the LinkeTurbidities.h5 database file
#' distributed with the package.
#'
#' @return Character string with full path to LinkeTurbidities.h5 file
#'
#' @examples
#' \dontrun{
#' # Get path to database file
#' db_path <- linke_turbidity_filepath()
#' file.exists(db_path)  # Should be TRUE
#' }
#'
#' @export
linke_turbidity_filepath <- function() {
  filepath <- system.file("extdata", "LinkeTurbidities.h5", package = "pvflux")
  if (filepath == "") {
    stop("LinkeTurbidities.h5 file not found in package installation")
  }
  return(filepath)
}
