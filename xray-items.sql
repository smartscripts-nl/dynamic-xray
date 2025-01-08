
-- Table to be created in statistics.sqlite3:
DROP TABLE IF EXISTS "xray_items";
CREATE TABLE "xray_items" (
    "id" INTEGER NOT NULL,
    "ebook",
    "name",
    "aliases",
    "linkwords",
    "short_names",
    "description",
    "xray_type" INTEGER NOT NULL DEFAULT 1,
    "hits" INTEGER,
    "ebook_hits_retrieved" INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY("id" AUTOINCREMENT)
)
