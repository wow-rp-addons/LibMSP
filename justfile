packager_url := "https://raw.githubusercontent.com/BigWigsMods/packager/v2/release.sh"

default: check

check:
	luacheck -q $(git ls-files '*.lua')

dist:
	curl -s {{ packager_url }} | bash -s -- -dl

libs:
	curl -s {{ packager_url }} | bash -s -- -cdlz
	cp -a .release/LibMSP/Libs/* Libs/
