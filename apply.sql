create or replace function update_page(page_id int, new_content text, 
    editor_id int, new_comment text DEFAULT '', context_len int DEFAULT 3) returns int as $$
declare
    latest page_latest;
    new_revision int;
    hunk text[];
    context text[]; -- only contains consecutive lines in LCS
    in_hunk boolean := FALSE;
    hunk_start int := 1;
    hunk_lines_added int := 0;
    hunk_lines_deleted int := 0;
    hunk_lines_context int := 0;
    ary1 text[];
    ary2 text[];
    LCS text[];
    line1 text;
    line2 text;
    lineLCS text;
    ptr1 int := 1;
    ptr2 int := 1;
    ptrLCS int := 1;
begin
    SELECT * INTO latest FROM page_latest WHERE id = page_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Page % not found', id;
    END IF;
    new_revision := latest.revision + 1;
    raise notice 'new revision: %', new_revision;
    -- write out new diff object
    INSERT INTO page_diff (page_id, revision, editor, comment)
        VALUES (page_id, latest.revision, latest.editor, latest.comment);
    -- make hunks
    ary1 := string_to_array(latest.content, E'\n');
    ary2 := string_to_array(new_content, E'\n');
    raise notice 'About to determine longest common substring';
    LCS := lcs(ary1, ary2);
    raise notice 'Longest common substring determined';
    line1 := ary1[ptr1];
    line2 := ary2[ptr2];
    lineLCS := LCS[ptrLCS];
    LOOP
        if line1 is null and line2 is null and lineLCS is null then
            -- we're done!
            IF in_hunk THEN
                IF array_length(context, 1) IS NOT NULL THEN
                    -- add context to hunk
                    hunk := hunk || context;
                    hunk_lines_context := hunk_lines_context + array_length(context, 1);
                END IF;
                -- write out the last hunk
                INSERT INTO page_diff_hunk (page_id, revision, start, 
                    content, lines_added, lines_deleted, lines_context)
                    VALUES 
                    (page_id, latest.revision, hunk_start, array_to_string(hunk, E'\n'),
                    hunk_lines_added, hunk_lines_deleted, hunk_lines_context);
            END IF;
            -- update the page_latest object
            UPDATE page_latest SET content = new_content, revision = new_revision,
                num_lines = array_length(ary2, 1), comment = new_comment,
                editor = editor_id, edited_on = now()
                WHERE id = page_id;
            return new_revision;
        end if;
        -- handle same line
        if line1 = lineLCS and line2 = lineLCS then
            raise notice 'equal lines: %', lineLCS;
            IF NOT in_hunk THEN
                -- LIFO queue
                IF array_length(context, 1) < context_len THEN
                    context := context || (' ' || lineLCS);
                    hunk_lines_context := hunk_lines_context + 1;
                ELSE
                    context := context[2:context_len] || (' ' || lineLCS);
                END IF;
            ELSE
                context := context || (' ' || lineLCS);
                hunk_lines_context := hunk_lines_context + 1;
                -- are we done with this hunk?
                IF array_length(context, 1) = context_len THEN
                    -- write out the hunk
                    INSERT INTO page_diff_hunk (page_id, revision, start, 
                        content, lines_added, lines_deleted, lines_context)
                        VALUES 
                        (page_id, latest.revision, hunk_start, array_to_string(hunk, E'\n'),
                        hunk_lines_added, hunk_lines_deleted, hunk_lines_context);
                    -- and reset
                    hunk := array[]::text[];
                    context := array[]::text[];
                    in_hunk := FALSE;
                    hunk_lines_added := 0;
                    hunk_lines_deleted := 0;
                    hunk_lines_context := 0;
                END IF;
            END IF;
            ptr1 := ptr1 + 1;
            ptr2 := ptr2 + 1;
            ptrLCS := ptrLCS + 1;
            line1 := ary1[ptr1];
            line2 := ary2[ptr2];
            lineLCS := LCS[ptrLCS];
            continue; -- skip the rest of this function and go on
        end if;
        -- reset context array
        IF NOT in_hunk THEN
            -- start a new hunk
            hunk = context;
            in_hunk = TRUE;
            IF ptr1 > context_len THEN
                hunk_start = ptr1 - context_len;
            ELSE
                IF array_length(context, 1) IS NULL THEN
                    hunk_start = ptr1;
                ELSE
                    hunk_start = ptr1 - array_length(context, 1);
                END IF;
            END IF;
        ELSE
            IF array_length(context, 1) IS NOT NULL THEN
                -- add context to hunk
                hunk := hunk || context;
                hunk_lines_context := hunk_lines_context + array_length(context, 1);
            END IF;
        END IF;
        context := array[]::text[];
        -- done resetting context; handle addition and deletion
        if line1 is not null and (line1 != lineLCS or lineLCS is null) then
            -- must have been deleted
            hunk := hunk || ('-' || line1);
            ptr1 := ptr1 + 1;
            line1 := ary1[ptr1];
            hunk_lines_deleted := hunk_lines_deleted + 1;
            continue;
        end if;
        if line2 is not null and (line2 != lineLCS or lineLCS is null) then
            -- must have been added
            hunk := hunk || ('+' || line2);
            ptr2 := ptr2 + 1;
            line2 := ary2[ptr2];
            hunk_lines_added := hunk_lines_added + 1;
            continue;
        end if;
    END LOOP;
end;
$$ language plpgsql
VOLATILE STRICT;

