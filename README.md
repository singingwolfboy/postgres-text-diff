Text diff storage for Postgresql
--------------------------------

Wiki engines usually store the full text of every revision of every page in the
database. This is convienent, but a massive waste of space. The goal of this
project is to store text diffs in a Postgresql database, and use triggers
and views to create a virtual table that contains the full text of every
revision of every page.

Yes, it's slower. But sometimes, you need or want to optimize for storage
space instead of time.
