
-- Table in statistics.sqlite3:
ALTER TABLE xray_items
RENAME COLUMN hits TO matches;
ALTER TABLE xray_items
RENAME COLUMN ebook_hits_retrieved TO ebook_matches_retrieved;

