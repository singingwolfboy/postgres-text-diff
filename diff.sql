create or replace function wiki.update_page(page_id int, new_content text, 
    new_editor_id int, new_comment text DEFAULT '', context_len int DEFAULT 3)
    returns int as $$
declare
    latest wiki.page_latest;
    new_revision int;
    hunk text[];
    context text[]; -- only contains consecutive lines in LCS
    context_length int;
    in_hunk boolean := FALSE;
    hunk_lines_added int := 0;
    hunk_lines_deleted int := 0;
    hunk_lines_context int := 0;
    X text[];
    Y text[];
    Xline text;
    Yline text;
    C int[][];
    i int;
    j int;
begin
    SELECT * INTO latest FROM wiki.page_latest WHERE id = page_id;
    IF NOT FOUND THEN
        RAISE 'Page % not found', id;
    END IF;
    new_revision := latest.revision + 1;
    --raise notice 'new revision: %', new_revision;
    -- write out new diff object
    INSERT INTO wiki.page_diff (page_id, revision, editor_id, comment)
        VALUES (page_id, latest.revision, latest.editor_id, latest.comment);
    -- make hunks
    X := string_to_array(latest.content, E'\n');
    Y := string_to_array(new_content, E'\n');
    i := array_length(X, 1) + 1;
    j := array_length(Y, 1) + 1;
    --hunk_start := i;
    C := lcs_length(X, Y);
    LOOP -- moving backwards
        --raise notice 'i = %, j = %', i, j;
        --raise notice 'hunk = %', hunk;
        --raise notice 'context here = %', context;
        if i = 1 and j = 1 then
            -- we're done!
            IF in_hunk THEN
                context_length := array_length(context, 1);
                IF context_length IS NOT NULL THEN
                    IF context_length > context_len THEN
                        --raise notice 'context before = %', context;
                        --raise notice '% %', context_length-context_len+1, context_length;
                        context := context[context_length-context_len+1:context_length];
                        --raise notice 'context after = %', context;
                        context_length = context_len;
                    END IF;
                    -- prepend context to hunk
                    hunk := context || hunk;
                    hunk_lines_context := hunk_lines_context + context_length;
                END IF;
                -- write out the last hunk
                INSERT INTO wiki.page_diff_hunk (page_id, revision, start, 
                    content, lines_added, lines_deleted, lines_context)
                    VALUES 
                    (page_id, latest.revision, i, array_to_string(hunk, E'\n'),
                    hunk_lines_added, hunk_lines_deleted, hunk_lines_context);
            END IF;
            -- update the page_latest object
            UPDATE wiki.page_latest SET content = new_content, revision = new_revision,
                num_lines = array_length(Y, 1), comment = new_comment,
                editor_id = new_editor_id, edited_on = now()
                WHERE id = page_id;
            return new_revision;
        end if;
        Xline := X[i-1];
        Yline := Y[j-1];
        --raise notice 'Xline = %', Xline;
        --raise notice 'Yline = %', Yline;
        -- handle same line
        if Xline = Yline THEN
            --raise notice 'equal lines: %, %', Xline, Yline;
            IF NOT in_hunk THEN
                -- LIFO queue
                IF array_length(context, 1) < context_len THEN
                    -- prepend to context array
                    context := (' ' || Xline) || context;
                    -- hunk_lines_context := hunk_lines_context + 1;
                ELSE
                    -- pull the last one off before you stick the new one in front
                    --raise notice 'sliced context = %', context[1:context_len-1];
                    context := (' ' || Xline) || context[1:context_len-1];
                END IF;
            ELSE
                context := (' ' || Xline) || context;
                --raise notice 'context whoa = %', context;
                -- are we done with this hunk?
                -- we need to check up until twice the context_len, because of
                -- pathological splitting case
                IF array_length(context, 1) = 2*context_len THEN
                    -- prepend context to hunk
                    hunk := context[context_len+1:2*context_len] || hunk;
                    hunk_lines_context = hunk_lines_context + context_len;
                    -- write out the hunk
                    INSERT INTO wiki.page_diff_hunk (page_id, revision, start, 
                        content, lines_added, lines_deleted, lines_context)
                        VALUES 
                        (page_id, latest.revision, i-1, array_to_string(hunk, E'\n'),
                        hunk_lines_added, hunk_lines_deleted, hunk_lines_context);
                    -- and reset
                    hunk := array[]::text[];
                    context := context[1:context_len];
                    in_hunk := FALSE;
                    hunk_lines_added := 0;
                    hunk_lines_deleted := 0;
                    hunk_lines_context := 0;
                END IF;
            END IF;
            i := i - 1;
            j := j - 1;
            continue; -- skip the rest of this function and go on
        end if;
        -- reset context array
        context_length := array_length(context, 1);
        --raise notice 'context there = %', context;
        IF NOT in_hunk THEN
            -- start a new hunk
            hunk = context;
            in_hunk = TRUE;
            IF context_length IS NOT NULL THEN
                hunk_lines_context := context_length;
            END IF;
        ELSE
            IF context_length IS NOT NULL THEN
                -- prepend context to hunk
                hunk := context || hunk;
                hunk_lines_context := hunk_lines_context + context_length;
            END IF;
        END IF;
        context := array[]::text[];
        -- done resetting context; handle addition and deletion
        if C[i][j-1] > C[i-1][j] THEN
            --raise notice 'added: %', Yline;
            -- must have been added
            hunk := ('+' || Yline) || hunk;
            hunk_lines_added := hunk_lines_added + 1;
            j := j - 1;
            continue;
        ELSE
            --raise notice 'deleted: %', Xline;
            -- must have been deleted
            hunk := ('-' || Xline) || hunk;
            hunk_lines_deleted := hunk_lines_deleted + 1;
            i := i - 1;
            continue;
        end if;
    END LOOP;
end;
$$ language plpgsql
VOLATILE STRICT;
