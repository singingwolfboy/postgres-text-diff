create or replace function apply_hunk(original text[], hunk text[],
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
        RAISE notice 'op = %, hp = %, ol = %, hl = %', orig_ptr, hunk_ptr, orig_line, hunk_line;
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
