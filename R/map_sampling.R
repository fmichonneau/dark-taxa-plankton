
us_raster <- function()
    raster(vals = NA, xmn = -127, ymn = 23, xmx = -61, ymx = 50, res = .2)

data_map_samples <- function(idig) {
    us_raster <- us_raster()
    pts <- SpatialPoints(data.frame(lon = idig$decimallongitude,
                                    lat = idig$decimallatitude))
    r <- rasterize(pts, us_raster, fun = "count")
    gg_r <- as.data.frame(as(r, "SpatialPixelsDataFrame"))
    colnames(gg_r) <- c("value", "x", "y")
    gg_r
}


data_map_diversity <- function(idig) {
    us_raster <- us_raster()
    raster_cell <- mapply(function(x, y) cellFromXY(us_raster, c(x, y)),
                          idig$decimallongitude, idig$decimallatitude)

    idig_r <- data.frame(idig, rastercell = raster_cell) %>%
        group_by(rastercell) %>%
        summarize(
            n_spp = length(unique(scientificname))
        )
    us_raster[na.omit(idig_r$rastercell)] <- idig_r$n_spp[!is.na(idig_r$rastercell)]
    gg_r <- as.data.frame(as(us_raster, "SpatialPixelsDataFrame"))
    colnames(gg_r) <- c("value", "x", "y")
    gg_r
}


data_map_standardized_diversity <- function(sampling, diversity) {
    sampling <- sampling %>%
        rename(n_specimen = value)
    diversity <- diversity %>%
        rename(n_species = value)

    res <- bind_cols(sampling, dplyr::select(diversity, n_species)) %>%
        dplyr::select(x, y, n_specimen, n_species) %>%
        mutate(value = n_species*n_species/n_specimen)

    res
}


make_heatmap_sampling <- function(gg_r, title, limits = NULL) {
    state <- maps::map("world", fill = TRUE, plot = FALSE)
    ## convert the 'map' to something we can work with via geom_map
    IDs <- sapply(strsplit(state$names, ":"), function(x) x[1])
    state <- map2SpatialPolygons(state, IDs=IDs, proj4string=CRS("+proj=longlat +datum=WGS84"))

    us_bathy <- suppressMessages(getNOAA.bathy(lon1 = -128, lon2 = -60, lat1 = 22, lat2 = 51, keep = TRUE)) %>%
        fortify() %>%
        filter(z < 0 & z > -1500)

    ## this does the magic for geom_map
    state_map <- fortify(state)

    if (!is.null(limits)) {
        limits <- c(1, limits)
        mid_point <-  log(quantile(seq(min(gg_r$value),
                                       max(limits),
                                       by = 1), .02))
    } else {
        mid_point <-  log(quantile(seq(min(gg_r$value),
                                       max(gg_r$value),
                                       by = 1), .02))
    }

    ggplot() +
        geom_raster(data = gg_r, aes(x = x, y = y, fill = value)) +
        scale_fill_gradient2(low = "#5E98AE", mid = "#E3C94A", high = "#D5331E",
                             midpoint = mid_point,
                             breaks = c(1, 10, 100, 1000, 5000), trans = "log",
                             limits = limits) +
        geom_map(data=state_map, map=state_map,
                 aes(x=long, y=lat, map_id=id),
                 fill="gray20", colour = "gray20", size = .05) +
        geom_contour(data = us_bathy, aes(x = x, y = y, z = z),
                     colour = "gray80", binwidth = 500, size = .1) +
        coord_quickmap(xlim = c(-128, -60), ylim = c(22, 51)) +
        #scale_fill_viridis(trans = "log", breaks = c(1, 10, 100, 1000, 10000)) +
        theme_bw(base_family = "Ubuntu Condensed") +
        theme(legend.title = element_blank()) +
        ggtitle(title) +
        xlab("Longitude") + ylab("Latitude")
}

make_heatmap_by_phylum <- function(idig, file = "figures/map_diversity_per_phylum.pdf") {
    uniq_phyla <- unique(idig$phylum)

    res <- parallel::mclapply(uniq_phyla, function(p) {
                         idig_sub <- idig[idig$phylumrg == p, ]
                         if (nrow(idig_sub) < 10) return(NULL)
                         ggr <- make_data_map_diversity(idig_sub)
                         ggr
                     }, mc.cores = 8L)
    has_data <- !vapply(res, is.null, logical(1))
    res <- res[has_data]
    max_limit <- dplyr::bind_rows(res) %>%
        max(.$value)
    names(res) <- uniq_phyla[has_data]
    pmaps <- parallel::mclapply(seq_along(res),
                       function(gg) {
                           make_heatmap_sampling(res[[gg]], names(res)[gg],
                                                 limits = max_limit)
                  }, mc.cores = 8L)
    pdf(file = file)
    on.exit(dev.off())
    for (i in seq_along(pmaps)) {
       print( pmaps[[i]])
    }
}