# Linux x86 / SourceMod 1.13. Run inside the System2 Docker image.
.PHONY: all debug
all:
	bash ./build.sh release
debug:
	bash ./build.sh debug
