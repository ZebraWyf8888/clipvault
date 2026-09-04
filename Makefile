.PHONY: build test e2e app install clean

build:
	swift build

test:
	swift test

e2e:
	bash scripts/e2e_test.sh

app:
	bash packaging/build_app.sh

install: app
	rm -rf /Applications/ClipVault.app
	cp -R dist/ClipVault.app /Applications/
	@echo "已安装到 /Applications/ClipVault.app"

clean:
	rm -rf .build dist
