PACKAGER_URL := https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh

.PHONY: check dist libs

all: check

check:
	@luacheck -q $(shell git ls-files '*.lua')

dist:
	@curl -s $(PACKAGER_URL) | bash -s -- -d -l -S

libs:
	@curl -s $(PACKAGER_URL) | bash -s -- -c -d -z
	@cp -a .release/LibMSP/Libs/* Libs/
