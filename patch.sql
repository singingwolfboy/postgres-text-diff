create or replace function wiki.apply_hunk(original text[], hunk text[],
    start int DEFAULT 1, reverse boolean DEFAULT FALSE) returns text[] as $$
declare
    result text[];
    orig_length int;
    hunk_length int;
    orig_ptr int := 1;
    hunk_ptr int := 1;
    orig_line text;
    hunk_line text;
    hunk_content text;
    marker char(1);
begin
    orig_length := array_length(original, 1);
    hunk_length := array_length(hunk, 1);
    IF orig_length IS NULL OR hunk_length IS NULL THEN
        RETURN original;
    END IF;
    IF start < 1 THEN
        RAISE 'start is %, but must be greater than 0', start;
    END IF;
    IF start > 1 THEN
        result := original[1:start-1];
    END IF;
    orig_ptr := start;
    orig_line := original[orig_ptr];
    hunk_line := hunk[hunk_ptr];

    LOOP
        --RAISE notice 'op = %, hp = %, ol = %, hl = %', orig_ptr, hunk_ptr, orig_line, hunk_line;
        IF hunk_line IS NULL THEN
            -- End of the hunk. Wrap up the rest, and leave.
            RETURN result || original[orig_ptr:orig_length];
        END IF;
        marker := left(hunk_line, 1);
        hunk_content := substring(hunk_line from 2);
        IF marker = ' ' THEN
            IF hunk_content = orig_line THEN
                result := result || hunk_content;
                orig_ptr := orig_ptr + 1;
                hunk_ptr := hunk_ptr + 1;
                orig_line := original[orig_ptr];
                hunk_line := hunk[hunk_ptr];
            ELSE
                RAISE 'line % of hunk is a context line, but does not match. "%" != "%"', hunk_ptr, hunk_content, orig_line;
            END IF;
        ELSIF (marker = '+' and not reverse) or (marker = '-' and reverse) THEN
            result := result || hunk_content;
            hunk_ptr := hunk_ptr + 1;
            hunk_line := hunk[hunk_ptr];
        ELSIF (marker = '-' and not reverse) or (marker = '+' and reverse) THEN
            IF hunk_content != orig_line THEN
                RAISE 'line % of hunk is a removal line, but does not match. "%" != "%"', hunk_ptr, hunk_content, orig_line;
            ELSE
                orig_ptr := orig_ptr + 1;
                hunk_ptr := hunk_ptr + 1;
                hunk_line := hunk[hunk_ptr];
                orig_line := original[orig_ptr];
            END IF;
        ELSE
            RAISE 'unknown marker "%" on line %', marker, hunk_ptr;
        END IF;
    END LOOP;
end;
$$ language plpgsql
IMMUTABLE;

create or replace function apply_hunk(original text, hunk text,
    start int DEFAULT 1, reverse boolean DEFAULT FALSE) returns text as $$
begin
    RETURN array_to_string(apply_hunk(
        string_to_array(original, E'\n'),
        string_to_array(hunk, E'\n'),
        start, reverse),
    E'\n');
end;
$$ language plpgsql
IMMUTABLE;

create or replace function wiki.get_content_array_at_revision(page_id int, revision int)
    returns text[] as $$
#variable_conflict use_variable
declare
    latest wiki.page_latest;
    hunk wiki.page_diff_hunk;
    content text[];
    cur_rev int := -1;
    line_offset int := 0;
begin
    IF revision < 1 THEN
        RAISE 'Revision must be positive (got %)', revision;
    END IF;
    SELECT * INTO latest FROM wiki.page_latest WHERE id = page_id;
    IF NOT FOUND THEN
        RAISE 'Page % not found', id;
    END IF;
    IF revision > latest.revision THEN
        RAISE 'Revision does not exist (requested %, latest is %)', revision,
            latest.revision;
    END IF;
    IF revision = latest.revision THEN
        RETURN latest.content;
    END IF;
    
    content = string_to_array(latest.content, E'\n');
    FOR hunk IN SELECT * FROM wiki.page_diff_hunk AS pdh 
                WHERE pdh.page_id = page_id
                AND pdh.revision >= revision
                ORDER BY pdh.revision desc, pdh.start asc
    LOOP
        IF cur_rev != hunk.revision THEN
            line_offset := 0;
            cur_rev := hunk.revision;
        END IF;
        content := apply_hunk(content,
            string_to_array(hunk.content, E'\n'),
            hunk.start + line_offset,
            TRUE);
        line_offset := line_offset + hunk.lines_added - hunk.lines_deleted;
    END LOOP;
    RETURN content;
end;
$$ language plpgsql STABLE STRICT;

create or replace function wiki.get_content_at_revision(page_id int, revision int)
    returns text as $$
begin
    RETURN array_to_string(wiki.get_content_array_at_revision(page_id, revision), E'\n');
end;
$$ language plpgsql STABLE STRICT;

create or replace function wiki.get_num_lines_at_revision(page_id int, revision int)
    returns int as $$
begin
    RETURN array_length(wiki.get_content_array_at_revision(page_id, revision), 1);
end;
$$ language plpgsql STABLE STRICT;

/*
create or replace function wiki.get_page_at_revision(page_id int, revision int)
    returns wiki.page as $$
#variable_conflict use_variable
declare
    latest wiki.page_latest;
    diff wiki.page_diff;
    content text;
    num_lines int;
    result wiki.page;
begin
    IF revision < 1 THEN
        RAISE 'Revision must be positive (got %)', revision;
    END IF;
    SELECT * INTO latest FROM wiki.page_latest WHERE id = page_id;
    IF NOT FOUND THEN
        RAISE 'Page % not found', id;
    END IF;
    IF revision > latest.revision THEN
        RAISE 'Revision does not exist (requested %, latest is %)', revision,
            latest.revision;
    END IF;
    IF revision = latest.revision THEN
        result := latest::wiki.page;
        RETURN result;
    END IF;
    SELECT * INTO diff FROM wiki.page_diff AS pd
        WHERE pd.page_id = page_id
        AND pd.revision = revision;
    IF NOT FOUND THEN
        RAISE 'Revision % for page % not found', revision, page_id;
    END IF;

    content := wiki.get_content_at_revision(page_id, revision);
    num_lines := wiki.get_num_lines_at_revision(page_id, revision);
    
    result := (latest.id, latest.title, latest.slug, latest.namespace,
        content, diff.comment, num_lines, revision, diff.editor, latest.markup,
        latest.language, diff.created_on);
    RETURN result;
end;
$$ language plpgsql
STABLE STRICT;
*/
