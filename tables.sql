DROP SCHEMA IF EXISTS wiki;
CREATE SCHEMA wiki;

DROP TABLE IF EXISTS wiki.editor;
CREATE TABLE wiki.editor (
    id serial PRIMARY KEY,
    username varchar(256) NOT NULL,
    email varchar(256) NOT NULL,
    email_verified boolean DEFAULT FALSE,
    created_on timestamp DEFAULT now(),
    admin boolean DEFAULT FALSE
);

DROP TABLE IF EXISTS wiki.page_latest CASCADE;
CREATE TABLE wiki.page_latest (
    id serial PRIMARY KEY,
    title varchar(256) NOT NULL,
    slug varchar(256) NOT NULL,
    namespace varchar(64) DEFAULT '',
    content text DEFAULT '',
    comment text DEFAULT '',
    num_lines int NOT NULL,
    revision int DEFAULT 1 CONSTRAINT "revision must be positive" CHECK (revision > 0),
    editor int REFERENCES wiki.editor(id),
    markup varchar(64) DEFAULT 'plain',
    language varchar(8) NOT NULL,
    edited_on timestamp DEFAULT now() NOT NULL
);

DROP TABLE IF EXISTS wiki.page_diff CASCADE;
CREATE TABLE wiki.page_diff (
    page_id int, 
    revision int,
    editor int REFERENCES wiki.editor(id),
    created_on timestamp DEFAULT now() NOT NULL,
    comment text DEFAULT '',
    PRIMARY KEY (page_id, revision),
    FOREIGN KEY (page_id) REFERENCES wiki.page_latest(id) ON DELETE CASCADE
);

DROP TABLE IF EXISTS wiki.page_diff_hunk;
CREATE TABLE wiki.page_diff_hunk (
    page_id int,
    revision int,
    start int NOT NULL CONSTRAINT "start must be positive" CHECK (start > 0),
    content text NOT NULL DEFAULT '',
    lines_added int NOT NULL DEFAULT 0,
    lines_deleted int NOT NULL DEFAULT 0,
    lines_context int NOT NULL DEFAULT 0,
    PRIMARY KEY (page_id, revision, start),
    FOREIGN KEY (page_id, revision) REFERENCES wiki.page_diff ON DELETE CASCADE
);

CREATE OR REPLACE FUNCTION wiki.hunk_overlap(wiki.page_diff_hunk, wiki.page_diff_hunk) returns boolean as $$
declare
    first wiki.page_diff_hunk;
    second wiki.page_diff_hunk;
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
    leftarg = wiki.page_diff_hunk,
    rightarg = wiki.page_diff_hunk,
    procedure = wiki.hunk_overlap,
    commutator = &&
);

DROP TABLE IF EXISTS wiki.page;
CREATE TABLE wiki.page (LIKE page_latest);

CREATE OR REPLACE FUNCTION wiki.page_latest_to_page(wiki.page_latest)
    returns wiki.page as $$
declare
    result wiki.page;
begin
    result := ($1.id, $1.title, $1.slug, $1.namespace, $1.content, $1.comment,
        $1.num_lines, $1.revision, $1.editor, $1.markup, $1.language,
        $1.edited_on);
    RETURN result;
end;
$$ language plpgsql IMMUTABLE STRICT;

CREATE CAST (wiki.page_latest AS wiki.page)
    WITH FUNCTION wiki.page_latest_to_page(wiki.page_latest);
