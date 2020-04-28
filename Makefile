-include config.mk

build: config.mk
	@echo "Nothing to build -- just do this:"
	@echo "  $$ sudo make install"
	@echo "Or this as root:"
	@echo "  # make install"

config.mk: config.mk.def
	cp $< $@

install: check
	./install $(PREFIX)

check:
	@for f in $(shell find lib -name \*.pm); do perl -Ilib -I../Biblio-Folio/lib -c $$f; done

.PHONY: build install check
