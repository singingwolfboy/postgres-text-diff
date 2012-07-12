truncate page_latest, page_diff, page_diff_hunk;
INSERT INTO "user"(id, username, email) VALUES (1, 'foo', 'foo');
INSERT INTO page_latest(id, title, slug, num_lines, editor, language, content)
    VALUES (1, 'page', 'page', 3, 1, 'en-us', 
'a
b
c');

SELECT update_page(1, 'b
c
d', 1);
SELECT update_page(1, 'c
d
e', 1);
SELECT update_page(1, 'd
e
f', 1);


SELECT update_page(1, 
'a
b
c
d
carrot
f
g
h
i
u
k
l
m
stick
o
p', 1);

INSERT INTO page_latest(id, title, slug, num_lines, editor, language, content)
    VALUES (2, 'short', 'short', 3, 1, 'en-us', E'a\nb\nc');
SELECT update_page(2, E'a\nx\nc\nd', 1);


select apply_hunk('a
b
c
d
e
f
g
h
i
j
k
l
m
n
o
p', ' b
 c
 d
+carrot
-e
 f
 g
 h
 i
+u
-j
 k
 l
 m
+stick
-n
 o
 p', 2);