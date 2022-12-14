library(targets)
library(tarchetypes)
library(tibble)
library(retry, tar_option_set(error = 'continue'))
suppressPackageStartupMessages(library(tidyverse))

options(tidyverse.quiet = TRUE)
tar_option_set(packages = c("tidyverse", "dataRetrieval", "urbnmapr", "rnaturalearth", "cowplot", "lubridate", "leaflet", "leafpop", "htmlwidgets"))

# Load functions needed by targets below
source("1_fetch/src/find_oldest_sites.R")
source("1_fetch/src/get_site_data.R")
source("2_process/src/tally_site_obs.R")
source("2_process/src/summarize_targets.R")
source("3_visualize/src/map_sites.R")
source("3_visualize/src/plot_site_data.R")
source("3_visualize/src/plot_data_coverage.R")
source("3_visualize/src/map_timeseries.R")

# Configuration
states <- c('AL','AZ','AR','CA','CO','CT','DE','DC','FL','GA','ID','IL','IN','IA',
            'KS','KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV','NH',
            'NJ','NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD','TN','TX',
            'UT','VT','VA','WA','WV','WI','WY','AK','HI','GU','PR')
parameter <- c('00060')


# Targets
list(
  # Identify oldest sites
  tar_target(oldest_active_sites, find_oldest_sites(states, parameter)),

  # Splitter target
  tar_target(nwis_inventory,
             oldest_active_sites %>%
               group_by(state_cd) %>%
               tar_group(),
             iteration = "group"),

  # Download the data
  tar_target(nwis_data,
             retry(get_site_data(nwis_inventory, nwis_inventory$state_cd, parameter),
                   when = "Ugh, the internet data transfer failed! Try again.", max_tries = 30),
             pattern = map(nwis_inventory)),

  # Tallying
  tar_target(tally,
             tally_site_obs(nwis_data),
             pattern = map(nwis_data)),

  # Plotting data coverage
  tar_target(
    plot_data_coverage_png,
    plot_data_coverage(tally, "3_visualize/out/data_coverage.png", parameter),
    format = "file"
  ),


  # Timeseries pngs
  tar_target(timeseries_png, plot_site_data(sprintf("3_visualize/out/timeseries_%s.png", unique(nwis_data$State)), nwis_data, parameter),
             pattern = map(nwis_data),
             format = "file"),


  # Summary time series
  tar_target(
    summary_state_timeseries_csv,
    command = summarize_targets('3_visualize/log/summary_state_timeseries.csv', names(timeseries_png)),
    format="file"
  ),


  # Map oldest sites
  tar_target(
    site_map_png,
    map_sites("3_visualize/out/site_map.png", oldest_active_sites),
    format = "file"
  ),

  # Leaflet map
  tar_target(
    timeseries_map_html,
    map_timeseries(oldest_active_sites, summary_state_timeseries_csv, "3_visualize/out/timeseries_map.html"),
    format = "file"
  )
)
