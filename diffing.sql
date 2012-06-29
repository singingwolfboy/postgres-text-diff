-- author: David Baumgold <david@davidbaumgold.com>

-- longest common subsequence
create or replace function lcs(text[], text[]) returns text[] as $$
declare
    len1 int;
    len2 int;
    lastrow1 text;
    lastrow2 text;
    recurse1 text[];
    recurse2 text[];
begin
    len1 := array_length($1, 1);
    len2 := array_length($2, 1);
    if len1 is null or len2 is null then
        return null;
    end if;

    lastrow1 := $1[len1];
    lastrow2 := $2[len2];

    if lastrow1 = lastrow2 then
        if len1 = 1 then
            return array[lastrow1];
        else
            return array_append(lcs($1[1:len1-1], $2[1:len2-1]), lastrow1);
        end if;
    else
        recurse1 := lcs($1[1:len1-1], $2);
        recurse2 := lcs($1, $2[1:len2-1]);
        if recurse2 is null or array_length(recurse1, 1) > array_length(recurse2, 1) then
            return recurse1;
        else
            return recurse2;
        end if;
    end if;
end;
$$ language plpgsql
IMMUTABLE STRICT;

-- generate diffs between text
create or replace function create_diff(text, text) returns text as $$
declare
    ary1 text[];
    ary2 text[];
    LCS text[];
    line1 text;
    line2 text;
    lineLCS text;
    ptr1 int := 1;
    ptr2 int := 1;
    ptrLCS int := 1;
    result text[];
begin
    ary1 := string_to_array($1, E'\n');
    ary2 := string_to_array($2, E'\n');
    LCS := lcs(ary1, ary2);
    line1 := ary1[ptr1];
    line2 := ary2[ptr2];
    lineLCS := LCS[ptrLCS];
    LOOP
        if line1 is null and line2 is null and lineLCS is null then
            return array_to_string(result, E'\n');
        end if;
        if line1 = lineLCS and line2 = lineLCS then
            result := array_append(result, ' ' || lineLCS);
            ptr1 := ptr1 + 1;
            ptr2 := ptr2 + 1;
            ptrLCS := ptrLCS + 1;
            line1 := ary1[ptr1];
            line2 := ary2[ptr2];
            lineLCS := LCS[ptrLCS];
            continue;
        end if;
        if line1 is not null and (line1 != lineLCS or lineLCS is null) then
            -- must have been deleted
            result := array_append(result, '-' || line1);
            ptr1 := ptr1 + 1;
            line1 := ary1[ptr1];
            continue;
        end if;
        if line2 is not null and (line2 != lineLCS or lineLCS is null) then
            -- must have been added
            result := array_append(result, '+' || line2);
            ptr2 := ptr2 + 1;
            line2 := ary2[ptr2];
            continue;
        end if;
    END LOOP;
end;
$$ language plpgsql
IMMUTABLE STRICT;



-- only for reference (unused)
create table thingy (
    id int,
    text text
);
insert into thingy (id, text) values (1, 'abc'), (2, 'def');
create or replace function get_things() returns setof thingy as $$
declare
    row1 thingy;
    row2 thingy;
begin
    row1 := (3, 'foo');
    row2 := (4, 'bar');
    return next row1;
    return next row2;
end;
$$ language plpgsql;

create or replace function process_things(things thingy[]) returns int[] as $$
declare
    thing thingy;
    results int[];
begin
    FOREACH thing IN ARRAY things LOOP
        results := results || thing.id;
    END LOOP;
    RETURN results;
end;
$$ language plpgsql;
select process_things(array(select get_things())); -- works


