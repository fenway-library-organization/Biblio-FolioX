-include config.mk

config.mk: config.mk.def
	cp $< $@

build:
	@echo "[sudo] make install"

install:
	./install $(PREFIX)

.PHONY: build install
