-----------------------------------------------------------------------
-- migrations for 1.3.0 release
-----------------------------------------------------------------------

-- add temp stop marker
storage.temp_stop = storage.temp_stop or {}

-- reset train groups
storage.train_groups = {}
