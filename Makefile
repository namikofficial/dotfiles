# NoxFlow Build System
# Builds noxd daemon and noxctl CLI from source.

CARGO ?= cargo
INSTALL_ROOT ?= $(HOME)/.local
BIN_DIR ?= $(INSTALL_ROOT)/bin

.PHONY: all build test install clean install-bin install-systemd install-shell

all: build

build:
	$(CARGO) build --workspace --release

test:
	$(CARGO) test --workspace

install-bin: build
	$(CARGO) install --path core/noxd --root $(INSTALL_ROOT) --force
	$(CARGO) install --path cli/noxctl --root $(INSTALL_ROOT) --force
	install -d $(BIN_DIR)
	install -m 755 setup/noxflow-shell-launcher.sh $(BIN_DIR)/noxflow-shell

install-systemd:
	install -d $(HOME)/.config/systemd/user
	ln -sfn $(CURDIR)/systemd/user/noxd.service \
		$(HOME)/.config/systemd/user/noxd.service
	ln -sfn $(CURDIR)/systemd/user/noxflow-shell.service \
		$(HOME)/.config/systemd/user/noxflow-shell.service
	ln -sfn $(CURDIR)/systemd/user/noxflow-fallback.service \
		$(HOME)/.config/systemd/user/noxflow-fallback.service
	ln -sfn $(CURDIR)/systemd/user/noxflow-session-optional.service \
		$(HOME)/.config/systemd/user/noxflow-session-optional.service

install-shell:
	install -d $(HOME)/.config/noxflow
	ln -sfn $(CURDIR)/shell/noxflow $(HOME)/.config/noxflow/shell

install: install-bin install-systemd install-shell

clean:
	$(CARGO) clean --workspace
