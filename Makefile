INSTALL_ARGS := $(if $(PREFIX),--prefix $(PREFIX),)
BIN := ./_build/default/bin/main.exe

default: boot.exe
	./boot.exe -j 4 --dev

boot.exe: bootstrap.ml
	ocaml bootstrap.ml

install:
	$(BIN) install $(INSTALL_ARGS)

uninstall:
	$(BIN) uninstall $(INSTALL_ARGS)

reinstall: uninstall reinstall

test:
	$(BIN) runtest

all-supported-ocaml-versions:
	$(BIN) build @install @runtest --workspace jbuild-workspace.dev --root .

clean:
	rm -rf _build

extract-makefile:
	$(BIN) extract-makefile -o Makefile.extracted @install

doc:
	cd doc && sphinx-build . _build

.PHONY: default install uninstall reinstall clean test doc
