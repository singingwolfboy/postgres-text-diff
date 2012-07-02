INSERT INTO user(id, username, email) VALUES (1, 'foo', 'foo');
INSERT INTO page_latest(id, title, slug, num_lines, editor, language, content)
    VALUES (1, 'page', 'page', 5, 1, 'en-us', 
'a
b
c
d
e
f
g
h
i
j');


SELECT update_page(1, 
'a
b
c
d
carrot
f
g
h
foo
bogey
k', 1);

truncate page_latest, page_diff, page_diff_hunk;
