## code to prepare `geofabrik_zones` dataset goes here

# packages
library(sf)
library(jsonlite)
library(purrr)
library(httr)
library(dplyr)

# Download official description of geofabrik data.
geofabrik_zones = st_read("https://download.geofabrik.de/index-v1.json", stringsAsFactors = FALSE) %>%
  janitor::clean_names()

# Check the result
str(geofabrik_zones, max.level = 1, nchar.max = 64, give.attr = FALSE)

# There are a few problems with the ISO3166 columns (i.e. they are read as list
# columns with character(0) instead of NA/NULL).
my_fix_iso3166 = function(list_column) {
  vapply(
    list_column,
    function(x) {
      if (identical(x, character(0))) {
        NA_character_
      } else {
        paste(x, collapse = " ")
      }
    },
    character(1)
  )
}

# We used the paste function in the else case because there are a few record
# where the ISO3166 code is composed by two or more elements, such as c("PS", "IL")
# for Israel and Palestine, c("SN", "GM") for Senegal and Gambia. The same
# situation happens with the US states where the ISO3166 code is c("US", state).
geofabrik_zones$iso3166_2 = my_fix_iso3166(geofabrik_zones$iso3166_2)
geofabrik_zones$iso3166_1_alpha2 = my_fix_iso3166(geofabrik_zones$iso3166_1_alpha2)

# We need to preprocess the urls column since it was read in a JSON format:
# geofabrik_zones$urls[[1]]
# "{
#   \"pbf\": \"https:\\/\\/download.geofabrik.de\\/asia\\/afghanistan-latest.osm.pbf\",
#   \"bz2\": \"https:\\/\\/download.geofabrik.de\\/asia\\/afghanistan-latest.osm.bz2\",
#   \"shp\": \"https:\\/\\/download.geofabrik.de\\/asia\\/afghanistan-latest-free.shp.zip\",
#   \"pbf-internal\": \"https:\\/\\/osm-internal.download.geofabrik.de\\/asia\\/afghanistan-latest-internal.osm.pbf\",
#   \"history\": \"https:\\/\\/osm-internal.download.geofabrik.de\\/asia\\/afghanistan-internal.osh.pbf\",
#   \"taginfo\": \"https:\\/\\/taginfo.geofabrik.de\\/asia\\/afghanistan\\/\",
#   \"updates\": \"https:\\/\\/download.geofabrik.de\\/asia\\/afghanistan-updates\"
# }"

(geofabrik_urls = map_dfr(geofabrik_zones$urls, fromJSON))
geofabrik_zones$urls = NULL # This is just to remove the urls column

# From rbind.sf docs: If you need to cbind e.g. a data.frame to an sf, use
# data.frame directly and use st_sf on its result, or use bind_cols; see
# examples.
geofabrik_zones = st_sf(data.frame(geofabrik_zones, geofabrik_urls))

# Now we are going to add to the geofabrik_zones sf object other useful
# information for each pbf file such as it's content-length (i.e. the file size
# in bytes). We can get this information from the headers of each file.
# Idea from:
# https://stackoverflow.com/questions/2301009/get-file-size-before-downloading-counting-how-much-already-downloaded-httpru/2301030
geofabrik_zones[["pbf_file_size"]] <- 0

###############################################################################
###### RUN THE FOLLOWING CODE CAREFULLY SINCE IT CREATES HUNDREDS OF HEAD #####
###### REQUESTS THAT CAN BLOCK YOUR IP ADDRESS ################################
###############################################################################

my_pb <- txtProgressBar(min = 0, max = nrow(geofabrik_zones), style = 3)
for (i in seq_len(nrow(geofabrik_zones))) {
  my_ith_url <- geofabrik_zones[["pbf"]][[i]]
  geofabrik_zones[["pbf_file_size"]][[i]] <- as.numeric(headers(HEAD(my_ith_url))$`content-length`)
  setTxtProgressBar(my_pb, i)
}

# Add a new column named "level", which is used for spatial matching. It has
# four categories named "1", "2", "3", and "4", and it is based on the geofabrik
# column "parent". It is defined as follows:
# - level = 1 when parent == NA. This happens for the continents plus the
# Russian Federation. More precisely it occurs for: Africa, Antarctica, Asia,
# Australia and Oceania, Central America, Europe, North America, Russian
# Federation and South America;
# - level = 2 correspond to each continent subregion such as Italy, Great
# Britain, Spain, USA, Mexico, Belize, Morocco, Peru ...
# There are also a few exceptions that correspond to the Special Sub Regions
# (according to the geofabrik definition), which are: South Africa (includes
# Lesotho), Alps, Britain and Ireland, Germany + Austria + Switzerland, US
# Midwest, US Northeast, US Pacific, US South, US West and all US states;
# - level = 3 correspond to the subregions of level 2 region. For example the
# West Yorkshire, which is a subregion of England, is a level 3 zone.
# - level = 4 are the subregions of level 3 (mainly related to some small areas
# in Germany)

geofabrik_zones = geofabrik_zones %>%
  mutate(
    level = case_when(
      is.na(parent) ~ 1L,
      parent %in% c(
        "africa", "asia", "australia-oceania", "central-america", "europe",
        "north-america", "south-america", "great-britain"
      )             ~ 2L,
      parent %in% c(
        "baden-wuerttemberg", "bayern", "greater-london", "nordrhein-westfalen"
      )             ~ 4L,
      TRUE          ~ 3L
    )
  ) %>%
  select(id, name, parent, level, iso3166_1_alpha2, iso3166_2, pbf_file_size, everything())

# The end
usethis::use_data(geofabrik_zones, version = 3, overwrite = TRUE)

