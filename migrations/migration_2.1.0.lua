-----------------------------------------------------------------------
-- migrations for 2.1.0 release
-----------------------------------------------------------------------

-- temp_stop never survived a single event; it is a local now
storage.temp_stop = nil
