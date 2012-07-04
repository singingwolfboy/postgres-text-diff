truncate page_latest, page_diff, page_diff_hunk;
INSERT INTO user(id, username, email) VALUES (1, 'foo', 'foo');
INSERT INTO page_latest(id, title, slug, num_lines, editor, language, content)
    VALUES (1, 'page', 'page', 15, 1, 'en-us', 
'a
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
p');


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
j
k
l
m
stick
o
p', 1);

INSERT INTO page_latest(id, title, slug, num_lines, editor, language, content)
    VALUES (2, 'short', 'short', 3, 1, 'en-us', E'a\nb\nc');
SELECT update_page(2, E'a\nx\nc\nd', 1);