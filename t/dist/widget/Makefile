MODULES = widget
DATA_built = widget.sql
DATA = uninstall_widget.sql
DOCS = README.widget
REGRESS = widget

ifdef NO_PGXS
subdir = contrib/widget
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
else
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
endif
