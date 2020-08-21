.DEFAULT_GOAL := help

PREFIX_ARG := $(if $(PREFIX),--prefix $(PREFIX),)
LIBDIR_ARG := $(if $(LIBDIR),--libdir $(LIBDIR),)
DESTDIR_ARG := $(if $(DESTDIR),--destdir $(DESTDIR),)
INSTALL_ARGS := $(PREFIX_ARG) $(LIBDIR_ARG) $(DESTDIR_ARG)
BIN := ./dune.exe

# Dependencies used for developing and testing dune
DEV_DEPS := \
bisect_ppx \
cinaps \
coq \
core_bench \
"csexp>=1.3.0" \
js_of_ocaml-ppx \
js_of_ocaml-compiler \
"mdx=1.6.0" \
menhir \
merlin \
ocaml-migrate-parsetree \
ocamlfind \
ocamlformat.0.14.3 \
"odoc>=1.5.0" \
"ppx_expect>=v0.14" \
ppx_inline_test \
"ppxlib.0.13.0" \
result \
"utop>=2.6.0"

-include Makefile.dev

help:
	@cat doc/make-help.txt

release: $(BIN)
	$(BIN) build -p dune --profile dune-bootstrap

dune.exe: bootstrap.ml boot/libs.ml boot/duneboot.ml
	ocaml bootstrap.ml

dev: $(BIN)
	$(BIN) build @install

all: $(BIN)
	$(BIN) build

install:
	$(BIN) install $(INSTALL_ARGS) dune

uninstall:
	$(BIN) uninstall $(INSTALL_ARGS) dune

reinstall: uninstall install

dev-deps:
	opam install -y $(DEV_DEPS)

dev-switch:
	opam update
	# Ensuring that either a dev switch already exists or a new one is created
	[[ $(shell opam switch show) == $(shell pwd) ]] || \
		opam switch create -y . --deps-only --with-test
	opam install -y $(DEV_DEPS)

test: $(BIN)
	$(BIN) runtest

test-windows: $(BIN)
	$(BIN) build @runtest-windows

test-js: $(BIN)
	$(BIN) build @runtest-js

test-coq: $(BIN)
	$(BIN) build @runtest-coq

test-all: $(BIN)
	$(BIN) build @runtest @runtest-js @runtest-coq

check: $(BIN)
	$(BIN) build @check

fmt: $(BIN)
	$(BIN) build @fmt --auto-promote

promote: $(BIN)
	$(BIN) promote

accept-corrections: promote

all-supported-ocaml-versions: $(BIN)
	$(BIN) build @install @runtest --workspace dune-workspace.dev --root .

clean: $(BIN)
	$(BIN) clean || true
	rm -rf _boot dune.exe

distclean: clean
	rm -f src/dune/setup.ml

doc:
	cd doc && sphinx-build . _build

livedoc:
	cd doc && sphinx-autobuild . _build \
	  -p 8888 -q  --host $(shell hostname) -r '\.#.*'

update-jbuilds: $(BIN)
	$(BIN) build @doc/runtest --auto-promote

# If the first argument is "run"...
ifeq (dune,$(firstword $(MAKECMDGOALS)))
  # use the rest as arguments for "run"
  RUN_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  # ...and turn them into do-nothing targets
  $(eval $(RUN_ARGS):;@:)
endif

dune: $(BIN)
	$(BIN) $(RUN_ARGS)

.PHONY: default install uninstall reinstall clean test doc dev-switch
.PHONY: promote accept-corrections opam-release dune check fmt

opam-release:
	dune-release distrib --skip-build --skip-lint --skip-tests -n dune
	# See https://github.com/ocamllabs/dune-release/issues/206
	DUNE_RELEASE_DELEGATE=github-dune-release-delegate dune-release publish distrib --verbose -n dune
	dune-release opam pkg -n dune
	dune-release opam submit -n dune
