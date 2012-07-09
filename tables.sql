DROP TABLE IF EXISTS "user";
CREATE TABLE "user" (
    id serial PRIMARY KEY,
    username varchar(256) NOT NULL,
    email varchar(256) NOT NULL,
    email_verified boolean DEFAULT FALSE,
    created_on timestamp DEFAULT now(),
    admin boolean DEFAULT FALSE
);

DROP TABLE IF EXISTS page_latest CASCADE;
CREATE TABLE page_latest (
    id serial PRIMARY KEY,
    title varchar(256) NOT NULL,
    slug varchar(256) NOT NULL,
    namespace varchar(64) DEFAULT '',
    content text DEFAULT '',
    comment text DEFAULT '',
    num_lines int NOT NULL,
    revision int DEFAULT 1 CONSTRAINT "revision must be positive" CHECK (revision > 0),
    editor int REFERENCES "user"(id),
    markup varchar(64) DEFAULT 'plain',
    language varchar(8) NOT NULL,
    edited_on timestamp DEFAULT now() NOT NULL
);

DROP TABLE IF EXISTS page_diff CASCADE;
CREATE TABLE page_diff (
    page_id int, 
    revision int,
    editor int REFERENCES "user"(id),
    created_on timestamp DEFAULT now() NOT NULL,
    comment text DEFAULT '',
    PRIMARY KEY (page_id, revision),
    FOREIGN KEY (page_id) REFERENCES page_latest(id) ON DELETE CASCADE
);

DROP TABLE IF EXISTS page_diff_hunk;
CREATE TABLE page_diff_hunk (
    page_id int,
    revision int,
    start int NOT NULL CONSTRAINT "start must be positive" CHECK (start > 0),
    content text NOT NULL DEFAULT '',
    lines_added int NOT NULL DEFAULT 0,
    lines_deleted int NOT NULL DEFAULT 0,
    lines_context int NOT NULL DEFAULT 0,
    PRIMARY KEY (page_id, revision, start),
    FOREIGN KEY (page_id, revision) REFERENCES page_diff ON DELETE CASCADE
    -- EXCLUDE USING gist (page_id WITH =, revision WITH =, [overlapping])
    -- Would need to define a page_diff_hunk_meta type, define the "&&" operation
    -- over it, and add a "meta" type to this table. Not worth the effort right now.
    -- See: http://www.pgcon.org/2010/schedule/attachments/136_exclusion_constraints2.pdf
);

CREATE OR REPLACE FUNCTION hunk_overlap(page_diff_hunk, page_diff_hunk) returns boolean as $$
declare
    first page_diff_hunk;
    second page_diff_hunk;
begin
    if $1.page_id != $2.page_id or $1.revision != $2.revision then
        RETURN FALSE;
    end if;
    -- if we have the same page_id, revision, and start, then it's
    -- the same hunk; and a hunk overlaps with itself.
    if $1.start = $2.start then
        RETURN TRUE;
    end if;
    -- check which comes first
    if $1.start < $2.start then
        first := $1;
        second := $2;
    else
        first := $2;
        second := $1;
    end if;
    RETURN second.start <= first.start + first.lines_context + first.lines_deleted;
end;
$$ language plpgsql
IMMUTABLE STRICT;

CREATE OPERATOR && (
    leftarg = page_diff_hunk,
    rightarg = page_diff_hunk,
    procedure = hunk_overlap,
    commutator = &&
);

create function compare() returns boolean as $$
declare
    one page_diff_hunk;
    two page_diff_hunk;
begin
    SELECT * into one FROM page_diff_hunk WHERE page_id = 1 AND revision = 1
        AND start = 1;
    SELECT * into two FROM page_diff_hunk WHERE page_id = 1 AND revision = 1
        AND start = 2;
    RETURN one && two;
end;
$$ language plpgsql;

DROP TABLE IF EXISTS page;
CREATE TABLE page (LIKE page_latest);
