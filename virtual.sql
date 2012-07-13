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
        pd.editor_id,
        pl.markup,
        pl.language,
        pd.created_on AS edited_on
    FROM wiki.page_latest AS pl, wiki.page_diff AS pd
    WHERE pl.id = pd.page_id
  UNION
    SELECT *
    FROM wiki.page_latest AS pl;

CREATE OR REPLACE FUNCTION wiki.do_update_page_trigger() RETURNS trigger AS $$
declare
    latest wiki.page_latest;
begin
    SELECT * INTO latest FROM wiki.page_latest WHERE id = NEW.id;
    IF NOT FOUND THEN
        RAISE 'Page % not found', id;
    END IF;
    IF latest.revision = NEW.revision THEN
        PERFORM wiki.update_page(NEW.id, NEW.content, NEW.editor_id, NEW.comment);
    ELSE
        RAISE notice 'not updating revision % (latest is %)', NEW.revision, latest.revision;
    END IF;
    RETURN null;
end;
$$ language plpgsql;

CREATE TRIGGER update_page_trigger
    INSTEAD OF UPDATE ON wiki.page 
    FOR EACH ROW
    EXECUTE PROCEDURE wiki.do_update_page_trigger();
