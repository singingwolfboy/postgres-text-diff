DROP VIEW IF EXISTS wiki.page;
CREATE VIEW wiki.page AS
    SELECT 
        pl.id,
        pl.title,
        pl.slug,
        pl.namespace,
        wiki.get_content_at_revision(pl.id, pd.revision) AS content,
        pd.comment,
        wiki.get_num_lines_at_revision(pl.id, pd.revision) AS num_lines,
        pd.revision, 
        pd.editor,
        pl.markup,
        pl.language,
        pd.created_on AS edited_on
    FROM wiki.page_latest AS pl, wiki.page_diff AS pd
    WHERE pl.id = pd.page_id
  UNION
    SELECT *
    FROM wiki.page_latest AS pl;


