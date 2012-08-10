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
        pd.created_on AS edited_on,
        pl.is_locked
    FROM wiki.page_latest AS pl, wiki.page_diff AS pd
    WHERE pl.id = pd.page_id
    AND is_deleted = FALSE
  UNION
    SELECT pl.id, pl.title, pl.slug, pl.namespace, pl.content, pl.comment,
        pl.num_lines, pl.revision, pl.editor_id, pl.markup, pl.language,
        pl.edited_on, pl.is_locked
    FROM wiki.page_latest AS pl
    WHERE is_deleted = FALSE;

CREATE OR REPLACE FUNCTION wiki.do_update_page_trigger() RETURNS trigger AS $$
declare
    latest wiki.page_latest;
begin
    SELECT * INTO latest FROM wiki.page_latest WHERE id = NEW.id;
    IF NOT FOUND THEN
        RAISE 'Page % not found', id;
    END IF;
    IF latest.is_locked THEN
        RAISE 'Page % is locked for editing', NEW.id;
    END IF;
    IF latest.revision = NEW.revision THEN
        PERFORM wiki.update_page(NEW.id, NEW.content, NEW.editor_id, NEW.comment);
    ELSE
        RAISE notice 'not updating old revision % of page % (latest revision is %)',
            NEW.revision, NEW.id, latest.revision;
    END IF;
    RETURN null;
end;
$$ language plpgsql;

CREATE TRIGGER update_page_trigger
    INSTEAD OF UPDATE ON wiki.page 
    FOR EACH ROW
    EXECUTE PROCEDURE wiki.do_update_page_trigger();

CREATE OR REPLACE FUNCTION wiki.do_insert_page_trigger() RETURNS trigger AS $$
declare
    num_lines int;
begin
    IF NEW.num_lines IS NULL THEN
        num_lines = array_length(string_to_array(NEW.content, E'\n'), 1);
    ELSE
        num_lines = NEW.num_lines;
    END IF;
    INSERT INTO wiki.page_latest (id, title, slug, namespace, content, comment,
        num_lines, editor_id, markup, language) VALUES
        (NEW.id, NEW.title, NEW.slug, NEW.namespace, NEW.content, NEW.comment,
        num_lines, NEW.editor_id, NEW.markup, NEW.language);
    RETURN NEW;
end;
$$ language plpgsql;

CREATE TRIGGER insert_page_trigger
    INSTEAD OF INSERT ON wiki.page
    FOR EACH ROW
    EXECUTE PROCEDURE wiki.do_insert_page_trigger();

CREATE OR REPLACE FUNCTION wiki.do_delete_page_trigger() RETURNS trigger AS $$
declare
    latest wiki.page_latest;
begin
    SELECT * INTO latest FROM wiki.page_latest WHERE id = NEW.id;
    IF NOT FOUND THEN
        RAISE 'Page % not found', id;
    END IF;
    IF latest.is_deleted THEN
        RETURN null;
    ELSE
        UPDATE wiki.page_latest SET is_deleted = TRUE WHERE id = OLD.id;
        RETURN OLD;
    END IF;
end;
$$ language plpgsql;

CREATE TRIGGER delete_page_trigger
    INSTEAD OF DELETE ON wiki.page
    FOR EACH ROW
    EXECUTE PROCEDURE wiki.do_delete_page_trigger();
