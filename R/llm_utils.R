#' Generate a Timestamp
#'
#' Returns the current system time formatted as a string.
#' Useful for logging purposes.
#'
#' @return Character string "YYYY-MM-DD HH:MM:SS"
llm_ts <- function() {
  format(Sys.time(), "%Y-%m-%d %H:%M:%S")
}