-- author: David Baumgold <david@davidbaumgold.com>

create or replace function max(int, int) returns int as $$
begin
    IF $2 is null or $1 > $2 THEN
        RETURN $1;
    ELSE
        RETURN $2;
    END IF;
end;
$$ language plpgsql
IMMUTABLE;

-- longest common subsequence: length table
create or replace function lcs_length(X text[], Y text[]) returns int[][] as $$
declare
    len1 int;
    len2 int;
    C int[][];
    i int;
    j int;
begin
    len1 := array_length(X, 1) + 1;
    len2 := array_length(Y, 1) + 1;
    -- initialize with zeroes
    C := array_fill(0, array[len1, len2]);
    -- loop and increment
    for i in 2..len1 LOOP
        for j in 2..len2 LOOP
            IF X[i-1] = Y[j-1] THEN
                C[i][j] := C[i-1][j-1] + 1;
            ELSE
                C[i][j] := max(C[i][j-1], C[i-1][j]);
            END IF;
        end loop;
    end loop;
    raise notice '%', C;
    RETURN C;
end;
$$ language plpgsql
IMMUTABLE STRICT;

-- read longest common subsequence out of length table
create or replace function backtrack(C int[][], X text[], Y text[], i int, j int)
    returns text[] as $$
begin
    IF i = 1 or j = 1 THEN
        return array[]::text[];
    ELSIF  X[i-1] = Y[j-1] THEN
        return backtrack(C, X, Y, i-1, j-1) || X[i-1];
    ELSE
        if C[i][j-1] > C[i-1][j] THEN
            return backtrack(C, X, Y, i, j-1);
        else
            return backtrack(C, X, Y, i-1, j);
        end if;
    END IF;
end;
$$ language plpgsql
IMMUTABLE STRICT;

create or replace function backtrack(C int[][], X text[], Y text[])
    returns text as $$
begin
    return backtrack(C, X, Y,
        array_length(X, 1) + 1, array_length(Y, 1) + 1);
end;
$$ language plpgsql
IMMUTABLE STRICT;

create or replace function lcs(text[], text[]) returns text[] as $$
begin
    return backtrack(lcs_length($1, $2), $1, $2);
end;
$$ language plpgsql
IMMUTABLE STRICT;

-- longest common subsequence
create or replace function lcs(text, text) returns text[] as $$
declare
    ary1 text[];
    ary2 text[];
begin
    ary1 := string_to_array($1, E'\n');
    ary2 := string_to_array($2, E'\n');
    return backtrack(lcs_length(ary1, ary2), ary1, ary2);
end;
$$ language plpgsql
IMMUTABLE STRICT;
