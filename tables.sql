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
    revision int DEFAULT 0 CONSTRAINT "revision must be positive" CHECK (revision >= 0),
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
    start int NOT NULL CONSTRAINT "start must be positive" CHECK (start >= 0),
    content text NOT NULL DEFAULT '',
    lines_added int NOT NULL DEFAULT 0,
    lines_deleted int NOT NULL DEFAULT 0,
    lines_context int NOT NULL DEFAULT 0,
    PRIMARY KEY (page_id, revision, start),
    FOREIGN KEY (page_id, revision) REFERENCES page_diff ON DELETE CASCADE
    -- EXCLUDE USING gist (page_id WITH =, revision WITH =, [overlapping])
    -- Would need to define a page_diff_hunk_meta type, define the "&&" operation
    -- over it, and add a "meta" type to this table. Not worth the efford right now.
    -- See: http://www.pgcon.org/2010/schedule/attachments/136_exclusion_constraints2.pdf
);

CREATE FUNCTION hunks_overlap(hunk, hunk) returns boolean as $$
declare
    first hunk;
    second hunk;
begin
    if $1.page_id != $2.page_id or $1.revision != $2.revision then
        RETURN FALSE;
    end if;
    -- can't have same start, due to primary key
    if $1.start < $2.start then
        first := $1;
        second := $2;
    else
        first := $2;
        second := $1;
    end if;
    RETURN second.start > first.start + first.lines_context + first.lines_deleted;
end;
$$ language plpgsql
IMMUTABLE STRICT;

DROP TABLE IF EXISTS page;
CREATE TABLE page (LIKE page_latest);

CREATE FUNCTION get_page_at_revision(id int, revision int) returns page as $$
declare
    latest page_latest;
    diff page_diff;
    hunk_cursor refcursor;
    content_ary text[];
    content text;
    result page;
begin
    IF revision < 0 THEN
        RAISE EXCEPTION 'Invalid revision % (must be positive)', revision;
    END IF;
    SELECT * INTO latest FROM page_latest WHERE id = id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Page % not found', id;
    END IF;
    IF revision = latest.revision THEN
        RETURN latest;
    END IF;
    IF revision > latest.revision THEN
        RAISE EXCEPTION 'Nonexistent revision % for page % (latest is %)',
            revision, id, latest.revision;
    END IF;

    content_ary := apply_hunks(latest.content, id, revision, latest.revision, TRUE);
    content := array_to_string(content_ary, E'\n');

    SELECT * INTO diff from page_diff where page_id = id;

    result := (latest.id, latest.title, latest.slug, latest.namespace,
        content, array_length(content_ary, 1), revision, diff.editor,
        latest.markup, latest.language, diff.created_on);
    RETURN result;
end;
$$ language plpgsql
STABLE STRICT;

CREATE FUNCTION apply_hunks(content text, page_id int,
    min_revision int, max_revision int, reverse boolean DEFAULT FALSE)
    RETURNS text[] AS $$
begin
    RETURN apply_hunks(string_to_array(content, E'\n'), 
        page_id, min_revision, max_revision, reverse);
end;
$$ language plpgsql
STABLE STRICT;

CREATE FUNCTION apply_hunks(content text[], page_id int,
    min_revision int, max_revision int, reverse boolean DEFAULT FALSE)
    RETURNS text[] as $$
declare
    hunk record;
    revision int := null;
    offset int := 0;
    start int;
    length int;
    content_line text;
    hunk_line text;
    hunk_content_line text;
    marker char(1);
    applied_hunk text[];
    content_length int;
begin
    FOR hunk in SELECT * 
        FROM page_diff_hunk AS hunk
        WHERE hunk.page_id = page_id
        AND hunk.revision >= min_revision
        AND hunk.revision < max_revision
        ORDER BY hunk.revision DESC, hunk.start ASC
    LOOP
        IF revision != hunk.revision THEN
            revision := hunk.revision;
            -- reset offset
            offset := 0;
        END IF;
        start := hunk.start + "offset";
        content_line := content[start];
        FOREACH hunk_line IN ARRAY string_to_array(hunk.content, E'\n') LOOP
            marker = left(hunk_line, 1);
            hunk_content_line = substr(hunk_line, 2);
            IF (marker = ' ') or (marker = '+' and not reverse) or (marker = '-' and reverse) THEN
                applied_hunk := array_append(applied_hunk, hunk_content_line);
            END IF;
        END LOOP;
        -- replace content array
        content_length := array_length(content, 1);
        content := content[1:hunk.start] + applied_hunk + 
            content[start:content_length];
    END LOOP;
    RETURN content;
end;
$$ language plpgsql
STABLE STRICT;

CREATE FUNCTION apply_patch_to_content(content text[], patch page_diff,
    reverse boolean DEFAULT FALSE) RETURNS text[] AS $$
declare
    results_so_far int := 0;
    offset int := 0;
    applied_patch text[];
    content_ptr int;
    content_line text;
    hunk_line text;
    marker char(1);
    hunk_content_line text;
begin
    FOR hunk in SELECT * FROM page_diff_hunk AS hunk
        WHERE hunk.page_id = patch.page_id
        AND hunk.revision = patch.revision
        ORDER BY hunk.start ASC
    LOOP
        -- move hunk gap into applied_patch
        results_so_far := array_length(applied_patch, 1)
        IF results_so_far IS NULL THEN results_so_far := 0; END IF;
        applied_patch := applied_patch || content[results_so_far+offset+1:hunk.start+offset];
        -- initialize content pointer/line
        content_ptr := hunk.start;
        content_line := content[content_ptr];
        -- loop through hunk
        FOREACH hunk_line IN ARRAY string_to_array(hunk.content, E'\n') LOOP
            marker = left(hunk_line, 1);
            hunk_content_line = substr(hunk_line, 2);
            IF (marker = ' ') or (marker = '-' and not reverse) or (marker = '+' and reverse) THEN
                -- verify that the patch matches
                IF hunk_content_line != content_line THEN
                    RAISE EXCEPTION 'Hunk (page %, rev %, start %) does not match content at line %',
                        (patch.page_id, patch.revision, patch.start, content_ptr);
                END IF;
                content_ptr := content_ptr + 1;
                content_line := content[content_ptr];
            END IF;
            IF (marker = ' ') or (marker = '+' and not reverse) or (marker = '-' and reverse) THEN
                -- add to applied_patch result
                applied_patch := applied_patch || hunk_content_line;
            END IF;
        END LOOP;
        offset := offset + hunk.lines_added - hunk.lines_deleted;
    END LOOP;
    -- append any missing results
    results_so_far := array_length(applied_patch, 1)
    IF results_so_far IS NULL THEN results_so_far := 0; END IF;
    applied_patch := applied_patch[results_so_far+offset+1:array_length(content, 1)]
    RETURN applied_patch;
end;
LANGUAGE plpgsql
STABLE STRICT;

